# Adding a Firebase product

How a new product client (Storage was the last one; Realtime Database, Functions or Remote Config
could be next) is designed, built and tested in this repository. It is written for contributors,
human or agent, and complements [AGENTS.md](../AGENTS.md) and [ARCHITECTURE.md](ARCHITECTURE.md).

## Design rules

1. **An idiomatic Dart client first.** Design the API as a Dart library, not after FlutterFire's
   platform interface. Keep a FlutterFire name where it is also the natural Dart one (`Reference`,
   `FullMetadata`, kebab-case error codes). The FlutterFire adapter is a separate Flutter package,
   `<product>_dart_platform`, that does all the mapping. Compare `cloud_firestore_dart` with
   `cloud_firestore_dart_platform`, and `firebase_auth_providers_dart` with
   `firebase_auth_dart_platform`.
2. **The JS SDK is the reference for the protocol and the behaviour.** It talks REST or
   WebChannel, like this SDK. Use the Android and iOS SDKs where the JS SDK is unclear. Port the
   behaviour, not the code.
3. **Fix upstream quirks on purpose.** When the reference SDK does something that looks like a bug
   (Storage: the app id header is never sent, error bodies are never read, a paused upload cannot
   be canceled), fix it, and list it in the product's parity document with the test that pins it.
4. **Configuration is immutable.** Settings go to the constructor: no global instance cache and no
   setters that must be called before the first request. Provide
   `emulatorHostFromEnvironment` for the official `FIREBASE_<PRODUCT>_EMULATOR_HOST` variable and a
   `close()`. Inject the clock, randomness and delays so retries are tested without waiting.
5. **Tokens come from the app.** The user's ID token comes from `app.authProvider` (no dependency
   on the Auth package) and the App Check token from `app.appCheckProvider`. Send them only over
   https, to the configured emulator, or to a loopback host.
6. **The web from the first commit.** No `dart:io` in the main library: put file helpers in a
   separate `io.dart` library and use conditional imports. `dart compile js` and
   `dart compile wasm` accept a `dart:io` import, so a compile test proves nothing on its own; run
   `dart tool/check_web_imports.dart <package>`, which follows the web branch of the import graph.
7. **Fail closed.** Check sizes before reading a whole body, do not follow redirects, check the host
   of every URL the server hands back (a resumable upload URL is a capability), keep tokens and
   upload ids out of messages, and refuse control characters in header values.
8. **Exceptions:** a subclass of `FirebaseException` with kebab-case codes, the HTTP status, a
   size-capped server response, and the original error as `cause`, never in the message.

## Order of work

1. **Read** AGENTS.md, CONTRIBUTING.md, ARCHITECTURE.md, [how_we_test.md](how_we_test.md), the
   closest existing package and the token interfaces of `firebase_app_dart`. Check for legacy code
   to replace and that the pub.dev name is free.
2. **Write down the protocol** from the JS SDK source (its `packages/util` holds the emulator and
   mock-token helpers), with constants, headers, retry rules and error mapping.
3. **Probe the emulator.** Add `tool/start_<product>_emulator.sh` and the stop script (copy
   `tool/start_auth_emulators.sh`), call every endpoint, and record where the emulator differs from
   production. Each emulator gets its own temporary directory, and the hub and logging ports must
   not collide with other emulators.
4. **Compare the official SDKs** (JS, Android, iOS, C++) feature by feature, from source, in the
   format of [auth_parity.md](auth_parity.md), and rank the gaps: first release, later, or not
   applicable to Dart.
5. **Write the API contract**: Dart signatures and the decisions above, before implementation. The
   code replaces it once it exists.
6. **Build**: the request layer and core operations first, then long-running tasks (uploads),
   streaming and file IO, the FlutterFire adapter, docs (README, guide, parity document, CHANGELOG),
   CI wiring, security tests, conformance tests ported from the JS SDK's unit tests, browser tests,
   examples (per-topic programs in `example/`, a server, a web page, a Flutter app) and a production
   verification kit modelled on `tool/verify_production`.
7. **Test** in this order: unit tests, emulator integration, browser, the adapter, examples, the
   README snippet golden (`UPDATE_GOLDEN=1 dart test test/unit/api/readme_snippets_test.dart` in
   `cloud_firestore/cloud_firestore_dart`), then the production kit against a test project with a
   throwaway user, then CI.

## Tests

- Unit tests use `package:http`'s `MockClient` and pin production behaviour.
- Integration tests run against a private emulator and pin emulator behaviour, with a comment where
  it differs from production.
- Security tests live in `test/security/`, conformance tests in `test/conformance/`.
- Say what was verified where: "passed on the emulator" is not "works in production".

## Packaging and release

- New packages go into `tool/test_all.sh`, the `others` leg of the unit jobs in
  `.github/workflows/ci.yml`, and (Flutter packages) the Flutter job.
- `pubspec_overrides.yaml` points at sibling packages; lockfiles must not hold absolute paths.
- Releases are the maintainer's manual step (see AGENTS.md). Do not add a package to
  `release.yml` or `publish.yml` in a feature change.
