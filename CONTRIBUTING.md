# Contributing

Issues and pull requests are welcome. The project has one maintainer, so small and focused changes get
reviewed fastest.

## What helps most

- **A report from a platform that is not tried yet.** Run an example (`examples/flutterfire_on_linux`,
  `examples/web_app`, `examples/cli`) on your distribution, board, browser or phone and open an issue with what
  happened, also when it worked. [`docs/parity.md`](docs/parity.md) and
  [`docs/support_policy.md`](docs/support_policy.md) say what was tried.
- **A failing test for a difference from the official SDKs.** The client is a port of the Firebase Android
  SDK; a case where it behaves differently from the Android or JS SDK is a bug unless
  [`docs/parity.md`](docs/parity.md) lists it as a known difference.
- **A row of `docs/parity.md` marked partial or missing.** Say in an issue that you are taking it, so two
  people do not do the same work.

## Before a pull request

1. Branch from `main`.
2. Run `./tool/test_all.sh` (pub get, analysis and the unit tests of the packages). For changes that touch
   networking or the local store, run the emulator integration tests too; the root
   [README](README.md#running-the-tests) has the commands.
3. Format `lib` and `example` of the package you changed with `dart format lib example`. CI checks it with
   Dart 3.8.0, the lowest supported SDK. Do not format `test/readme/readme_snippets.dart`; it is generated.
4. If you changed the public API or a README snippet, regenerate the goldens:
   `UPDATE_GOLDEN=1 dart test test/unit/api` in `cloud_firestore/cloud_firestore_dart`.
5. Add a line to the `## (unreleased)` section of the package's `CHANGELOG.md` when users can see the change.

Do not weaken or remove an assertion to get a test passing. If a test is flaky, report it.

## Where things are

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) explains the layers and how they map to the Android SDK. Code that is
ported keeps the upstream names, so the Android source is the best reference for why something is the way it
is.

To add a Firebase product that the SDK does not cover yet, follow
[`docs/contributing_a_product.md`](docs/contributing_a_product.md).

## Licence

Contributions to the published packages are under the Apache License 2.0, the licence of those packages.
