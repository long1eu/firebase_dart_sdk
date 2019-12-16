import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as rp from "request-promise-native";
import {config} from "./config";
import {StatusCodeError} from "request-promise-native/errors";

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
        }).catch(reason => {
            if (reason instanceof StatusCodeError) {
                return reason.error;
            }
            throw  reason;
        });
    } else if (data.provider === 'yahoo.com') {
        if (!data.code) {
            return new functions.https.HttpsError('invalid-argument', 'You need to provide the code.');
        }
        if (!data.redirect_uri) {
            return new functions.https.HttpsError('invalid-argument', 'You need to provide the redirect_uri.');
        }

        return rp.post('https://api.login.yahoo.com/oauth2/get_token', {
            headers: {
                'content-type': 'application/json',
            },
            json: true,
            form: {
                client_id: config.yahooClientId,
                client_secret: config.yahooClientSecret,
                redirect_uri: data.redirect_uri,
                code: data.code,
                grant_type: 'authorization_code',
            }
        })
            .catch(reason => {
                if (reason instanceof StatusCodeError) {
                    return reason.error;
                }
                throw  reason;
            });
    } else if (data.provider === 'microsoft.com') {
        if (!data.code) {
            return new functions.https.HttpsError('invalid-argument', 'You need to provide the code.');
        }
        if (!data.redirect_uri) {
            return new functions.https.HttpsError('invalid-argument', 'You need to provide the redirect_uri.');
        }

        return rp.post('https://login.microsoftonline.com/common/oauth2/v2.0/token', {
            headers: {
                'content-type': 'application/json',
            },
            json: true,
            form: {
                client_id: config.microsoftClientId,
                client_secret: config.microsoftClientSecret,
                redirect_uri: data.redirect_uri,
                code: data.code,
                grant_type: 'authorization_code',
                scope: 'openid profile email',
            }
        }).catch(reason => {
            if (reason instanceof StatusCodeError) {
                return reason.error;
            }
            throw  reason;
        });
    } else {
        return new functions.https.HttpsError('unimplemented', 'This provider is not implemented.')
    }
});
