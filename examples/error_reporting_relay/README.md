# error_reporting_relay

A relay for [`firebase_error_reporting_dart`](../../firebase_error_reporting/firebase_error_reporting_dart/) on
`package:shelf`. An app sends each error report to it with `ErrorReportingTransport.relay(url)`; the relay
checks the request with [`relay_guard`](../relay_guard/) and forwards the report to Cloud Error Reporting
(`projects.events.report`) with the server's own service account. No credential of the project ships in the
app.

What it does with each report, on `POST /errors` only:

1. `relayGuard` refuses it unless it has a valid App Check token, a valid ID token when one is sent, a body of
   at most 64 KiB that arrives within 10 seconds, and the rate limits have room.
2. The `serviceContext.service` must be in `SERVICES`, and with `APP_SERVICES` one of the services of the
   caller's verified app; otherwise 422. The version must look like a release (`1.4.0`).
3. The report is rebuilt from the fields the relay trusts: `eventTime` (dropped unless RFC 3339 with a zone,
   within the last 30 days or the next hour), `message` (control characters other than line breaks and tabs
   removed, cut at 32 KiB), `serviceContext`, `context.reportLocation` and `context.httpRequest` (control
   characters removed, fields cut at 2 KiB, `remoteIp` left out). Anything else is dropped.
4. `context.user` is the uid of the verified ID token, never what the app wrote.
5. Error Reporting gets 10 seconds; after a 401 the relay retries once with a refreshed token. Its answer
   becomes 204, 400 (Error Reporting refused the event), or 503 with `Retry-After` for anything that is not the
   event's fault (a refused credential, a wrong project, an outage). The client drops events on 400 and 422 and
   keeps them on 503 and 401; `test/contract_test.dart` runs the client against the relay to pin this.

## Run it

```
export PROJECT_ID=my-project
export SERVICES=notes-desktop,notes-web
dart run bin/relay.dart
```

The forwarding credential is Application Default Credentials. On Cloud Run, give the service its own service
account with the role Error Reporting Writer (`roles/errorreporting.writer`) and nothing else, enable the Error
Reporting API in the project, set `--timeout=30`, and choose `--concurrency` and `--max-instances`. Nothing in
this repository creates the service account or grants the role.

| Variable | Meaning |
| --- | --- |
| `PROJECT_ID` | the project |
| `SERVICES` | the allowed services, comma-separated |
| `APP_SERVICES` | optional: `service@appId` pairs, so each app reports only as its own services |
| `PROJECT_NUMBER` | optional: makes the App Check check exact; checked at start |
| `TRUSTED_PROXY_HOPS` | proxies in front of the relay that append to `X-Forwarded-For` (1 on Cloud Run) |
| `REQUIRE_APP_CHECK` | `false` accepts requests without App Check: development only, refused unless `HOST` is loopback |
| `HOST`, `PORT` | where to listen (default `0.0.0.0:8080`) |

```
dart test        # MockClient; no emulator, no request to Google
```
