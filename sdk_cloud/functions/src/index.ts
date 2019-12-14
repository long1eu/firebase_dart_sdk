import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

export const createCustomToken = functions.https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid || !context.auth.token) {
        return new functions.https.HttpsError('unauthenticated', 'You need to be authenticated to call this endpoint.');
    }

    const uid = context.auth.uid;
    const customClaims = data || {};
    console.log(`creating custom token for ${uid} with custom claims: ${JSON.stringify(customClaims)}`);

    const result = await admin.auth().createCustomToken(uid, customClaims);
    console.log(`result: ${result}`);
    return result;
});
