# Storage production verification kit

`firebase_storage_dart` was verified against the Storage emulator only. This kit runs named checks
against a **real** Cloud Storage for Firebase bucket and prints, for each one, `PASS`, `FAIL`,
`INCONCLUSIVE` or `SKIPPED` with a one-line explanation. It answers what the emulator cannot: real
error bodies and codes, `Range`, download tokens, paging tokens, the resumable protocol, App Check,
the refresh after a 401 and CORS.

The code is `firebase_storage/firebase_storage_dart/test/production/verify_production.dart`;
`run.sh` here runs it from the right directory. It is modelled on `tool/verify_production` (Firestore).

**Status of the kit itself:** it runs against the Storage emulator, where the result of every check is
known (`test/production/verify_production_test.dart`). It has been run once against a real project with a
signed-in throwaway user (`--create-user`): 19 of 20 checks passed and check 13 was inconclusive.

## What it does to your project

- It writes only below one prefix that is unique to the run: `verify_storage_kit/run_<utc>_<suffix>/`
  in the bucket you name. It lists only that prefix and deletes only objects below it.
- At the end it deletes everything it could have written, also when a check failed. If the clean-up
  fails it says so and names the prefix to delete by hand. `--keep` skips the clean-up.
- It prints the project, bucket and prefix first. Against production it does nothing more without
  `--yes`.
- It uploads at most `--max-bytes` in total (default 64 MiB, counted per upload); a check that would pass
  the cap stops before it uploads and is `INCONCLUSIVE`. A full run uploads about 11 MiB.
- Credentials: it never reads or prints any. Requests carry no user, or, with `--create-user`, the token
  of a throwaway user the kit signs up itself (`storage-verify-<run>@example.com`, a random password that
  lives in memory and is never printed or stored). It signs in through `FirebaseUserAuth`
  (`firebase_auth_providers_dart`) and deletes that user at the end through the same client, also when
  checks failed. If the deletion fails it prints the uid to delete by hand. Nothing is read from files, no
  service account is used, and the URI of a resumable session (a bearer capability) is never printed.
- The only other resource it creates is that user (Auth) and the objects under the prefix (Storage).

Use a throwaway project or bucket if you can. The rules of the bucket must let the user (or anyone, with
no user) write, read and delete under `verify_storage_kit/`; otherwise checks end `INCONCLUSIVE` with
`unauthorized`.

## Commands

Production, from the repository root:

    unset FIREBASE_STORAGE_EMULATOR_HOST                      # the kit refuses to guess between the two
    export FIREBASE_TEST_PROJECT_ID=my-project
    export FIREBASE_TEST_STORAGE_BUCKET=my-project.firebasestorage.app
    export FIREBASE_TEST_APP_ID=1:123:web:abc                  # optional: the X-Firebase-GMPID the checks send
    # for --create-user (checks 13 and 20, and buckets whose rules need a user; the Email/Password
    # sign-in provider must be enabled):
    export FIREBASE_API_KEY=...                                # the Web API key, or --api-key=

    tool/verify_production_storage/run.sh --backend=production          # prints the plan, does nothing
    tool/verify_production_storage/run.sh --backend=production --yes    # runs it
    tool/verify_production_storage/run.sh --backend=production --yes --only=3,7

Options: `--bucket=NAME` (instead of the variable), `--denied-bucket=NAME` (a bucket whose rules refuse
requests without a user: check 2 needs one, else it is `SKIPPED`; the check only tries to write one tiny
object there without a user, and deletes it if the write was wrongly accepted), `--create-user`,
`--api-key=KEY`, `--only=1,2`, `--max-bytes=N`, `--keep`,
`--list`.

Save the report: `... --yes | tee verify_storage_report.txt`. It holds the project, the bucket and the
prefix, and no credentials.

Emulator (to see a run, or to check the kit):

    STORAGE_HUB_PORT=9499 STORAGE_LOGGING_PORT=9599 tool/start_storage_emulator.sh 9399
    AUTH_HUB_PORT=9498 AUTH_LOGGING_PORT=9598 tool/start_auth_emulators.sh 9398 9397
    export FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9399 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9398
    tool/verify_production_storage/run.sh --backend=emulator --create-user \
      --denied-bucket=demo-test-auth.appspot.com
    (cd firebase_storage/firebase_storage_dart && dart test test/production)   # the kit's own test
    tool/stop_storage_emulator.sh 9399; tool/stop_auth_emulators.sh 9398 9397

`--help` prints every option. Exit code: 0 when no check failed, 1 when one is `FAIL`, 2 for a usage error
(a missing variable, a bad value) or when `--yes` is missing, 64 for an unknown flag.

## The checks and how to read them

For the checks that ask a question the **answer is the first word of the line** (`HONOURED` / `IGNORED`,
`ACCEPTED` / `ENFORCED`, `VERIFIED` / `NOT VERIFIED`, ...): both answers are a `PASS` as long as the client
copes. `FAIL` means the client misbehaved or the backend does something it does not handle. Checks 1 and
14 are strict only on production: on the emulator a difference there is `INCONCLUSIVE`.

| id | check | what a result means |
| --- | --- | --- |
| 1 | Missing object | A raw GET of a missing object answers 404 with the JSON envelope `{"error": {"code": 404, ...}}` (`JSON ENVELOPE`), and the SDK reports `object-not-found` with the status and body. `PLAIN BODY` is what the emulator sends. |
| 2 | Under rules | Needs `--denied-bucket`. A write without a user answers 403 with a JSON envelope and the SDK reports `unauthorized`. `FAIL` if the write is accepted. |
| 3 | Range | A control read without `Range`, then `Range: bytes=10-19` on `alt=media`, both with the user's token: `HONOURED` (206 and the right 10 bytes) or `IGNORED` (200 and the whole object); also the answer for a range past the end. `REFUSED` (INCONCLUSIVE) when the ranged read answers 403 although the control read is served. |
| 4 | Download token | A new object has a download token, and `downloadUrl()` serves it without credentials. The answer to a wrong token is reported (a bucket with public read rules serves it too). |
| 5 | List paging | Pages of 2 over 3 objects and 1 prefix: a `nextPageToken`, no repeats beyond prefixes, the last page has none. Its length and character class are reported (never the token). |
| 6 | Multipart | `putBytes`: size, content type and the md5Hash equal the local ones. |
| 7 | Resumable | Raw protocol: start (`x-goog-upload-status: active`), three chunks of 256 KiB, `upload, finalize`, stored size and md5. |
| 8 | Pause and resume | The second chunk is aborted in flight; a `query` says how much the server has (a 5xx, 408 or 429 answer is retried up to four times, as the SDK would, and the line says so); the upload goes on from there. |
| 9 | Resume by session URI | A new connection that knows only the session URI queries and finishes the upload. |
| 10 | md5Hash integrity | A multipart upload with a wrong `md5Hash` in the metadata: `VERIFIED` (rejected) or `NOT VERIFIED` (accepted; the client must compare the returned hash). The right hash is always accepted. |
| 11 | App Check header | The SDK sends `X-Firebase-AppCheck` with a token that is not valid: `ACCEPTED` (not enforced) or `ENFORCED` (refused, the SDK reports `unauthorized-app`). A real App Check token is not covered. |
| 12 | X-Firebase-GMPID | The SDK sends the app id on every request; the answer without the header is reported. |
| 13 | Refresh after a 401 | Needs `--create-user`. The first token is one the backend refuses (401); the SDK asks for a forced refresh and the retry is served. `INCONCLUSIVE` when the backend does not answer 401 to it: production answers 403 (`unauthorized`), so the refresh path is not reached. |
| 14 | CORS | Starts a real resumable session from a browser `Origin` with the user's token, then queries it. Every `x-goog-upload-*` header those responses carry must be in `access-control-expose-headers`; a preflight to the returned upload URL must allow `x-goog-upload-command` and `x-goog-upload-offset`. The line and details report exactly what is exposed and allowed. |
| 15 | Retry on a 5xx | Two 503 answers are **simulated in the client** and never reach the backend; the SDK retries and the third attempt is served. A real 5xx cannot be provoked safely. |
| 16 | SDK resumable | `Reference.startUpload` over 256 KiB: a session, progress events, stored size and md5. |
| 17 | SDK pause and resume | `UploadTask.pause()` then `resume()` finishes the upload. `INCONCLUSIVE` if it finished before it could be paused. |
| 18 | SDK session resume | A second task started with `existingSessionUri` of a paused one finishes the upload. |
| 19 | SDK download | `getBytes`, `openRead(100, 200)`, an open-ended `openRead`, `maxSize` too small (`download-size-exceeded`) and equal to the size. |
| 20 | Signed-in round trip | Needs `--create-user`. As the throwaway user, upload, read, describe, list and delete an object (in `--denied-bucket` when given, else the main bucket); with `--denied-bucket` the same read without a user must answer `unauthorized`. With check 2 (the signed-out 403) it covers the rules in both directions. |
| 21 | Out-of-order chunk | A resumable session for 768 KiB gets the second chunk first (`X-Goog-Upload-Offset: 262144`). `REFUSED` (PASS): a 4xx or size received stays 0 (the line shows the status, headers and a body snippet), and the session then takes the chunks in order and the stored size and md5 match. `FAIL` (`ACCEPTED`): size received becomes 524288, the early bytes were taken as valid. `INCONCLUSIVE` otherwise, e.g. the emulator, which ignores offsets. |

What to send back: the whole report. The most valuable lines are the answers of 1, 2, 3, 10, 11 and 14,
and the results of 8, 9, 13, 17 and 18.

## Known results

Emulator: `demo-test.appspot.com` open, `demo-test-auth.appspot.com` with rules that need a user.
Production: one run against a real project with a signed-in throwaway user; no project, account or bucket is
named here.

| id | emulator | production |
| --- | --- | --- |
| 1 | INCONCLUSIVE: plain `Not Found` body | PASS, `JSON ENVELOPE` |
| 2 | PASS: 403 with an envelope | PASS |
| 3 | PASS, `HONOURED`; the past-the-end range answers 200 | PASS, `HONOURED`: 206 for the range, 416 past the end |
| 4 | PASS; a wrong token is served (the emulator does not check it) | PASS |
| 5 | PASS (the emulator repeats the prefix on every page; its token has other characters) | PASS; the page token is 72 base64 characters |
| 6-9 | PASS | PASS |
| 10 | PASS, `NOT VERIFIED` | PASS, `NOT VERIFIED`: production stores the real hash of the data, so the client compares the returned `md5Hash` |
| 11, 12 | PASS, `ACCEPTED` and `SENT` | PASS, `ACCEPTED` and `SENT`: both headers are accepted |
| 13 | SKIPPED without `--create-user` | INCONCLUSIVE: an invalid ID token gets 403 (`unauthorized`), not 401, so the refresh path is not reached |
| 14 | PASS | PASS: the preflight answers `access-control-allow-origin: *` and the session responses echo the request origin; the `x-goog-upload-*` headers are exposed on the session responses; the preflight to the upload URL allows `x-goog-upload-command` and `x-goog-upload-offset` |
| 15 | PASS (simulated 503s, about 6 s of backoff) | PASS |
| 16-19 | PASS | PASS |
| 20 | SKIPPED without `--create-user`; PASS with it and the Auth emulator | PASS |
| 21 | INCONCLUSIVE: the emulator ignores offsets and appends the early chunk | PASS, `REFUSED`: HTTP 400 "Client uploaded to the wrong offset (262144 instead of 0).", size received stays 0, then the chunks in order are stored |

Upload progress is per byte on the VM and per chunk on the web.

## Not verified

- The kit against more than one real project.
- App Check with a real token; the kit has no App Check token provider.
- A real 5xx of the backend (check 15 simulates it).
- Browser behaviour: check 14 reads the CORS headers, no browser is involved.
- Quotas, large objects (the cap is 64 MiB) and sessions that expire.
