const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { HttpsError, logger } = require('firebase-functions/v2');
const admin = require('firebase-admin');
admin.initializeApp();

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
