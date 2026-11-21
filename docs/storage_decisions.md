# Storage decisions

The decisions behind `firebase_storage_dart` (`firebase_storage/firebase_storage_dart`) and its FlutterFire
adapter (`firebase_storage/firebase_storage_dart_platform`): what was decided, why, what it costs, and where
to check it. [storage_parity.md](storage_parity.md) compares the API with the JS, Android, iOS and C++ SDKs and
lists the deliberate differences from the JS SDK; [contributing_a_product.md](contributing_a_product.md) has the
rules a new product client follows. Paths in "Pinned by" are relative to
`firebase_storage/firebase_storage_dart` unless they start with `docs/`, `tool/` or `.github/`.

Section 6 describes an upload strategy that is not on `main` yet (branch `storage/upload-single-request`, for
0.1.1); its "Pinned by" says so.

## 1. An idiomatic Dart client first

**Decision.** The client is designed as a Dart library. Configuration is immutable and goes to the
constructor (`FirebaseStorage(app, bucket:, emulatorHost:, mockUserToken:, retry:, httpClient:)`). There is no
`instanceFor` cache, no retry setters and no `DownloadTask`. FlutterFire's shape (`FirebaseStorage.instance`,
`setMaxUploadRetryTime`, tasks that are futures) lives in `firebase_storage_dart_platform`, which maps onto the
client. FlutterFire names stay where they are also natural Dart: `Reference`, `FullMetadata`,
`SettableMetadata`, `ListResult`, kebab-case error codes.

**Why.** The same split already exists for Firestore and Auth. A client shaped after a platform interface
carries its global state and its mutable settings into every program. Downloads are a `Stream` (`openRead`)
or a file (`writeToFile` in `io.dart`); the JS SDK has no download task either.

**What we gave up.** A program written for `firebase_storage` does not compile against the client; it needs the
adapter, which is thicker as a result. Download progress and pause are not in the client (a gap in
[storage_parity.md](storage_parity.md), state "later").

**Pinned by.** `lib/src/firebase_storage.dart` (the constructor and its fields are `final`);
`../firebase_storage_dart_platform/lib/src/firebase_storage.dart`, `task.dart` and `reference.dart` (the
mapping); `docs/contributing_a_product.md`, design rules 1 and 4.

## 2. The REST v0 API over `package:http`

**Decision.** The client calls the Firebase Storage REST API (`/v0/b/<bucket>/o`) through `package:http`. It
does not use `googleapis` or gRPC.

**Why.** It is the protocol of the JS SDK, the reference for behaviour, and the only one the Storage emulator
speaks. `package:http` has a browser client, so the same code runs on the VM and the web. The package depends
on `firebase_app_dart`, `http` and `meta` only. `http` 1.5 is required for `AbortableRequest`, which pause and
cancel use.

**What we gave up.** The Google Cloud Storage JSON API, with its ACLs, signed URLs and bucket calls, is not
reachable; a trusted server that needs those uses the Google Cloud Storage client. There is no streaming
upload progress from the browser (see section 7).

**Pinned by.** `pubspec.yaml` (dependencies); `test/web_imports_test.dart` (the main library reaches neither
`dart:io` nor `dart:ffi`); `test/web_compile_test.dart`; `tool/check_web_imports.dart`.

## 3. Tokens from the app, and where they may go

**Decision.** The ID token comes from `app.authProvider` and the App Check token from `app.appCheckProvider`;
the package does not depend on the Auth package. A token is sent only over https, to the configured
`emulatorHost`, or to a loopback host. The App Check token still goes to the configured emulator, as in the JS
SDK. Without a signed-in user the request carries no `Authorization` header.

**Why.** Any token provider works, including a service account or a test fake. A token in clear text to an
arbitrary host is a credential leak, and a misconfigured host is easy to produce.

**What we gave up.** A plain-http server on a private address (for example an emulator reached through another
host name) gets no token unless it is the configured `emulatorHost`.

**Pinned by.** `test/hardening_test.dart` (group "tokens travel only over https, to the emulator or to
loopback"); `test/security/hosts_test.dart` (groups "token scope of the request layer" and "emulator", test
"the configured emulator gets both tokens over plain http"); `test/requester_test.dart` (group "headers").

## 4. Fixes of JS quirks

**Decision.** Where the JS SDK does something that looks like a bug, the client fixes it and says so: it sends
`X-Firebase-GMPID`, reports the real HTTP status, reads the error body, lets `cancel()` work from `paused`,
grows chunks to a cap of 16 MiB, resets the retry wait after a success, retries a 401 once with a refreshed
token, and gives downloads their own retry time. `getBytes` is section 5, token scope is section 3.

**Why.** Each one is a behaviour the JS code or its own documentation contradicts, and Android or iOS already
do it.

**What we gave up.** The client is not a line-for-line port; a test written against JS timing can differ.

**Pinned by.** The table "Deliberate differences from the JS SDK" in
[storage_parity.md](storage_parity.md); its last column names the test of each row.

## 5. `getBytes` fails past `maxSize`

**Decision.** `getBytes(maxSize:)` asks for `maxSize + 1` bytes with a `Range` header and throws
`download-size-exceeded` when it gets more than `maxSize`, including from a server that ignores `Range`.

**Why.** The JS SDK truncates silently at the limit, which turns a too-large object into valid-looking, wrong
data. Android, iOS and C++ fail. One extra byte proves the overflow without reading the object.

**What we gave up.** Code that relied on JS's truncation to read a prefix must use `openRead(0, n)`.

**Pinned by.** `test/reference_operations_test.dart` ("an object larger than maxSize is
download-size-exceeded"); `test/security/limits_test.dart` ("asks for maxSize + 1 bytes with a Range header",
"stops reading when a server ignores Range and sends more"); `test/hardening_test.dart` ("getBytes stops
reading once the body passes maxSize").

## 6. Upload strategy (0.1.1, not on `main` yet)

**Decision.** All the SDKs send the data of one file in order, because the server accepts data only at the
next offset. JS and Android send chunks one at a time (JS waits for the answer of a chunk before it sends the next; Android
loops over `uploadChunk()` on one thread, and after a failed send it drops the chunk size back to 256 KiB);
Android runs at most two uploads at once (`UPLOAD_POOL_SIZE = 2`); iOS passes `uploadChunkSizeBytes`, which is
`Int64.max` unless the caller sets it, as the chunk size of `GTMSessionUploadFetcher`, so by default the
whole file goes as one chunk (the fetcher is not in our clones; we infer one request from the setting).
The client, new in 0.1.1 (none of the following is in 0.1.0):

- bytes and files on the VM go as one streamed request;
- streams, and everything on the web, go in chunks: a stream cannot be read twice, and `fetch` gives no upload
  progress;
- `maxChunkSize` forces chunks;
- up to 256 KiB, one multipart request;
- a queue, `maxConcurrentUploads`, with 4 by default, limits the uploads running at once.

Not done: parallel chunks of one file (the protocol refuses them), isolates (the work is I/O, not CPU), and a
batch upload (Cloud Storage batch requests exclude uploads).

**Why.** One request removes the round trips of a session and is the fastest on a good link. Chunks stay where
resuming or progress needs them. The queue keeps many small uploads from opening many sockets.

**What we gave up.** A one-request upload that fails starts again from zero unless a session is in use; the
chunked path is how a caller asks for resumability.

**Pinned by.** Not on `main`: the tests come with branch `storage/upload-single-request`. On `main`, 0.1.0
sends `startUpload` data above 256 KiB in chunks that start at 256 KiB, double, and stop at 16 MiB:
`test/upload_task_test.dart` ("chunks double from 256 KiB and stop at 16 MiB", "256 KiB + 1 byte starts a
session and sends two chunks"). TODO at merge: the test names of the single request, `maxChunkSize` and
the queue (`maxConcurrentUploads`). On `main`, `maxChunkSize` is only the internal 16 MiB cap of the growth.

## 7. Progress

**Decision.** On the VM, `UploadTask.progress` reports bytes as they are written, at most every 100 ms and 64 KiB; on the
web it reports once per confirmed chunk. The stream starts with the current snapshot and does not replay
earlier events. `state`, `bytesTransferred` and `result` answer for what happened before you listened.

**Why.** `dart:io` shows how much of a body has gone out; the browser's `fetch` does not. Replaying events makes
a late subscriber race with a fast upload; the getters are a stable alternative.

**What we gave up.** A listener added late does not see the `success` event. Progress on the web is coarse.

**Pinned by.** `test/upload_task_test.dart` ("a chunk reports its bytes as the client takes them");
`test/browser/storage_resumable_web_test.dart` ("a multi-chunk upload reports progress per chunk only");
`lib/src/upload/upload_task.dart` (doc of `progress`).

## 8. Resuming after a restart

**Decision.** `UploadTask.sessionUri` exposes the session URI, and `existingSessionUri` on `startUpload`,
`startStreamUpload` and `putFile` continues it. The client checks the URI against the origin of the instance
(`storage.origin`, so the API host over https, or the emulator host): the scheme, host and port must be the
same, there must be no user info, and the path must start with `/v0/b/`. Otherwise the task fails before
sending anything to it.

**Why.** Flutter apps are killed often, and the resume protocol is already needed for `pause`. The session URI
is a bearer capability: whoever holds it can write to the object. A stored URI must not be able to send the
client's tokens or data to another host.

**What we gave up.** The caller stores the URI like a credential. A session that expired or was finalized
cannot be resumed; the call fails and the upload starts again.

**Pinned by.** `test/security/upload_session_test.dart` ("a session URL with ${bad.key} fails the task and
sends nothing to it", "the emulator session URL must stay on the emulator host"); `test/upload_task_test.dart`
(group "session"); `test/integration/upload_task_emulator_test.dart` ("a new task resumes the session of a
paused one").

## 9. Security hardening

**Decision.** Redirects are not followed. Sizes are capped before a body is read: a server response in an
exception is cut at 16 KiB, `getBytes` stops at `maxSize + 1`, `listAll` stops when a page token repeats, and
a stalled body ends at `requestTimeout`. Tokens, download tokens, upload ids and the query of a URL stay out of
exception messages (a failing provider's message is kept as the `cause`). CR and LF are refused in header and
multipart values. The names `.` and `..` are refused as objects and buckets, and object names, prefixes and
page tokens each travel as one path segment or query value.

**Why.** Each is a way a server or a stored value could make the client leak a credential, read without
limit, or reach another path. `package:http` follows redirects by default and Dart's `Uri.parse` removes dot
segments, so these need explicit code.

**What we gave up.** A legitimate redirect from the API fails as `unknown`. Names that other tools accept
(`..`) are refused.

**Pinned by.** `test/security/hosts_test.dart` ("a 3xx answer is an error, not something to follow");
`test/security/leakage_test.dart`; `test/security/limits_test.dart`; `test/security/headers_test.dart`;
`test/security/paths_test.dart`; `test/hardening_test.dart` (group "dot names"); `test/security/upload_session_test.dart`
("the upload id never appears in the error of a failed session").

## 10. Production facts that shaped the docs

**Decision.** The documentation states what one run of the verification kit against a real project found:
`md5Hash` is not verified by the server; an invalid ID token gets 403, not 401; a missing object answers a
JSON envelope; `Range` gets 206 and 416; CORS exposes the `x-goog-upload-*` headers. A legacy `*.appspot.com`
bucket needs the Blaze plan, and without it the server answers 402, which maps to `quota-exceeded`.

**Why.** The emulator differs from production in each of these, and the API docs would be wrong if written
from the emulator alone. The 403 result means the one forced refresh on a 401 does not apply to invalid
tokens.

**What we gave up.** One run, with one throwaway user, is the evidence. The Blaze fact was seen during that
work and has no automated check.

**Pinned by.** `tool/verify_production_storage/README.md` ("Known results"); `README.md` of the package
("Verified"); `lib/src/metadata.dart` (doc of `SettableMetadata.md5Hash`);
`test/conformance/errors_conformance_test.dart` (the 402 mapping to `quota-exceeded`).

## 11. How the client is tested

**Decision.** The differences of the emulator from production are written as tests, so an emulator upgrade
that changes one fails there first. The two requests that hang the emulator's rules runtime run only with
`STORAGE_EMULATOR_HANG_TESTS=1`, against an emulator of their own. A production kit
(`tool/verify_production_storage`) runs 20 named checks against a real bucket with a throwaway user it creates
and deletes, and writes only below one unique prefix. Assertions do not depend on timing: injected clocks and
delays in the unit tests, and emulator tests that check order and bounds instead of exact event lists.

**Why.** A test that depends on the speed of a runner fails at random and gets disabled. A hang test that runs
by default breaks the tests after it.

**What we gave up.** The kit has not been run on a schedule, and the opt-in tests run only when someone sets
the variable.

**Pinned by.** `test/integration/emulator_conformance_test.dart` (the groups of differences, and the guard
`hangTestsEnabled`); `test/production/verify_production_test.dart` (the kit against the emulator);
`test/requester_test.dart` (injected time); commit `a47f6b28` (two tests made independent of timing);
`.github/workflows/ci.yml`, job `storage`.

## 12. Release

**Decision.** The client, the adapter and the CI wiring went into one pull request. The first versions of the
two packages are published by hand with `tool/publish_first_version.sh <package>`, and later versions by tag
(`<package>-v<version>`) through `publish.yml`.

**Why.** pub.dev allows automated publishing only for a package that already exists, and the adapter needs the
client's API to be in `main` to be tested. A single review sees the whole feature.

**What we gave up.** A large pull request; the first publish needs a person with the right pub.dev login.

**Pinned by.** `tool/publish_first_version.sh`; `.github/workflows/publish.yml` and `release.yml` (both list
`firebase_storage_dart` and `firebase_storage_dart_platform`); `CHANGELOG.md` of each package.
