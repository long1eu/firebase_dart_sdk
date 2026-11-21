# Storage production verification kit

`firebase_storage_dart` was verified against the Storage emulator only. This kit runs named checks
against a **real** Cloud Storage for Firebase bucket and prints, for each one, `PASS`, `FAIL`,
`INCONCLUSIVE` or `SKIPPED` with a one-line explanation. It answers what the emulator cannot: real
error bodies and codes, `Range`, download tokens, paging tokens, the resumable protocol, App Check,
the refresh after a 401 and CORS.

The code is `firebase_storage/firebase_storage_dart/test/production/verify_production.dart`;
`run.sh` here runs it from the right directory. It is modelled on `tool/verify_production` (Firestore).

**Status of the kit itself:** it runs against the Storage emulator, where the result of every check is
known (`test/production/verify_production_test.dart`). It has **not** been run against a real project.

## What it does to your project

- It writes only below one prefix that is unique to the run: `verify_storage_kit/run_<utc>_<suffix>/`
  in the bucket you name. It lists only that prefix and deletes only objects below it.
- At the end it deletes everything it could have written, also when a check failed. If the clean-up
  fails it says so and names the prefix to delete by hand. `--keep` skips the clean-up.
- It prints the project, bucket and prefix first. Against production it does nothing more without
  `--yes`.
- It uploads at most `--max-bytes` in total (default 64 MiB, counted per upload); a check that would pass
  the cap stops before it uploads and is `INCONCLUSIVE`. A full run uploads about 11 MiB.
- Credentials: it never reads, creates or prints any. Requests carry no user, or the token of a test
  user that **already exists** and signs in with an email and password from the environment (Firebase
  Auth REST, through `FirebaseUserAuth`). Nothing is read from files, no service account is used, and the
  URI of a resumable session (a bearer capability) is never printed.
- It creates no user and no other resource; the only objects are the ones under the prefix.

Use a throwaway project or bucket if you can. The rules of the bucket must let the user (or anyone, with
no user) write, read and delete under `verify_storage_kit/`; otherwise checks end `INCONCLUSIVE` with
`unauthorized`.

## Commands

Production, from the repository root:

    unset FIREBASE_STORAGE_EMULATOR_HOST                      # the kit refuses to guess between the two
    export FIREBASE_TEST_PROJECT_ID=my-project
    export FIREBASE_TEST_STORAGE_BUCKET=my-project.firebasestorage.app
    export FIREBASE_TEST_APP_ID=1:123:web:abc                  # optional: the X-Firebase-GMPID the checks send
    # a test user, optional (check 13 needs it, and so does a bucket whose rules need a user):
    export FIREBASE_TEST_WEB_API_KEY=...
    export FIREBASE_TEST_USER_EMAIL=...
    export FIREBASE_TEST_USER_PASSWORD=...

    tool/verify_production_storage/run.sh --backend=production          # prints the plan, does nothing
    tool/verify_production_storage/run.sh --backend=production --yes    # runs it
    tool/verify_production_storage/run.sh --backend=production --yes --only=3,7

Options: `--bucket=NAME` (instead of the variable), `--denied-bucket=NAME` (a bucket whose rules refuse
requests without a user: check 2 needs one, else it is `SKIPPED`; the check only tries to write one tiny
object there without a user, and deletes it if the write was wrongly accepted), `--auth=none|user|auto`
(default `auto`: the user when the three variables are set), `--only=1,2`, `--max-bytes=N`, `--keep`,
`--list`.

Save the report: `... --yes | tee verify_storage_report.txt`. It holds the project, the bucket and the
prefix, and no credentials.

Emulator (to see a run, or to check the kit):

    tool/start_storage_emulator.sh 9399
    FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9399 tool/verify_production_storage/run.sh \
      --backend=emulator --denied-bucket=demo-test-auth.appspot.com
    (cd firebase_storage/firebase_storage_dart && \
      FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9399 dart test test/production)   # the kit's own test
    tool/stop_storage_emulator.sh 9399

Exit code: 0 when no check failed, 1 when one is `FAIL`, 2 for a usage error or when `--yes` is missing.

## The checks and how to read them

For the checks that ask a question the **answer is the first word of the line** (`HONOURED` / `IGNORED`,
`ACCEPTED` / `ENFORCED`, `VERIFIED` / `NOT VERIFIED`, ...): both answers are a `PASS` as long as the client
copes. `FAIL` means the client misbehaved or the backend does something it does not handle. Checks 1 and
14 are strict only on production: on the emulator a difference there is `INCONCLUSIVE`.

| id | check | what a result means |
| --- | --- | --- |
| 1 | Missing object | A raw GET of a missing object answers 404 with the JSON envelope `{"error": {"code": 404, ...}}` (`JSON ENVELOPE`), and the SDK reports `object-not-found` with the status and body. `PLAIN BODY` is what the emulator sends. |
| 2 | Under rules | Needs `--denied-bucket`. A write without a user answers 403 with a JSON envelope and the SDK reports `unauthorized`. `FAIL` if the write is accepted. |
| 3 | Range | `Range: bytes=10-19` on `alt=media`: `HONOURED` (206 and the right 10 bytes) or `IGNORED` (200 and the whole object); also the answer for a range past the end. |
| 4 | Download token | A new object has a download token, and `downloadUrl()` serves it without credentials. The answer to a wrong token is reported (a bucket with public read rules serves it too). |
| 5 | List paging | Pages of 2 over 3 objects and 1 prefix: a `nextPageToken`, no repeats beyond prefixes, the last page has none. Its length and character class are reported (never the token). |
| 6 | Multipart | `putBytes`: size, content type and the md5Hash equal the local ones. |
| 7 | Resumable | Raw protocol: start (`x-goog-upload-status: active`), three chunks of 256 KiB, `upload, finalize`, stored size and md5. |
| 8 | Pause and resume | The second chunk is aborted in flight; a `query` says how much the server has; the upload goes on from there. |
| 9 | Resume by session URI | A new connection that knows only the session URI queries and finishes the upload. |
| 10 | md5Hash integrity | A multipart upload with a wrong `md5Hash` in the metadata: `VERIFIED` (rejected) or `NOT VERIFIED` (accepted; the client must compare the returned hash). The right hash is always accepted. |
| 11 | App Check header | The SDK sends `X-Firebase-AppCheck` with a token that is not valid: `ACCEPTED` (not enforced) or `ENFORCED` (refused, the SDK reports `unauthorized-app`). A real App Check token is not covered. |
| 12 | X-Firebase-GMPID | The SDK sends the app id on every request; the answer without the header is reported. |
| 13 | Refresh after a 401 | Needs a test user. The first token is one the backend refuses (401); the SDK asks for a forced refresh and the retry is served. |
| 14 | CORS | The resumable start response exposes `x-goog-upload-url`, `-status` and `-size-received`, and the preflight allows the `x-goog-upload-*` request headers. |
| 15 | Retry on a 5xx | Two 503 answers are **simulated in the client** and never reach the backend; the SDK retries and the third attempt is served. A real 5xx cannot be provoked safely. |
| 16 | SDK resumable | `Reference.startUpload` over 256 KiB: a session, progress events, stored size and md5. |
| 17 | SDK pause and resume | `UploadTask.pause()` then `resume()` finishes the upload. `INCONCLUSIVE` if it finished before it could be paused. |
| 18 | SDK session resume | A second task started with `existingSessionUri` of a paused one finishes the upload. |
| 19 | SDK download | `getBytes`, `openRead(100, 200)`, an open-ended `openRead`, `maxSize` too small (`download-size-exceeded`) and equal to the size. |

What to send back: the whole report. The most valuable lines are the answers of 1, 2, 3, 10, 11 and 14,
and the results of 8, 9, 13, 17 and 18.

## Known results

Only the emulator has been run (`demo-test.appspot.com` open, `demo-test-auth.appspot.com` with rules that
need a user). Production: not run.

| id | emulator | production |
| --- | --- | --- |
| 1 | INCONCLUSIVE: plain `Not Found` body | expected `JSON ENVELOPE` |
| 2 | PASS: 403 with an envelope | to be run |
| 3 | PASS, `HONOURED`; the past-the-end range answers 200 | to be run |
| 4 | PASS; a wrong token is served (the emulator does not check it) | to be run |
| 5 | PASS (the emulator repeats the prefix on every page; its token has other characters) | to be run |
| 6-9 | PASS | to be run |
| 10 | PASS, `NOT VERIFIED` | to be run |
| 11, 12 | PASS, `ACCEPTED` and `SENT` | to be run |
| 13 | SKIPPED: no test user | to be run |
| 14 | PASS | to be run |
| 15 | PASS (simulated 503s, about 6 s of backoff) | to be run |
| 16-19 | PASS | to be run |

## Not verified

- The kit itself against a real project.
- App Check with a real token; the kit has no App Check token provider.
- A real 5xx of the backend (check 15 simulates it).
- Browser behaviour: check 14 reads the CORS headers, no browser is involved.
- Quotas, large objects (the cap is 64 MiB) and sessions that expire.
