const { onDocumentUpdated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { HttpsError, logger } = require('firebase-functions/v2');
const { onCall } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const vision = require('@google-cloud/vision');
const admin = require('firebase-admin');
const {
    containsBlockedTerm,
    validateUserLevelSubmission,
} = require('./src/user_level_submission');
const {
    normalizePendingPuzzleGeneration,
    validatePuzzleGenerationDraftForStart,
    validatePuzzleGenerationDraftForStatus,
} = require('./src/puzzle_generation');
const {
    extractBase64Payload,
    detectImageFormat,
    assertFaceUploadBufferWithinSizeLimit,
} = require('./src/face_upload_validation');
const { sanitizeUploadedFaceImage } = require('./src/face_upload_processing');
const { validateWritableCreatorDraft } = require('./src/creator_draft_access');
const { planUserLevelDeletion } = require('./src/user_level_deletion');
admin.initializeApp();

const runpodApiKey = defineSecret('RUNPOD_API_KEY');
const runpodEndpointId = defineSecret('RUNPOD_ENDPOINT_ID');
const safeSearchClient = new vision.ImageAnnotatorClient();
const SAFE_SEARCH_BLOCKED = new Set(['LIKELY', 'VERY_LIKELY']);

async function assertCreatorCanUseUserLevels(db, uid) {
    const moderationSnapshot = await db.collection('creatorModeration').doc(uid).get();
    if (!moderationSnapshot.exists) {
        return;
    }

    const moderationData = moderationSnapshot.data() || {};
    if (moderationData.userLevelCreationBlocked !== true) {
        return;
    }

    const reason = String(moderationData.reason || '').trim();
    throw new HttpsError(
        'permission-denied',
        reason
            ? `Level creation is unavailable for this account right now. ${reason}`
            : 'Level creation is unavailable for this account right now.',
    );
}

async function deleteStorageFileIfExists(bucket, storagePath) {
    const normalizedPath = String(storagePath || '').trim();
    if (!normalizedPath) {
        return;
    }

    try {
        await bucket.file(normalizedPath).delete();
    } catch (error) {
        const code = Number(error?.code || 0);
        if (code === 404) {
            return;
        }
        throw error;
    }
}

exports.checkAndAssignPromoCode = onDocumentUpdated('players/{playerId}', async (event) => {
    const newValue = event.data.after.data();
    const previousValue = event.data.before.data();
    const playerId = event.params.playerId;
    const db = admin.firestore();

    try {
        if (newValue.current_level === 60 && !newValue.promo_code && previousValue.finished == false) {
            const promoCode = await db.runTransaction(async (transaction) => {
                const promoSnapshot = await transaction.get(
                    db.collection('promo_codes')
                        .where('assigned', '==', false)
                        .limit(1)
                );

                if (promoSnapshot.empty) {
                    logger.info(`No available promo codes for player ${playerId}`);
                    return null;
                }

                const promoDoc = promoSnapshot.docs[0];
                const promoCode = promoDoc.data().code;

                transaction.update(promoDoc.ref, { 
                    assigned: true, 
                    assigned_to: playerId 
                });
                transaction.update(event.data.after.ref, {
                    finished: true,
                    promo_code: promoCode
                });

                return promoCode;
            });

            if (promoCode) {
                logger.info(`Assigned promo code ${promoCode} to player ${playerId}`);
            } else {
                logger.warn(`Failed to assign promo code to player ${playerId}: No available promo codes`);
            }
        } else {
            logger.info(`Player ${playerId} level change does not require a promo code assignment.`);
        }

        return null;

    } catch (error) {
        logger.error(`Error processing promo code for player ${playerId}:`, error);
        throw new HttpsError('internal', 'Unable to process promo code assignment.');
    }
});

async function runLightSafeSearch(buffer) {
    try {
        const [result] = await safeSearchClient.safeSearchDetection({
            image: { content: buffer },
        });
        const annotation = result.safeSearchAnnotation || {};
        const adult = String(annotation.adult || 'UNKNOWN').trim().toUpperCase();
        const racy = String(annotation.racy || 'UNKNOWN').trim().toUpperCase();
        const violence = String(annotation.violence || 'UNKNOWN').trim().toUpperCase();

        const blocked =
            SAFE_SEARCH_BLOCKED.has(adult) ||
            violence === 'VERY_LIKELY' ||
            racy === 'VERY_LIKELY';

        return {
            status: 'checked',
            blocked,
            adult,
            racy,
            violence,
        };
    } catch (error) {
        logger.warn('SafeSearch check unavailable for user upload.', error);
        return {
            status: 'unavailable',
            blocked: false,
            adult: 'UNKNOWN',
            racy: 'UNKNOWN',
            violence: 'UNKNOWN',
        };
    }
}

function buildRunpodWorkflow(prompt, difficulty, solutionFileName = '1.png') {
    return {
        '10': {
            class_type: 'CheckpointLoaderSimple',
            inputs: { ckpt_name: 'Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors' },
        },
        '11': {
            class_type: 'CLIPTextEncode',
            inputs: { text: prompt, clip: ['10', 1] },
        },
        '14': {
            class_type: 'ControlNetLoader',
            inputs: { control_net_name: 'diffusion_pytorch_model.safetensors' },
        },
        '15': {
            class_type: 'CLIPTextEncode',
            inputs: { text: 'worst quality poor details unrealistic', clip: ['10', 1] },
        },
        '16': {
            class_type: 'ControlNetApplyAdvanced',
            inputs: {
                strength: difficulty,
                start_percent: 0.0,
                end_percent: 1.0,
                positive: ['11', 0],
                negative: ['15', 0],
                control_net: ['14', 0],
                image: ['17', 0],
            },
        },
        '17': {
            class_type: 'LoadImage',
            inputs: { image: solutionFileName, upload: 'image' },
        },
        '18': {
            class_type: 'KSampler',
            inputs: {
                seed: Math.floor(Math.random() * 1000000000000),
                steps: 20,
                cfg: 8,
                sampler_name: 'euler',
                scheduler: 'normal',
                denoise: 1.0,
                model: ['10', 0],
                positive: ['16', 0],
                negative: ['16', 1],
                latent_image: ['19', 0],
            },
        },
        '19': {
            class_type: 'EmptyLatentImage',
            inputs: { width: 1024, height: 1024, batch_size: 1 },
        },
        '20': {
            class_type: 'VAEDecode',
            inputs: { samples: ['18', 0], vae: ['10', 2] },
        },
        '21': {
            class_type: 'SaveImage',
            inputs: { filename_prefix: 'ComfyUI', images: ['20', 0] },
        },
    };
}

async function callRunpodApi(endpointId, apiKey, action, body) {
    const url = `https://api.runpod.ai/v2/${endpointId}${action}`;
    const options = {
        method: body ? 'POST' : 'GET',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`,
        },
    };
    if (body) {
        options.body = JSON.stringify(body);
    }
    const response = await fetch(url, options);

    const json = await response.json();
    logger.info(`RunPod API Response for ${action}:`, json);
    
    if (!response.ok) {
        throw new Error(
            json.error?.message || json.error || `RunPod API request failed with status ${response.status}.`,
        );
    }

    return json;
}

function extractGeneratedImage(statusData) {
    if (statusData.output && Array.isArray(statusData.output.images) && statusData.output.images[0]) {
        const firstImage = statusData.output.images[0];
        if (typeof firstImage === 'string') {
            return firstImage;
        }
        return firstImage.data || firstImage.image || '';
    }

    if (statusData.output && typeof statusData.output.message === 'string') {
        return statusData.output.message;
    }

    if (Array.isArray(statusData.output) && statusData.output[0]) {
        return statusData.output[0];
    }

    return '';
}

exports.startUserLevelPuzzleGeneration = onCall({
    secrets: [runpodApiKey, runpodEndpointId],
    timeoutSeconds: 120,
    enforceAppCheck: true,
}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError('unauthenticated', 'You must be signed in to generate a puzzle.');
    }

    const prompt = String(request.data?.prompt || '').trim();
    const solutionImageBase64 = String(request.data?.solutionImageBase64 || '').trim();
    const difficulty = Number(request.data?.difficulty) || 1.0;
    const levelId = String(request.data?.levelId || '').trim();
    const solutionFileName =
        String(request.data?.solutionFileName || '1.png').trim() || '1.png';

    if (!prompt) {
        throw new HttpsError('invalid-argument', 'A generation prompt is required.');
    }

    if (!solutionImageBase64.startsWith('data:image/')) {
        throw new HttpsError('invalid-argument', 'A valid solution image is required.');
    }

    if (containsBlockedTerm(prompt)) {
        throw new HttpsError('failed-precondition', 'Please remove profanity before generating.');
    }

    const db = admin.firestore();
    if (levelId) {
        const ownerLevelSnapshot = await db
            .collection('userLevels')
            .doc(uid)
            .collection('levels')
            .doc(levelId)
            .get();
        try {
            validatePuzzleGenerationDraftForStart(ownerLevelSnapshot.data());
        } catch (error) {
            throw new HttpsError(
                ownerLevelSnapshot.exists ? 'failed-precondition' : 'not-found',
                error instanceof Error && error.message
                    ? error.message
                    : 'The selected level could not be used for puzzle generation.',
            );
        }


    }

    const apiKey = runpodApiKey.value();
    const endpointId = runpodEndpointId.value();
    if (!apiKey || !endpointId) {
        throw new HttpsError('internal', 'The RunPod secrets are not configured.');
    }

    const payload = {
        input: {
            workflow: buildRunpodWorkflow(prompt, difficulty, solutionFileName),
            images: [{ name: solutionFileName, image: solutionImageBase64 }],
        },
    };

    logger.info(`Starting RunPod Job creation for endpoint [${endpointId}]...`);
    const runData = await callRunpodApi(endpointId, apiKey, '/run', payload);
    const jobId = String(runData.id || '').trim();
    logger.info(`RunPod /run successfully returned jobId: [${jobId}]`);

    if (!jobId) {
        throw new HttpsError('internal', 'The generation backend did not return a job id.');
    }

    if (levelId) {
        try {
            const bucket = admin.storage().bucket();
            const payloadStoragePath = `user-levels/${uid}/${levelId}/pending-payload.txt`;
            await bucket.file(payloadStoragePath).save(solutionImageBase64);
        } catch (e) {
            logger.warn("Failed to backup generation payload", e);
        }

        await db
            .collection('userLevels')
            .doc(uid)
            .collection('levels')
            .doc(levelId)
            .set({
                editorData: {
                    pendingPuzzleGeneration: {
                        status: 'running',
                        jobId,
                        prompt,
                        difficulty,
                        solutionFileName,
                        retryCount: 0,
                        jobStartedAt: admin.firestore.FieldValue.serverTimestamp(),
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    },
                },
                modifiedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
    }

    return {
        jobId,
        reusedExisting: false,
    };
});

exports.getUserLevelPuzzleGenerationStatus = onCall({
    secrets: [runpodApiKey, runpodEndpointId],
    timeoutSeconds: 60,
    enforceAppCheck: true,
}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError('unauthenticated', 'You must be signed in to check puzzle status.');
    }

    const jobId = String(request.data?.jobId || '').trim();
    const levelId = String(request.data?.levelId || '').trim();
    if (!jobId) {
        throw new HttpsError('invalid-argument', 'A jobId is required.');
    }
    if (!levelId) {
        throw new HttpsError('invalid-argument', 'A levelId is required.');
    }

    const apiKey = runpodApiKey.value();
    const endpointId = runpodEndpointId.value();
    if (!apiKey || !endpointId) {
        throw new HttpsError('internal', 'The RunPod secrets are not configured.');
    }

    const db = admin.firestore();
    await assertCreatorCanUseUserLevels(db, uid);
    const ownerLevelSnapshot = await db
        .collection('userLevels')
        .doc(uid)
        .collection('levels')
        .doc(levelId)
        .get();
    try {
        validatePuzzleGenerationDraftForStatus(ownerLevelSnapshot.data(), jobId);
    } catch (error) {
        throw new HttpsError(
            ownerLevelSnapshot.exists ? 'failed-precondition' : 'not-found',
            error instanceof Error && error.message
                ? error.message
                : 'The selected draft can no longer be used for puzzle generation.',
        );
    }

    const statusData = await callRunpodApi(endpointId, apiKey, `/status/${jobId}`, null);
    const status = String(statusData.status || 'UNKNOWN').trim().toUpperCase();
    const imageBase64 = extractGeneratedImage(statusData);
    const errorMessage = String(
        statusData.error ||
        statusData.errorMessage ||
        statusData.message ||
        '',
    ).trim();

    return {
        status,
        imageBase64,
        errorMessage,
        retryable: statusData.retryable === true,
        retryAfterMs: Number(statusData.retryAfterMs || 0) || 0,
    };
});

async function sendFCMNotification(uid, payload) {
    const db = admin.firestore();
    const androidTokens = await db.collection('fcmTokensAndroid').doc(uid).get();
    const iosTokens = await db.collection('fcmTokensIos').doc(uid).get();
    const tokens = [];
    if (androidTokens.exists && androidTokens.data().token) tokens.push(androidTokens.data().token);
    if (iosTokens.exists && iosTokens.data().token) tokens.push(iosTokens.data().token);
    
    if (tokens.length > 0) {
        try {
             const response = await admin.messaging().sendEachForMulticast({
                tokens: tokens,
                android: { 
                    priority: 'high',
                    notification: { channelId: 'creator_review_updates', sound: 'default' }
                },
                apns: { 
                    payload: { aps: { contentAvailable: true, sound: 'default' } } 
                },
                ...payload,
             });
             logger.info(`FCM push notification sent successfully: ${response.successCount} delivered, ${response.failureCount} failed.`);
        } catch(e) {
             logger.warn("FCM push notification error", e);
        }
    }
}

exports.processPendingPuzzleGeneration = onDocumentWritten({
    document: 'userLevels/{uid}/levels/{levelId}',
    secrets: [runpodApiKey, runpodEndpointId],
    timeoutSeconds: 540,
    memory: '512MiB',
}, async (event) => {
    logger.info(`[Job Start] Trigger fired for level ${event.params.levelId}`);
    const afterData = event.data.after.data();
    if (!afterData) {
        logger.info(`[Exit] No afterData found`);
        return;
    }
    
    const pending = afterData.editorData?.pendingPuzzleGeneration;
    if (!pending || pending.status !== 'running' || !pending.jobId) {
        logger.info(`[Exit] Missing pending or status! Pending object:`, pending);
        return;
    }

    // Check if the previous state was the same running job (idempotency check)
    const beforeData = event.data.before.data();
    const beforePending = beforeData?.editorData?.pendingPuzzleGeneration;
    if (beforePending && beforePending.jobId === pending.jobId) {
        logger.info(`[Exit] Idempotency catch. Same jobId as before: ${pending.jobId}`);
        // If it was already running this exact job ID, don't start a duplicate loop.
        return;
    }
    logger.info(`[Job Start] Passed early exits! Starting loop for jobId: ${pending.jobId}`);

    const jobId = pending.jobId;
    const uid = event.params.uid;
    const levelId = event.params.levelId;

    const apiKey = runpodApiKey.value();
    const endpointId = runpodEndpointId.value();
    if (!apiKey || !endpointId) {
        logger.error('Missing RunPod secrets');
        return;
    }

    const db = admin.firestore();
    const maxWaitTimeMs = 500000; // ~8 minutes safety limit inside the loop
    const pollIntervalMs = 10000; // 10 seconds
    const startTime = Date.now();
    let consecutiveErrors = 0;

    while (Date.now() - startTime < maxWaitTimeMs) {
        const currentDoc = await db.collection('userLevels').doc(uid).collection('levels').doc(levelId).get();
        const currentJobId = currentDoc.data()?.editorData?.pendingPuzzleGeneration?.jobId;
        if (!currentDoc.exists || currentJobId !== jobId) {
            logger.info(`[Exit Loop] Document changed! currentJobId: ${currentJobId}, expected: ${jobId}`);
            return; // State cleared or restarted by client safely
        }

        let statusData;
        try {
            statusData = await callRunpodApi(endpointId, apiKey, `/status/${jobId}`, null);
            consecutiveErrors = 0;
        } catch (error) {
            consecutiveErrors++;
            logger.warn(`Transient error polling Runpod Proxy (attempt ${consecutiveErrors}):`, error);
            if (consecutiveErrors >= 6) {
                logger.error('Too many consecutive proxy errors. Aborting job.');
                await db.collection('userLevels').doc(uid).collection('levels').doc(levelId).update({
                    'editorData.pendingPuzzleGeneration': admin.firestore.FieldValue.delete(),
                    'editorData.hasPuzzleImage': false
                });
                return;
            }
            await new Promise(r => setTimeout(r, pollIntervalMs));
            continue;
        }

        const status = String(statusData.status || 'UNKNOWN').trim().toUpperCase();
        
        logger.info(`Polling ${jobId}: Current Status is [${status}]`);

        if (status === 'COMPLETED') {
            const imageBase64 = extractGeneratedImage(statusData);
            if (imageBase64) {
                try {
                    const base64Data = imageBase64.replace(/^data:image\/\w+;base64,/, '');
                    const rawBuffer = Buffer.from(base64Data, 'base64');
                    
                    const sharp = require('sharp');
                    const buffer = await sharp(rawBuffer)
                        .resize(1024, 1024, { fit: 'inside', withoutEnlargement: true })
                        .webp({ quality: 60, effort: 6, smartSubsample: true })
                        .toBuffer();

                    const bucket = admin.storage().bucket();
                    const ts = Date.now();
                    const storagePath = `user-levels/${uid}/${levelId}/puzzle_${ts}.webp`;
                    
                    const oldPuzzlePath = currentDoc.data().puzzlePath;
                    const oldThumbnailPath = currentDoc.data().puzzleThumbnailPath;
                    
                    await bucket.file(storagePath).save(buffer, {
                        contentType: 'image/webp',
                        metadata: {
                            metadata: { ownerUid: uid, assetRole: 'puzzle' }
                        }
                    });

                    if (oldPuzzlePath && oldPuzzlePath !== storagePath) {
                        await deleteStorageFileIfExists(bucket, oldPuzzlePath);
                    }
                    if (oldThumbnailPath && oldThumbnailPath !== storagePath && oldThumbnailPath !== oldPuzzlePath) {
                        await deleteStorageFileIfExists(bucket, oldThumbnailPath);
                    }

                    await currentDoc.ref.update({
                        puzzlePath: storagePath,
                        puzzleThumbnailPath: storagePath,
                        'editorData.hasPuzzleImage': true,
                        'editorData.pendingPuzzleGeneration': admin.firestore.FieldValue.delete(),
                        modifiedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    
                    logger.info(`Successfully saved image and updated document for ${levelId} at ${storagePath}`);

                    await sendFCMNotification(uid, {
                        data: { notificationType: 'puzzle_generation_completed', draftLevelId: levelId },
                        notification: { title: 'Puzzle Generated!', body: 'Your drafted AI puzzle generation has just finished. Tap to continue editing.' }
                    });
                    await deleteStorageFileIfExists(bucket, `user-levels/${uid}/${levelId}/pending-payload.txt`);
                    
                } catch(err) {
                    logger.error("Failed saving generated image:", err);
                }
            } else {
                 await sendFCMNotification(uid, {
                    data: { notificationType: 'puzzle_generation_failed', errorMessage: 'No image payload successfully returned from generation.', draftLevelId: levelId },
                    notification: { title: 'Puzzle Generation Failed', body: 'No image payload successfully returned from generation.' }
                 });
                 await currentDoc.ref.update({
                    'editorData.pendingPuzzleGeneration': admin.firestore.FieldValue.delete()
                 });
            }
            return;
        }

        if (status === 'FAILED' || status === 'CANCELLED') {
             let errorMsg = String(statusData.error || statusData.errorMessage || statusData.message || 'The server rejected the generation request.').trim();
             const isCrash = errorMsg.includes('127.0.0.1') || errorMsg.includes('Connection refused') || errorMsg.includes('Max retries exceeded');
             const retryCount = Number(currentDoc.data()?.editorData?.pendingPuzzleGeneration?.retryCount || 0);

             if (isCrash && retryCount < 2) {
                 logger.info(`Job ${jobId} failed with proxy crash. Retrying (attempt ${retryCount + 1})...`);
                 const bucket = admin.storage().bucket();
                 const payloadStoragePath = `user-levels/${uid}/${levelId}/pending-payload.txt`;
                 try {
                     const [fileContents] = await bucket.file(payloadStoragePath).download();
                     const base64Image = fileContents.toString('utf-8');
                     const prompt = currentDoc.data()?.editorData?.pendingPuzzleGeneration?.prompt || '';
                     const diff = Number(currentDoc.data()?.editorData?.pendingPuzzleGeneration?.difficulty || 1.0);
                     const solutionFileName = currentDoc.data()?.editorData?.pendingPuzzleGeneration?.solutionFileName || '1.png';

                     const payload = {
                         input: {
                             workflow: buildRunpodWorkflow(prompt, diff, solutionFileName),
                             images: [{ name: solutionFileName, image: base64Image }],
                         },
                     };

                     const runData = await callRunpodApi(endpointId, apiKey, '/run', payload);
                     const newJobId = String(runData.id || '').trim();
                     if (newJobId) {
                         logger.info(`GC Autonomous Retry triggered new RunPod jobId: [${newJobId}]`);
                         await currentDoc.ref.update({
                             'editorData.pendingPuzzleGeneration': {
                                 status: 'running',
                                 jobId: newJobId,
                                 prompt: prompt,
                                 difficulty: diff,
                                 solutionFileName: solutionFileName,
                                 retryCount: retryCount + 1,
                                 jobStartedAt: admin.firestore.FieldValue.serverTimestamp(),
                                 updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                             }
                         });
                         return; // Terminate this loop. The document update will inherently re-fire this CF!
                     }
                 } catch (e) {
                     logger.error("GC Autonomous Retry natively failed execution:", e);
                 }
             }

             if (isCrash) {
                 errorMsg = 'The AI generator node lost connection. The operation failed.';
             }
             await sendFCMNotification(uid, {
                data: { notificationType: 'puzzle_generation_failed', errorMessage: errorMsg, draftLevelId: levelId },
                notification: { title: 'Puzzle Generation Failed', body: errorMsg }
             });
             await currentDoc.ref.update({
                'editorData.pendingPuzzleGeneration': admin.firestore.FieldValue.delete()
             });
             await deleteStorageFileIfExists(admin.storage().bucket(), `user-levels/${uid}/${levelId}/pending-payload.txt`);
             return;
        }

        await new Promise(r => setTimeout(r, pollIntervalMs));
    }

    const finalDoc = await db.collection('userLevels').doc(uid).collection('levels').doc(levelId).get();
    if (finalDoc.exists && finalDoc.data()?.editorData?.pendingPuzzleGeneration?.jobId === jobId) {
         logger.warn(`Job ${jobId} timed out after ${maxWaitTimeMs}ms. Cleaning up.`);
         await sendFCMNotification(uid, {
             data: { notificationType: 'puzzle_generation_failed', errorMessage: 'The generation request timed out after 8 minutes. Please try again.', draftLevelId: levelId },
             notification: { title: 'Generation Timed Out', body: 'The AI took too long to respond. Please try again.' }
         });
         await finalDoc.ref.update({
             'editorData.pendingPuzzleGeneration': admin.firestore.FieldValue.delete()
         });
    }
});

exports.sanitizeUserLevelUpload = onCall({
    timeoutSeconds: 60,
    memory: '512MiB',
    enforceAppCheck: true,
}, async (request) => {
    const uid = request.auth?.uid;
    const levelId = String(request.data?.levelId || '').trim();
    const uploadKind = String(request.data?.uploadKind || '').trim();

    if (!uid) {
        throw new HttpsError('unauthenticated', 'You must be signed in before uploading an image.');
    }

    if (!levelId) {
        throw new HttpsError('invalid-argument', 'A level id is required.');
    }

    if (uploadKind !== 'face_source') {
        throw new HttpsError('invalid-argument', 'Unsupported upload kind.');
    }

    const db = admin.firestore();
    await assertCreatorCanUseUserLevels(db, uid);
    const ownerLevelSnapshot = await db
        .collection('userLevels')
        .doc(uid)
        .collection('levels')
        .doc(levelId)
        .get();
    try {
        validateWritableCreatorDraft(ownerLevelSnapshot.data(), {
            lockedMessage: 'Submitted levels are locked and cannot change the face photo.',
        });
    } catch (error) {
        throw new HttpsError(
            ownerLevelSnapshot.exists ? 'failed-precondition' : 'not-found',
            error instanceof Error && error.message
                ? error.message
                : 'The selected level could not be used for this upload.',
        );
    }

    let base64Payload;
    try {
        base64Payload = extractBase64Payload(request.data?.imageBase64);
    } catch (error) {
        throw new HttpsError(
            'invalid-argument',
            error instanceof Error && error.message
                ? error.message
                : 'A face photo is required.',
        );
    }
    const imageBuffer = Buffer.from(base64Payload, 'base64');
    if (!imageBuffer.length) {
        throw new HttpsError('invalid-argument', 'A face photo is required.');
    }

    try {
        assertFaceUploadBufferWithinSizeLimit(imageBuffer);
    } catch (error) {
        throw new HttpsError(
            'invalid-argument',
            error instanceof Error && error.message
                ? error.message
                : 'That face photo is too large. Please choose a smaller image.',
        );
    }

    const detectedFormat = detectImageFormat(imageBuffer);
    if (!detectedFormat) {
        throw new HttpsError(
            'invalid-argument',
            'Only JPG, PNG, or WebP face photos are allowed.',
        );
    }

    const safeSearch = await runLightSafeSearch(imageBuffer);
    if (safeSearch.blocked) {
        throw new HttpsError(
            'failed-precondition',
            'This face photo looks too explicit for Subliminal Words.',
        );
    }

    let sanitized;
    try {
        sanitized = await sanitizeUploadedFaceImage(imageBuffer);
    } catch (error) {
        throw new HttpsError(
            'invalid-argument',
            error instanceof Error && error.message
                ? error.message
                : 'Could not read that face photo.',
        );
    }
    const storagePath = `user-levels/${uid}/${levelId}/source.webp`;
    await admin.storage().bucket().file(storagePath).save(sanitized.bytes, {
        contentType: 'image/webp',
        resumable: false,
        metadata: {
            contentType: 'image/webp',
            metadata: {
                ownerUid: uid,
                editorMode: 'photoSketch',
                assetRole: 'source',
                sourceValidation: 'sanitized',
                originalContentType: detectedFormat.contentType,
                nsfwCheckStatus: safeSearch.status,
                safeSearchAdult: safeSearch.adult,
                safeSearchRacy: safeSearch.racy,
                safeSearchViolence: safeSearch.violence,
            },
        },
    });

    return {
        storagePath,
        contentType: 'image/webp',
        width: sanitized.width,
        height: sanitized.height,
        sizeBytes: sanitized.bytes.length,
        safetyStatus: 'clean',
        nsfwCheckStatus: safeSearch.status,
        safeSearch,
    };
});

exports.deleteUserLevelDraft = onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError('unauthenticated', 'You must be signed in before deleting a level.');
    }

    const levelId = String(request.data?.levelId || '').trim();
    if (!levelId) {
        throw new HttpsError('invalid-argument', 'A levelId is required.');
    }

    const db = admin.firestore();
    await assertCreatorCanUseUserLevels(db, uid);

    const ownerLevelRef = db.collection('userLevels').doc(uid).collection('levels').doc(levelId);
    const ownerLevelSnapshot = await ownerLevelRef.get();
    if (!ownerLevelSnapshot.exists) {
        return {
            deleted: false,
            mode: 'missing',
            deletedSubmissionCount: 0,
        };
    }

    const levelData = ownerLevelSnapshot.data() || {};
    const submissionsSnapshot = await db
        .collection('userLevelSubmissions')
        .where('ownerLevelPath', '==', ownerLevelRef.path)
        .get();
    const submissionDocs = submissionsSnapshot.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() || {},
    }));

    const deletionPlan = planUserLevelDeletion({
        levelData,
        submissionDocs,
    });

    const batch = db.batch();
    batch.delete(ownerLevelRef);
    if (deletionPlan.deleteSubmissionDocs) {
        for (const submissionDoc of submissionsSnapshot.docs) {
            batch.delete(submissionDoc.ref);
        }
    }
    await batch.commit();

    const bucket = admin.storage().bucket();
    const editorData = levelData.editorData && typeof levelData.editorData === 'object'
        ? levelData.editorData
        : {};
    const explicitStoragePaths = new Set([
        String(levelData.solutionPath || '').trim(),
        String(levelData.puzzlePath || '').trim(),
        String(levelData.puzzleThumbnailPath || '').trim(),
        String(editorData.sourceImagePath || '').trim(),
    ]);

    for (const storagePath of explicitStoragePaths) {
        await deleteStorageFileIfExists(bucket, storagePath);
    }

    try {
        await bucket.deleteFiles({
            force: true,
            prefix: `user-levels/${uid}/${levelId}/`,
        });
    } catch (error) {
        const code = Number(error?.code || 0);
        if (code !== 404) {
            throw error;
        }
    }

    return {
        deleted: true,
        mode: deletionPlan.published
            ? 'private_copy_deleted'
            : 'draft_and_submission_deleted',
        deletedSubmissionCount: deletionPlan.submissionDocIdsToDelete.length,
    };
});

exports.submitUserLevelSubmission = onCall(async (request) => {
    const uid = request.auth?.uid;
    const levelId = request.data?.levelId;

    if (!uid) {
        throw new HttpsError('unauthenticated', 'You must be signed in to submit a level.');
    }

    if (!levelId || typeof levelId !== 'string') {
        throw new HttpsError('invalid-argument', 'A levelId is required.');
    }

    const db = admin.firestore();
    await assertCreatorCanUseUserLevels(db, uid);
    const ownerLevelRef = db.collection('userLevels').doc(uid).collection('levels').doc(levelId);

    const result = await db.runTransaction(async (transaction) => {
        const ownerLevelSnapshot = await transaction.get(ownerLevelRef);
        if (!ownerLevelSnapshot.exists) {
            throw new HttpsError('not-found', 'The selected level could not be found.');
        }

        const levelData = ownerLevelSnapshot.data() || {};
        if (levelData.isLocked === true) {
            throw new HttpsError(
                'failed-precondition',
                'This level has already been submitted and is now locked.',
            );
        }

        let validatedSubmission;
        try {
            validatedSubmission = validateUserLevelSubmission(levelData);
        } catch (error) {
            throw new HttpsError(
                'failed-precondition',
                error instanceof Error && error.message
                    ? error.message
                    : 'This level is not ready for review yet.',
            );
        }
        const {
            creatorName,
            answer,
            editorMode,
            contentCategory,
            editorData,
            tooltipStart,
            tooltipEnd,
        } = validatedSubmission;

        const submissionRef = db.collection('userLevelSubmissions').doc();
        const submittedAt = admin.firestore.FieldValue.serverTimestamp();

        transaction.set(submissionRef, {
            ownerLevelPath: ownerLevelRef.path,
            sourceLevelId: ownerLevelSnapshot.id,
            creatorUid: uid,
            creatorName,
            name: answer,
            hintType: levelData.hintType || 'fact',
            editorMode,
            contentCategory,
            hints: levelData.hints || {},
            puzzlePath: levelData.puzzlePath || '',
            puzzleThumbnailPath: levelData.puzzleThumbnailPath || levelData.puzzlePath || '',
            solutionPath: levelData.solutionPath || levelData.puzzlePath || '',
            tooltipStart,
            tooltipEnd,
            isEnabled: false,
            status: 'pending_review',
            editorData,
            createdAt: levelData.createdAt || submittedAt,
            submittedAt,
        });

        transaction.update(ownerLevelRef, {
            isLocked: true,
            submissionStatus: 'pending_review',
            submissionId: submissionRef.id,
            submittedAt,
            modifiedAt: submittedAt,
        });

        return {submissionId: submissionRef.id};
    });

    return result;
});

exports.updatePackAndCategoryCounts = onDocumentWritten('packs/{packId}/levels/{levelId}', async (event) => {
    const db = admin.firestore();
    const packId = event.params.packId;

    try {
        const levelsSnapshot = await db.collection('packs').doc(packId).collection('levels')
            .where('isEnabled', '==', true)
            .count()
            .get();
            
        const packTotalLevels = levelsSnapshot.data().count;
        
        await db.collection('packs').doc(packId).update({
            totalLevels: packTotalLevels,
            modifiedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        const packDoc = await db.collection('packs').doc(packId).get();
        if (!packDoc.exists) return;
        
        const categoryId = packDoc.data().categoryId;
        if (categoryId) {
            let categoryTotalLevels = 0;
            const packsSnapshot = await db.collection('packs')
                .where('categoryId', '==', categoryId)
                .where('isEnabled', '==', true)
                .get();
                
            for (const pDoc of packsSnapshot.docs) {
                const countObj = await db.collection('packs').doc(pDoc.id).collection('levels')
                    .where('isEnabled', '==', true)
                    .count()
                    .get();
                categoryTotalLevels += countObj.data().count;
            }

            await db.collection('categories').doc(categoryId).update({
                totalLevels: categoryTotalLevels,
                modifiedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            
            logger.info(`Updated category ${categoryId} to ${categoryTotalLevels} levels and pack ${packId} to ${packTotalLevels} levels.`);
        }
    } catch (e) {
        logger.error(`Error updating counts for pack ${packId}: ${e}`);
    }
});
