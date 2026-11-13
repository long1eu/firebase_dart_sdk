# Production verification kit

Everything in this repository was verified against the Firestore emulator only. This kit runs a
short list of named checks against a **real** Firestore database and prints, for each one,
`PASS`, `FAIL`, `INCONCLUSIVE` or `SKIPPED` with a one-line explanation. It answers the questions
the emulator cannot answer.

The code is `cloud_firestore/cloud_firestore_dart/test/production/verify_production.dart`;
`run.sh` here is a wrapper that runs it from the right directory.

**Status of the kit itself:** it was run against the emulators only (Standard and Enterprise
edition), where the expected results are known
(`test/production/verify_production_test.dart`). It has never been run against production.
The parts that could not be exercised that way are listed under "Not verified" below.

## What it does to your project

- It writes only below one document that is unique to the run:
  `verify_production_kit/run_<utc time>_<suffix>/<collection>/<document>`. The collection ids
  below it are fixed (`vp_crud`, `vp_listen`, `vp_queries`, `vp_lost_ack`, `vp_lost_commit`,
  `vp_resume`, `vp_targets`, `vp_edition`, `vp_bson`, `vp_values`, `vp_tokens`, `vp_web`,
  `vp_lite_grpc`, `vp_lite_rest`).
- It reads only those documents. It never lists, reads or deletes anything else.
- At the end it deletes every document it could have written (also when a check failed). If the
  clean-up fails it says so and prints the path to delete by hand. `--keep` skips the clean-up.
- It prints the project, the database, the root path and the write cap first, and in production
  mode does nothing more unless `--yes` is given.
- It never reads, creates or prints credentials. Access tokens come from Application Default
  Credentials through `package:grpc` and are only passed to the transport.

Use a throwaway project or a test database if you can. Requests made with a service account
bypass security rules.

## Cost and quotas

| | per full run |
| --- | --- |
| document writes | 54 on the emulator; capped at 80 (`--max-writes=N`), the run stops a check before it would exceed the cap |
| document deletes | one per document of the run, about 27 (the clean-up; not counted against the cap) |
| document reads | normally under 200; a few hundred more when a check has to wait and poll |
| listen streams | about 15 short-lived listeners |
| duration | about 5 s on the emulator; allow a few minutes |

This is far below the daily free quota (20,000 writes, 50,000 reads). On a billed database it
costs a fraction of a cent. Check 1c may need one composite index (see below); an index is free
to create but takes a minute or two to build.

## Commands

Prerequisites: the Dart SDK, and for production one of

    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json   # role: Cloud Datastore User
    # or: gcloud auth application-default login

Production (from the repository root):

    unset FIRESTORE_EMULATOR_HOST                 # the kit refuses to guess between the two
    export FIRESTORE_TEST_PROJECT_ID=my-project
    export FIRESTORE_TEST_DATABASE_ID=my-database # optional, default: (default)
    export FIREBASE_TEST_WEB_API_KEY=...          # optional: runs check 13 (creates and deletes one anonymous Auth user)

    tool/verify_production/run.sh --backend=production          # prints the plan, does nothing
    tool/verify_production/run.sh --backend=production --yes    # runs it
    tool/verify_production/run.sh --backend=production --yes --only=2,3   # single checks

Save the report: `... --yes | tee verify_production_report.txt`. It contains the project id, the
database id and document paths, and no credentials.

Emulator (to see what a run looks like, or to check the kit):

    tool/start_emulator.sh
    FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 tool/verify_production/run.sh --backend=emulator

Other options: `--list` (the checks), `--max-writes=N`, `--keep`.

Exit code: 0 when no check failed, 1 when at least one check is `FAIL`, 2 for a usage error or
when `--yes` is missing.

## The checks and how to read them

`PASS` means the behaviour was observed and the SDK handled it. For the checks that ask a
question (2, 3, 6) the **answer is the first word of the line** (`DEDUPLICATED` / `APPLIED TWICE`,
`STANDARD` / `ENTERPRISE`): both answers are a `PASS` as long as no write was lost and the cache
agrees with the backend. `FAIL` means the SDK misbehaved or the backend does something the SDK
does not handle. `INCONCLUSIVE` means the check could not reach a result and says what to do.
`SKIPPED` means it does not apply to this database.

| id | check | what a result means |
| --- | --- | --- |
| 1a | Basic CRUD | set, get, update with `increment` and `arrayUnion`, server timestamp, delete. |
| 1b | Listeners | A document and a collection listener see adds, updates and deletes of another client. |
| 1c | Queries and composite indexes | Filters, order, limit, OR, `count()`. Then a query that needs a composite index on collection id `vp_queries` (`a` ascending, `b` descending, collection scope). If the index is missing the check is `INCONCLUSIVE` and prints the console link the backend returned: open it, create the index, wait until it is built, run `--only=1c` again. The index serves every later run. |
| 2 | Lost write acknowledgement (F1) | A TCP proxy holds back the answers of the backend and cuts the connection after the backend applied `increment(1)`; the client sends the write again. `DEDUPLICATED` (n == 1): production does not apply a re-sent write twice. `APPLIED TWICE` (n == 2): writes are at-least-once, as on the emulator, and `increment` can be counted again after a lost acknowledgement. `FAIL`: a write was lost, or the cache disagrees with the backend afterwards. |
| 3 | Lost commit answer (F2) | The same for a transaction commit. `APPLIED ONCE` or `APPLIED TWICE` (the retry ran the body on top of its own first commit; emulator and the other SDKs do this). `FAIL`: the transaction was lost. |
| 4 | Resume from snapshot JSON | `querySnapshotsFromJson` with the read time of the snapshot unchanged, 2 hours old and 8 days old. `PASS`: the listener gets in sync each time. `FAIL` with the error of the backend: it rejects an old read time and the SDK needs a fallback to a full listen; the detail lines say for which age. |
| 5 | Target ids from 1000 up | A raw Listen with the target ids the SDK uses (1002, 1003) and the largest 32-bit ones. `FAIL`: the backend rejects them. |
| 6 | Null and NaN in filters | `array-contains`, `array-contains-any` and `in` with `null` and `NaN`. `STANDARD`: they never match. `ENTERPRISE`: they match. `INCONCLUSIVE`: neither profile of the emulators; update the "Enterprise edition differences" section of `docs/guides/emulator_and_testing.md`. `FAIL`: with the documents in the cache, a server read does not complete or returns something else than the backend alone does (see "Known results" below). The detail lines also list where a query answered from the cache alone differs from the backend. |
| 7 | BSON numeric increment | Only on a database that behaves like Enterprise in check 6. `increment` on a `Decimal128Value` and an `Int32Value` must add. |
| 8 | -0.0 and empty bytes | Written over gRPC and over the web transport, read back over both. `FAIL` lists the combination that lost the sign or the type. |
| 9 | Half-close timing after unlisten | How long the backend takes to end a Listen stream after the client unlistened and half-closed (three samples, in ms). The SDK waits 10 s before it resets the call; `FAIL` when the backend takes longer or ends the stream with an error. |
| 10 | Auth token acceptance | Requests with the OAuth access token are served; the detail line says what the same read without a token gets. App Check is not covered: the kit has no App Check token provider. `SKIPPED` on the emulator. |
| 11 | Web transport | The experimental web transport (REST unary calls and WebChannel streams over `dart:io` HTTP) against the same database: read, transaction, aggregation, listen, batch. The detail lines list the endpoints used and whether the backend asked for session routing (`gsessionid`). |
| 12 | Firestore Lite over gRPC and REST | The lite library (`package:cloud_firestore_dart/lite.dart`, no cache, no listeners), once over gRPC and once over the transport it has on the web (REST only): set, get, update with transforms, a batch, queries (filter, `limitToLast`, cursor), an aggregation with aliases, a transaction, a read-only transaction with a query (`BeginTransaction` / `Rollback`), delete. `FAIL` names the transport and the step, or says that a client did not use the transport it was asked for (the REST client must not open a WebChannel session). The detail line lists the REST calls used. The clients are made through the public API; their requests carry the credentials of the kit, not those of a `FirebaseApp`. |
| 13 | Firebase Auth user token (optional) | Only when `FIREBASE_TEST_WEB_API_KEY` is set (the Web API key of the project; the Anonymous sign-in provider must be enabled). Signs in an anonymous user with `firebase_auth_providers_dart` against the real Firebase Auth service, reads one document of the run with the ID token, and deletes the account again. `PASS`: Firestore accepted the token; the line says whether the security rules then served or refused the read (both are a pass). `FAIL`: the token itself was refused. `INCONCLUSIVE`: the sign-in failed (provider not enabled, wrong key). `SKIPPED` without the variable. On the emulator it runs when `FIREBASE_AUTH_EMULATOR_HOST` is set. |

What to send back: the whole report. The most valuable lines are the answers of 2, 3, 4, 6, 8, 9,
11 and 12, which nobody has seen for production yet.

## Known results on the emulators

| id | Standard emulator | Enterprise emulator |
| --- | --- | --- |
| 1a, 1b, 5, 9, 11 | PASS | PASS |
| 12 | PASS | PASS |
| 13 | SKIPPED; PASS with the Auth emulator (`tool/start_auth_emulators.sh`) | not run |
| 1c | PASS (the emulator needs no index) | PASS (one unexplained FAIL in six runs while other test suites used the emulator; not reproduced) |
| 2 | PASS, `APPLIED TWICE` | PASS, `APPLIED TWICE` |
| 3 | PASS, `APPLIED TWICE`, 2 attempts | PASS, `APPLIED TWICE` |
| 4 | PASS (the emulator accepts any read time) | PASS |
| 6 | PASS, `STANDARD` | PASS, `ENTERPRISE` |
| 7 | SKIPPED | **FAIL**: the emulator (v1.22.0) replaces the field with the operand |
| 8 | **FAIL**: -0.0 written over the web transport comes back as 0.0 | **FAIL**, the same |
| 10 | SKIPPED | SKIPPED |

The failures are real and not about the kit:

- **8:** the emulator's JSON front end stores `-0` as `0` (also for a plain REST request with
  `"doubleValue": "-0"`). Whether production does the same is what the check is for.
- **7 on Enterprise:** emulator behaviour; the check is for a production Enterprise database.

Check 6 on Standard used to fail: the SDK itself matches `null` and `NaN` in `in`,
`array-contains` and `array-contains-any` (the Enterprise behaviour), the Standard backend does
not, and with the documents in the cache a server read of such a query did not complete. The
sync engine now drops a limbo document that the backend confirms but does not match (4c72e9ea),
so the server read returns what the backend returns and the check passes. Its detail lines still
list the difference that remains: a query answered from the cache alone (`get(Source.cache)`)
returns those documents on a Standard database. If check 6 fails on a production Standard
database, that fix does not hold there.

## Not verified

- **TLS through the proxy (checks 2 and 3)** was verified locally, not against production:
  `test/production/proxy_tls_test.dart` puts the proxy in front of a `package:grpc` server with
  a self-signed certificate and uses the channel of the kit (`proxiedGrpcChannel`). The client
  dials the proxy with the name of the server for SNI, certificate verification and the call
  authority; a wrong name or an untrusted certificate is rejected; holding back answers or
  requests and cutting ends the call exactly as on plain TCP, and the next call reconnects.
  What remains unverified is only Google's front end itself. If it does not work there, the
  checks report `INCONCLUSIVE` ("could not write through the TCP proxy").
- **Application Default Credentials end to end.** The token plumbing is unit-tested with a fake
  authenticator; no real token was ever fetched by this code.
- **The web transport against production** (check 11) and with an OAuth token. The same holds for
  Firestore Lite (check 12): its REST transport was never used with TLS or a token, and the
  read-only transaction of the check (`BeginTransaction`, `Rollback`) was only run on the emulator.
- **The index link** of check 1c: the kit looks for a `https://console...` link in the error
  message; if the backend words it differently the message is printed as is.
- The edition of the database is inferred from check 6; the kit cannot ask the backend for it.
