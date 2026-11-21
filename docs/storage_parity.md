# Storage parity with the JS, Android, iOS and C++ SDKs

This document compares the public API of Cloud Storage for Firebase in four official SDKs with `firebase_storage_dart` 0.1.0 (`firebase_storage/firebase_storage_dart`):

- **JS**: `packages/storage/src` of firebase-js-sdk `main`. It is the reference for the protocol and for behaviour.
- **Android**: `firebase-storage` of firebase-android-sdk.
- **iOS**: `FirebaseStorage` of firebase-ios-sdk.
- **C++**: `storage` of firebase-cpp-sdk (the desktop code speaks REST itself; the mobile wrappers delegate to the native SDKs).
- **Dart**: the API of `firebase_storage_dart` 0.1.0 as it is in the code.

The sources were read as shallow clones on 2026-11-21, from GitHub only. Line numbers are from that reading and will drift. A cell of the Dart column that says "gap" means there is no equivalent; "n/a" means the feature belongs to another runtime; the notes say how a decided behaviour works. A "—" means the SDK has no such API.

Path shorthand: `J:` is JS `src/`, `A:` is Android `src/main/java/com/google/firebase/storage/`, `I:` is iOS `Sources/`, `C:` is C++ `storage/src/` (`C:d` desktop, `C:i` iOS wrapper, `C:a` Android wrapper).

Where the C++ wrapper on mobile delegates to the native SDK, the behaviour of that SDK applies. C++ desktop is the only C++ code that speaks HTTP itself, and its behaviour is described where it differs.

## 1. Instance and configuration

| Feature | JS | Android | iOS | C++ | Dart | Notes |
|---|---|---|---|---|---|---|
| Get default instance | `getStorage(app?)` api.ts:330 | `FirebaseStorage.getInstance()` / `Firebase.storage` | `Storage.storage()` | `Storage::GetInstance(app)` | `FirebaseStorage(app)` | Dart has no instance cache by design (shim does it). |
| Instance for another bucket | `getStorage(app, 'gs://b')` | `getInstance(app, url)` | `Storage.storage(app:url:)` | `GetInstance(app, url)` | `bucket:` | Android/iOS/C++ reject a URL with a path component; JS `Location.makeFromBucketSpec` does the same via regex. |
| Bucket from app options | `options.storageBucket` (`extractBucket` service.ts:31) | same | same (`fatalError` when missing, Storage.swift:341) | `app->options().storage_bucket()` | default `app.options.storageBucket`, else ArgumentError | JS throws `no-default-bucket` / `invalid-default-bucket`. |
| Accept `bucket` with or without `gs://` | yes | yes | yes | yes | yes | |
| Read the bucket back | `ref.bucket` | `ref.getBucket()` | `ref.bucket` | `Storage::url()` | `FirebaseStorage.bucket` | |
| Read the app back | `storage.app` | `getApp()` | `storage.app` | `app()` | `app` | |
| Emulator | `connectStorageEmulator(storage, host, port, {mockUserToken})` api.ts:356; also auto from `FIREBASE_STORAGE_EMULATOR_HOST` via `getDefaultEmulatorHostnameAndPort` api.ts:337 | `useEmulator(host, port)` | `useEmulator(withHost:port:)` | `UseEmulator(host, port)` (logs an error and ignores a second call once configured, C:d storage_desktop.cc:140) | `emulatorHost` (`host:port`), `emulatorHostFromEnvironment` | |
| Emulator mock token | `options.mockUserToken` (string or object, sets `_overrideAuthToken`) service.ts:59 | — | — | — | `mockUserToken` | JS only. |
| Emulator over https (Cloud Workstations) | `isCloudWorkstation(host)` picks https and pings the server, service.ts:50 | — | — | — | gap | Dart's emulator is http only. Rare. |
| Custom host or domain (non-emulator) | internal `host` setter only, default `firebasestorage.googleapis.com` (J:implementation/constants.ts) | constant `PROD_BASE_URL` (A:network/NetworkRequest.java:52), not configurable | fixed | fixed | gap (not needed) | No official SDK exposes a public custom-host option outside the emulator. |
| Attach tokens over plain http | JS always sends (emulator http) | sends | only https or loopback, unless debug-only `allowInsecureTokenAttachment` (I:Internal/StorageTokenAuthorizer.swift:47) | desktop sends | tokens only over https, the emulator or loopback (0.1.0) | Decided for 0.1.0: the client attaches a token only to an https host, to `emulatorHost`, or to a loopback host. |
| Max operation retry time (get/update metadata, delete, list, URL) | `maxOperationRetryTime`, 2 min, settable | `set/getMaxOperationRetryTimeMillis`, 2 min | `maxOperationRetryTime`, 120 s | `max_operation_retry_time`, 120 s | `StorageRetryPolicy.operation` | Dart is immutable at construction; others are mutable at runtime. |
| Max upload retry time | `maxUploadRetryTime`, 10 min | `set/getMaxUploadRetryTimeMillis`, 10 min | `maxUploadRetryTime`, 600 s | `max_upload_retry_time`, 600 s | `upload` | |
| Max download retry time | none (downloads use the operation time, requests.ts:219) | `set/getMaxDownloadRetryTimeMillis`, 10 min | `maxDownloadRetryTime`, 600 s | `max_download_retry_time`, 600 s | `download` (10 min) | Dart follows the three-value split of the native SDKs, JS only has two. Notes need to say which JS value is used for Dart `download` when it differs. |
| Max per-chunk upload retry | — | `set/getMaxChunkUploadRetry`, 60 s (A:FirebaseStorage.java:56) | — | — | gap | Android caps retrying one chunk separately from the overall upload. |
| Max upload chunk size | none, fixed 256 KiB growing to 16 MiB effective (J:task.ts:336) | none, 256 KiB growing to 32 MiB (A:UploadTask.java:59-60) | `uploadChunkSizeBytes`, default unlimited, rounded to 256 KiB multiples (I:Storage.swift:109) | — | `FirebaseStorage(maxUploadChunkSize:)`, default null (0.1.1) | Like iOS: null sends the rest of an upload of bytes or a file in one request on the VM (iOS also uses one request by default); a value is rounded down to a multiple of 256 KiB, at least 256 KiB. Streams and the web are always chunked, up to 16 MiB or the cap. |
| Callback queue / executor | — (promises, microtasks) | `Executor` and `Activity` overloads on every listener | `callbackQueue: DispatchQueue`, default main (I:Storage.swift:112) | callbacks on a worker thread, no queue option | n/a | Dart streams and futures deliver on the event loop. |
| App Check | `appCheckProvider.getToken()` -> `X-Firebase-AppCheck`; error -> header dropped; `FirebaseServerApp.settings.appCheckToken` shortcut (service.ts:182) | `InteropAppCheckTokenProvider` | `AppCheckInterop.getToken(forcingRefresh:false)`, header `X-Firebase-AppCheck` (I:StorageTokenAuthorizer.swift:69) | desktop waits up to 10 s for a token (C:d storage_reference_desktop.cc:234) | `app.appCheckProvider?.getToken` | |
| Auth header | `Authorization: Firebase <idToken>` (request.ts:237) | same | same | same | yes | |
| Auth 401 handling | one retry is not done; 401 maps to `unauthenticated` | same | same | `kErrorUnauthenticated` | one forced refresh | Dart adds one forced token refresh; no official SDK does. See the differences below. |
| `X-Firebase-Storage-Version` | `webjs/<sdk version>` (request.ts:245) | `Android/<gms version>` | `ios/<version>` | `Cpp/<version>` | `dart/<version>` | |
| `X-Firebase-GMPID` | dead code path, `_appId` always null (request.ts:251) | sent (A:NetworkRequest.java:62) | sent (I:StorageTokenAuthorizer.swift:36) | not sent | yes (a deliberate fix, see below) | |
| Per-request timeout | `RequestInfo.timeout` = retry budget | connection timeouts + retry budget | `request.timeoutInterval = maxUploadRetryTime` for uploads | none (`timeout_ms = 0` for gets, C:d storage_reference_desktop.cc:245) | `requestTimeout`, an idle timeout (0.1.1) | Fires when no byte of the request body is sent for that long, when no response comes that long after the body was sent, or when a response body pauses that long; a long transfer never times out while data flows. On the web it bounds the time to the response. |
| Release resources / dispose | `app.delete()` -> `app-deleted` for later requests (service.ts:346) | — | — | `~Storage()` | `close()` (later calls throw StateError) | |
| Instance equality | — | `equals` on app+url | `isEqual`, `hash` | — | gap (trivial) | |

## 2. References and paths

| Feature | JS | Android | iOS | C++ | Dart | Notes |
|---|---|---|---|---|---|---|
| Root reference | `ref(storage)` | `getReference()` | `reference()` | `GetReference()` | `ref()` | |
| Reference by path | `ref(storage, 'a/b')` | `getReference(path)` | `reference(withPath:)` | `GetReference(path)` | `ref(path)` | |
| Reference from URL | `ref(storage, 'gs://…' or 'https://…')` (location.ts) | `getReferenceFromUrl(url)` | `reference(forURL:)`, `reference(for: URL)` | `GetReferenceFromUrl(url)` | `refFromUrl` | JS accepts gs://, firebasestorage `/v0/b/<bucket>/o/<path>` and storage.googleapis.com / storage.cloud.google.com. A different bucket gives `bucketMismatch` on iOS, an error on C++, accepted on JS and Android. Dart follows JS. |
| Reference from another reference | `ref(ref, path)` | `child` | `child` | `Child` | `child` | |
| `child(path)` normalises slashes | yes (`child()` path.ts) | yes (`Slashes.normalizeSlashes`, A:internal/Slashes.java) | yes (`StoragePath`) | yes | yes | |
| `parent` | `ref.parent` (null at root) | `getParent()` | `parent()` | `GetParent()` | yes | |
| `root` | `ref.root` | `getRoot()` | `root()` | — | yes | |
| `name` | `ref.name` | `getName()` | `name` | `name()` | yes | |
| `fullPath` | `ref.fullPath` | `getPath()` | `fullPath` | `full_path()` | yes | |
| `bucket` | `ref.bucket` | `getBucket()` | `bucket` | `bucket()` | yes | |
| `storage` back-reference | `ref.storage` | `getStorage()` | `storage` | `storage()` | yes | |
| `gs://` string | `toString()` | `toString()` | `description` | — | `gsUri`, `toString` | |
| Equality / hash | — | `equals`, `hashCode`, `compareTo` (A:StorageReference.java:675-689) | `isEqual`, `hash` | — | yes (`==`, `hashCode`); gap: `compareTo` | Trivial, later. |
| Operations on the root reference | throw `invalid-root-operation` (reference.ts:146) | request fails (404 etc.) | request fails | request fails | `invalid-root-operation` (0.1.0) | Decided for 0.1.0: the client throws before sending a request. |
| Reference validity check | — | — | — | `is_valid()` | n/a | C++ null-object pattern. |
| Active task lists | — | `getActiveUploadTasks()`, `getActiveDownloadTasks()` | — | — | gap (won't do) | Android keeps a task registry (A:StorageTaskManager.java). Shim can do it. |

## 3. Metadata

Field names are given per SDK. "R" = read-only, "S" = settable at upload or update.

| Field | JS (`FullMetadata`) | Android (`StorageMetadata`) | iOS (`StorageMetadata`) | C++ (`Metadata`) | Dart | Notes |
|---|---|---|---|---|---|---|
| bucket | `bucket` R | `getBucket()` R | `bucket` R | `bucket()` R | `bucket` R | |
| fullPath | `fullPath` R | `getPath()` R | `path` R | `path()` R | `fullPath` R | |
| name | `name` R | `getName()` R | `name` R | `name()` R | `name` R | |
| generation | `generation` R (string) | `getGeneration()` R (string) | `generation` R (Int64) | `generation()` R (int64) | `generation` R | JS and Android use a string, and so does Dart (`String?`). |
| metageneration | `metageneration` R | `getMetadataGeneration()` R | `metageneration` R | `metadata_generation()` R | `metageneration` R | |
| size | `size` R (number) | `getSizeBytes()` R | `size` R | `size_bytes()` R | `size` R (int) | |
| timeCreated | `timeCreated` R (ISO string) | `getCreationTimeMillis()` R | `timeCreated` R (Date) | `creation_time()` R (seconds on desktop, C:d metadata_desktop.cc:41) | `timeCreated` R (DateTime?) | |
| updated | `updated` R (string) | `getUpdatedTimeMillis()` R | `updated` R | `updated_time()` R | `updated` R | |
| md5Hash | `md5Hash` R, and in `UploadMetadata` settable ("Base64 MD5 of the object being uploaded", public-types.ts:169) | `getMd5Hash()` R | `md5Hash` R | `md5_hash()` R | `md5Hash` R and S (0.1.0) | `SettableMetadata.md5Hash` is sent with an upload, as `UploadMetadata.md5Hash` in JS. Production does not verify it: it stores the real hash of the data, so compare the `md5Hash` of the returned `FullMetadata` yourself. |
| cacheControl | S | `setCacheControl` S | S | `set_cache_control` S | S | |
| contentDisposition | S | S | S | S | S | |
| contentEncoding | S | S | S | S | S | |
| contentLanguage | S | S | S | S | S | |
| contentType | S | S | S | S | S | |
| customMetadata | `customMetadata` S (map) | `setCustomMetadata(key, value)`, `getCustomMetadataKeys()` | `customMetadata` S | `custom_metadata()` map, desktop returns a pointer | `customMetadata` S | |
| downloadTokens | `downloadTokens` R (`string[]`, from comma list) | — | — | — | `downloadTokens` R | Only JS surfaces them. |
| Back-reference to reference | `ref` R (optional) | `getReference()` | — | `reference()` | gap (won't do) | Dart `FullMetadata` has no `ref`, `Reference` already holds it. |
| isFile / isFolder | — | — | `isFile`, `isFolder` (I:StorageMetadata.swift:130; `.folder` is never set) | — | gap (won't do) | |
| Raw dictionary form | — | — | `dictionaryRepresentation()`, `init(dictionary:)` | — | `toJson()` | |
| Copy-with | — | `Builder(original)` | `copy()` | copy ctor | `SettableMetadata.copyWith` |  |
| `getMetadata` | `getMetadata(ref)` | `getMetadata()` | `getMetadata(completion:)` | `GetMetadata()` | `metadata()` | GET `/b/<bucket>/o/<path>` in all of them. |
| `updateMetadata` | `updateMetadata(ref, SettableMetadata)` | `updateMetadata(metadata)` | `updateMetadata(_:)` | `UpdateMetadata(metadata)` | `updateMetadata` | PATCH. JS semantics for "clear a field" (null) are in `implementation/metadata.ts` (`metadataToDict`); the Dart documentation of `SettableMetadata` states it. |
| Default content type at upload | `metadata.contentType`, else blob type, else `application/octet-stream` (requests.ts:300) | from stream/uri, else `application/octet-stream` | from file extension (I:StorageUploadTask.swift:310), else required | `content_type` argument | yes (JS rule) | |

## 4. Uploads

| Feature | JS | Android | iOS | C++ | Dart | Notes |
|---|---|---|---|---|---|---|
| Upload bytes, simple | `uploadBytes(ref, Blob/Uint8Array/ArrayBuffer, metadata)` (multipart/related, `X-Goog-Upload-Protocol: multipart`) requests.ts:330 | `putBytes(byte[], metadata?)` (always resumable) | `putData(_:metadata:)` (always resumable) | `PutBytes(buffer, size, metadata?, listener?, controller?)` (desktop: one POST of the raw body, C:d storage_reference_desktop.cc:445) | `putBytes` | Only JS has a non-resumable multipart path. Android, iOS use resumable for every size. |
| Upload bytes, resumable, with task | `uploadBytesResumable` | `putBytes` returns `UploadTask` | `putData` returns `StorageUploadTask` | `PutBytes` returns a future plus `Controller` | `startUpload` | |
| Resumable threshold | data > 256 KiB resumable; smaller single request (task.ts:172) | always | always | none (single POST) | `startUpload`: up to 256 KiB one multipart request, above that a session; `putBytes` and `putString` always one multipart request (0.1.0) | As JS for `startUpload`. `putBytes` and `putString` never open a session, whatever the size. |
| String upload | `uploadString(ref, value, format, metadata)` | — | — | — | `putString` | |
| String formats | `raw` (UTF-8), `base64`, `base64url`, `data_url` (J:implementation/string.ts:38-62) | — | — | — | `StringFormat.raw/base64/base64Url/dataUrl` | `invalid-format` on bad input. |
| Upload from file | — (browser `File` is a `Blob`) | `putFile(Uri, metadata?, existingUploadUri?)` | `putFile(from: URL, metadata?)` | `PutFile(path, metadata?, listener?, controller?)` | `putFile(File)` in `io.dart` | iOS on device can use a background URLSession for file uploads (I:StorageUploadTask.swift:130-140); no Dart equivalent. |
| Upload from stream | — (Node/browser streams are not accepted) | `putStream(InputStream, metadata?)` (unknown length allowed, total byte count -1) | — | — | `startStreamUpload(Stream, length:)` (length required) | Android accepts unknown length through `AdaptiveStreamBuffer`. Dart requires `length`: unknown-length streams are a gap. |
| Upload from Blob | `Blob` | — | — | — | n/a | Web only. Dart uses `Uint8List`. |
| Upload from ArrayBuffer / Uint8Array | yes | `byte[]` | `Data` | `void*` + size | `Uint8List` | |
| Pause | `task.pause()` -> bool | `pause()` | `pause()` | `Controller::Pause()` | `pause()` | |
| Resume | `task.resume()` -> bool | `resume()` | `resume()` | `Controller::Resume()` | `resume()` | |
| Cancel | `task.cancel()` -> bool (JS cancels from running only, in practice paused is ignored; doc says both) | `cancel()` | `cancel()` | `Controller::Cancel()` | `cancel()` (also from paused, a deliberate fix) | |
| Progress | `on('state_changed', next)` with `UploadTaskSnapshot {bytesTransferred, totalBytes, state, metadata, ref, task}` | `addOnProgressListener` (`bytesTransferred`, `totalByteCount`) | `observe(.progress)` with `snapshot.progress` | `Listener::OnProgress(controller)` | `progress` stream | |
| Paused notification | state `paused` in `state_changed` | `addOnPausedListener` | `observe(.pause)` | `Listener::OnPaused` | `UploadState.paused` on the stream | |
| Success / failure listeners | `then`, `catch`, observer `complete`/`error` | `addOnSuccess/Failure/Complete/Canceled Listener`, `getResult`, `getException` | `observe(.success)`, `observe(.failure)` | futures | `result` future | |
| Canceled as a distinct signal | state `canceled`, rejection with `canceled` | `addOnCanceledListener`, `isCanceled` | `StorageErrorCode.cancelled` | `kErrorCancelled` | `canceled` exception | |
| Task state query | `snapshot.state` | `isInProgress`, `isPaused`, `isComplete`, `isSuccessful`, `isCanceled` | `snapshot.status` (`resume/progress/pause/success/failure`) | `Controller::is_paused()`, `bytes_transferred()`, `total_byte_count()` | `state`, `bytesTransferred`, `totalBytes` | |
| Remove listeners | unsubscribe function from `on` | `removeOn*Listener` | `removeObserver(withHandle:)`, `removeAllObservers` | listener lifetime | n/a | Dart stream subscription cancel. |
| Activity-scoped listeners | — | `addOn*Listener(Activity, …)` auto-removed on stop (A:internal/ActivityLifecycleListener.java) | — | — | n/a | Android lifecycle. |
| Async/await form | promise is thenable | `Task<T>` (Play services) and Kotlin `taskState` Flow (A:Storage.kt:143) | `putDataAsync(_:metadata:onProgress:)` etc. (I:AsyncAwait.swift) | `Future<T>` | `result` future plus stream | |
| Task as Future | `UploadTask.then` | `Task<T>` | — | `Future<T>` | gap (shim) | Dart: `UploadTask` is not a Future; shim builds FlutterFire's Task-as-Future. |
| Upload session start | POST `X-Goog-Upload-Command: start` + `X-Goog-Upload-Header-Content-Length/Type` (requests.ts:428) | `ResumableUploadStartRequest` | GTMSessionUploadFetcher (`uploadType=resumable`, I:StorageUploadTask.swift:112) | — | yes | |
| Upload session query (after failure, pause, resume) | `X-Goog-Upload-Command: query`, reads `X-Goog-Upload-Size-Received` (requests.ts:465) | `ResumableUploadQueryRequest` | GTM | — | yes | |
| Resume the same session after an app restart | — | `putFile(uri, metadata, existingUploadUri)` plus `TaskSnapshot.getUploadSessionUri()` (A:StorageReference.java:280, UploadTask.java:622) | — (GTM keeps a session in-process; background session for files) | — | `UploadTask.sessionUri`, `existingSessionUri` on `startUpload`, `startStreamUpload`, `putFile` (0.1.0) | Decided for 0.1.0, after Android. The uploaded bytes are asked from the server (`query`) before sending. |
| Session cancel on `cancel()` | `X-Goog-Upload-Command: cancel` | `ResumableUploadCancelRequest` | GTM stop | — | yes (JS) | |
| Chunk size, first | 256 KiB (`RESUMABLE_UPLOAD_CHUNK_SIZE`) | 256 KiB (`PREFERRED_CHUNK_SIZE`) | whole object by default (`.max`), caller can cap | — | 256 KiB | |
| Chunk growth | doubles after each success while `size*2 < 32 MiB`, so the cap is 16 MiB (task.ts:336) | doubles while `< 32 MiB`, resets to 256 KiB after a failed send (A:UploadTask.java:486-497) | none | — | doubling, cap 16 MiB (or `maxUploadChunkSize`), when chunked | Android resets the chunk size after a failure, JS does not. Dart chunks streams, the web and instances with `maxUploadChunkSize`; on the VM bytes and files go in one request. |
| Upload commands | `upload`, `upload, finalize`, `finalize` with `X-Goog-Upload-Offset` (requests.ts:538) | same | GTM | — | yes | |
| Checksum on upload | `md5Hash` in `UploadMetadata`; no client-side verification | none; HTTP 409 maps to `ERROR_INVALID_CHECKSUM` (A:StorageException.java:89) | none (`nonMatchingChecksum` exists, but nothing raises it, I:StorageError.swift:121) | `kErrorNonMatchingChecksum` (mapped from iOS/Android) | gap: the client does not verify; production does not either | No official SDK verifies the MD5 or CRC32C on the client. JS has a TODO for per-range `x-range-md5` (requests.ts:560). |
| Server size mismatch guard | `server-file-wrong-size` when status total differs from the data (requests.ts:529) | "Unexpected error. The server lost a chunk update." (A:UploadTask.java:406) | — | — | `server-file-wrong-size` | |
| Retry of a failing chunk | whole-request backoff (see section 10) | per-chunk loop with `sleepTime` that resets on success (A:UploadTask.java:341-456) | GTM retry | desktop retries whole POST | JS backoff, with the wait reset | |

## 5. Downloads

| Feature | JS | Android | iOS | C++ | Dart | Notes |
|---|---|---|---|---|---|---|
| Bytes into memory | `getBytes(ref, maxDownloadSizeBytes?)` -> `ArrayBuffer` | `getBytes(long maxDownloadSizeBytes)` (required) | `getData(maxSize:completion:)`, `data(maxSize:)` async | `GetBytes(buffer, buffer_size, listener?, controller?)` | `getBytes({maxSize})` | Different semantics below. |
| Behaviour at the size limit | Sends `Range: bytes=0-N`, accepts 200 or 206, then truncates to N silently (J:reference.ts:157-170, requests.ts:228). No error. | Throws `IndexOutOfBounds` ("the maximum allowed buffer size was exceeded"), mapped to unknown (A:StorageReference.java:411) | Cancels the task with `downloadSizeExceeded(total:maxSize:)` (I:StorageReference.swift:196, 563) | Android/iOS wrappers return `kErrorDownloadSizeExceeded`; desktop copies what fits the buffer | `getBytes` throws `download-size-exceeded` (0.1.0) | Decided for 0.1.0: the request asks for `maxSize + 1` bytes, so one extra byte proves the overflow. JS truncates silently. |
| Blob | `getBlob` (browser only; Node throws) | — | — | — | n/a | |
| Stream | `getStream` (Node only: `ReadableStream`; browser throws) | `getStream()`, `getStream(StreamProcessor)` -> `StreamDownloadTask` | — | — | `openRead([start, end])` | |
| Range / offset | `Range` only via `maxDownloadSizeBytes` (start fixed at 0) | `GetNetworkRequest` sets `Range: bytes=<start>-` to resume (A:network/GetNetworkRequest.java:32) | via GTM resume data | — | `openRead(start, end)` | Only the Dart plan exposes arbitrary ranges. |
| To a file | — | `getFile(File)`, `getFile(Uri)` -> `FileDownloadTask` | `write(toFile:)` -> `StorageDownloadTask`, `writeAsync` | `GetFile(path, listener?, controller?)` | `writeToFile(File)` in `io.dart` (temp sibling, rename on success) | |
| Download task object | — | `FileDownloadTask`, `StreamDownloadTask` (both `StorageTask`) | `StorageDownloadTask` (observable) | `Controller` out-parameter | none by design (shim builds it) | |
| Pause / resume / cancel download | — | `pause()`, `resume()`, `cancel()` on both tasks | `pause()`, `resume()`, `cancel()` (resume data in memory, I:StorageDownloadTask.swift:67) | `Controller` (desktop uses curl pause) | gap | Dart has no way to pause a download. A cancelled `openRead` stream subscription covers cancel only. |
| Resume after failure | — | file download resumes from the written offset and fails when the `ETag` changes (A:FileDownloadTask.java:213-225); stream task throws "The ETag on the server changed" (A:StreamDownloadTask.java:133) | GTM resume data | — | gap | See gap list: ETag/generation guard. |
| Download progress | — | `addOnProgressListener` on both | `observe(.progress)`, `progress: Progress` | `Listener::OnProgress` | gap (shim) | `openRead` has no progress. `writeToFile` returns `Future<int>` only. |
| Download chunk size | — | 256 KiB (`PREFERRED_CHUNK_SIZE`, both tasks) | — | — | n/a | |
| Download URL | `getDownloadURL(ref)` -> `https://<host>/v0/b/<bucket>/o/<path>?alt=media&token=<first token>` (metadata.ts:166-190) | `getDownloadUrl()` -> `Uri` | `downloadURL(completion:)` | `GetDownloadUrl()` | `downloadUrl()` | JS throws `no-download-url` when the object has no token (reference.ts:474). iOS builds the same URL (`StorageGetDownloadURLTask.swift:69`). |
| Download URL with a token that is missing | `no-download-url` | `StorageException` (object has no token) | `StorageError.unknown`/404 | error | `no-download-url` (0.1.0) | Dart raises it, as JS does. |
| Download over emulator | URL uses `http://host:port` | same | same | same | as JS |  |

## 6. List, listAll, pagination

| Feature | JS | Android | iOS | C++ | Dart | Notes |
|---|---|---|---|---|---|---|
| One page | `list(ref, {maxResults, pageToken})` | `list(int maxResults)`, `list(int, String pageToken)` | `list(maxResults:)`, `list(maxResults:pageToken:)` | `List(max_results_per_page = 1000, page_token)` | `list({maxResults, pageToken})` | Request has `delimiter=/`, `prefix=<path>/`, `maxResults`, `pageToken`. |
| All pages | `listAll(ref)` (recursive helper, default page size 1000) | `listAll()` | `listAll(completion:)` | — (loop `List` yourself) | `listAll()` | |
| Lazy paging as a stream | — | — | — | — | `listPages({pageSize})` | Dart extra. |
| `maxResults` bounds | 1..1000, `invalid-argument` | 1..1000, `IllegalArgumentException` (A:StorageReference.java:562-587) | none client-side | none client-side (default 1000) | 1..1000 | |
| Result fields | `items`, `prefixes`, `nextPageToken` | `getItems()`, `getPrefixes()`, `getPageToken()` | `items`, `prefixes`, `pageToken` | `items()`, `prefixes()`, `next_page_token()` | `ListResult(items, prefixes, nextPageToken)` | Android and iOS call it `pageToken`. |
| Prefix and items as references | `StorageReference` | `StorageReference` | `StorageReference` | `StorageReference` | `Reference` | |
| Listing needs Rules v2 | yes | yes | yes (doc, I:Result.swift:83) | yes | doc | Note in Dart docs. |
| Kotlin destructuring | — | `component1..3` | — | — | n/a | |

## 7. Delete

| Feature | JS | Android | iOS | C++ | Dart | Notes |
|---|---|---|---|---|---|---|
| Delete object | `deleteObject(ref)` | `delete()` | `delete(completion:)` | `Delete()` | `delete()` | DELETE `/b/<bucket>/o/<path>`. |
| Delete a folder or prefix | — | — | — | — | — | No SDK supports recursive delete. |
| Delete a missing object | `object-not-found` | `ERROR_OBJECT_NOT_FOUND` | `objectNotFound` | `kErrorObjectNotFound` | `object-not-found` | |

## 8. Errors

Mapping from HTTP status (all SDKs read the status; error body use differs). "Raised?" says whether the code is produced anywhere in that SDK's source.

| Code (JS name) | JS | Android | iOS | C++ | Dart | Notes |
|---|---|---|---|---|---|---|
| `unknown` | yes (any other status) | `ERROR_UNKNOWN` -13000 | `unknown` -13000 | `kErrorUnknown` | `unknown` | |
| `object-not-found` | 404 | `ERROR_OBJECT_NOT_FOUND` -13010 (404) | `objectNotFound` -13010 (404) | `kErrorObjectNotFound` | `object-not-found` | |
| `bucket-not-found` | defined, never raised | `ERROR_BUCKET_NOT_FOUND` -13011, never raised | `bucketNotFound` -13011, never raised | `kErrorBucketNotFound`, never raised on desktop | not raised | Server 404 is ambiguous, all SDKs report object-not-found. |
| `project-not-found` | defined, never raised | `ERROR_PROJECT_NOT_FOUND` -13012, never raised | `projectNotFound` -13012, never raised | `kErrorProjectNotFound` | not raised |  |
| `quota-exceeded` | 402 | `ERROR_QUOTA_EXCEEDED` -13013 (no 402 mapping in `calculateErrorCode`) | `quotaExceeded` (402) | `kErrorQuotaExceeded` (402) | `quota-exceeded` | |
| `unauthenticated` | 401 | `ERROR_NOT_AUTHENTICATED` -13020 | `unauthenticated` -13020 | `kErrorUnauthenticated` | `unauthenticated` | |
| `unauthorized` | 403 | `ERROR_NOT_AUTHORIZED` -13021 | `unauthorized` -13021 | `kErrorUnauthorized` | `unauthorized` | |
| `unauthorized-app` | 401 with body text "Firebase App Check token is invalid" (requests.ts:112) | — | — | — | `unauthorized-app` (from the body of the error response) | JS only. |
| `retry-limit-exceeded` | backoff budget spent (request.ts:182, task.ts:130) | `ERROR_RETRY_LIMIT_EXCEEDED` -13030 (`NETWORK_UNAVAILABLE`); `getIsRecoverableException()` | `retryLimitExceeded` -13030 | `kErrorRetryLimitExceeded` (also 408 on desktop, C:d curl_requests.cc:84) | `retry-limit-exceeded` | |
| `invalid-checksum` | defined, never raised | `ERROR_INVALID_CHECKSUM` -13031 (HTTP 409) | `nonMatchingChecksum` -13031, never raised | `kErrorNonMatchingChecksum` | not raised | Mapped by status 409 only on Android. |
| `download-size-exceeded` | — | — (wrapped as unknown) | `downloadSizeExceeded` -13032 | `kErrorDownloadSizeExceeded` | `download-size-exceeded` | |
| `canceled` | yes | `ERROR_CANCELED` -13040 | `cancelled` -13040 | `kErrorCancelled` | `canceled` | Spelling differs between SDKs, Dart follows JS. |
| `invalid-event-name` | defined, never raised | — | — | — | gap (won't do) | |
| `invalid-url` | bad `gs://`/https URL | `IllegalArgumentException` | `bucketMismatch` / `invalidArgument` | log + invalid reference | `invalid-url` | |
| `invalid-default-bucket` | bad `storageBucket` in options | — | `fatalError` | — | ArgumentError | |
| `no-default-bucket` | no `storageBucket` | — | `fatalError` (I:Storage.swift:341) | — | ArgumentError | |
| `cannot-slice-blob` | blob slice returned null | — | — | — | gap (n/a) | Blob only. |
| `server-file-wrong-size` | yes | text only | — | — | `server-file-wrong-size` | |
| `no-download-url` | yes | — | — | — | `no-download-url` (0.1.0) | Add. |
| `invalid-argument` | validators (e.g. `maxResults`) | `IllegalArgumentException` | `invalidArgument` -13050 | — | `invalid-argument` | |
| `invalid-argument-count` | defined, never raised | — | — | — | gap (n/a) | |
| `app-deleted` | requests after `app.delete()` | — | — | — | gap (StateError) | Dart throws `StateError` after `close()`. |
| `invalid-root-operation` | root reference | — | — | — | `invalid-root-operation` (0.1.0) | Add. |
| `invalid-format` | bad string for `uploadString` | — | — | — | `invalid-format` | |
| `internal-error` | impossible-state checks | — | `internalError` -13052 | — | gap | Add as a catch-all for bugs. |
| `unsupported-environment` | missing polyfill, `getBlob` in Node | — | — | — | gap (n/a) | |
| `bucket-mismatch` | — | — | `bucketMismatch` -13051 | `GetReferenceFromUrl` check (C:common storage.cc:199) | follow JS | |
| `path-error` | — | — | `pathError` -13053 | — | gap (n/a) | |
| HTTP status on the error | `StorageError.status` (set, but 0 for object-not-found, error.ts:42) | `getHttpResultCode()` | `ResponseErrorCode` in `userInfo` | — | `httpStatus` (always set) | |
| Server body on the error | `customData.serverResponse` (raw string) | — | `ResponseBody` in `userInfo` | — | `serverResponse` (16 KiB cap) | |
| Underlying cause | — | `getCause()` | `NSUnderlyingErrorKey` | — | gap (trivial) | |
| Numeric codes | — (string) | -13000 series | -13000 series | `Error` enum (no values stable across wrappers) | n/a | The shim maps to FlutterFire strings. |

## 9. Observers, listeners, threading and callback queues

| Feature | JS | Android | iOS | C++ | Dart | Notes |
|---|---|---|---|---|---|---|
| Observer API | `on('state_changed', next?, error?, complete?)` or `StorageObserver` object; returns `Unsubscribe` | per-state `addOn…Listener` | `observe(status, handler)` -> handle string | `Listener` subclass (`OnPaused`, `OnProgress`) | `progress` broadcast stream | |
| States | `running`, `paused`, `success`, `canceled`, `error` | `isInProgress/isPaused/isComplete/isSuccessful/isCanceled` | `StorageTaskStatus {unknown, resume, progress, pause, success, failure}` | paused flag | `UploadState {running, paused, success, canceled, error}` | iOS has a distinct `resume` event. |
| Replay the last state to a late subscriber | `on` delivers the current state first (observer.ts) | listeners get a callback if already complete | `observe` after success fires immediately | — | `progress` starts with the current snapshot and does not replay earlier events (0.1.0) | Decided for 0.1.0: a late subscriber gets the snapshot of the moment it listens, then the new events. `state`, `bytesTransferred` and `result` give the rest. |
| Thread / queue of callbacks | event loop | main thread by default, `Executor` overloads | `callbackQueue` (default main) | arbitrary thread | event loop | |
| Task scheduling | — | `StorageTaskScheduler` thread pools (A:StorageTaskScheduler.java); the upload pool has 2 threads | `dispatchQueue` | one thread per retried request (`std::thread`, C:d storage_reference_desktop.cc:341) | `FirebaseStorage(maxConcurrentUploads:)`, default 4 (0.1.1) | A first-in, first-out queue per instance; `putBytes` and `putString` count. A waiting task is `running` with 0 bytes, can be paused or canceled, and a paused task gives its turn away. |
| Continuations | `then`/`catch` | `continueWith`, `continueWithTask`, `onSuccessTask` | — | `OnCompletion` on `Future` | n/a | |
| Progress is throttled | per chunk (XHR upload progress inside a chunk too, request.ts:100) | per chunk | per GTM callback | per curl callback | on each chunk and state change | JS also reports sub-chunk progress through the connection's upload progress listener. Dart does the same on the VM (per byte, at most every 100 ms) and reports per chunk on the web, where the browser gives no upload progress. |

## 10. Retry and backoff behaviour

| Item | JS | Android | iOS | C++ | Dart | Notes |
|---|---|---|---|---|---|---|
| Retryable statuses | 5xx, 408, 429, plus request-specific extra codes (J:implementation/utils.ts); network failure that never reached the server is retried too (request.ts:128) | 5xx, 408, 429, network unavailable (A:internal/ExponentialBackoffSender.java:60) | GTMSessionFetcher defaults (5xx, 408, 429) plus "not connected to Internet" (I:Internal/StorageFetcherService.swift:90) | 5xx, 408, 429 (C:d storage_reference_desktop.cc:412) | "per JS" | |
| First wait | 1 s base, `(waitSeconds + random) * 1000` where `waitSeconds` doubles before the first retry, so the first wait is 2 to 3 s (J:implementation/backoff.ts:35-70) | 1000 ms + 0..249 ms | GTM: 1 s, doubling | 1000 ms | yes | |
| Growth | doubles while `< 64`, so cap is 64 s | doubles until `MAXIMUM_WAIT_TIME_MILLI` = 30 s | doubles, `maxRetryInterval` derived from the retry time (I:Storage.swift:324) | doubles, cap 30 s | JS | |
| Jitter | `Math.random()` seconds (0 to 1 s) | `random.nextInt(250)` ms | GTM | none | injected random | |
| Wait reset on success | each request starts its own backoff at 1 s; within one request the wait never resets (`waitSeconds` only grows) | chunk `sleepTime` resets to 0 after a successful send (A:UploadTask.java:453) | GTM | per request | reset after a successful request (a deliberate fix) | JS's `sleepTime` in the upload task's retry loop never resets; Dart's does. |
| Overall deadline | `timeout` per request, from `maxOperation/maxUploadRetryTime` | `clock.elapsedRealtime() + retryTime` | derived retry interval | `end_time` loop | `StorageRetryPolicy` | |
| Cancel during backoff | `stop()` ends the wait, one more request is made with `canceled` | `cancel()` flag, checked after sleeping | task cancel | `Controller::Cancel` | injected delay is cancellable | |
| Offline handling | treated as a retryable failure | polls every second while `NETWORK_UNAVAILABLE`, does not double (A:ExponentialBackoffSender.java:93) | explicit retry when not connected | — | as JS | |
| Test hooks | — | static `sleeper`, `clock` | `testBlock` | `g_retry_all_errors_for_testing` | injected clock, random, delay | |

## 11. Platform specifics

| Feature | JS | Android | iOS | C++ | Dart | Notes |
|---|---|---|---|---|---|---|
| Node streams | `getStream` -> `ReadableStream` (api.node.ts:58) | — | — | — | `openRead` | |
| Browser Blob | `getBlob`, `Blob` upload input | — | — | — | n/a | |
| File upload from OS URI | — | `putFile(Uri)` (content://, file://) | `putFile(from: URL)` | `PutFile(path)` | `putFile(File)` in `io.dart` | |
| File download to OS URI | — | `getFile(Uri)`, `getFile(File)` | `write(toFile: URL)` | `GetFile(path)` | `writeToFile(File)` | |
| Background transfers | — | — | background URLSession for file uploads on device | — | gap (won't do) | Platform runtime. |
| Lifecycle-aware listeners | — | `Activity` overloads | — | — | n/a | |
| Controller / listener split | — | — | — | `Controller` (`Pause/Resume/Cancel/is_paused/bytes_transferred/total_byte_count/GetReference`) and `Listener` (`OnPaused`, `OnProgress`) are passed to the call | n/a | Dart `UploadTask` plays both roles. |
| Future "last result" accessors | — | — | — | `<Op>LastResult()` per method | n/a | C++ `Future` API. |
| Kotlin extensions | — | `Firebase.storage`, `storageMetadata {}`, destructuring, `taskState` Flow | — | — | n/a | |
| Swift concurrency | — | — | `async` overloads plus `Result` completion overloads (I:AsyncAwait.swift, I:Result.swift) | — | n/a | |
| FirebaseServerApp | `appCheckToken` setting honoured (service.ts:182) | — | — | — | n/a | Server runtime object. |
| Large-file memory | `Blob` slice per chunk | `AdaptiveStreamBuffer` reads chunk by chunk | GTM reads file | desktop reads the whole file into memory for `PutFile` (TODO in C:d storage_reference_desktop.cc:493) | stream from disk | |
| Wire protocol | REST `https://firebasestorage.googleapis.com/v0/b/<bucket>/o…` | same | same (`www.googleapis.com` rewrite for uploads, I:StorageUploadTask.swift:103) | same | yes | |
| CORS (web) | the browser enforces it; the bucket needs a CORS configuration | — | — | — | the production bucket answers `access-control-allow-origin: *`, exposes the `x-goog-upload-*` headers on the session responses, and its preflight to the upload URL allows `x-goog-upload-command` and `x-goog-upload-offset` (verified, see the README of the package) | |
| HTTP client | XHR / `fetch` (Node) | `HttpURLConnection` | `GTMSessionFetcher` | curl | `package:http` | |

## Gaps and their state

The state is **0.1.0 (adopted)**: decided and part of the first release; **0.1.1 (adopted)**: added in 0.1.1; **later**: wanted, not yet in a release; or **won't do**.

| # | State | Gap | What 0.1.0 does, or why not |
|---|---|---|---|
| 1 | 0.1.0 (adopted) | `md5Hash` in upload metadata (JS `UploadMetadata.md5Hash`) | `SettableMetadata.md5Hash`. Adding a field to the immutable metadata class later would be a breaking change. Production does not verify the hash on upload; compare the returned `md5Hash`. |
| 2 | 0.1.0 (adopted) | Size-limit semantics of `getBytes` (JS truncates silently; Android, iOS and C++ fail) | `getBytes` throws `download-size-exceeded` when the object is larger than `maxSize`. It asks for `maxSize + 1` bytes with a `Range` header, so one extra byte proves the overflow. |
| 3 | 0.1.0 (adopted) | Resuming an upload session after the process was killed (Android `existingUploadUri`) | `UploadTask.sessionUri`, and `existingSessionUri` on `startUpload`, `startStreamUpload` and `putFile`. |
| 4 | 0.1.0 (adopted) | Error codes `invalid-root-operation` and `no-download-url`, which JS raises | Both exist, with the JS meaning. |
| 5 | 0.1.0 (adopted) | One request or a session for small uploads | `startUpload` sends a single multipart request up to 256 KiB and uses a resumable session above, as JS. `putBytes` and `putString` are always one multipart request. |
| 6 | 0.1.0 (adopted) | Tokens over plain http (iOS refuses unless https or loopback) | The client attaches a token only over https, to `emulatorHost`, or to a loopback host. |
| 7 | 0.1.0 (adopted) | Replay of the last state to a late subscriber (JS `on` does) | The `progress` stream starts with the current snapshot and does not replay earlier events. `state` and `bytesTransferred` are readable at any time, and `result` completes for a task that already finished. |
| 8 | later | Pause, resume and progress for downloads (Android and iOS tasks, C++ controllers) | A `DownloadTask` in the FlutterFire shim and `io.dart`, with `Range` resume from the offset of the temporary file. Not in the 0.1.0 surface. |
| 9 | later | An `ETag` or generation guard on resumed downloads (Android fails when the `ETag` changed) | Comes with 8; without it a resumed download can join two versions of an object. |
| 10 | later | Stream upload of unknown length (Android `putStream`) | `startStreamUpload` needs `length`. The resumable protocol needs the total at the end, so an unknown length needs buffering. |
| 11 | later | `internal-error` for impossible states | A catch-all code for bugs. |
| 12 | 0.1.1 (adopted) | Chunk size cap (iOS) and per-chunk retry limit (Android) | `FirebaseStorage(maxUploadChunkSize:)`: null (one request on the VM, like the iOS default) or a cap rounded down to 256 KiB multiples. It is transport configuration of the instance, as `uploadChunkSizeBytes` is on the iOS `Storage`, so it sits next to `maxConcurrentUploads` and not in `StorageRetryPolicy`, which is about retry time. The per-chunk retry limit stays a gap: the upload retry time covers it. |
| 13 | later | Emulator over https (JS, Cloud Workstations) | `emulatorHost` with an explicit scheme. Rare. |
| 14 | won't do | Active task registry, `compareTo`, `FullMetadata.ref`, `isFile` and `isFolder`, Kotlin and Swift sugar, `Activity` listeners, callback queues, Blob, Node streams, `FirebaseServerApp`, background URL sessions | Tied to another runtime, or covered by Dart streams and futures. The shim can add a task registry. |
| 15 | won't do | `app-deleted`, `invalid-event-name`, `invalid-argument-count`, `cannot-slice-blob`, `unsupported-environment`, `path-error` | Not reachable in Dart, or replaced by `StateError` or `ArgumentError`. |

## Deliberate differences from the JS SDK

Each of these is a fix, an addition or a choice. Each one has a test, named in the last column (paths are relative to `firebase_storage/firebase_storage_dart`).

| # | JS behaviour | Dart behaviour | Pinned by |
|---|---|---|---|
| 1 | `X-Firebase-GMPID` is never sent (`_appId` is always null, request.ts:251) | Sends `X-Firebase-GMPID: <app.options.appId>`, as Android and iOS do | `test/requester_test.dart`: headers > version and app id on every request, no token without a provider |
| 2 | `StorageError.status` is 0 for `object-not-found` (error.ts:42) | `httpStatus` holds the real HTTP status for every error | `test/conformance/errors_conformance_test.dart`: status mapping > 404 is object-not-found, with the status and the body (one test per status) |
| 3 | The body of an error response is not read for the status | `serverResponse` holds the body, capped at 16 KiB, never headers or tokens; a body that says the App Check token is invalid maps to `unauthorized-app` | `test/conformance/errors_conformance_test.dart`: the body in serverResponse is cut at 16 KiB; 401 with the App Check message in the body is unauthorized-app |
| 4 | `cancel()` acts from `running` only, although its doc says paused too | `cancel()` works from `paused` as well as `running`, as on Android | `test/conformance/task_conformance_test.dart`: cancel works from paused; `test/upload_task_test.dart`: cancel from paused |
| 5 | Chunks double while the size stays under 32 MiB; the effective cap is 16 MiB | Chunks start at 256 KiB, double after each successful chunk, stop at 16 MiB, and are a multiple of 256 KiB except the last | `test/upload_task_test.dart`: chunks double from 256 KiB and stop at 16 MiB |
| 6 | The backoff wait of the upload retry loop (`sleepTime`) never resets | The wait starts again from the beginning after a successful request | `test/conformance/task_conformance_test.dart`: the retry wait resets after a successful chunk; `test/upload_task_test.dart`: the wait doubles while chunks keep failing and starts over after a success |
| 7 | A 401 is final and maps to `unauthenticated` | One forced token refresh and one more request on a 401; a second 401 maps to `unauthenticated`. No official SDK does this. In production an invalid ID token gets 403 (`unauthorized`), not 401, so the refresh is not reached by invalid tokens; it applies when the backend answers 401 | `test/requester_test.dart`: 401 > is retried once with a refreshed token, a second 401 is unauthenticated; `test/conformance/errors_conformance_test.dart`: a 401 is sent again once with a refreshed token |
| 8 | Tokens are sent over any scheme | Tokens are sent only over https, to `emulatorHost`, or to a loopback host | `test/hardening_test.dart`: tokens travel only over https, to the emulator or to loopback; `test/security/hosts_test.dart`: token scope of the request layer |
| 9 | `getBytes` truncates silently at `maxDownloadSizeBytes` | `getBytes` throws `download-size-exceeded` | `test/reference_operations_test.dart`: an object larger than maxSize is download-size-exceeded; `test/security/limits_test.dart`: asks for maxSize + 1 bytes with a Range header |
| 10 | Downloads use the operation retry time (2 minutes) | `StorageRetryPolicy.download` has its own value, 10 minutes, as Android, iOS and C++ | `test/requester_test.dart`: downloads and uploads use their own retry time |
| 11 | Every resumable upload goes in chunks of 256 KiB doubling to 16 MiB | On the VM, an upload of bytes or of a file sends the rest of the object in one streamed request (`upload, finalize`); after a failure or a pause it queries the offset and streams from there. Streams, the web and instances with `maxUploadChunkSize` are chunked as JS | `test/upload_single_request_test.dart`: one request > bytes go in one request of the session, a failure in the middle resumes from the server offset (bytes, and a file) |
| 12 | No limit on uploads at once | `maxConcurrentUploads` (4 by default) queues the uploads of an instance, `putBytes` and `putString` included | `test/upload_single_request_test.dart`: maxConcurrentUploads > runs uploads in order, at most the limit at once |

## Differences between JS and the native SDKs worth knowing

- JS never reads the error body for the status; Android and iOS keep the body in `userInfo` or log it.
- JS `cancel()` only acts from `running` in the code path; Android cancels paused tasks. Dart follows Android.
- JS 401 never retries; the forced token refresh is Dart-only.
- JS download retry uses the 2 minute operation time; Android, iOS and C++ use a separate 10 minute download time. Dart uses the native split.
