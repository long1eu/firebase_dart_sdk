## 0.2.0

- `startStreamUpload` takes the `length` as an optional argument. Without it the stream is uploaded in a
  resumable session until it ends, holding one chunk plus one read-ahead event in memory, like `putStream` on
  Android. Existing calls are unchanged. New: `UploadTask.totalBytes` and `UploadProgress.totalBytes` are -1
  while the length is unknown, so code that divides by them must check for it. `existingSessionUri` works
  with such a stream too (pass the whole data again).
- The error code `internal-error` (as in the JS and iOS SDKs) reports a state the client believes impossible,
  such as an upload session that reports bytes it was never sent.
- `startDownloadToFile(File)` in `package:firebase_storage_dart/io.dart` returns a `DownloadTask`: `progress`
  (`DownloadProgress` with `DownloadState`, at most one event per 64 KiB and 100 ms plus every change of
  state), `pause`, `resume`, `cancel` (from running and paused) and `result` (the `FullMetadata` of the
  object). A pause closes the connection; resuming asks for the rest with `Range: bytes=<written>-`. A body
  that breaks on the network is asked for again from the bytes written, with the backoff and the `download`
  time of `StorageRetryPolicy`; bytes received reset that time.
- Downloads to a file check the generation of the object on each response (`x-goog-generation`, or the
  metadata read again when a server does not send it) and fail with the new code `object-changed` instead
  of joining two versions of an object.
- File downloads send `Accept-Encoding: identity`, so a `Range` and the bytes received count the same stored
  bytes; an object stored with `Content-Encoding: gzip` arrives unzipped by the server.
- `writeToFile` runs on `DownloadTask`, so it also resumes after a network failure. It reads the metadata of
  the object before the content.

## 0.1.2

- Fix: on the VM, `openRead` from an offset and `getBytes(maxSize:)` of an object stored gzip-compressed
  (`contentEncoding: gzip`) failed with `unknown` ("Filter error, bad data"), or counted compressed bytes.
  The `dart:io` client asked for gzip, so the server sent the stored bytes and applied the `Range` header
  to them, while the client unzipped them. Requests for the bytes of an object now ask for the identity
  encoding on the VM: the server unzips the object, offsets and `maxSize` are in unzipped bytes, and the
  server answers a ranged request with the whole object (200), which the client cuts to the range. Seen on
  a real project (verification kit check 26). The web is unchanged: browsers unzip by themselves.

## 0.1.1

- On the VM, `startUpload` and `putFile` send the data in one streamed request of the resumable session,
  with progress per 64 KiB. After a failure or a pause they ask the server how much it has and send the
  rest from that offset, reading the file again from there. Streams (`startStreamUpload`) and uploads on the
  web stay chunked.
- `FirebaseStorage(maxUploadChunkSize:)` caps the requests of an upload; a value is rounded down to a
  multiple of 256 KiB, with 256 KiB as the minimum.
- `FirebaseStorage(maxConcurrentUploads:)`, 8 by default: the uploads of an instance over the limit
  (including `putBytes` and `putString`) wait in order. A waiting task is running with 0 bytes and can be
  paused or canceled; a paused task gives its turn to the next one.
- `requestTimeout` is an idle timeout: it fires when no byte of a request body is sent for that long, when
  no response arrives that long after the body was sent, or when a response body pauses that long. A long
  upload no longer times out while data flows.
- A file that gets shorter or longer during `putFile` fails the task with `invalid-argument`.

## 0.1.0

- First version: `FirebaseStorage` (bucket from the app's options or `gs://`, emulator host, retry policy),
  `Reference` (path operations, `metadata`, `updateMetadata`, `downloadUrl`, `delete`, `list`, `listAll`,
  `listPages`, `getBytes`, `putBytes`, `putString` with `StringFormat.raw`, `base64`, `base64Url` and
  `dataUrl`), `FullMetadata`, `SettableMetadata`, `ListResult` and `FirebaseStorageException`. Requests carry
  the Firebase Auth token of `app.authProvider` (refreshed once after a 401) and the App Check token of
  `app.appCheckProvider`, and are retried with the backoff of the JS SDK.
