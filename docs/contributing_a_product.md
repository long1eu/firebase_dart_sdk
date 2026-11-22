# Adding a Firebase product

How a new product client (Realtime Database was the last one, after Firestore and Storage;
Functions or Remote Config could be next) is designed, built and tested in this repository. It is
written for contributors, human or agent, and complements [AGENTS.md](../AGENTS.md) and
[ARCHITECTURE.md](ARCHITECTURE.md).
[storage_decisions.md](storage_decisions.md) and [database_decisions.md](database_decisions.md)
record the decisions of the Storage and Realtime Database clients.

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
9. **Numbers from a server are untrusted, and the web has its own number rules.** Compiled to
   JavaScript an infinity passes `is int`, `1.0` prints as `1`, `1 << 32` is 0 and integers above
   2^53 lose precision. Ask every number that arrives from a server `isFinite`, and route number
   checks through one helper. `1e999` from the server passed the request-number, tag and data checks
   of the database client on the web, with hundreds of green VM tests.

## Order of work

1. **Read** AGENTS.md, CONTRIBUTING.md, ARCHITECTURE.md, [how_we_test.md](how_we_test.md), the
   closest existing package and the token interfaces of `firebase_app_dart`. Check for legacy code
   to replace and that the pub.dev name is free.
2. **Write down the protocol** from the JS SDK source (its `packages/util` holds the emulator and
   mock-token helpers), with constants, headers, retry rules and error mapping.
3. **Probe the emulator.** Add `tool/start_<product>_emulator.sh` and the stop script (copy
   `tool/start_auth_emulators.sh`), call every endpoint, and record where the emulator differs from
   production. Each emulator gets its own temporary directory, and the hub and logging ports must
   not collide with other emulators. The script refuses the Firebase CLI's default ports and
   defaults to a port of the repository's own, and every example and tool defaults to that same
   port: examples that defaulted to 9000 could not reach an emulator started by the database
   script. Measure before deciding protocol behaviour, and write the measured facts down with the
   emulator version; two decisions about key ordering and integer keys were overturned by
   measurement and by reading the upstream source.
4. **Compare the official SDKs** (JS, Android, iOS, C++) feature by feature, from source, in the
   format of [auth_parity.md](auth_parity.md), and rank the gaps: first release, later, or not
   applicable to Dart.
5. **Write the API contract**: Dart signatures and the decisions above, before implementation. The
   code replaces it once it exists. A document written before the code is checked against the code
   by someone other than its author: the database contract had ten statements the code
   contradicted.
6. **Build**: the request layer and core operations first, then long-running tasks (uploads),
   streaming and file IO, the FlutterFire adapter, docs (README, guide, parity document, CHANGELOG),
   CI wiring, security tests, conformance tests ported from the JS SDK's unit tests, browser tests,
   examples (per-topic programs in `example/`, a server, a web page, a Flutter app) and a production
   verification kit modelled on `tool/verify_production`.
7. **Test** in this order: unit tests, emulator integration, browser, the adapter, examples, the
   README snippet golden (`UPDATE_GOLDEN=1 dart test test/unit/api/readme_snippets_test.dart` in
   `cloud_firestore/cloud_firestore_dart`), then the production kit against a test project with a
   throwaway user, then CI.
8. **Review** anything that touches the network, storage, concurrency or security once the suite
   is green: an independent code review by a reviewer who did not write the code and is not told
   what to conclude. Two reviews of the database connection and SQLite packages found 4 high and
   13 medium defects in code whose suites were green, among them a storage error that deleted
   pending writes and a timeout rule that failed requests that were not slow.

## Tests

- Unit tests use `package:http`'s `MockClient` and pin production behaviour.
- Integration tests run against a private emulator and pin emulator behaviour, with a comment where
  it differs from production.
- Security tests live in `test/security/`, conformance tests in `test/conformance/`.
- Say what was verified where: "passed on the emulator" is not "works in production".
- **A browser leg is the whole test tree**, run on dart2js and on dart2wasm, with VM-only files
  marked `@TestOn('vm')`. Running a chosen list of folders is not a browser leg: the connection's
  own unit tests had never been compiled to JavaScript, and 22 failed on the first full run.
- **No real-time waits under about 100 ms.** A browser clamps nested timers to 4 ms, so short
  waits do not survive it. Drive time with `fake_async`, or use wide margins.
- **Analyze on the lowest supported Dart and on the newest stable**; each reports things the other
  does not. Dart 3.13 reported a Future returned from inside a `try` without `await` in the SQLite
  package, a real defect that 3.11 did not report. Run the suite once on the lowest SDK the
  pubspec declares before claiming it.
- **Windows:** do not shell out to Unix tools in tests (`which`), and do not expect an open file to
  be deletable. A test that stands in for a crashed process by keeping a handle open behaves
  differently there.
- **`flutter test` on a file under `integration_test/` picks a connected device.** A gate that must
  run on the host goes through a wrapper under `test/`; a gate run tried to build for a connected
  phone.
- **Check every fix with a revert.** Break the production code and see the test fail for the stated
  reason; a mutation that does not compile proves nothing. A test for stray files passed with the
  code under test disabled.
- **Benchmarks:** record the power state of the machine (Low Power Mode halves the numbers), compare
  only runs taken in the same state, and report a missed target with the measured cause.

## Packaging and release

- New packages go into `tool/test_all.sh`, the `others` leg of the unit jobs in
  `.github/workflows/ci.yml`, and (Flutter packages) the Flutter job.
- `pubspec_overrides.yaml` points at sibling packages; lockfiles must not hold absolute paths.
- Releases are the maintainer's manual step (see AGENTS.md). Do not add a package to
  `release.yml` or `publish.yml` in a feature change.
