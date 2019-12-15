import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const buildUrl = require("build-url");

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

export const handler = functions.https.onRequest((request, response) => {


    // Auth response for facebook. The only reason for having this is the fact that facebook doesn't allow redirects
    // to localhost. This is needed to the cli example app.
    if (request.hostname.includes('facebook.com') && request.query.continue_uri) {
        const redirectUrl = buildUrl(decodeURIComponent(request.query.continue_uri), {queryParams: request.query,});
        console.log(`redirectUrl: ${redirectUrl}`);
        response.redirect(redirectUrl);
    } else {
        response.status(403).send('Forbidden');
    }
});
