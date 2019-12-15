import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as rp from "request-promise-native";
import {config} from "./config";

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

export const handler = functions.https.onCall(async (data, context) => {
    if (data.provider === 'github.com') {
        if (!data.code) {
            return new functions.https.HttpsError('invalid-argument', 'You need to provide the code.');
        }

        return rp.post('https://github.com/login/oauth/access_token', {
            json: true,
            body: {
                client_id: config.githubClientId,
                client_secret: config.githubClientSecret,
                code: data.code,
            }
        });
    } else {
        return new functions.https.HttpsError('unimplemented', 'This provider is not implemented.')
    }
});
