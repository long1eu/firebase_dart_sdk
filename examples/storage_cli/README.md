# storage_cli

`storage_cli`, a command-line tool on [`package:args`](https://pub.dev/packages/args) and
`firebase_storage_dart`:

| Command | What it does |
| --- | --- |
| `ls [path]` | Lists the prefixes (with a trailing `/`) and objects under a path, a page at a time (`--page-size`). |
| `put <file> <path>` | Resumable upload streamed from disk, with a progress line on stderr. `--content-type`, `--meta key=value` (repeatable). |
| `get <path> <file>` | Downloads an object, streamed to a file. |
| `cat <path>` | Writes an object to standard output. |
| `stat <path>` | Prints the metadata of an object as JSON. |
| `rm <path>` | Deletes an object. |
| `url <path>` | Prints the download URL. |

Global flags, each with an environment variable (the flag wins):

| Flag | Variable | Meaning |
| --- | --- | --- |
| `--emulator-host` | `FIREBASE_STORAGE_EMULATOR_HOST` | `host:port` of the Storage emulator |
| `--project` | `FIREBASE_PROJECT_ID` | project id; `demo-example` with an emulator |
| `--bucket` | `STORAGE_BUCKET` | default `<project>.appspot.com` |
| `--email`, `--password` | `STORAGE_EMAIL`, `STORAGE_PASSWORD` | sign in first, so rules with `request.auth` pass |
| `--create-account` | | create the user first (a new address on the Auth emulator) |
| `--auth-emulator-host` | `FIREBASE_AUTH_EMULATOR_HOST` | `host:port` of the Auth emulator |
| `--api-key` | `FIREBASE_API_KEY` | needed only to sign in to a real project |

Exit codes: `64` usage, `66` missing local file or object, `77` sign-in failed, `78` no backend
configured, `1` any other Storage error.

## Run it against the emulator

Needs the Dart SDK (3.8 or later) and the Storage emulator of `tool/start_storage_emulator.sh`
(see `tool/README.md`). From the repository root, then this directory:

```sh
./tool/start_storage_emulator.sh 9384     # buckets demo-test.appspot.com (open rules) and demo-test-auth.appspot.com
cd examples/storage_cli && dart pub get
export FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9384 FIREBASE_PROJECT_ID=demo-test
echo hello > hello.txt && dart run storage_cli put hello.txt docs/hello.txt && dart run storage_cli ls docs
dart run storage_cli cat docs/hello.txt && dart run storage_cli stat docs/hello.txt && dart run storage_cli rm docs/hello.txt
```

When you are done, `./tool/stop_storage_emulator.sh 9384`.

## Rules that need a user

The bucket `demo-test-auth.appspot.com` refuses everything without a signed-in user (`shared/`
for any user, `users/<uid>/` for its owner). Start an Auth emulator too, for example
`firebase emulators:start --only auth --project demo-test` (port 9099), then:

```sh
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
dart run storage_cli --bucket demo-test-auth.appspot.com put hello.txt shared/hello.txt   # unauthenticated
dart run storage_cli --bucket demo-test-auth.appspot.com --email me@example.com \
  --password correct-horse --create-account put hello.txt shared/hello.txt                # uploaded
```

The tool signs in with `FirebaseUserAuth` from `firebase_auth_providers_dart`, which registers
itself as the token provider of the `FirebaseApp`; `FirebaseStorage` reads the token from there for
each request.

## What it shows

- `putFile` (`package:firebase_storage_dart/io.dart`): a resumable upload that reads the file as a
  stream; `UploadTask.progress` feeds the progress line and `result` completes with the metadata.
- `writeToFile`: streams to a temporary sibling and renames on success, so a failed `get` never
  leaves a partial file. `openRead` pipes `cat` to standard output without buffering the object.
- `listPages`: follows `nextPageToken` lazily, so `ls` prints the first page before the second is
  requested.
- Errors are `FirebaseStorageException`s with a kebab-case `code` (`object-not-found`,
  `unauthenticated`, `unauthorized`, ...).

## Test

```sh
FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9384 dart test      # skipped with a reason when the variable is not set
```

Add `FIREBASE_AUTH_EMULATOR_HOST` to include the rules test.

Against a real project the tool takes `--project`, `--bucket` and, to sign in, `--api-key`; nothing
is written into a file.
