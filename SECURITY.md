# Security policy

## Reporting a vulnerability

Report it privately with GitHub's form:
<https://github.com/long1eu/firebase_dart_sdk/security/advisories/new>
(the "Report a vulnerability" button under the repository's Security tab). The report is visible only to the
maintainer and to you.

Do not open a public issue for a security problem, and do not put credentials, tokens or service account keys
in a report.

Useful in a report: the package and version, where it runs (Dart VM, Flutter platform, browser), what an
attacker needs to have, and the smallest steps that show the problem.

## What to expect

- A first answer within 48 hours: that the report was read, and what happens next.
- No fixed date for a fix. A security fix takes priority over everything else in the project.
- The fix is released as a new version of the affected package, with a note in its changelog. You are credited
  unless you ask not to be.

The project has one maintainer.

## Which versions get fixes

The latest release of each package on pub.dev. Older versions are not patched; the fix is in the next release.

## What is in scope

The packages published from this repository: `cloud_firestore_dart`, `cloud_firestore_dart_sqlite`,
`cloud_firestore_dart_platform`, `cloud_firestore_dart_flutterfire`, `firebase_auth_dart_platform`,
`firebase_app_dart`, `firebase_auth_providers_dart` and `firebase_admin_dart`.

Problems in the Firebase backend, in the official Firebase SDKs or in the Firestore emulator belong to Google:
<https://www.google.com/about/appsecurity/>.
