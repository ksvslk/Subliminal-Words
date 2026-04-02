const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { HttpsError, logger } = require('firebase-functions/v2');
const { onCall } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const vision = require('@google-cloud/vision');
const admin = require('firebase-admin');
const sharp = require('sharp');
admin.initializeApp();

const runpodProxyBearer = defineSecret('RUNPOD_PROXY_BEARER');
const RUNPOD_PROXY_BASE_URL = 'https://runpod-proxy-549374376791.us-central1.run.app';
const safeSearchClient = new vision.ImageAnnotatorClient();
const MAX_UPLOAD_BYTES = 3 * 1024 * 1024;
const MAX_IMAGE_DIMENSION = 4096;
const MAX_IMAGE_PIXELS = 20 * 1024 * 1024;
const SANITIZED_FACE_MAX_DIMENSION = 1400;
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

const BLOCKED_TERMS = [
    'fuck',
    'shit',
    'bitch',
    'asshole',
    'cunt',
    'nigger',
    'fag',
    'porn',
    'sex',
];

function containsBlockedTerm(value) {
    const normalized = String(value || '').trim().toLowerCase();
    if (!normalized) {
        return false;
    }

    return BLOCKED_TERMS.some((term) => normalized.includes(term));
}

function hasReviewReadyPuzzleImage(levelData) {
    const editorData = levelData?.editorData || {};
    if (typeof editorData.hasPuzzleImage === 'boolean') {
        return editorData.hasPuzzleImage;
    }

    const puzzlePath = String(levelData?.puzzlePath || '').trim();
    const solutionPath = String(levelData?.solutionPath || '').trim();
    const editorMode = String(levelData?.editorMode || 'draw_object').trim();

    if (!puzzlePath) {
        return false;
    }

    if (editorMode === 'draw_object') {
        return !!solutionPath && puzzlePath !== solutionPath;
    }

    return true;
}

function normalizeContentCategory(value, editorMode) {
    const normalized = String(value || '').trim().toLowerCase();
    if (['words', 'faces', 'characters', 'objects'].includes(normalized)) {
        return normalized;
    }

    if (editorMode === 'highlight') {
        return 'words';
    }

    if (editorMode === 'photo_sketch' || editorMode === 'photoSketch') {
        return 'faces';
    }

    return 'objects';
}

function extractBase64Payload(value) {
    const normalized = String(value || '').trim();
    if (!normalized) {
        throw new HttpsError('invalid-argument', 'A face photo is required.');
    }

    const match = normalized.match(/^data:[^;]+;base64,(.+)$/i);
    return match ? match[1] : normalized;
}

function detectImageFormat(buffer) {
    if (buffer.length >= 3 &&
        buffer[0] === 0xFF &&
        buffer[1] === 0xD8 &&
        buffer[2] === 0xFF) {
        return { contentType: 'image/jpeg', extension: 'jpg' };
    }

    if (buffer.length >= 8 &&
        buffer[0] === 0x89 &&
        buffer[1] === 0x50 &&
        buffer[2] === 0x4E &&
        buffer[3] === 0x47 &&
        buffer[4] === 0x0D &&
        buffer[5] === 0x0A &&
        buffer[6] === 0x1A &&
        buffer[7] === 0x0A) {
        return { contentType: 'image/png', extension: 'png' };
    }

    if (buffer.length >= 12 &&
        buffer.toString('ascii', 0, 4) === 'RIFF' &&
        buffer.toString('ascii', 8, 12) === 'WEBP') {
        return { contentType: 'image/webp', extension: 'webp' };
    }

    return null;
}

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

async function sanitizeUploadedFaceImage(buffer) {
    const metadata = await sharp(buffer, {
        failOn: 'error',
        limitInputPixels: MAX_IMAGE_PIXELS,
    }).metadata();

    const width = Number(metadata.width || 0);
    const height = Number(metadata.height || 0);
    if (!width || !height) {
        throw new HttpsError('invalid-argument', 'Could not read that face photo.');
    }

    if (width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION) {
        throw new HttpsError(
            'invalid-argument',
            'That face photo is too large. Please choose a smaller image.',
        );
    }

    if ((width * height) > MAX_IMAGE_PIXELS) {
        throw new HttpsError(
            'invalid-argument',
            'That face photo has too many pixels. Please choose a smaller image.',
        );
    }

    const resized = await sharp(buffer, {
        failOn: 'error',
        limitInputPixels: MAX_IMAGE_PIXELS,
    })
        .rotate()
        .resize({
            width: SANITIZED_FACE_MAX_DIMENSION,
            height: SANITIZED_FACE_MAX_DIMENSION,
            fit: 'inside',
            withoutEnlargement: true,
        })
        .webp({
            quality: 82,
            effort: 5,
        })
        .toBuffer();

    const sanitizedMetadata = await sharp(resized).metadata();
    return {
        bytes: resized,
        width: Number(sanitizedMetadata.width || 0),
        height: Number(sanitizedMetadata.height || 0),
    };
}

function buildRunpodWorkflow(prompt, difficulty) {
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
                strength: Math.max(0.1, difficulty / 5),
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
            inputs: { image: '1.png', upload: 'image' },
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

async function callRunpodProxy(path, body, bearerToken) {
    const response = await fetch(`${RUNPOD_PROXY_BASE_URL}${path}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${bearerToken}`,
        },
        body: JSON.stringify(body),
    });

    const json = await response.json();
    if (!response.ok || json.error) {
        throw new HttpsError(
            'internal',
            json.error || `RunPod proxy request failed with status ${response.status}.`,
        );
    }

    return json;
}

function extractGeneratedImage(statusData) {
    if (statusData.output && Array.isArray(statusData.output.images) && statusData.output.images[0]) {
        return statusData.output.images[0].data || statusData.output.images[0].image || '';
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
    secrets: [runpodProxyBearer],
    timeoutSeconds: 120,
}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError('unauthenticated', 'You must be signed in to generate a puzzle.');
    }

    const prompt = String(request.data?.prompt || '').trim();
    const solutionImageBase64 = String(request.data?.solutionImageBase64 || '').trim();
    const difficulty = Number(request.data?.difficulty) || 1.0;

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
    await assertCreatorCanUseUserLevels(db, uid);

    const bearerToken = runpodProxyBearer.value();
    if (!bearerToken) {
        throw new HttpsError('internal', 'The generation proxy secret is not configured.');
    }

    const payload = {
        input: {
            workflow: buildRunpodWorkflow(prompt, difficulty),
            images: [{ name: '1.png', image: solutionImageBase64 }],
        },
    };

    const runData = await callRunpodProxy('/api/generate-run', { payload }, bearerToken);
    const jobId = String(runData.id || '').trim();

    if (!jobId) {
        throw new HttpsError('internal', 'The generation backend did not return a job id.');
    }

    return { jobId };
});

exports.getUserLevelPuzzleGenerationStatus = onCall({
    secrets: [runpodProxyBearer],
    timeoutSeconds: 60,
}, async (request) => {
    if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'You must be signed in to check puzzle status.');
    }

    const jobId = String(request.data?.jobId || '').trim();
    if (!jobId) {
        throw new HttpsError('invalid-argument', 'A jobId is required.');
    }

    const bearerToken = runpodProxyBearer.value();
    if (!bearerToken) {
        throw new HttpsError('internal', 'The generation proxy secret is not configured.');
    }

    const statusData = await callRunpodProxy('/api/generate-status', { jobId }, bearerToken);
    const status = String(statusData.status || 'UNKNOWN').trim().toUpperCase();
    const imageBase64 = extractGeneratedImage(statusData);

    return {
        status,
        imageBase64,
    };
});

exports.sanitizeUserLevelUpload = onCall({
    timeoutSeconds: 60,
    memory: '512MiB',
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

    const base64Payload = extractBase64Payload(request.data?.imageBase64);
    const imageBuffer = Buffer.from(base64Payload, 'base64');
    if (!imageBuffer.length) {
        throw new HttpsError('invalid-argument', 'A face photo is required.');
    }

    if (imageBuffer.length > MAX_UPLOAD_BYTES) {
        throw new HttpsError(
            'invalid-argument',
            'That face photo is too large. Please choose a smaller image.',
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

    const sanitized = await sanitizeUploadedFaceImage(imageBuffer);
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

        const creatorName = String(levelData.creatorName || '').trim();
        const answer = String(levelData.name || '').trim();
        const editorMode = String(levelData.editorMode || 'draw_object').trim();
        const contentCategory = normalizeContentCategory(
            levelData.contentCategory,
            editorMode,
        );
        const factText = String(levelData?.hints?.fact || '').trim();
        const tooltipStart = String(levelData.tooltipStart || '').trim();
        const tooltipEnd = String(levelData.tooltipEnd || '').trim();
        const sourceImageSafetyStatus = String(
            levelData.sourceImageSafetyStatus ||
            levelData?.editorData?.sourceImageSafetyStatus ||
            '',
        ).trim().toLowerCase();
        const sourceImagePath = String(
            levelData?.editorData?.sourceImagePath || '',
        ).trim();

        if (!creatorName || answer.length < 2) {
            throw new HttpsError(
                'failed-precondition',
                'The level is missing a creator name or answer.',
            );
        }

        if (editorMode !== 'highlight' && !factText) {
            throw new HttpsError(
                'failed-precondition',
                'The level is missing a fact hint.',
            );
        }

        if ((editorMode === 'photoSketch' || editorMode === 'photo_sketch') &&
            (sourceImageSafetyStatus !== 'clean' || !sourceImagePath)) {
            throw new HttpsError(
                'failed-precondition',
                'Save this face level again so the face photo can be safety-checked before review.',
            );
        }

        if (!hasReviewReadyPuzzleImage(levelData)) {
            throw new HttpsError(
                'failed-precondition',
                'Add the actual puzzle image before submitting this level.',
            );
        }

        const profanityCheckedValues = [
            creatorName,
            answer,
            tooltipStart,
            tooltipEnd,
        ];
        if (editorMode !== 'highlight') {
            profanityCheckedValues.push(factText);
        }

        for (const value of profanityCheckedValues) {
            if (containsBlockedTerm(value)) {
                throw new HttpsError(
                    'failed-precondition',
                    'Please remove profanity before submitting this level.',
                );
            }
        }

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
            editorData: levelData.editorData || {},
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
