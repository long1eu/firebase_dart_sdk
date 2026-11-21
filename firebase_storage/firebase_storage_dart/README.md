# firebase_storage_dart

Unofficial, pure-Dart client for [Cloud Storage for Firebase](https://firebase.google.com/docs/storage),
for Dart servers, command line tools, Flutter apps and the web. It speaks the same REST protocol as the
Firebase JS SDK, with Dart names (`Reference`, `putBytes`, `UploadTask`) instead of a Flutter plugin or a
native SDK. It is not affiliated with or supported by Google or Firebase.

> **Status: 0.1.1, unreleased.** Verified with unit tests, against the Firebase Storage emulator, and once
> against a real Firebase project with a signed-in throwaway user (see [Verified](#verified)).

## Install

```shell
dart pub add firebase_storage_dart firebase_app_dart
dart pub add firebase_auth_providers_dart   # only when the Storage rules look at request.auth
```

Dart 3.8 or later; no Flutter dependency.

## Set up

`FirebaseStorage` is created from a `FirebaseApp`. Requests carry the token of the app's token provider, so
create the provider first (see [Authentication and App Check](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/authentication.md)).

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<the Web API key of the project>',
    appId: '1:1234567890:dart:example',
    projectId: 'my-project',
    storageBucket: 'my-project.appspot.com',
  ),
);
final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
await auth.signInAnonymously();

final FirebaseStorage storage = FirebaseStorage(app);
final Reference photo = storage.ref('users/${auth.uid}/photo.jpg');
print(photo.gsUri); // gs://my-project.appspot.com/users/<uid>/photo.jpg
```

The bucket is `app.options.storageBucket` unless you pass `bucket:` (`'my-bucket'` or
`'gs://my-bucket'`); with neither, the constructor throws an `ArgumentError`. A `FirebaseStorage` is
immutable: there is no global instance and no setting to change after the first request. Call `close()`
when you are done; it closes the HTTP client the instance created, and later calls throw a `StateError`.
Pass `httpClient:` to use your own client, which is then left open.

Without a token provider, requests carry no `Authorization` header and the Storage rules see no user,
which is enough for open rules and the emulator. The App Check token of the app, when it has an App Check
provider, is sent as `X-Firebase-AppCheck`; if getting it fails, the header is left out.

## Emulator

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: 'fake-api-key',
    appId: '1:1234567890:dart:example',
    projectId: 'demo-test',
    storageBucket: 'demo-test.appspot.com',
  ),
);
final FirebaseStorage storage = FirebaseStorage(
  app,
  emulatorHost: FirebaseStorage.emulatorHostFromEnvironment ?? '127.0.0.1:9199',
);
```

`emulatorHost` is `host:port`, reached over plain HTTP. `emulatorHostFromEnvironment` reads
`FIREBASE_STORAGE_EMULATOR_HOST` and is `null` on the web. `mockUserToken:` sets the token sent to the
emulator, as `connectStorageEmulator` does in the JS SDK; the emulator then evaluates your rules for that
user. In this repository `tool/start_storage_emulator.sh [port]` starts a private Storage emulator with an
open bucket and one whose rules need a signed-in user.

## Upload, download, metadata, delete

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> basics(FirebaseStorage storage) async {
  final Reference note = storage.ref('notes').child('hello.txt');

  final FullMetadata uploaded = await note.putBytes(
    Uint8List.fromList(utf8.encode('hello')),
    metadata: const SettableMetadata(
      contentType: 'text/plain',
      customMetadata: <String, String>{'author': 'ada'},
    ),
  );
  print('${uploaded.size} bytes, md5 ${uploaded.md5Hash}');

  await note.putString('hello again', metadata: const SettableMetadata(contentType: 'text/plain'));

  final Uint8List bytes = await note.getBytes(maxSize: 1024 * 1024);
  print(utf8.decode(bytes));

  final Uri url = Uri.parse(await note.downloadUrl());
  print(url);

  final FullMetadata updated = await note.updateMetadata(
    const SettableMetadata(cacheControl: 'max-age=60'),
  );
  print(updated.cacheControl);

  await note.delete();
}
```

`getBytes` buffers the object in memory and throws `download-size-exceeded` when it is larger than
`maxSize`. For large objects stream it with `openRead([start, end])`, which returns a `Stream<List<int>>`
like `File.openRead` and sends a `Range` header for a slice:

```dart
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> head(Reference video) async {
  int count = 0;
  await for (final List<int> chunk in video.openRead(0, 1024)) {
    count += chunk.length;
  }
  print('read $count bytes');
}
```

`downloadUrl()` returns the `https://firebasestorage.googleapis.com/...?alt=media&token=...` URL built from
the object's download token. Anyone holding the URL can read the object, whatever the rules say. An
object that has no download token has no such URL and the call throws a `FirebaseStorageException`.

## List

```dart
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> listing(FirebaseStorage storage) async {
  final Reference folder = storage.ref('photos');

  final ListResult page = await folder.list(maxResults: 100);
  for (final Reference prefix in page.prefixes) {
    print('folder ${prefix.name}');
  }
  for (final Reference item in page.items) {
    print('file ${item.fullPath}');
  }
  print(page.nextPageToken); // null on the last page

  final ListResult everything = await folder.listAll();
  print(everything.items.length);

  await for (final ListResult next in folder.listPages(pageSize: 50)) {
    print(next.items.length);
  }
}
```

Storage has no real folders: a prefix is the part of an object name before the next `/`. `list` takes
`maxResults` from 1 to 1000. `listAll` follows every page and holds the whole result; `listPages` fetches
one page at a time as you read the stream.

## Resumable upload with progress

`startUpload` and `startStreamUpload` return an `UploadTask`. It is not a `Future`: await `result`.

```dart
import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> resumable(Reference target, Uint8List data) async {
  final UploadTask task = target.startUpload(
    data,
    metadata: const SettableMetadata(contentType: 'application/octet-stream'),
  );

  final progress = task.progress.listen((UploadProgress p) {
    print('${p.state.name}: ${p.bytesTransferred} of ${p.totalBytes}');
  });

  // task.pause(); task.resume(); task.cancel();  each returns false when the state does not allow it
  try {
    final FullMetadata metadata = await task.result;
    print('uploaded ${metadata.fullPath}');
  } on FirebaseStorageException catch (e) {
    print('upload ended with ${e.code}'); // 'canceled' after cancel()
  } finally {
    await progress.cancel();
  }
}
```

`progress` is a broadcast stream that emits while data is sent and on every state change, and closes when
the task ends. The task starts as soon as it is created. A stream you listen to first emits the current
snapshot, then the new events; earlier events are not replayed. `cancel()` works from the running and the
paused state.

How the data goes:

- Up to 256 KiB: one multipart request, like `putBytes`.
- On the VM, bytes (`startUpload`) and files (`putFile`): one streamed request of a resumable session, with
  progress per 64 KiB. After a failure or a pause the task asks the server how much it has and sends the rest
  from there.
- `startStreamUpload`, every upload on the web, and every upload of a `FirebaseStorage` created with
  `maxUploadChunkSize`: chunks that start at 256 KiB and double after each success, up to 16 MiB (or
  `maxUploadChunkSize`). A stream is chunked because the chunk is what is sent again after a failure; the
  web, because the browser reports no progress inside a request, so progress there comes per chunk.

`startStreamUpload(stream, length: n)` uploads a stream whose total length you know, holding one chunk in
memory.

At most `maxConcurrentUploads` uploads of a `FirebaseStorage` run at once (4 by default; `putBytes` and
`putString` count). The others wait in order in the running state with 0 bytes; `pause()` and `cancel()`
work while a task waits, and a paused task gives its turn to the next one.

`requestTimeout` (1 minute by default) is an idle timeout: a request is retried when no byte of its body is
sent for that long, when no response comes that long after the body was sent, or when a response body
pauses that long. A long upload or download does not time out while data flows.

## Files on the VM and in Flutter

`package:firebase_storage_dart/io.dart` adds file helpers; it needs `dart:io` and does not compile for the
web.

```dart
import 'dart:io';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/io.dart';

Future<void> files(Reference backup) async {
  final UploadTask task = backup.putFile(File('backup.tar.gz'));
  await task.result;

  final int written = await backup.writeToFile(File('restored.tar.gz'));
  print('$written bytes');
}
```

`putFile` is a resumable upload that streams from disk; after a failure it reads the file again from the
offset the server reports. `writeToFile` streams into a temporary file next
to the target and renames it when the download finishes, so a failed download does not leave a partial
file.

## Web

The main library compiles for the web and uses `package:http`'s browser client. Things to know:

- The browser enforces CORS. Set it on the bucket (`gsutil cors set`) for the origins of your app; the
  emulator allows any origin.
- `io.dart` is not available. Upload with `putBytes`, `putString` or `startUpload`, and read with
  `getBytes` or `openRead`.
- `FirebaseStorage.emulatorHostFromEnvironment` is `null`; pass `emulatorHost` yourself.

## Errors

Every failure is a `FirebaseStorageException`, which extends `FirebaseException` (`plugin` is
`'firebase_storage'`):

```dart
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> readOrNull(Reference ref) async {
  try {
    await ref.getBytes();
  } on FirebaseStorageException catch (e) {
    switch (e.code) {
      case 'object-not-found':
        print('no such object');
      case 'unauthorized' || 'unauthenticated':
        print('the rules refused the request (HTTP ${e.httpStatus})');
      case 'retry-limit-exceeded':
        print('gave up after the retry time of the policy');
      default:
        print('${e.code}: ${e.message} ${e.serverResponse ?? ''}');
    }
  }
}
```

`code` is the lower-case, hyphenated name without the `storage/` prefix the JS SDK uses. `httpStatus` is
the HTTP status of the last response when there was one. `serverResponse` is the body of the error
response, capped at 16 KiB; it never holds headers or tokens.

Requests that fail with a network error, a 408, 429 or 5xx status are retried with exponential backoff
until the `StorageRetryPolicy` time runs out (2 minutes for an operation, 10 for an upload or a download by
default). A 401 triggers one token refresh and one more try. Production answers an invalid ID token with 403, not
401, so that refresh is not reached by invalid tokens.

## Verified

The verification kit (`tool/verify_production_storage` in the repository) ran against a real project with a
signed-in throwaway user: 19 of its 20 checks passed, and check 13 (the refresh after a 401) was
inconclusive, because production does not answer 401 to an invalid token. What it found:

- A missing object answers 404 with a JSON envelope; the emulator sends plain text.
- `Range` gets 206, and a range past the end of the object gets 416.
- List page tokens are 72 base64 characters long.
- `md5Hash` is not verified on upload. Production stores the real hash of the data, whatever you send, so
  compare the `md5Hash` of the returned `FullMetadata` with your own.
- The App Check header and `X-Firebase-GMPID` are accepted.
- An invalid ID token gets 403, not 401. The one forced token refresh on a 401 is therefore not reached by
  invalid tokens.
- CORS: `access-control-allow-origin` is `*`, the `x-goog-upload-*` headers are exposed on the session
  responses, and the preflight to the upload URL allows `x-goog-upload-command` and `x-goog-upload-offset`.
- Upload progress is per byte on the VM and per chunk on the web.

## What is not supported

- No `DownloadTask`: stream with `openRead` or `writeToFile`.
- No `FirebaseStorage.instance`, and no instance cache: keep the object you create.
- No Firebase Auth in this package; use
  [`firebase_auth_providers_dart`](https://pub.dev/packages/firebase_auth_providers_dart).
- No Admin SDK features (signed URLs, ACLs, bucket management); those belong to the Google Cloud Storage
  client for trusted code.
- A download URL needs a download token that the backend created at upload. Objects uploaded with the plain
  Cloud Storage API have none, and `downloadUrl()` throws `no-download-url` for them; minting a token is a
  server task.

Parity with the other SDKs and the deliberate differences from the JS SDK:
[docs/storage_parity.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/storage_parity.md).
Why it is built this way: [docs/storage_decisions.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/storage_decisions.md).
More: [the Storage guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/storage.md).

## License

Apache License 2.0, as the rest of the repository.
