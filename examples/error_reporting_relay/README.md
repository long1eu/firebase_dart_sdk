# error_reporting_relay

A relay for [`firebase_error_reporting_dart`](../../firebase_error_reporting/firebase_error_reporting_dart/) on
`package:shelf`. An app sends each error report to it with `ErrorReportingTransport.relay(url)`; the relay
checks the request with [`relay_guard`](../relay_guard/) and forwards the report to Cloud Error Reporting
(`projects.events.report`) with the server's own service account. No credential of the project ships in the
app.

What it does with each report:

1. `relayGuard` refuses it unless it has a valid App Check token, a valid ID token when one is sent, a body of
   at most 64 KiB, and the caller is under 60 reports a minute.
2. The `serviceContext.service` must be in `SERVICES`; the version must look like a release (`1.4.0`).
3. The report is rebuilt from the fields the relay trusts: `eventTime` (dropped unless within the last 30 days
   or the next hour), `message` (cut at 32 KiB), `serviceContext`, `context.reportLocation` and
   `context.httpRequest` (fields cut at 2 KiB, `remoteIp` left out). Anything else is dropped.
4. `context.user` is the uid of the verified ID token, never what the app wrote.
5. Error Reporting's answer becomes 204, 400, or 503 with `Retry-After` (when Error Reporting or the relay's own
   credential failed), which the client retries.

## Run it

```
export PROJECT_ID=my-project
export SERVICES=notes-desktop,notes-web
dart run bin/relay.dart
```

The forwarding credential is Application Default Credentials. On Cloud Run, give the service its own service
account with the role Error Reporting Writer (`roles/errorreporting.writer`) and nothing else, and enable the
Error Reporting API in the project. `PROJECT_NUMBER` makes the App Check check exact; `REQUIRE_APP_CHECK=false`
accepts requests without App Check, for development only. Nothing in this repository creates the service
account or grants the role.

```
dart test        # MockClient; no emulator, no request to Google
```
