# firebase_storage_dart examples

Small command-line programs, one per topic. They run against the local Storage emulator. From the
root of the repository (it needs Java and the Firebase CLI in `.emulator/`, see `tool/README.md`):

```sh
./tool/start_storage_emulator.sh 9199        # buckets demo-test.appspot.com and demo-test-auth.appspot.com
cd firebase_storage/firebase_storage_dart && dart pub get
FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 dart run example/upload_bytes_and_strings.dart
./tool/stop_storage_emulator.sh 9199         # when you are done, from the root again
```

Each program uses a folder of its own name plus a timestamp and deletes what it wrote. Without
`FIREBASE_STORAGE_EMULATOR_HOST` they stop with a message: none of them talks to a real project.

| File | Shows |
|---|---|
| `upload_bytes_and_strings.dart` | `putBytes`, and `putString` with each `StringFormat` (`raw`, `base64`, `base64Url`, `dataUrl`), with metadata. |
| `resumable_upload.dart` | `startUpload`: the `progress` stream, `result`, `pause()` / `resume()` and `cancel()` with the `bool` they return. |
| `streamed_download.dart` | `openRead()` as a stream, `openRead(start, end)` for a range, `getBytes()` with `maxSize`. |
| `files.dart` | `putFile` and `writeToFile` of `package:firebase_storage_dart/io.dart`: a file streamed into a resumable upload, and an object streamed into a file. |
| `list_and_paging.dart` | `list` with `maxResults` and `pageToken`, `listPages`, `listAll`; folders are `prefixes`. |
| `metadata.dart` | `metadata()`, `updateMetadata` with `SettableMetadata`, custom keys, and `MetadataField` to remove fields. |
| `download_url.dart` | `downloadUrl()`: the link with a token, read with a plain HTTP client. |
| `error_handling.dart` | `FirebaseStorageException`: `code`, `httpStatus`, `serverResponse`; a missing object, a rule that refuses, a bad argument, a closed client. |
| `emulator_and_auth.dart` | The bucket whose rules need a user, and `mockUserToken` to act as one; with a real project the token comes from `firebase_auth_providers_dart`. |

`common.dart` holds the setup the programs share: a `FirebaseApp` for the `demo-test` project, the two
bucket names, and `emulatorStorage()`, which reads `FIREBASE_STORAGE_EMULATOR_HOST`. Every program ends with
`storage.close()`.

For a complete program, see [`examples/storage_cli`](../../../examples/storage_cli), a command-line
tool on this package, and [`examples/server_shelf`](../../../examples/server_shelf) (a file API with
streamed uploads and downloads) and [`examples/web_app`](../../../examples/web_app) (a browser page
with an upload that can be paused).
