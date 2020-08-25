# OAuth2 code exchange endpoint

In order to keep the user logged in, we need an `refresh_token` from
Google. This token is obtained by exchanging the `code` we receive when
the user logs in. This operation requires your app to be identified by
Google using a `Client ID` and a `Client Secret`. The `Client ID` must
be shared with you client app and it's used to create the initial
authentication request. The `Client Secret` on the other hand, can not
be shared due to the fact that the app cannot keep the `Client Secret`
confidential. This is why you need to create an endpoint in a trusted
environment (eg. Cloud Function, server), one that can keep both the
`Client Secret` confidential, to do the code exchange.

The package is going to make the following two types of request to the
same endpoint:
 

1. Code exchange
     ```http request
     POST <endpoint>
     Content-Type: application/json
     
     {
       "code": "<code>",
       "codeVerifier": "<codeVerifier>",
       "clientId": "<clientId>",
       "redirectUrl": "<redirectUrl>"
     }
     ```
     You are expected to make a request to the Google `token` endpoint
     with `grant_type` field set to `authorization_code`. Return the
     response to the initial request.
     ```http request
     POST /token HTTP/1.1
     Host: oauth2.googleapis.com
     Content-Type: application/x-www-form-urlencoded
     
     code=<code>&
     client_id=<clientId>&
     client_secret=<clientSecret>&
     redirect_uri=<returnUrl>&
     code_verifier=<codeVerifier>&
     grant_type=authorization_code
     ```        
    
1. Refresh token
   ```http request
   POST <endpoint>
   Content-Type: application/json
   
   {
     "refreshToken": "<refreshToken>",
     "clientId": "<clientId>"
   }
   ```                
   In this case make a request to the same endpoint but with `grant_type` field set to `refresh_token`. Return
    the response to the initial request.
     ```http request
     POST /token HTTP/1.1
     Host: oauth2.googleapis.com
     Content-Type: application/x-www-form-urlencoded
     
     client_id=<clientId>&
     client_secret=<clientSecret>&
     refresh_token=<refresh_token>&
     grant_type=refresh_token
     ```        
    
## Example

You can have a look at `functions` to see how this can be implemented with Google Cloud Function.