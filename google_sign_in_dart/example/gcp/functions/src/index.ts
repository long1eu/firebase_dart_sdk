import * as functions from 'firebase-functions';
import * as rp from "request-promise-native";
import {StatusCodeError} from "request-promise-native/errors";

const CLIENT_ID = '233259864964-go57eg1ones74e03adlqvbtg2av6tivb.apps.googleusercontent.com';
const CLIENT_SECRET = '<clientSecret>';

// noinspection JSUnusedGlobalSymbols
export const authHandler = functions.https.onRequest(async (req, res) => {
    const body = JSON.parse(req.body);
    const code = body.code;
    const token = body.refreshToken;
    const clientId = body.clientId;
    const redirectUrl = body.redirectUrl;
    const codeVerifier = body.codeVerifier;

    if (!code && !token) {
        return res
            .contentType('text/plain')
            .status(400)
            .send('no_code_or_token');
    }

    if (!clientId || code && (!codeVerifier || !redirectUrl)) {
        return res
            .contentType('text/plain')
            .status(400)
            .send('invalid_request');
    }

    if (clientId !== CLIENT_ID) {
        return res
            .contentType('text/plain')
            .status(400)
            .send('invalid_client_id');
    }

    return (code
        ? exchangeCode(code, codeVerifier, redirectUrl)
        : refreshToken(token))
        .then(value => res.send(value))
        .catch(reason => {
            if (reason instanceof StatusCodeError) {
                return res
                    .contentType('text/plain')
                    .status(400)
                    .send(reason.error);
            }
            throw reason;
        });
});

function exchangeCode(code: string, codeVerifier: string, redirectUrl: string): Promise<any> {
    return rp.post('https://oauth2.googleapis.com/token', {
        json: true,
        headers: {
            'content-type': 'application/x-www-form-urlencoded'
        },
        form: {
            code: code,
            client_id: CLIENT_ID,
            code_verifier: codeVerifier,
            client_secret: CLIENT_SECRET,
            redirect_uri: redirectUrl,
            grant_type: 'authorization_code',
        }
    });
}

function refreshToken(token: string): Promise<any> {
    return rp.post('https://oauth2.googleapis.com/token', {
        json: true,
        headers: {
            'content-type': 'application/x-www-form-urlencoded'
        },
        form: {
            refresh_token: token,
            client_id: CLIENT_ID,
            client_secret: CLIENT_SECRET,
            grant_type: 'refresh_token',
        }
    });
}