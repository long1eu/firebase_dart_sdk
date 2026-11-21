# firebase_auth_secure_storage_dart

Keeps the Firebase Auth session of [`firebase_auth_providers_dart`](https://pub.dev/packages/firebase_auth_providers_dart)
in the secure store of the system, for command line tools and servers, without Flutter: the login keychain on macOS,
the Secret Service (libsecret) on Linux and files encrypted with DPAPI on Windows, all called through `dart:ffi`.
`SecureAuthStorage` is an `AuthStorage`, so `FirebaseUserAuth` takes it as its `storage`. It is not affiliated with or
endorsed by Google or Firebase.

A Flutter app uses [`firebase_auth_secure_storage_flutter`](../firebase_auth_secure_storage_flutter) instead (it also
covers Android, iOS and the data-protection keychain of signed macOS apps). Both use the same key scheme and the same
`migrateFrom` rules.

> **Status: 0.1.0, not published.** Unit-tested with fakes of the store on any system. The integration tests run
> against the real store of each system; only macOS has run them so far. **Linux and Windows are untested**: the
> code is written against the documented libsecret and DPAPI interfaces, not proven on a real system. See
> [Integration tests](#integration-tests) for the commands.

## How a command line tool uses it

```yaml
dependencies:
  firebase_auth_providers_dart: ^0.3.0
  firebase_auth_secure_storage_dart: ^0.1.0
```

Use the secure store when the system has one, and an owner-only file when it does not (an SSH session on Linux
without a Secret Service, a Windows service, a container):

```dart
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';

Future<FirebaseUserAuth> openAuth(String apiKey) async {
  final String home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']!;
  final FileAuthStorage file = FileAuthStorage('$home/.config/my_tool/session.json');
  final SecureAuthStorage secure = SecureAuthStorage(
    namespace: 'com.example.my_tool',
    migrateFrom: file, // moves a session an earlier version kept in the file
  );
  final AuthStorage storage = await secure.isAvailable() ? secure : file;
  final FirebaseUserAuth auth = FirebaseUserAuth(apiKey: apiKey, storage: storage);
  await auth.restore();
  return auth;
}
```

`isAvailable()` writes, reads back and deletes a probe entry (`<namespace>/.probe`). It returns false only when the
store as a whole cannot be used in this run (`SecureAuthStorageException.isUnavailable`), and throws for anything else,
so a session that is stored but cannot be read now (a locked macOS keychain over SSH, a value that does not decrypt)
is never mistaken for no session. The fallback is the caller's choice: this package never writes a session anywhere
but the secure store.

The Flutter shim `firebase_auth_dart_platform` has its own default storage and fallback; this package does not change
them.

### Arguments

| Argument | Default | What it does |
| --- | --- | --- |
| `namespace` | `SecureAuthStorage.defaultNamespace()` (see [Keys](#keys)) | Prefix of every key. Must not be empty. |
| `store` | `SecretStore.platform()` | The secret store; implement `SecretStore` to use another one or a fake. |
| `migrateFrom` | none | The storage that held the sessions before; see [Migration](#migration). |
| `onMigrationIssue` | writes to standard error | Receives the migration steps that failed without failing the operation. |

The constructor does no I/O: the native library is loaded and the store first used at the first `read`, `write` or
`isAvailable`. The calls are synchronous inside the library and block the isolate while the store answers, which is
fine for a command line tool; a server that cannot afford that runs them in another isolate. No stored value is
printed, logged or put in an exception.

## Keys

Each session is stored under `<namespace>/<key>`, where `<key>` is the key `FirebaseUserAuth` passes
(`firebase_auth_providers_dart:<apiKey>` by default). The default namespace is the one the Flutter package uses on
desktop: `firebase_auth_secure_storage:<app>`, where `<app>` is the first 16 hex digits of the SHA-256 of the absolute
path of the running executable (`Platform.resolvedExecutable`).

**Pass a fixed `namespace` for a program run with `dart run` or `dart <file>.dart`:** its executable is the Dart VM,
so every such program of the user would share the default namespace and see each other's sessions. A compiled
program (`dart compile exe`) gets its own, which changes when the program is moved or renamed (the users then sign in
again). Changing the namespace later loses the stored sessions.

## Where the sessions are kept

| System | Store | Item |
| --- | --- | --- |
| macOS | the login keychain (the legacy, file-based keychain), through Security.framework | a generic password with the service `firebase_auth_secure_storage` and the account `<namespace>/<key>` |
| Linux | the default collection of the Secret Service (GNOME Keyring, KDE Wallet, KeePassXC), through `libsecret-1.so.0` | an item of the schema `firebase_auth_secure_storage` with the attributes `service` = `firebase_auth_secure_storage` and `account` = `<namespace>/<key>` |
| Windows | files encrypted with DPAPI for the current user, in `%LOCALAPPDATA%\firebase_auth_secure_storage` | one file per key, named after a SHA-256 prefix of `<namespace>/<key>`, `.dpapi`; the key is the DPAPI entropy |

`SecretStore.platform(service: ...)` changes the service (the directory on Windows).

**macOS.** A command line program has no entitlements, so it cannot use the data-protection keychain; the items go to
the login keychain, selected explicitly (`kSecUseDataProtectionKeychain = false`). An item there trusts the program
that created it: another program, or the same one rebuilt with another signature, makes macOS ask the user. Over SSH
or in a daemon there is no window server to ask, and a locked login keychain cannot be unlocked by a prompt
(`errSecInteractionNotAllowed`; run `security unlock-keychain` first).

**Windows: why DPAPI files, not Credential Manager.** A Credential Manager secret (`CredentialBlob`) holds at most
2,560 bytes (`CRED_MAX_CREDENTIAL_BLOB_SIZE`). A session is a JSON object with the refresh token and the user record
(profile, provider data, multi-factor enrollments), which can pass that, and splitting it over several credentials
would make writes non-atomic. DPAPI has no size limit, a file per key is replaced atomically (written next to it,
then renamed), and it is what the Windows implementation of `flutter_secure_storage` uses. DPAPI protects the files
from other users and from a copy of the disk, not from other programs of the same user, and it needs an interactive
logon: in an SSH session or a Windows service it refuses with `ERROR_ACCESS_DENIED`, which `isUnavailable` reports.

**Linux.** libsecret is loaded with `dlopen` at the first call, so the package builds and runs without it; the store
is unavailable then. It also needs a D-Bus session bus with a Secret Service on it and an unlocked collection. SSH
sessions, CI and containers usually have none.

## Errors

Every failure of the store becomes a `SecureAuthStorageException` with the `platform`, the `operation` (`read`,
`write` or `delete`), the `cause` (a `SecretStoreError` with the native `function` and `status`), and a `remedy`.

`isUnavailable` is true when the store as a whole cannot be used in this run:

| System | Cause |
| --- | --- |
| any | the native library could not be loaded (`dlopen`); a system other than macOS, Linux or Windows |
| macOS | `errSecNotAvailable` (-25291), `errSecNoDefaultKeychain` (-25307) |
| Linux | a `GError` of `g-dbus-error-quark` or `g-io-error-quark` (no session bus, no Secret Service); `secret-error` 2, a locked collection |
| Windows | `CryptProtectData` or `CryptUnprotectData` with `ERROR_ACCESS_DENIED` (5): no interactive logon; `LOCALAPPDATA` not set |

It is false for a failure that may concern a stored value: a value that does not decrypt or is not UTF-8, a file that
cannot be read, and on macOS a locked keychain that cannot prompt (`errSecInteractionNotAllowed`, -25308) or a denied
prompt (`errSecAuthFailed`, `errSecUserCanceled`). Falling back to another storage for those would make a stored
session look signed out.

## Migration

With `migrateFrom`, a read of a key that the secure store does not have moves it: the value is read from
`migrateFrom`, written to the secure store, read back and compared, and only then deleted from `migrateFrom`
(`FileAuthStorage` deletes the file with its last key). A key the secure store already has is read from there only.
A sign-out (a write of null) deletes the key from `migrateFrom` too, so that a session the move never reached cannot
come back at a later start. Nothing is read from a storage that was not passed.

| Failure | Result |
| --- | --- |
| the secure store fails during the move | the `SecureAuthStorageException` is thrown; `migrateFrom` is unchanged |
| the value read back differs | the copy in the secure store is deleted, `migrateFrom` is unchanged, and a `SecureAuthStorageMigrationException` is thrown |
| `migrateFrom` cannot be read | the read returns null (the user signs in again); `onMigrationIssue` gets `MigrationStep.readOld` |
| `migrateFrom` cannot delete the key | the read returns the value; `onMigrationIssue` gets `MigrationStep.deleteOld` (a copy remains there) |

The operations of one instance run one at a time, in order, so a move cannot overwrite a session written after it
started.

## Integration tests

They use the real store of the system, with a random service name per test
(`firebase_auth_secure_storage_test_<random>`), and delete what they wrote even when a test fails. They are skipped
unless `FIREBASE_AUTH_SECURE_STORAGE_INTEGRATION=1`, and each runs only on its own system. From this directory:

macOS, in a desktop session (not over SSH):

```sh
FIREBASE_AUTH_SECURE_STORAGE_INTEGRATION=1 dart test test/integration/macos_keychain_test.dart
```

Linux (Debian or Ubuntu with `libsecret-1-0`, `gnome-keyring` and `dbus`; `libsecret-tools` adds a check of the item's
attributes), headless:

```sh
FIREBASE_AUTH_SECURE_STORAGE_INTEGRATION=1 dbus-run-session -- sh -c 'printf "test\n" | gnome-keyring-daemon --unlock --components=secrets >/dev/null && dart test test/integration/linux_libsecret_test.dart'
```

Windows, in the user's desktop session (DPAPI refuses access over SSH), in PowerShell:

```powershell
$env:FIREBASE_AUTH_SECURE_STORAGE_INTEGRATION = '1'; dart test test/integration/windows_dpapi_test.dart
```

The unit tests (`dart test test/unit`) run anywhere and touch no store.
