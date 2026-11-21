# Spike: a secure-storage adapter for the Auth session

> **Status.** Scoping only, written on 2026-11-21 against `origin/main` at `8addaf0`. No code was written, no
> package was installed and nothing was run on a keychain. Versions and dates come from the pub.dev API on the
> day of writing; the effort figures are estimates in agent days.

**The answer.** Gap 12 of `docs/auth_parity.md` (row 12: "An optional secure-storage adapter ... as a separate
package") is a small package if it wraps `flutter_secure_storage` (about 3 agent days with migration, tests and
docs) and a large one if it talks to the Keychain, libsecret and Credential Manager itself (about 12 to 16 agent
days, and three native surfaces to keep working). The wrapper covers what matters most: Android and iOS, where the
session is in memory today (`firebase_auth/firebase_auth_dart_platform/README.md`, "Platforms" table), and the
three desktop systems, where it is in a 0600 file. It cannot run in a plain Dart program (it depends on Flutter),
so a command line tool or a server keeps `FileAuthStorage`, which is the right tool there. On Linux without a
keyring the adapter should fail with a clear message and never fall back to a file on its own.

## What exists today

| What | Where | Behaviour |
|---|---|---|
| `AuthStorage` | `firebase_auth/firebase_auth_providers_dart/lib/src/auth_storage.dart` | `FutureOr<String?> read(String key)` and `FutureOr<void> write(String key, String? value)`; null deletes. Its doc already names `flutter_secure_storage` for Flutter and "the system keychain or secret service" for tools. `FirebaseUserAuth` calls `read` once (in `restore`) and `write` after every change, and awaits both; an exception reaches the caller. |
| `FileAuthStorage` | `lib/src/storage/file_auth_storage_io.dart` | One JSON file of `key -> value`, written atomically, mode 0600 (via a `chmod` process) on Linux and macOS, the profile's ACL on Windows. Deleting the last key deletes the file. |
| `WebAuthStorage` | `lib/src/storage/web_auth_storage_web.dart` | `sessionStorage` or `localStorage`. |
| `defaultStorage()` and `FallbackStorage` | `firebase_auth/firebase_auth_dart_platform/lib/src/storage.dart` | The default is one `FileAuthStorage` at `defaultSessionFile()` (memory on Android, iOS and web). `FallbackStorage` wraps the storage of every instance: when a **write** throws an `Exception`, the session is kept in memory for the rest of the run and one line is printed; reads of a failed storage then come from memory. |
| `storageFor` | `FirebaseAuthDart.use(storageFor: (FirebaseApp app) => ...)` in `lib/firebase_auth_dart_platform.dart`, read in `lib/src/firebase_auth.dart:83` | Chooses the `AuthStorage` per FlutterFire app. The README already says "pass `storageFor` to keep it in the system keyring". |
| The stored value | `lib/src/user_record.dart`, `encodeSession` | A JSON object (`version` 2, uid, email, provider data, `mfaInfo`, and the refresh token). Its size was not measured; see "Value size" below. |
| The key | `firebase_user_auth.dart:150` | `firebase_auth_providers_dart:<apiKey>` by default; the shim derives one per app name. |

## Backends per platform

| Platform | Secure store | Notes |
|---|---|---|
| macOS | Keychain (`SecItemAdd` and related, Security.framework) | The data-protection keychain needs the `keychain-access-groups` entitlement, which needs a provisioning profile; the legacy file-based keychain does not. `flutter_secure_storage` documents this and offers `usesDataProtectionKeychain: false` ([README](https://github.com/juliansteenbakker/flutter_secure_storage/blob/develop/flutter_secure_storage/README.md)). |
| iOS | Keychain | Same entitlement note; works in a normal app build. Accessibility class (`first_unlock`, `unlocked`) is a choice. |
| Android | Android Keystore wrapping an AES key | `flutter_secure_storage` 10+ uses RSA-OAEP key wrapping plus AES-GCM and no longer recommends Jetpack `EncryptedSharedPreferences` (deprecated); minimum SDK 23. Auto Backup can restore the ciphertext without the Keystore key, which gives `InvalidKeyException: Failed to unwrap key`; the README says to set `allowBackup="false"` and exclude the preferences. |
| Linux | Secret Service (`org.freedesktop.secrets` over D-Bus: GNOME Keyring, KDE Wallet) through `libsecret` | Needs a session bus and an unlocked keyring service at run time. Not available by default in CI, containers, servers or plain SSH sessions. |
| Windows | Credential Manager (`CredWrite`, `CredRead`) or DPAPI (`CryptProtectData`) | `flutter_secure_storage_windows` uses **DPAPI over a file** (`DpapiJsonFileMapStorage`, file `flutter_secure_storage.dat` in the app support directory; [source](https://github.com/juliansteenbakker/flutter_secure_storage/blob/develop/flutter_secure_storage_windows/lib/src/flutter_secure_storage_windows_ffi.dart)), not Credential Manager. DPAPI protects against other users, not against other programs of the same user. |
| Web | None | `localStorage` and IndexedDB are readable by any script of the origin. `flutter_secure_storage_web` wraps values with a WebCrypto key kept in the same origin's storage, which its README calls experimental and which a cross-site scripting flaw defeats just the same. The adapter should not claim web support; the advice in `auth_storage.dart` (memory or `WebAuthStorage.session`, strict CSP) stays. |

## Options for the code

### A. Wrap `flutter_secure_storage`

| Fact | Value (2026-11-21, pub.dev) |
|---|---|
| Version | 11.2.0, published 2026-09-16, BSD-3-Clause, publisher `steenbakker.dev` |
| Popularity | 160 of 160 pub points, 4,512 likes, about 6.5 million downloads in 30 days |
| Platforms | Android, iOS, macOS, Linux, Windows, web |
| Federated parts | `_linux` 3.0.3 (2026-09-11), `_windows` 4.2.2 (2026-05-22), `_darwin` 0.4.3 (2026-09-16), `_web`, `_platform_interface` 2.1.1 |
| Dependencies | `flutter`, `meta`, and its platform packages; Windows adds `ffi`, `win32`, `path`, `path_provider` |
| SDK | Dart `>=3.8.0 <4.0.0`, Flutter `>=3.19.0` (compatible with this repository's `^3.8.0`) |
| Linux | `libsecret-1-0` at run time, `libsecret-1-dev` to build, a running keyring; the Linux README lists a headless recipe (`dbus-launch` plus `gnome-keyring-daemon --unlock`) |
| Windows build | Needs the C++ ATL libraries in Visual Studio Build Tools (its README) |
| Open issues seen | 4 open issues matched a search for Linux with libsecret or keyring; one is #1308 (4.0.0-beta.1 Linux: deleting the last key brings back legacy-schema secrets on the next read) and #1282 (Android: `resetOnError` recurses until the process dies when the fresh key also fails). Neither was reproduced. |

For: the one dependency every Flutter app already uses for this; five native stacks maintained by someone else; the
API fits `AuthStorage` one to one (`read(key:)`, `write(key:, value:)`, `delete(key:)`). Against: it is a Flutter
plugin, so the package cannot be used in `dart run` (a CLI or server); Linux needs a native library at build time
and run time; the macOS entitlement is the app's job, not the adapter's; Windows is DPAPI, not Credential Manager.
It also has a large option surface (`AndroidOptions`, `IOSOptions`, `MacOsOptions`) that the adapter would pass
through rather than hide.

### B. Own code with `dart:io` and FFI, no Flutter

| Platform | Route | Status of what exists |
|---|---|---|
| macOS, iOS | `dart:ffi` to Security.framework (`SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`) with CoreFoundation dictionaries built by hand | No maintained package for this was found in the search on pub.dev (not exhaustive). The calls are few but the CFDictionary and `CFStringRef` constants need care, and every `CFRelease` is on us. |
| Linux | `freedesktop_secret` 0.1.6 (2026-10-18, pure Dart over the `dbus` package 0.8.1, no `libsecret`; [README](https://github.com/EchoEllet/dart-packages/tree/main/packages/linux_secret_store/freedesktop_secret)) | Young (0.1.x, one maintainer), pre-1.0. It says secrets written by libsecret stay readable, so a later move between the two needs no migration. |
| Windows | `package:win32` 6.4.0 (2026-08-05): `CredWriteW`, `CredReadW`, `CredDeleteW` | The bindings exist; the `CREDENTIALW` struct and the blob handling are ours. |
| Android | Nothing in pure Dart: Keystore is a Java API | Needs a Flutter plugin or JNI (`jnigen`), so B does not cover Android without more work. |
| All | `keyring` 1.0.0 (2026-06-27, umbrella over `keyring_native`: Rust through `native_toolchain_rust`, build hooks) | MIT, 0 GitHub stars at the check, and it needs Dart `^3.12.1` (this repository is on `^3.8.0`) and a Rust toolchain at build time. Not reviewed beyond its pubspec. |

For: works in `dart run` and Flutter alike; no plugin registration. Against: three native surfaces and their CI (a
macOS runner with a keychain, a Windows runner, Linux with `gnome-keyring` under D-Bus) that this repository would
own; no Android; crash and leak risk in hand-written FFI; the Keychain from an unsigned command line binary prompts
the user for access when another build of the binary reads the item (not verified here).

### Comparison

| | A. `flutter_secure_storage` | B. Own FFI |
|---|---|---|
| Android, iOS | yes | Android no; iOS by hand |
| macOS, Windows, Linux | yes | yes, by hand |
| Works in a CLI or server | no | yes (macOS, Windows, Linux) |
| Build dependencies | libsecret on Linux, ATL on Windows | none for Linux with `freedesktop_secret`; none elsewhere |
| Code to write | about 150 lines plus tests | about 800 to 1,200 lines plus tests |
| Maintenance | follows a popular plugin's releases | ours |
| Agent days (estimate) | 3 | 12 to 16 |

## Package name

The packages are `firebase_auth_dart`, `firebase_auth_dart_platform`, `firebase_auth_providers_dart` and
`firebase_auth_vm`; the common root is `firebase_auth_` with `_dart` on the pure-Dart ones. Options:

| Name | For | Against |
|---|---|---|
| `firebase_auth_secure_storage_dart` | Says what it is; sorts with the others | Long |
| `firebase_auth_keychain_dart` | Short | Wrong on Android, Linux and Windows |
| `firebase_auth_storage_dart` | Short | Does not say "secure"; `FileAuthStorage` is storage too |

Recommended: `firebase_auth_secure_storage_dart`, with the class `SecureAuthStorage`. If it wraps a Flutter plugin
it is not pure Dart and `_dart` is a slight misnomer; `firebase_auth_secure_storage` (no suffix) is the honest
name for option A and `_dart` fits a later B. This is a question for Razvan (see below).

## How it plugs in

- **The interface.** `class SecureAuthStorage implements AuthStorage`, constructed with a `FlutterSecureStorage`
  (default `const FlutterSecureStorage()`), a `service` or key prefix, and an optional migration source. `read` is
  `storage.read(key: prefixed(key))`; `write` with null is `delete`.
- **The shim.** `FirebaseAuthDart.use(storageFor: (app) => SecureAuthStorage())` works today with no change in
  `firebase_auth_dart_platform`: `storageFor` already exists and `firebase_auth.dart:83` takes its result in
  place of `defaultStorage()`. One adapter instance can serve every app, as `defaultStorage()` does, because the
  key already includes the API key and the app name. The README paragraph "Pass `storageFor` to keep it in the
  system keyring instead" gets an example and a link.
- **`FallbackStorage`.** The shim wraps whatever `storageFor` returns in a `FallbackStorage`
  (`firebase_auth.dart:83` region; `storage.dart`). A secure-storage **write** failure then keeps the sign-in
  alive in memory and prints one line, which is the right behaviour on a desktop where the keyring is locked or
  missing (the user can still use the app, and signs in again at the next start). A **read** failure is not
  caught: it reaches `restore()` and the caller of `FirebaseAuth` creation. The adapter should therefore decide
  per error: "no keyring or locked" throws (the app can show it); "cannot decrypt" (Android after a restore from
  backup, a Keystore key lost) returns null and deletes the entry, because losing a session costs one sign-in and
  must not leave the app unable to start.
- **Key naming.** The key passed in is already unique per project. Prefix it, for example
  `firebase_auth_dart/<key>`, so it cannot collide with the app's own `flutter_secure_storage` keys; the macOS
  and iOS Keychain `service` (or `accountName` in the plugin's options) should be set to a fixed value for the
  same reason. The prefix means the legacy file's keys are not the Keychain's keys; migration maps one to the other.
- **Value size.** The Keychain and libsecret take far more than a session. Windows Credential Manager limits a
  credential blob to `CRED_MAX_CREDENTIAL_BLOB_SIZE`, 5 x 512 = 2,560 bytes ([Microsoft Learn,
  `CREDENTIALA`](https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentiala)); a refresh
  token is a few hundred characters but the JSON also carries provider data, photo URLs and MFA factors, so an
  account with several providers could approach that. Option A is not affected (DPAPI file); option B on Windows
  must either split the value over several credentials or store only the refresh token and uid in the blob.
  The size of a real stored session was not measured.

## Migration from the 0600 file

The file is `defaultSessionFile()` (exported by `firebase_auth_dart_platform`) and holds one entry per app, so the
migration runs per key, on first read:

1. `read(key)`: ask the secure store; if it has the value, return it and do not touch the file.
2. If not, and the file exists, read `key` from a `FileAuthStorage` at the old path.
3. If found, write it to the secure store, **read it back and compare**, and only then `write(key, null)` on the
   file (`FileAuthStorage` removes the file when the last key goes).
4. Return the value.

Failure modes:

| Failure | Result | Handling |
|---|---|---|
| Secure write throws (no keyring, locked, entitlement missing) | Nothing changed; the file still has the session | Rethrow; the user stays signed in through the file next start, once the problem is fixed |
| Write succeeds, read-back differs | Possible truncation or encoding fault | Keep the file, delete the new entry, throw |
| File delete fails after a good write | Session in both places; plaintext copy remains | Return the value, print one line, retry on the next start |
| File unreadable or not JSON | `FileAuthStorage` treats it as empty | Nothing to migrate; no error |
| Two processes migrate at once | Both write the same value, the second delete finds nothing | Harmless; the file's last-writer-wins semantics already apply |
| Android, iOS | No file exists (memory default) | The step is skipped |

The migration source must be explicit (`SecureAuthStorage(migrateFrom: defaultSessionFile())`), not guessed, so
that a plaintext file is only read when the app says so. Removing the migration code in a later release is cheap
(the repo's rule is replace, not deprecate).

## Headless Linux without a keyring

What happens with option A: `libsecret` calls fail when there is no session bus (`DBUS_SESSION_BUS_ADDRESS`
unset, as in most CI containers and SSH sessions) or when no service owns `org.freedesktop.secrets`; the plugin
surfaces that as a platform exception. If a service exists but the collection is locked and no prompt can be shown,
a call may block or fail; the behaviour of the plugin in that case was not checked here. The Linux README of the
plugin documents only starting `gnome-keyring-daemon --unlock` yourself.

Options:

| Option | For | Against |
|---|---|---|
| **Fail with a clear error** (recommended) | The user asked for secure storage and gets either that or an explanation; no silent downgrade; the shim's `FallbackStorage` still keeps sign-in working in memory on a write failure | A server or CI job has to choose another storage |
| Fall back to the 0600 file | Works everywhere | The app believes it has secure storage when it has the file it wanted to leave; the downgrade is invisible, and a test on a developer machine (keyring) passes while production (no keyring) writes plaintext |

The error should name the cause and the two remedies: start a Secret Service and unlock it, or pass a
`FileAuthStorage` explicitly. An app that wants "keyring if present, else file" writes that in three lines of
`storageFor` (try `SecureAuthStorage`, catch, return `FileAuthStorage`); a helper for it is not worth adding until
two users ask.

## Effort

| Piece | Agent days |
|---|---|
| Option A: package, `SecureAuthStorage`, error mapping, migration, key prefix, unit tests with a fake plugin platform, README and CHANGELOG, example | 2 |
| Real-platform checks (macOS Keychain, Linux with `gnome-keyring` in CI, Android emulator; iOS and Windows by hand, since a runner is needed) and the `auth_parity.md` and README updates | 1 |
| **Option A total** | **3** |
| Option B (all of it): Security.framework FFI 4 to 5, Linux on `freedesktop_secret` 2 to 3, Windows `CredWrite` 2 to 3, CI on three systems 2 to 3, migration and docs 1 to 2 | 12 to 16 |

The scale follows `docs/auth_client_assessment.md` (Tier 1, "7 to 9 agent days, about 3,000 lines"): option A is
about 300 lines with tests, option B about 2,000.

## Recommendation

Build option A: a separate package `firebase_auth_secure_storage` (name to be confirmed) with
`SecureAuthStorage implements AuthStorage` on top of `flutter_secure_storage` ^11, key prefix, per-key migration
from the 0600 file, fail-clearly on a missing keyring, and no web support. Leave command line tools and servers on
`FileAuthStorage`, and add a pure-Dart backend (B) only when a user needs a keychain outside Flutter. Do not
change `firebase_auth_dart_platform`; `storageFor` and `FallbackStorage` already fit. About 3 agent days.

## Questions only Razvan can answer

1. Is a Flutter-only package acceptable (so no `dart run` keychain access), or must the first release work in a
   plain Dart CLI? That decides A or B.
2. The name: `firebase_auth_secure_storage` or `firebase_auth_secure_storage_dart`?
3. Should the package live in this repository (`firebase_auth/`) or in its own, given that it adds a Flutter plugin
   dependency to a repository whose clients are pure Dart?
4. Should the shim make the secure store the default on Android and iOS (where memory is the default today), which
   would make the package a dependency of `firebase_auth_dart_platform`, or stay opt-in through `storageFor`?
5. macOS: is a build that needs the `keychain-access-groups` entitlement (and so a provisioning profile) acceptable
   by default, or should the adapter default to `usesDataProtectionKeychain: false`?
6. Who owns the manual checks on Windows, iOS and a real Android device?

## Not checked

- No code was run. No keychain, keyring, Keystore or Credential Manager was touched; every statement about run-time
  behaviour is from documentation or source reading.
- The size of a real stored session was not measured, so the Windows 2,560-byte limit is a risk for option B, not a
  finding.
- The behaviour of `flutter_secure_storage_linux` on a headless host (no session bus; locked collection with no
  prompt) was not tested; it may hang or throw. Which exception types each platform throws for "no keyring" and for
  "cannot decrypt" was not read.
- Issues #1308 and #1282 of `flutter_secure_storage` were read by title only.
- Whether a Keychain item written by an unsigned Dart binary prompts when a rebuilt binary reads it was not
  checked.
- `freedesktop_secret` and `keyring` were read at the pubspec and README level only; their maintenance beyond the
  dates above and their security were not reviewed. The search for a Keychain FFI package on pub.dev was not
  exhaustive.
- Android Auto Backup behaviour with the 10+ ciphers was taken from the plugin's README, not from a device.
