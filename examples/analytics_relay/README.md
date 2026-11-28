# analytics_relay

A relay for [`firebase_analytics_dart`](../../firebase_analytics/firebase_analytics_dart/) on `package:shelf`.
An app sends its events to it with `AnalyticsTransport.relay(url)`; the relay checks the request with
[`relay_guard`](../relay_guard/), checks the shape of the Measurement Protocol body, and forwards it to Google
Analytics with the API secret of the stream.

## Why a relay

Every Measurement Protocol request needs an API secret of the GA4 data stream, and Google says to keep it
private. An app on a user's machine cannot: anyone can pull the secret out of the binary or watch it leave, and
then send whatever events they like into the property. So the secret stays on a server you run, and the app
proves who it is with App Check (and, when a user is signed in, an ID token) instead.

```dart
final FirebaseAnalytics analytics = FirebaseAnalytics(
  app, // with app.appCheckProvider set
  transport: AnalyticsTransport.relay(Uri.parse('https://relay.example.com/collect')),
);
```

## What it does with each request

On `POST /collect` only:

1. `relayGuard` refuses it unless it has a valid App Check token, a valid ID token when one is sent (or always,
   with `REQUIRE_USER=true`; analytics is often anonymous, so by default it is not required), a body of at most
   128 KiB that arrives within 10 seconds, and the rate limits have room (60 a minute per App Check token and
   per user, 600 per app, 3000 in all, per instance; `MAX_PER_CALLER`, `MAX_PER_APP` and `MAX_PER_MINUTE`
   change them). A refreshed App Check token starts a new per-token budget, so for an app whose users are
   anonymous the per-app limit is what bounds one install that misbehaves; where users sign in, set
   `REQUIRE_USER=true` and the per-user limit applies too. The client sends at most 130,000 bytes per request,
   about one request every five seconds while events come in.
2. With `ALLOWED_APP_IDS`, the app id of the verified App Check token must be one of them; otherwise 403,
   which the client keeps, so a typo in the list does not drop a real app's events.
3. The query may hold only `measurement_id`, which the client always adds, and it must equal
   `GA_MEASUREMENT_ID`. An `api_secret` there is refused with 400; anything else with 403, which the client
   keeps until the app's relay URL and the relay's settings agree.
4. The body must be a JSON object of at most 130,000 bytes with a string `client_id` and an `events` list of 1
   to 25 objects, each with a `name`; a body that holds `api_secret` or `measurement_id` is refused. Otherwise
   400 (or 413). The relay does not judge the events further (the client validates them) and never rewrites
   `client_id`.
5. The body goes to `https://www.google-analytics.com/mp/collect` (or `region1.google-analytics.com` with
   `GA_REGION=eu`) with the measurement id and the secret from the environment. None of the caller's headers
   go with it. Google Analytics gets 10 seconds; no redirect is followed and the relay does not retry: the
   client does.
6. The answer becomes 204 when Google took it; 400 when Google refused the body itself (400, 413 or 422);
   503 with `Retry-After` for anything else: a 5xx, a 429, a redirect, a 4xx such as the 401 or 404 of a
   wrong secret or path (a fault of the relay, not of the events), a network error or a timeout. The client keeps the events on 401, 403, 408, 429 and 5xx and
   tries again later, and drops a batch on any other 4xx, so a request that can never succeed does not loop.
   `test/contract_test.dart` runs the client against the relay to pin this.

No answer has a body, and the log holds statuses and error types only: never the secret, never the upstream URL.
`test/relay_test.dart` checks that the secret appears in no answer and no log line.

## Run it

```
export GA_MEASUREMENT_ID=G-XXXXXXXXXX
read -rs GA_API_SECRET && export GA_API_SECRET   # typed, so it stays out of the shell history
export PROJECT_ID=my-project
dart run bin/relay.dart
```

For a local try with a client on the same machine, `HOST=127.0.0.1 REQUIRE_APP_CHECK=false` accepts requests
without App Check (the client may then use `http://127.0.0.1:8080/collect`). Events still go to the real stream:
use a stream made for testing.

| Variable | Meaning |
| --- | --- |
| `GA_MEASUREMENT_ID` | the `G-…` id of the GA4 web data stream |
| `GA_API_SECRET` | a Measurement Protocol API secret of that stream (Admin > Data streams > the stream > Measurement Protocol API secrets) |
| `GA_REGION` | optional: `eu` collects at `region1.google-analytics.com` |
| `PROJECT_ID` | the Firebase project whose App Check and ID tokens are accepted |
| `PROJECT_NUMBER` | optional: makes the App Check check exact; checked at start |
| `ALLOWED_APP_IDS` | optional: the Firebase app ids that may send, comma-separated |
| `REQUIRE_USER` | `true` accepts only requests with a valid ID token; `false` (the default) also anonymous ones. Any other value stops the relay at start |
| `TRUSTED_PROXY_HOPS` | proxies in front of the relay that append to `X-Forwarded-For` (1 on Cloud Run) |
| `MAX_PER_CALLER`, `MAX_PER_APP`, `MAX_PER_MINUTE` | optional: requests a minute per App Check token and per user (60), per app (600) and in all (3000), per instance |
| `REQUIRE_APP_CHECK` | `false` accepts requests without App Check: development only, refused unless `HOST` is loopback |
| `HOST`, `PORT` | where to listen (default `0.0.0.0:8080`) |

## Deploy

An outline for Cloud Run; nothing in this repository creates the service, the secret or a role binding.

1. Create an API secret for the stream in Google Analytics and store it in Secret Manager.
2. Deploy the relay with its own service account, which needs no role other than Secret Manager Secret
   Accessor on that one secret (checking tokens needs no credential). Pass the secret with
   `--set-secrets GA_API_SECRET=<secret>:latest`, never as a plain environment variable or a build argument.
3. Set `GA_MEASUREMENT_ID`, `PROJECT_ID`, `PROJECT_NUMBER`, `ALLOWED_APP_IDS` and `TRUSTED_PROXY_HOPS=1`;
   `--timeout=30`; and choose `--concurrency` and `--max-instances` so that a flood cannot scale it without
   bound (the rate limits are per instance).
4. Turn on App Check enforcement for your apps, and point the client at `https://<service URL>/collect`.

```
dart test        # MockClient; no emulator, no request to Google
```

Not done: App Check replay protection (`consumeAppCheckToken`); tying the body's `user_id` to the verified uid;
per-user or per-client quotas across instances; a production verification kit (step 6 of
`docs/analytics_spec.md`).
