# Cloud Storage for Firebase

`firebase_storage_dart` is the Storage client of this repository: pure Dart, the REST protocol of the
Firebase JS SDK, no plugin and no native code. This guide covers how it relates to the rest of the
packages, the rules your requests must pass, retries and resumable uploads, and tests against the emulator.
The [package README](../../firebase_storage/firebase_storage_dart/README.md) has the install steps and an
example of each call.

## How a request is built

`FirebaseStorage(app)` needs only the `FirebaseApp` from `firebase_app_dart`. For each request it asks the
app for:

- the token of `app.authProvider` (`getAccessToken`), sent in the `Authorization` header. When the
  provider reports that no user is signed in, the header is left out and the Storage rules see
  `request.auth == null`;
- the token of `app.appCheckProvider`, sent as `X-Firebase-AppCheck`, when there is a provider and it
  returns a token;
- `X-Firebase-Storage-Version: dart/<version>` and `X-Firebase-GMPID: <appId>`.

A 401 answer makes the client fetch a fresh token once and send the request again.

The provider has to be set on the app before the first request. With `firebase_auth_providers_dart`:

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> signedIn(FirebaseApp app) async {
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
  await auth.signInWithEmailAndPassword(email: 'ada@example.com', password: 'a-password');

  final FirebaseStorage storage = FirebaseStorage(app);
  final Reference mine = storage.ref('users/${auth.uid}/profile.json');
  print(await mine.metadata());
}
```

A service account or Application Default Credentials (`OAuthTokenProvider.serviceAccount`,
`applicationDefaultCredentials()`) also work as the provider; those requests bypass the Storage rules, as
they do for Firestore. For code that holds such credentials, the Google Cloud Storage client is usually the
better fit, since it offers the whole bucket API.

## Rules and errors

The Storage security rules run on the server for every request. A request they refuse fails with
`unauthorized` (the user is signed in) or `unauthenticated` (no user), HTTP 403 or 401. Rules that need
`request.auth` are the usual reason for a request that works against open rules and then fails in the app.

```dart
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<bool> exists(Reference ref) async {
  try {
    await ref.metadata();
    return true;
  } on FirebaseStorageException catch (e) {
    if (e.code == 'object-not-found') {
      return false;
    }
    rethrow;
  }
}
```

`FirebaseStorageException` keeps the HTTP status in `httpStatus` and the error body of the server in
`serverResponse`. A request rejected because of App Check has the code `unauthorized-app`. Arguments that
cannot be valid, such as a `maxResults` of 0 or a negative range, throw an `ArgumentError` before any
request is sent.

## Retries

Network errors and the statuses 408, 429 and 5xx are retried with exponential backoff and jitter, until the
time of the `StorageRetryPolicy` has passed; then the call fails with `retry-limit-exceeded`. The wait after
a failure starts again from the beginning once a request succeeds.

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

FirebaseStorage patient(FirebaseApp app) => FirebaseStorage(
      app,
      retry: const StorageRetryPolicy(
        operation: Duration(seconds: 30),
        upload: Duration(minutes: 30),
        download: Duration(minutes: 5),
      ),
    );
```

The defaults are the ones of the JS SDK: 2 minutes for metadata, list and delete calls, 10 minutes for
uploads and for downloads.

## Resumable uploads

`startUpload`, `startStreamUpload` and `putFile` use the resumable protocol: the client opens an upload
session, sends the data in chunks and finalizes it. A chunk that fails is asked about (`query`) and sent
again from the offset the server has, so a dropped connection costs one chunk. `putBytes` and `putString`
send one multipart request; use them for small objects.

```dart
import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> pauseAndResume(Reference target, Uint8List data) async {
  final UploadTask task = target.startUpload(data);

  task.progress.listen((UploadProgress p) {
    if (p.state == UploadState.running && p.bytesTransferred > data.length ~/ 2) {
      task.pause();
    }
  });

  await Future<void>.delayed(const Duration(seconds: 1));
  if (task.state == UploadState.paused) {
    task.resume();
  }
  await task.result;
}
```

States: `running`, `paused`, `success`, `canceled`, `error`. `pause`, `resume` and `cancel` return `false`
when the current state does not allow them. `result` completes with the object's `FullMetadata`, or with a
`FirebaseStorageException`: `canceled` after `cancel()`, otherwise the error of the failed request.

An upload session lives only as long as the `UploadTask`; there is no way to continue it from another
process.

## Strings, and the format of the data

`putString` takes `StringFormat.raw` (UTF-8 text, the default), `base64`, `base64Url` or `dataUrl`. A data
URL sets the content type unless you pass one in the metadata.

```dart
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> strings(Reference ref) async {
  await ref.putString('aGVsbG8=', format: StringFormat.base64);
  await ref.putString('data:text/plain;base64,aGVsbG8=', format: StringFormat.dataUrl);
}
```

## Metadata

`updateMetadata` sends the fields you set. A `customMetadata` key with a `null` value is deleted on the
server; fields you leave `null` stay as they are. `FullMetadata.toJson()` gives the map of the object
resource for logging or caching.

```dart
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> tag(Reference ref) async {
  final FullMetadata metadata = await ref.updateMetadata(
    const SettableMetadata(
      contentLanguage: 'en',
      customMetadata: <String, String>{'reviewed': 'yes'},
    ),
  );
  print(metadata.toJson());
}
```

## Test against the emulator

Start the Storage emulator of the Firebase CLI (`firebase emulators:start --only storage --project
demo-my-app`, port 9199), or, in this repository, a private one with `tool/start_storage_emulator.sh [port]`
(default 9299; it creates `demo-test.appspot.com` with open rules and `demo-test-auth.appspot.com` with rules
that need a user, and `tool/stop_storage_emulator.sh [port]` stops it).

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> roundTrip() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:demo',
      projectId: 'demo-my-app',
      storageBucket: 'demo-my-app.appspot.com',
    ),
  );
  final FirebaseStorage storage = FirebaseStorage(app, emulatorHost: '127.0.0.1:9199');
  try {
    final Reference ref = storage.ref('test/hello.txt');
    await ref.putBytes(Uint8List.fromList(utf8.encode('hello')));
    print(utf8.decode(await ref.getBytes()));
    await ref.delete();
  } finally {
    storage.close();
  }
}
```

Things the emulator does differently from production: it does not enforce the 256 KiB multiple of resumable
chunks, and it ignores the content type of a request that is not multipart, so use `putBytes` or the
resumable calls with `SettableMetadata(contentType: ...)` when a test depends on it. Mock users
(`mockUserToken`) are evaluated by the rules of the emulator; tests of the rules themselves are better run
with the Firebase rules unit-testing library.

## Platforms

| Platform | Main library | `io.dart` |
| --- | --- | --- |
| Dart VM (servers, tools) | yes | yes |
| Flutter (Android, iOS, macOS, Linux, Windows) | yes | yes |
| Web | yes, over the browser's HTTP client; the bucket needs a CORS configuration | no |

## Not covered

No `DownloadTask`, no singleton and no instance cache, no signed URLs, no ACL or bucket management. The
`firebase_storage` API of FlutterFire is not offered by this package; a separate platform package is planned
to put that API on top of it.
