# Support policy

What this repository supports today, how it follows upstream Firestore, and how versions are
numbered. The packages are `cloud_firestore_dart`, `firebase_app_dart` and
`firebase_auth_providers_dart`; version 0.1.0 is in preparation and not published yet.

Lines marked **DRAFT** are proposals that the maintainer has not confirmed. Until they are
confirmed they are not commitments.

## Dart and Flutter SDKs

- All three packages declare `sdk: ^3.8.0` in their `pubspec.yaml`: Dart 3.8.0 or later, below
  4.0.0. The floor comes from `grpc` 5, which needs Dart 3.8.
- CI runs the unit suites of the three packages on Dart **3.8.0** (the lowest supported SDK) and
  on the current **stable** SDK, on every pull request and every push to `main`
  (`.github/workflows/ci.yml`, jobs `unit` and `unit-stable`). The emulator, web transport and
  browser suites run on stable.
- Flutter: the packages do not depend on Flutter. A Flutter app can use them as plain Dart
  packages with any Flutter release whose Dart SDK is 3.8 or later. No Flutter app is run by
  the tests of this repository (see [Platforms](#platforms)).
- **DRAFT:** The lower bound is raised only in a release whose changelog says so, and only when
  a dependency or a language feature needs it.
- **DRAFT:** A new stable Dart SDK is supported once CI passes on it; a problem with a new SDK is
  treated as a bug.

## Platforms

As tested in this repository (details in [docs/guides/platforms.md](guides/platforms.md)):

| Platform | How it is tested | Status |
|---|---|---|
| Dart VM on macOS | Development machine: unit, integration (gRPC and web transport), chaos and soak suites against the emulator | supported |
| Dart VM on Linux | CI on Ubuntu x64: the unit, integration (three transports) and Enterprise suites on every change, the browser suite on dart2wasm when a change touches what it covers, and nightly the browser suite on both compilers, the scale soak and the long property runs; unit and standard integration suites in a Debian arm64 container (`tool/linux/run_in_container.sh`); the unit suite in a Debian container on linux/amd64 nightly | supported |
| Dart VM on Windows | not tested | expected to work; see the notes on `sqlite3.dll` and file locks in the platforms guide |
| Flutter apps (Android, iOS, desktop) | not run by the tests; the client runs on the Dart VM there, like on a server | expected to work |
| Web, Chrome | browser suite in Chrome with dart2wasm and dart2js against the emulator; the standard integration suite on the VM over the web transport (REST, WebChannel, WebChannel with long polling) | **experimental** |
| Web, other browsers | not tested | unknown |

Backends:

- The Firestore emulator (v1.22.0), Standard and Enterprise edition: every suite runs against it.
- Production Firestore, Standard edition: the production verification kit
  (`tool/verify_production`) was run against a real database; in its latest run 13 of its 15
  checks passed and 2 were skipped. See [docs/how_we_test.md](how_we_test.md).
- Production Firestore, Enterprise edition: not tested. The Enterprise features (BSON value
  types, Pipelines) were tested against the emulator only.

## Tracking upstream

The port follows the Firebase Android SDK class by class, and takes newer pieces of the public
API from the Firebase JS SDK, which is the reference for behaviour that the two SDKs share.
[`docs/upstream_sync/`](upstream_sync/) holds the record:

- [`UPSTREAM_PLAN.md`](upstream_sync/UPSTREAM_PLAN.md): the state of each plan item (done,
  preview, skipped by design), the upstream commit the port was compared against, and what was
  found while testing that is not from upstream.
- `commits_oldest_first.tsv`: the 707 commits that touched `firebase-firestore` in the Android
  SDK between the old sync point (`576da00e85`, 2019-07-23) and the start of the revival.
- `analysis_0.md` to `analysis_4.md`: those commits, triaged one by one (category, area,
  relevance for the port, whether the Dart code already has it). Rows that were not read in
  depth are marked unverified there.
- `android_firestore_changelog.md`: the release notes of the Android SDK, used to map commits to
  released features.
- `BRIEF.md`: the instructions the triage followed.

Behaviour is ported in Dart, not copied. Where the port deliberately differs from upstream,
[`docs/ARCHITECTURE.md`](ARCHITECTURE.md) lists the deviation with the test that pins it.

- **DRAFT:** Upstream Firestore releases (Android and JS) are reviewed for changes that apply to
  the port at least once per upstream minor release, and the review is recorded in
  `docs/upstream_sync/`.
- **DRAFT:** Fixes of data-safety and correctness bugs in upstream are ported with priority over
  new features.

## Versions and breaking changes

- The three packages are versioned together for 0.1.0. A release tag `v<version>` checks that
  all three are at that version; a tag `<package>-v<version>` checks one package
  (`.github/workflows/release.yml`, which validates and never publishes).
- Publishing to pub.dev is a manual step of the maintainer. CI has no pub.dev credentials.
- Each package has a `CHANGELOG.md` with a heading for every version.
- **DRAFT:** Versions follow [semantic versioning](https://semver.org/) as pub applies it before
  1.0: while the version is 0.x, a breaking change increments the minor version (0.1.x to
  0.2.0), and everything else increments the patch version.
- **DRAFT:** Every breaking change is listed in the changelog under a "Breaking changes" heading,
  with what to change in calling code.
- **DRAFT:** Public API that is replaced is first marked `@Deprecated` for at least one minor
  release before it is removed, unless keeping it would be unsafe.
- **DRAFT:** Changes to the SQLite cache format always come with a migration of existing caches
  (the schema version is in `local/sqlite/sqlite_schema.dart`; the migration tests open caches
  written by older versions, including caches written by the published `cloud_firestore_vm`
  0.0.7).
- What is not covered by any compatibility promise: everything under `lib/src`,
  `package:firebase_app_dart/internal.dart`, the Pipelines library
  (`package:cloud_firestore_dart/pipelines.dart`, preview) and Firestore Lite
  (`package:cloud_firestore_dart/lite.dart`, experimental). These can change in any release.

## Reporting problems

Open an issue at <https://github.com/long1eu/firebase_dart_sdk/issues> (the issue tracker named
in the packages' `pubspec.yaml`). Useful in a report: the package versions, the Dart SDK, the
platform, whether it happens against the emulator or production, and a log with
`Firestore.setLogLevel(LogLevel.debug)` if the problem is in syncing.

- **DRAFT:** Security problems are reported privately, by the channel the maintainer names here:
  `<MAINTAINER: security contact>`.
- **DRAFT:** Response times: `<MAINTAINER: what you can commit to, or "best effort">`.
