# Why use this library instead of the official ones

A note for the maintainer, to decide where to aim the project. It answers one question: when would a developer
pick `cloud_firestore_dart` over FlutterFire (`cloud_firestore`, `firebase_core`, `firebase_auth`) or, on a
server, over the Dart Admin SDK (`firebase_admin_sdk` / `google_cloud_firestore`), `googleapis` or `firedart`?

Every outside source below was checked on **2026-11-16** unless a line says otherwise. Statements about this
repository come from `docs/parity.md`, `docs/guides/*.md` and `docs/support_policy.md` at `origin/main`
(`eb33218a`). Nothing was built or run for this note; no Firebase service was contacted.

**Updated 2026-11-17** for three facts that came after it, read at `origin/main` (`b67e8e3e`) and on pub.dev
on that date:

- A Flutter Linux desktop app written only against the official `cloud_firestore` and `firebase_core` API was
  built and run on 2026-11-16, with `cloud_firestore_dart_platform` 0.1.0 from pub.dev: Debian 13 x86_64,
  Flutter 3.44.9, debug build under Xvfb, Firestore emulator only. Its 3 integration tests that drive the
  window passed, and so did a disk-cache test across a restart with the emulator stopped. Source: the run
  record in the README of [`examples/flutterfire_on_linux`](../examples/flutterfire_on_linux/).
- `firebase_admin_dart` 0.1.0 is on `main` (`firebase_admin/firebase_admin_dart`): Firebase Auth custom
  tokens, users, custom claims and ID token verification. Checked with unit tests and the Auth emulator (its
  README). See the 2026-11-18 update below for its first run against a real project.
- 0.2.0 of `cloud_firestore_dart`, `firebase_app_dart` and `firebase_auth_providers_dart` (pub.dev,
  2026-11-16) took FlutterFire's API names (`docs/api_migration_0_2.md`). `cloud_firestore_dart_sqlite`,
  `cloud_firestore_dart_platform` and `cloud_firestore_dart_flutterfire` 0.1.0 were published the same day.
  The examples on `main` use 0.2.

**Updated 2026-11-18** for one fact, from the run record in the README and CHANGELOG of `firebase_admin_dart`:

- `firebase_admin_dart` 0.1.0 passed its production check against one real Firebase project on 2026-11-18,
  with `firebase_auth_providers_dart` 0.2.1 as the client, keyless: admin calls with the Application Default
  Credentials of a person, custom tokens signed by the IAM Credentials API (`signBlob`) as a service account.
  All seven steps passed (create a user, mint a custom token and sign in, claims in the ID token,
  `verifyIdToken` with `checkRevoked`, custom claims, revocation, delete). Not run against a real project:
  local signing with a key file, `findUserByEmail`, `updateUser`, `deleteUsers`, tenants, the metadata server
  of Google Cloud.

**Updated 2026-11-20** for the 0.3.1 release, the web, and fresh numbers. Repository facts are read on branch
`wave/why-this-library-update` (`2d703778`, on top of `origin/main`), in `docs/parity.md`, `docs/guides/web.md`,
`docs/guides/platforms.md`, `docs/support_policy.md` and the CHANGELOG of `cloud_firestore_dart`. Nothing outside
this repository was re-checked except the adoption numbers below. No Firebase service was contacted.

- Versions: `cloud_firestore_dart` 0.3.1 (pub.dev, published 2026-11-20), `firebase_app_dart` 0.2.0,
  `firebase_auth_providers_dart` 0.3.0, `cloud_firestore_dart_sqlite` 0.1.3, `cloud_firestore_dart_platform`
  0.1.1, `cloud_firestore_dart_flutterfire` 0.1.1, `firebase_admin_dart` 0.1.1. Where this note says "version 0.2"
  below, read 0.3.1; the FlutterFire API names of 0.2 are unchanged.
- Tests: the full unit suite had 6869 passing tests on this branch on 2026-11-20 (run for this note). No newer
  integration count exists in the repository: `docs/parity.md` still gives 887 passed and 21 skipped over gRPC, and
  882 passed and 26 skipped over each web transport, run on 2026-11-14. The integration suite was not run for this
  update.
- No longer experimental since 0.3.1 (CHANGELOG): Firestore Lite, the cache in your own storage, `mergeUnsentWrites`,
  `importJsSdkCache` and `deleteJsSdkCache`, the pending write count, and the IndexedDB cache engine on the web
  (it reads and writes the JS SDK's own database, rows and schema). The CHANGELOG states what each was tested with:
  mostly the emulator and Chrome, never a production backend. Pipelines stay a preview.
- Multi-tab, a preview that is unreleased (CHANGELOG "(unreleased)", `docs/guides/web.md`):
  `indexedDbCacheSettings(multiTab: true)` lets several tabs share one IndexedDB cache. Chrome only, emulator only,
  tested with dart2js and dart2wasm. **Never tried with a JS SDK tab beside a tab of this client.** Not tested
  either: the handover on real visibility changes, different users in the tabs, other browsers. The SQLite caches
  stay at one tab, and secondary isolates on the Dart VM still do not share listeners through the public API.
  The statements "one tab per persistent cache" and "several tabs ... not supported" were true on 2026-11-16;
  they are updated in place below, with a mark.
- The web is now a reason (new reason 6 in "The answer", Hypothesis 6 and the table). It is the weakest of the
  six, because its evidence is a CI interop job and emulator tests in one browser.
- Long offline use is now a reason (new reason 5 in "The answer"), from the measurements of
  `docs/guides/long_offline.md`. Its weak point is that the official SDKs were not measured the same way.
- Adoption on 2026-11-20 (pub.dev API `/score`, and `gh api repos/long1eu/firebase_dart_sdk`): 221 downloads in
  30 days (58 on 2026-11-16), 0 likes (0), 80 GitHub stars (80). The 499 of 513 commits was not counted again.
- Not changed: every outside source (FlutterFire, the Admin SDK, `firedart`, Flutter docs, the other pub.dev
  numbers) is still as of 2026-11-16 to 2026-11-18.

## The answer

Ranked by how strong the evidence is that this library is the better or the only choice today.

1. **Flutter apps on Linux desktop and embedded Linux.** FlutterFire has no Linux implementation, and in July
   2026 a maintainer closed a community PR that added it: "Linux support is not currently on the FlutterFire
   roadmap" ([flutterfire#18461](https://github.com/firebase/flutterfire/pull/18461), closed 2026-07-23).
   Here this library is the only Firestore client with listeners and an offline cache, and through
   `cloud_firestore_dart_platform` the app keeps the official `cloud_firestore` API. Caveat: one app was built
   and run on Debian 13 x86_64, a debug build against the emulator (see the update above); no sign-in, no
   real project, no release build, no embedded board.
2. **Dart servers, workers and CLIs that need real-time listeners, an offline cache, or access as a Firebase
   user under security rules.** The official Dart Admin SDK has no listeners: its own design note says "no
   bidirectional `Listen` RPC, so realtime listeners are a transport limit and a gap"
   ([rest-transport.md](https://github.com/firebase/firebase-admin-dart/blob/main/.agents/knowledge/firestore/rest-transport.md)).
   `firedart` has no query operators, no cache and no retries ([README](https://github.com/cachapa/firedart)).
   Caveat: draft PRs to add listeners to the Admin SDK were opened on 2026-11-09 (see Hypothesis 2), so the
   listener part of this lead may last months, not years. The user-under-rules and offline-cache parts do not
   depend on that.
3. **Firestore listeners on a background isolate in a Flutter app.** FlutterFire's own tracking issue lists
   `cloud_firestore` as "no support for subscribing to documents" on background isolates and was closed as not
   planned ([flutterfire#10353](https://github.com/firebase/flutterfire/issues/10353), closed 2026-06-23). A
   pure-Dart client runs in any isolate. Caveat: not tried in a Flutter app here; each isolate needs its own
   app name or cache (`docs/guides/multiple_clients.md`).
4. **Windows desktop in production.** Firebase says "Firebase on Windows is not intended for production use
   cases, only local development workflows" ([Flutter setup](https://firebase.google.com/docs/flutter/setup)),
   and the Windows plugin rejects sum and average aggregations, pipelines and the cache index manager
   ([cloud_firestore_plugin.cpp](https://github.com/firebase/flutterfire/blob/main/packages/cloud_firestore/cloud_firestore/windows/cloud_firestore_plugin.cpp)).
   The gap is well proven; that this library fills it is shown only on one Windows 11 VM against the emulator
   (2026-11-17): the test suites pass there, and a Flutter Windows app on the official API ran sum and average
   aggregations through it (`examples/flutterfire_on_windows`). Not in CI, not on a logged-on desktop, not
   against production.
5. **(Added 2026-11-20) An app that stays offline for weeks or months and keeps writing** (field work, kiosks,
   embedded devices; it goes with reason 1). `docs/guides/long_offline.md` measured the SQLite cache with queues
   of 10,000 to 10 million pending writes: a write, a read by key, a reopen and garbage collection stay
   constant; a query of a collection of 10 documents among 1 million pending writes takes 0.09 ms (246 ms before
   the fixes). Two extensions that the official SDKs do not have matter here: `mergeUnsentWrites` keeps a
   document that is edited many times as one pending write (the drain of 100,000 edits of one document with a
   `serverTimestamp`: 0.09 s with it, 344 s without), and `getPendingWriteCount()` / `pendingWriteCounts()` show
   the queue while it drains. Caveat: no period of a year was run, the queues were generated. One machine (a Mac
   with 64 GB, `synchronous = OFF`), the emulator only; no phone, no production drain (estimated at about 8
   minutes for 100,000 writes and 1.4 hours for 1 million, bounded by the backend). The cache file grows by
   about 1 KB per pending document and nothing shrinks it. `mergeUnsentWrites` changes what rules and functions
   see. **The official SDKs were not measured with the same queues**, so this is "measured, with its limits
   written down", not "better than FlutterFire".
6. **(Added 2026-11-20) A web app whose users are on the Firebase JS SDK or FlutterFire web, and that wants to
   move to this client without losing their offline cache.** The IndexedDB engine reads and writes the JS SDK's
   own database (documents, pending writes of every user, indexes, bundles), so the switch needs no import step
   and works in both directions; `importJsSdkCache` moves a JS cache, pending writes included, into the other
   engines (SQLite, memory, your own storage); and tabs can share the cache with `multiTab: true`. Caveat:
   Chrome only, against the emulator only. The evidence for the format is the JS SDK interop job in CI
   (`tool/bench/web_idb/js_import/interop_check.sh`, `firebase` 12.19.0, headless Chrome, both ways, run when the
   engine changes) and the persistence suites on the engine (about 600 tests). No JS SDK tab was ever run beside
   a tab of this client. Multi-tab is a preview and unreleased. The reason exists only for an app that already
   has a JS SDK cache to keep; it is not a reason to choose this client for a new web app.

Two weaker reasons follow: testing real client code under `dart test` against the emulator (Hypothesis 3), and
Firestore in a Dart web app that does not use Flutter, such as Jaspr (Hypothesis 7).

Four reasons that were expected and **do not hold up** today: iOS build time (Firestore now ships precompiled
through Swift Package Manager, the Flutter default since 3.44), dart2wasm (the FlutterFire web plugins are
`is:wasm-ready`), web bundle size (about the same; this is separate from reason 6), and de-Googled Android (Firestore and Auth do not need
Google Play services). Feature gaps are also not a reason: FlutterFire has pipelines, bundles, named databases
and the cache index manager.

## Hypothesis 1: platform gaps

**What is true today.**

- `cloud_firestore` 7.1.0 on pub.dev carries the tags android, ios, windows, macos, web. **No linux, and no
  pure-Dart (`sdk:dart`) tag**: it needs Flutter
  ([pub.dev API](https://pub.dev/api/packages/cloud_firestore/score)). Same for `firebase_core` and
  `firebase_auth`. `cloud_firestore_dart` has all six platforms and `sdk:dart`.
- The FlutterFire README marks Cloud Firestore as beta on macOS and "(\*) for development only. Production on
  Windows is not supported"; it has no Linux column
  ([README](https://github.com/firebase/flutterfire#readme)). The Firebase setup page says the same for
  Windows and does not mention Linux ([Flutter setup](https://firebase.google.com/docs/flutter/setup)).
- Linux: a community PR added Linux to core, auth, firestore, database, storage and others; it was closed
  unmerged because Linux "is not currently on the FlutterFire roadmap"
  ([#18461](https://github.com/firebase/flutterfire/pull/18461), 2026-07-23). The open request for Linux in
  `firebase_auth` has 37 thumbs-up ([#17338](https://github.com/firebase/flutterfire/issues/17338), opened
  2025-05-07). Invertase's `firebase_core_desktop` and `firebase_auth_desktop` (Linux and Windows, no
  Firestore) were last published in August 2022.
- Windows: the plugin wraps the Firebase C++ SDK. Missing on Windows in the current source: sum and average
  ("not supported by the Firebase C++ SDK on Windows"), pipelines and the persistent cache index manager
  ("Not implemented on Windows"). Open crash reports exist
  ([#12987](https://github.com/firebase/flutterfire/issues/12987), app crashes getting a document, open since
  2024-06), and a PR from 2026-11-10 fixes the Windows codec not forwarding `persistenceEnabled`
  ([#18936](https://github.com/firebase/flutterfire/pull/18936), open).
- Embedded Linux (flutter-pi, flutter-elinux and similar embedders): these use Linux plugins, so with no Linux
  implementation there is no FlutterFire Firestore there. This is inferred from the above; no embedder's
  plugin list was checked.
- Non-Flutter Dart: no Google client SDK exists. The official Dart option is the Admin SDK (Hypothesis 2).

**This library.** Linux is tested on the Dart VM (CI on Ubuntu x64, a Debian arm64 container). On Windows 11
x64 (one VM, 2026-11-17) the Dart VM suites pass, and `flutter_notes` and `flutterfire_on_windows` were built
and run against the emulator (no window drawn). No Flutter app was built for Android or iOS
(`docs/guides/flutter.md`). Updated
2026-11-17: a Flutter Linux app on the official `cloud_firestore` API ran on Debian 13 x86_64 with
`cloud_firestore_dart_platform`, against the emulator, in a debug build (see the update at the top).

**How sure.** High that the gaps exist. Medium-high that this library fills Linux (Dart VM tested, one Flutter
Linux app run against the emulator). Medium-low for Windows: one VM, emulator only.

**Unverified.** Sign-in in a Flutter Linux app (`firebase_auth` has no Linux implementation), a real project
and TLS from a Flutter Linux process, a release build, arm64 and other distributions, a Windows release build, a logged-on
Windows desktop, Windows in CI, an embedded board.

## Hypothesis 2: pure-Dart servers and CLIs

**What the existing options give.**

| | Dart Admin SDK (`firebase_admin_sdk` 0.5.6 / `google_cloud_firestore` 0.5.5) | `firedart` 0.9.8 | `googleapis` 19.0.0 (`FirestoreApi`) | this library |
|---|---|---|---|---|
| Publisher | firebase.google.com (repo `firebase/firebase-admin-dart`, built by Invertase) | cachapa.net | google.dev (generated REST client) | none (one person) |
| Transport | REST (HTTP/2 pool) | gRPC | REST | gRPC on the VM, WebChannel on the web |
| Real-time listeners | no (TODO in source; draft PRs) | yes, but "closed streams are not automatically recovered" | no (not checked in source) | yes, with resume and backoff |
| Queries | full, plus pipelines, vector search, bulk writer, recursive delete, partitions | "collection queries (limit, sort, etc.) are currently not supported" | raw REST | full, plus pipelines (preview) |
| Transactions | yes | no | raw REST | yes, read-write and read-only |
| Offline cache, pending writes | no | "the data is not cached locally" | no | yes (memory or SQLite) |
| Identity | service account / ADC, bypasses rules | Firebase user (REST sign-in), under rules | OAuth | service account / ADC (bypasses rules) or a Firebase user (under rules) |
| Last release | 2026-09-21; repo active (2026-11-13) | 2024-03-15; last push 2024-07 | 2026-11-12 | 2026-11-16 |

Sources: [firebase_admin_sdk](https://pub.dev/packages/firebase_admin_sdk),
[google_cloud_firestore README](https://github.com/firebase/firebase-admin-dart/tree/main/packages/google_cloud_firestore),
[rest-transport.md](https://github.com/firebase/firebase-admin-dart/blob/main/.agents/knowledge/firestore/rest-transport.md)
(`// TODO onSnapshot` in `query.dart`, `// TODO snapshots` in `document_reference.dart`),
[firedart README "Limitations"](https://github.com/cachapa/firedart#limitations),
[googleapis](https://pub.dev/packages/googleapis), this repo's `docs/guides/server.md` and `docs/parity.md`.
`dart_firebase_admin` (Invertase) is marked discontinued on pub.dev and replaced by `firebase_admin_sdk`.

**The listener lead is closing.** Listener requests in the Admin SDK date from 2025-10-01
([#95](https://github.com/firebase/firebase-admin-dart/issues/95)); a maintainer answered then that streaming
"isn't supported yet ... It's being discussed with Google". On 2026-11-09 an Invertase engineer opened three
draft PRs: generated protos ([#346](https://github.com/firebase/firebase-admin-dart/pull/346)), a Listen
transport ([#350](https://github.com/firebase/firebase-admin-dart/pull/350)) and an internal watch "a draft
proof of concept and isn't meant for release yet"
([#352](https://github.com/firebase/firebase-admin-dart/pull/352)). Expect admin-side listeners in Dart within
some months.

**What stays different after that.** The Admin SDK is admin access. This library can also act as a signed-in
Firebase user whose reads and writes are checked by security rules (email/password, anonymous or custom token,
`docs/guides/server.md`), and it keeps an offline cache with pending writes that survive a restart. That fits a
CLI on a laptop, a kiosk or field device, or an agent process that must not hold admin rights. It is the same
engine as the mobile SDKs, not a server SDK: no bulk writer, no recursive delete, no partitioned queries.
Updated 2026-11-17: `firebase_admin_dart` 0.1.0 adds a small set of Firebase Auth admin calls (custom tokens,
users, claims, ID token verification). Updated 2026-11-18: besides the Auth emulator, its main path passed once
against a real project, keyless (see the update at the top).

**How sure.** High for the current table (read from source and READMEs). Medium on timing of Admin listeners.

**Unverified.** Whether `googleapis` exposes `listen` usefully (its generated REST client is said to buffer
server streams, per the Admin note above; not checked in `googleapis` itself). Whether anyone needs
"user under rules on a server" at scale: no issue or discussion asking for it was found.

## Hypothesis 3: testing

**Today with FlutterFire.** The plugins talk to native code over platform channels, so under `flutter test` they
fail with `MissingPluginException` ([#3311](https://github.com/firebase/flutterfire/issues/3311)). Teams either
use a fake or run `integration_test` on a device, simulator or desktop against the emulator. The fake is
popular: `fake_cloud_firestore` has 344,284 downloads in 30 days and 148 likes
([pub.dev](https://pub.dev/packages/fake_cloud_firestore)). It is a reimplementation, not the SDK: its README
says security rules are checked only for operations on `DocumentReference`, not for batches, collections or
queries, and timestamps are not supported in rules
([README](https://github.com/atn832/fake_cloud_firestore#security-rules)).

**This library.** The real client (sync engine, cache, listeners, pending writes, transactions) runs under
`dart test` or `flutter test` against the emulator, with `mockUserToken` for rules as a user
(`docs/guides/emulator_and_testing.md`). The repository's own 887 integration tests over gRPC (882 over each web transport; `docs/parity.md`, run
2026-11-14, not repeated since) and its 6869 passing unit tests (2026-11-20) run this way or need no backend.

**The catch.** The test runs this engine, not the Android or iOS one that ships, so it tests the app logic and
the rules, not the production SDK. Updated 2026-11-17: code written against the official `cloud_firestore` API
can run this way too, through `cloud_firestore_dart_platform` 0.1.0 (`CloudFirestoreDart.use()`); that
package's own tests run `cloud_firestore` 7.1.0 classes under `flutter test` against the emulator. No outside
app has done it yet. `firebase_admin_dart` 0.1.0 has no Flutter dependency, so an integration test
can create a user and mint a custom token with it.

**How sure.** High on the facts; medium on the value (demand for test tools is large; the bridge to
FlutterFire users exists since 2026-11-16 but has no users yet).

## Hypothesis 4: native build cost

**What changed.** The famous problem was real: Firestore on iOS compiled about 500k lines of mostly C++;
Invertase measured a clean Xcode build at about 240 s before and 45 s after switching to precompiled frameworks (Mac mini
2018), 551 s and 174 s on a 2-core CI runner
([flutterfire#2751](https://github.com/firebase/flutterfire/issues/2751), 2020;
[#349](https://github.com/firebase/flutterfire/issues/349), 211 thumbs-up). But:

- Firebase's Swift package ships `FirebaseFirestoreInternal` as a **binary target** by default (source only
  with `FIREBASE_SOURCE_FIRESTORE`) ([Package.swift](https://github.com/firebase/firebase-ios-sdk/blob/main/Package.swift)).
- `cloud_firestore` has a `Package.swift` for iOS that depends on that package
  ([source](https://github.com/firebase/flutterfire/tree/main/packages/cloud_firestore/cloud_firestore/ios/cloud_firestore)).
- "As of the 3.44 release, Flutter's Swift Package Manager (SwiftPM) support is on by default", and the
  CocoaPods registry becomes read-only on 2026-12-02
  ([Flutter docs](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)).
- The precompiled-pods repo is now deprecated: "Firestore via SPM already ships as a precompiled binary"
  ([firestore-ios-sdk-frameworks](https://github.com/invertase/firestore-ios-sdk-frameworks)).

So the slow-compile argument is mostly gone for new projects. Android: no current measurement of what
`firebase-firestore` adds to an APK or to the method count was found; Firebase's SDK metrics page now
redirects to the GitHub repo. Native version conflicts (pods pinned to different Firebase versions) were a
classic FlutterFire pain ([#4625](https://github.com/firebase/flutterfire/issues/4625), 98 thumbs-up, 2021)
but no current data was collected.

**This library is not free either.** It adds `sqlite3_flutter_libs` (a native SQLite build) for a persistent
cache, and gRPC and protobuf compiled into the Dart AOT snapshot.

**To claim anything we must measure:** a clean and an incremental iOS build of the same small app with
`cloud_firestore` (SwiftPM, Flutter 3.44+) and with `cloud_firestore_dart` + `sqlite3_flutter_libs`; the
thinned IPA size and the Android release APK/AAB size of both; three runs each on one named machine and one CI
runner.

**How sure.** High that iOS build time is no longer a strong reason. Size: unknown either way.

## Hypothesis 5: background isolates

FlutterFire's umbrella issue for background isolates
([#10353](https://github.com/firebase/flutterfire/issues/10353)) lists `cloud_firestore` as "works but some
errors when hot reloading, no support for subscribing to documents". The cause, per the maintainer, is that the
plugins use event channels, and Flutter's background isolate channels only go from Dart to the host
([flutter#119207](https://github.com/flutter/flutter/issues/119207), open since 2023-01, 65 thumbs-up). The
FlutterFire issue was closed on 2026-06-23 "since it doesn't seem to be planned for Google to support this
feature". The documentation request is still open
([#9518](https://github.com/firebase/flutterfire/issues/9518)).

This library has no platform channels: it runs in any isolate. Two clients on one SQLite file elect a primary
and the secondary stays offline (`docs/parity.md`, known limitation 4), so a background isolate needs its own
app name, database or memory cache.

**How sure.** High on the FlutterFire limit. Medium on ours: `shared_cache_isolates_test.dart` covers isolates
on the Dart VM, but no Flutter app ran a listener in a background isolate.

## Hypothesis 6: web

- dart2wasm: `cloud_firestore_web`, `firebase_core_web` and `firebase_auth_web` are all tagged
  `is:wasm-ready` on pub.dev. **Not a differentiator.**
- Bundle size: FlutterFire web loads the Firebase JS SDK from the gstatic CDN at run time, version 13.3.0
  ([firebase_core_web](https://github.com/firebase/flutterfire/blob/main/packages/firebase_core/firebase_core_web/lib/src/firebase_core_web.dart)).
  The same files from npm (`firebase@13.3.0` on unpkg, gzipped with `gzip -9`, measured for this note):
  `firebase-app.js` 24 KB, `firebase-firestore.js` 187 KB, `firebase-firestore-lite.js` 44 KB,
  `firebase-firestore-pipelines.js` 198 KB. This library: a small app with the main library and a memory cache
  is 196 KB gzipped in total, with Lite 128 KB (`docs/guides/web.md`, dart2js `-O2`). That is roughly the same
  as app + Firestore from the CDN, and bigger than JS Lite. Inside a Flutter web app (several MB of engine)
  the difference is noise. **Not a differentiator.**
- Maturity: the JS SDK is the reference; this library's web is supported in Chrome only (other browsers
  untested), against the emulator (`docs/guides/platforms.md`). Updated 2026-11-20: several tabs can share one
  IndexedDB cache with `indexedDbCacheSettings(multiTab: true)`, a preview, unreleased, Chrome only, emulator only
  (`docs/guides/web.md`); the SQLite caches stay at one tab.
- (Added 2026-11-20) **A way across for apps that already run on the JS SDK or FlutterFire web.** The
  IndexedDB cache engine (supported in 0.3.1, no longer experimental) uses the JS SDK's own database and schema
  (version 18), so an app can switch between the two SDKs on one browser profile, one after the other, in either
  direction, and keep the documents and the pending writes of every user.
  `importJsSdkCache` copies a JS cache into the SQLite, memory or key-value caches, one way. No way to carry
  a JS cache to another client was found in the official docs; that was not searched for exhaustively. Evidence and limits: the interop job in CI runs the real JS SDK and this engine on one database in
  headless Chrome, both ways (documents, pending writes of two users, indexes, bundles, garbage collection, the
  lease handover); `importJsSdkCache` was tested against databases the JS SDK wrote, every schema version from 5
  to 18, up to 5,000 pending writes. Not done: Firefox and Safari, a production backend, a JS SDK tab running
  beside a tab of this client (the engine refuses to open while a JS client holds a live lease), a schema
  version other than 18 for the engine.
- (Added 2026-11-20) **Tabs.** Before, a persistent cache meant one tab. With `multiTab: true` the tabs elect a
  primary with the JS SDK's lease (5 s), rows and `localStorage` keys, and the others get listener results and
  write acknowledgements through it. Tested in Chrome with dart2js and dart2wasm against the emulator. Not
  tested: a JS SDK tab beside a tab of this client, handover on real visibility changes, different users in the
  tabs, other browsers. It is unreleased.
- One real niche: Dart web apps without Flutter (Jaspr and similar) cannot use the FlutterFire web packages,
  because the platform interfaces still declare the Flutter SDK
  ([flutterfire#18645](https://github.com/firebase/flutterfire/issues/18645), open, 2 thumbs-up). They can
  call the JS SDK through `dart:js_interop` themselves, or use this library.

**How sure.** High on wasm and size. Updated 2026-11-20: medium-low on the switch from the JS SDK (one browser,
emulator only, the evidence is the CI interop job, and the two SDKs were never run in two tabs at once). The web
is still the weakest place to aim; for a Flutter web app where FlutterFire works, the official option wins.

## Hypothesis 7: other reasons

- **De-Googled Android: false.** Firebase lists Cloud Firestore and Authentication under "Google Play services
  not required" ([Play services dependencies](https://firebase.google.com/docs/android/android-play-services)).
  The native SDK runs on AOSP-style devices too. (Google and phone sign-in do need Play services; not checked
  further.)
- **Features: mostly a wash.** FlutterFire `cloud_firestore` has pipelines, `loadBundle` / `namedQueryGet`,
  named databases (`databaseId`), the persistent cache index manager, `snapshotsInSync`, `ListenSource`, and
  vector search as a pipeline stage (from `lib/src/` of
  [cloud_firestore](https://github.com/firebase/flutterfire/tree/main/packages/cloud_firestore/cloud_firestore/lib/src)).
  Extras here, from `docs/parity.md`: read-only transactions, `Query.findNearest` on a classic query, snapshot
  JSON (`toJson` / `fromJson`, resume a listener from it), and fixes in the cache index over the JS and
  Android SDKs. None of these is a reason to switch on its own.
- **One behaviour on every platform: real but unproven as a draw.** FlutterFire runs four engines (Android,
  iOS, JS, C++ on Windows) with different gaps; the Windows gaps above are an example. This library runs one
  engine everywhere. No issue was found where users ask for this directly.
- **Hackability:** the whole client is Dart, readable and debuggable in the IDE, patchable with a
  `dependency_overrides`. Real for a small group; no demand signal measured.

## Comparison table

| Situation | Official option | This library | Who wins and why |
|---|---|---|---|
| Flutter app on Linux desktop or embedded Linux | none for Firestore | the official `cloud_firestore` API through `cloud_firestore_dart_platform`; listeners, offline cache | this library: the only option (one debug build run on Debian against the emulator; embedded not tried) |
| Flutter app on Windows, shipped to users | `cloud_firestore`, "development only", C++ SDK gaps | run on one Windows 11 VM against the emulator; sum, average and the disk cache work | unclear until tested; the official option is not supported in production |
| Dart server reacting to changes | Admin SDK: no listeners (drafts in progress); polling | listeners with resume and backoff | this library today; may change in months |
| Dart server or CLI acting as a user under rules, or working offline | none (Admin bypasses rules; `firedart` has no cache, no queries) | yes | this library |
| Dart server doing admin jobs (bulk writes, user management, recursive delete) | Admin SDK | Firestore: not built for it; `firebase_admin_dart` 0.1.0 (emulator, and one keyless run against a real project): Auth users, custom tokens, ID tokens | Admin SDK |
| Listener on a Flutter background isolate | not supported, not planned | runs in any isolate | this library (not tried in Flutter yet) |
| Testing Firestore code without a device | fake (`fake_cloud_firestore`) or device tests | real client under `dart test` with the emulator; `cloud_firestore` code through `cloud_firestore_dart_platform` | this library, with no outside user of the second path yet |
| Flutter app on Android or iOS | `cloud_firestore`, Google-supported, native SDKs | works as plain Dart, never run on a device | official |
| Flutter web, FlutterFire works | JS SDK via `cloud_firestore_web`, wasm-ready | supported in Chrome only; tabs can share a cache (preview, unreleased) | official |
| Web app with users on the JS SDK or FlutterFire web, moving to this client (added 2026-11-20) | the JS SDK itself; no import to another client was found (not searched exhaustively) | IndexedDB engine on the JS SDK's own database, both ways; `importJsSdkCache`; tabs (preview) | this library, weakly: Chrome and emulator only, interop checked in CI, never with a JS SDK tab beside it |
| Dart web without Flutter (Jaspr) | none packaged; hand-written JS interop | supported in Chrome | this library, weakly |
| iOS build time | precompiled via SwiftPM since Flutter 3.44 | not measured | no claim possible |

## When not to use it

- A Flutter app on Android, iOS or the web where FlutterFire works: you get Google's SDKs, Google's support,
  and years of production use. This library has 221 downloads in 30 days, 0 likes and 80 GitHub stars
  (2026-11-20; 58, 0 and 80 on 2026-11-16) and one maintainer (499 of the 513 commits GitHub counts, 2026-11-16).
- When you need a provider's sign-in page (Google, Apple popups or redirects), phone sign-in, or multi-factor:
  not provided. Email link sign-in and federated sign-in with a token the app already has are
  (`docs/guides/authentication.md`).
- When you need App Check with device attestation, Analytics, Crashlytics, Remote Config, Messaging or Storage:
  not part of this project (see `appsup-dart/firebase_dart` for Auth, Realtime Database and Storage in pure
  Dart).
- Several browser tabs sharing one cache: only the IndexedDB cache with `multiTab: true`, a preview that is
  unreleased, in Chrome against the emulator, never with a JS SDK tab beside it (updated 2026-11-20; it was "not
  supported" on 2026-11-16). With a SQLite cache, one tab at a time. Secondary isolates sharing listeners through
  the public API: not supported.
- Web: Chrome only, emulator only; Firefox, Safari and a production backend were not tested.
- High load or long running time in production: only a 15-check verification kit ran against a real
  database; the integration suite's real-project mode and long load have not (`docs/parity.md`, limitation 1).
- Admin work on a server: use `firebase_admin_sdk`. `firebase_admin_dart` here covers only a few Auth calls, and
  ran against a real project once (2026-11-18, keyless; local key signing and several calls not run).
- When you need a vendor to call: there is no SLA and no Google support; it is not affiliated with Google.

## What would make the case stronger

Ranked by expected effect on adoption.

1. **The drop-in FlutterFire platform implementation, Linux first.** Most demand sits with people who already
   wrote `cloud_firestore` code. A `cloud_firestore` platform implementation for Linux (and then Windows) lets
   them add one dependency instead of rewriting. It also turns the testing reason into a real one for every
   FlutterFire user. Needs `firebase_core` and at least email/anonymous auth with it. Updated 2026-11-17: done
   for `cloud_firestore` and `firebase_core` (`cloud_firestore_dart_platform` 0.1.0 on pub.dev); sign-in on
   Linux still needs `FirebaseUserAuth`, since `firebase_auth` has no Linux implementation.
2. **A Flutter Linux desktop app that is built and run, and one on an embedded board** (for example a
   Raspberry Pi with flutter-pi), with sign-in, a listener, an offline edit and a restart, written up with
   screenshots. This is the one place where the library is the only answer; it must be shown working.
   Updated 2026-11-17: half done. The desktop app ran with a listener, writes, a transaction, a query and the
   disk cache across a restart, against the emulator; still missing are sign-in, a real project, a screenshot
   and the embedded board.
3. **Production evidence.** Run the integration suite's real-project mode and a multi-day soak against a real
   database, and publish the numbers. Every reason above is weakened by "tested against the emulator".
4. **A server page that compares honestly with `firebase_admin_sdk`**, with one example that the Admin SDK
   cannot do today: a worker that listens and acts as a restricted Firebase user. Do it before the Admin
   listener PRs land, and keep the comparison current after.
5. **A Windows CI job** (unit and integration on the Dart VM) and one Flutter Windows build. Cheap, and it turns
   reason 4 from a gap into a claim. Build-time and size measurements (Hypothesis 4) come last: they are
   needed only to avoid false claims, not to win users.
6. **(Added 2026-11-20) The long-offline measurements repeated with the official SDKs and on a phone.** The
   same queues (100,000 and 1 million pending writes, one document edited 100,000 times) on FlutterFire on
   Android and on the JS SDK, and this client on one low-memory device. Without it reason 5 can not say
   "better", only "measured".

## Positioning statements

**The README can say today:**

- "A pure-Dart Firestore client for places FlutterFire does not reach: Linux, Dart servers and command-line
  tools, and background isolates."
- "Real-time listeners and an offline cache on the Dart VM, as a Firebase user under security rules or with
  service-account credentials."
- "The same client engine on every platform: a port of the Firebase Android SDK, tested against the emulator
  with 6869 unit tests passing (2026-11-20) and about 880 integration tests per transport (2026-11-14)."
- "Test your Firestore code with `dart test` against the emulator, running the real client."
- "Unofficial, maintained by one person, version 0.3.1, with FlutterFire's API names."
- (Added 2026-11-17) "A Flutter Linux desktop app on the official `cloud_firestore` API was built and run with
  `cloud_firestore_dart_platform`, against the emulator." Say emulator and debug build with it.
- (Added 2026-11-20) "Firestore Lite, the cache in your own storage, `mergeUnsentWrites`, the JS SDK cache
  import, the pending write count and the IndexedDB cache on the web are supported since 0.3.1; Pipelines are a
  preview." Say Chrome and emulator for the web parts.
- (Added 2026-11-20) "On the web, the IndexedDB cache uses the official JS SDK's own database, so an app can move
  from the JS SDK or FlutterFire web and keep its offline cache and pending writes; the format is checked against
  the real JS SDK in a CI job in Chrome." Say Chrome, emulator only.
- (Added 2026-11-20) "Several tabs can share one IndexedDB cache (`multiTab: true`, a preview, in the next
  version)." Say Chrome, emulator, preview, and that it is not released.

**It must not say yet:**

- "Production ready", or anything that implies scale or reliability beyond the emulator and the 15-check kit.
- "Works in Flutter apps on Android / iOS": not run there yet. Say "expected to work" until it has been.
  "Works on Windows": say only what ran (one VM, the emulator, debug builds). For Linux (updated 2026-11-17), do not go beyond what ran: one debug build on Debian 13
  x86_64 against the emulator, without sign-in.
- "Faster builds" or "smaller apps" than FlutterFire: not measured, and the iOS build argument is mostly
  obsolete.
- "Smaller web bundles" or "the wasm option": FlutterFire web is wasm-ready and about the same size.
- (Added 2026-11-20) "Works beside the JS SDK in another tab": no JS SDK tab was ever run beside a tab of this
  client. Also not "multi-tab is supported" or "released" (preview, unreleased), "works in Firefox or Safari",
  "migrates any JS cache" (the engine opens schema version 18 only; the import was tested with versions 5 to 18),
  or "experimental" for the features of 0.3.1 listed above (they are supported). Do not call Pipelines supported.
- "Works on devices without Google Play services, unlike FlutterFire": the native Firestore SDK does not need
  them either.
- "The only Dart server client with listeners": true today, but the Admin SDK has draft PRs; date the claim
  or leave it out.
- "Drop-in replacement for FlutterFire": the platform implementation (published 2026-11-16) covers
  `cloud_firestore` and `firebase_core` only, has its own differences, and has run in one app.
- (Added 2026-11-17, updated 2026-11-18) Anything about `firebase_admin_dart` beyond "checked against the
  Auth emulator, and its main path once against one real project, keyless".

## Demand signals (pub.dev API and GitHub, 2026-11-16; this library's own row also 2026-11-20)

| Package or issue | Signal |
|---|---|
| `cloud_firestore` | 1,744,022 downloads in 30 days, 3,783 likes |
| `fake_cloud_firestore` | 344,284 downloads in 30 days, 148 likes |
| `google_cloud_firestore` / `firebase_admin_sdk` | 24,833 / 21,547 downloads in 30 days (the first includes use through the second), 8 / 27 likes |
| `dart_firebase_admin` (discontinued) | 18,908 downloads in 30 days, 61 likes |
| `firebase_dart` (pure-Dart Auth, Realtime Database, Storage; no Firestore) | 18,650 downloads in 30 days, 130 likes |
| `firedart` | 3,898 downloads in 30 days, 319 likes, no release since 2024-03 |
| `cloud_firestore_dart` | 58 downloads in 30 days, 0 likes; on 2026-11-20 (pub.dev API): 221 downloads in 30 days, 0 likes |
| flutterfire#17338, Linux for `firebase_auth` | open since 2025-05, 37 thumbs-up |
| flutter#119207, platform channel calls into background isolates | open since 2023-01, 65 thumbs-up |
| firebase-admin-dart#95, `onSnapshot` on the server | open since 2025-10, 0 reactions, 7 comments |
| flutterfire#18645, FlutterFire web without Flutter | open since 2026-09, 2 thumbs-up |

Read: test tooling and server use have real numbers; Linux and background isolates have steady but small
requests; nobody is asking loudly for a pure-Dart Firestore client as such. `firedart`'s 319 likes with an
unmaintained, query-less client suggest there is room for a working one in desktop and CLI use.
