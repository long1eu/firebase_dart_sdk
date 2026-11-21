# firebase_auth_secure_storage_flutter

Keeps the Firebase Auth session of [`firebase_auth_providers_dart`](https://pub.dev/packages/firebase_auth_providers_dart)
in the secure store of the platform, through [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage):
the Keychain on iOS and macOS, a Keystore-wrapped key on Android, libsecret on Linux and DPAPI on Windows.
`SecureAuthStorage` is an `AuthStorage`, so it works with `FirebaseUserAuth` directly and with
`firebase_auth_dart_platform` (the official `firebase_auth` API). It is not affiliated with or endorsed by Google or
Firebase.

`firebase_auth_dart_platform` uses it by default (see [With `firebase_auth_dart_platform`](#with-firebase_auth_dart_platform));
`FirebaseUserAuth` uses it only when the app passes it. It needs Flutter; a command line tool or a server keeps
`FileAuthStorage`.

> **Status: 0.1.1.** Unit-tested with `flutter test` against a fake of the plugin's method channel. On
> macOS, the six integration tests of `example/` pass against the real data-protection keychain in a Developer ID
> signed build on a GitHub-hosted runner (see [Signed integration tests](#signed-integration-tests)). It has not yet
> run in CI against the iOS Keychain, the Android Keystore, a Secret Service or DPAPI.

## How to use it

```yaml
dependencies:
  firebase_auth_secure_storage_flutter: ^0.1.1
```

With `firebase_auth_dart_platform` there is nothing to do: it is the default. Pass your own only to change its
arguments (one storage for every FlutterFire app):

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SecureAuthStorage storage = SecureAuthStorage(namespace: 'com.example.notes');
  FirebaseAuthDart.use(storageFor: (FirebaseApp app) => storage);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}
```

With `FirebaseUserAuth`:

```dart
final FirebaseUserAuth auth = FirebaseUserAuth(apiKey: apiKey, storage: SecureAuthStorage());
await auth.restore();
// or, later: await auth.setStorage(SecureAuthStorage());
```

### Arguments

| Argument | Default | What it does |
| --- | --- | --- |
| `namespace` | `SecureAuthStorage.defaultNamespace()`, unique per program (see [Keys](#keys)) | Prefix of every key. Must not be empty. |
| `storage` | `SecureAuthStorage.defaultSecureStorage()` | The `FlutterSecureStorage` to use, with your own platform options. |
| `migrateFrom` | none | The storage that held the sessions before; see [Migration](#migration). |
| `onMigrationIssue` | prints with `debugPrint` | Receives the migration steps that failed without failing the operation. |

The library re-exports `FlutterSecureStorage` and its option classes, so an app that passes its own `storage` does
not need a direct dependency on `flutter_secure_storage`.

## Keys

Each session is stored under `<namespace>/<key>`. `<key>` is the key `FirebaseUserAuth` passes, which names the
project and, in the shim, the FlutterFire app:

| Who | `<key>` |
| --- | --- |
| `FirebaseUserAuth` (default) | `firebase_auth_providers_dart:<apiKey>` |
| `firebase_auth_dart_platform` | `firebase_auth_providers_dart:<apiKey>:<app name>` |

`<namespace>` names the program. On desktop the secure store is shared by every program of the user (the Linux Secret
Service, the legacy macOS keychain), so without it two programs on this library would read and overwrite each other's
sessions. The default, `SecureAuthStorage.defaultNamespace()`, is `firebase_auth_secure_storage:<app>`:

| Platform | `<app>` | Why |
| --- | --- | --- |
| macOS, Linux, Windows | first 16 hex digits of the SHA-256 of the executable's absolute path (`Platform.resolvedExecutable`) | Flutter and the plugin do not expose the bundle ID or application ID there without another plugin |
| Android, iOS | `sandbox` | the system keeps each app's store apart; the executable path is the same for every Android app and changes at every iOS update |
| Web | `web` | the browser keeps each origin apart |

It is stable from one start to the next and never random, so nothing has to be stored to find it again. On desktop it
changes when the program is moved or renamed, or when an installer puts each version in its own directory (MSIX):
the users then sign in again. Pass a fixed `namespace` (the application ID) to avoid that:

```dart
SecureAuthStorage(namespace: 'com.example.notes')
```

Changing the namespace later loses the stored sessions. Two `FirebaseUserAuth` instances with the same API key and
the default key share one session, on purpose (a new instance restores the session of an earlier one); give one a
`storageKey` to keep them apart.

On iOS and macOS the default storage also sets a fixed Keychain service (`kSecAttrService`,
`SecureAuthStorage.keychainService` = `firebase_auth_secure_storage`), so `FlutterSecureStorage().deleteAll()` of the
app's own values does not delete the session.

## Errors

Every exception of `flutter_secure_storage` becomes a `SecureAuthStorageException` with the `platform`, the
`operation` (`read`, `write` or `delete`), the plugin's `code` and `cause`, and a `remedy`. The session is never
written anywhere else instead. Common cases:

| Platform | Cause | Remedy in the message |
| --- | --- | --- |
| Linux | no Secret Service or no D-Bus session bus (SSH, CI, containers) | install `libsecret-1-0`, run GNOME Keyring or KDE Wallet (headless: `dbus-run-session`, then `gnome-keyring-daemon --unlock`), or pass a `FileAuthStorage` |
| Linux | `KeyringLocked` | unlock the login keyring |
| macOS | `errSecMissingEntitlement` (-34018) | add the entitlement below and sign the app, or use the legacy keychain |
| iOS, macOS | `errSecInteractionNotAllowed` (-25308) | the device is locked; use `KeychainAccessibility.first_unlock` |
| Android | Keystore failure, for example "Failed to unwrap key" | see [Android](#android) |
| Windows | `CryptProtectData` or `CryptUnprotectData` refused with `E_ACCESSDENIED` (0x80070005): no interactive logon (an SSH session, a service) | run in the user's desktop session, or pass a `FileAuthStorage`; DPAPI needs an interactive logon, it is not a directory permission |
| any | `MissingPluginException` | run in a Flutter app built for the platform, or fake the plugin in tests |

This package does not fall back on its own, so an app never believes it has secure storage when it has a file.
`SecureAuthStorageException.isUnavailable` tells a store that cannot be used at all in this run (no plugin, a Linux
session without a Secret Service or with a locked keyring, `errSecMissingEntitlement`, `errSecNotAvailable` or
`errSecNoDefaultKeychain` on iOS and macOS, `CryptProtectData` or `CryptUnprotectData` refused with `E_ACCESSDENIED` on Windows) from a failure that may concern a stored value (one that cannot be parsed
or decrypted, an iOS device locked for now). A caller that uses another storage when the store is unavailable must
do it only for the first kind: for the second, the stored session would look signed out.

### As a default

The constructor does no I/O and calls no plugin; the namespace is worked out and the store first used at the first
`read` or `write`. A missing or locked store fails that call with a `SecureAuthStorageException`, which a caller that
uses this storage by default catches to choose what to do (memory, a file, or showing the error).

### With `firebase_auth_dart_platform`

The shim's default storage is a `SecureAuthStorage` with the shim's session file as `migrateFrom`. Before the first
operation of the run, the shim probes the store (writes, reads back and deletes `<namespace>/.probe`): a read alone
cannot tell, because a macOS build without the entitlement reads a missing key as null and fails only at a write.
When a step fails with `isUnavailable`, the shim keeps that run's sessions in the session file (memory on Android and
iOS) and prints one line; other errors are thrown. It wraps that storage, like whatever `storageFor`
returns, in its `FallbackStorage`:

* A failed **write** (sign-in, token refresh, sign-out) is caught there: the session is kept in memory for the rest
  of the run, the `SecureAuthStorageException` is printed once, and the sign-in succeeds. The user signs in again at
  the next start. From then on that app's storage is memory until the program ends.
* A failed **read** (the restore at start) is not caught: the app starts signed out, and the error reaches
  `authStateReady()`.

The shim's README ("The session") has the details.

## Migration

An app that kept the sessions elsewhere (any `AuthStorage`) names that storage. Nothing is read from a storage that
was not passed. The default storage of `firebase_auth_dart_platform` already does this with its session file; the
example below is what an app that passes its own `SecureAuthStorage` to the shim writes to keep that move.

```dart
final String? file = defaultSessionFile(); // firebase_auth_dart_platform; null on Android and iOS
final SecureAuthStorage storage = SecureAuthStorage(
  migrateFrom: file == null ? null : FileAuthStorage(file),
);
FirebaseAuthDart.use(storageFor: (FirebaseApp app) => storage);
```

A read of a key that the secure store does not have moves it: the value is read from `migrateFrom`, written to the
secure store, read back and compared, and only then deleted from `migrateFrom` (`FileAuthStorage` deletes the file
with its last key). A key the secure store already has is read from there only. A sign-out (a write of null) deletes
the key from `migrateFrom` too, so that a session the move never reached cannot come back at a later start.

| Failure | Result |
| --- | --- |
| The secure store fails (write or read-back) | `SecureAuthStorageException` is thrown; `migrateFrom` is unchanged, and the next read tries again |
| The value read back differs | the copy in the secure store is deleted, `migrateFrom` is unchanged, `SecureAuthStorageMigrationException` is thrown (its `cleanupError` says if the delete failed) |
| `migrateFrom` cannot be read | the read returns null (the user signs in again); `onMigrationIssue` gets `MigrationStep.readOld` |
| `migrateFrom` cannot delete the key | the read returns the value; `onMigrationIssue` gets `MigrationStep.deleteOld`: a plaintext copy remains, and it is not retried |
| Nothing in either storage | null; nothing is written |

The operations of one `SecureAuthStorage` run one at a time, so a move cannot overwrite a session written after it
started. Two processes moving the same key at once both write the same value; the second delete finds nothing.

While the user is signed out, every start reads `migrateFrom` once per key (a missing file costs a `stat`). Drop
`migrateFrom` in a later release of the app, once its users have started it.

## Platforms

`SecureAuthStorage.defaultSecureStorage` uses the plugin's defaults, except the Keychain service on iOS and macOS
(`keychainService`) and an explicit `usesDataProtectionKeychain: true` on macOS.

| Platform | Store | Set up |
| --- | --- | --- |
| iOS | Keychain, accessible while unlocked (the plugin's default) | nothing; see below for background use |
| macOS | data-protection keychain | the entitlement below, in a signed app |
| Android | AES-GCM values, key wrapped by an RSA-OAEP Keystore key (`AndroidOptions()`, API 23+) | exclude it from Auto Backup |
| Linux | one libsecret secret per `APPLICATION_ID` | `libsecret-1-dev` to build, `libsecret-1-0` and a running Secret Service to run |
| Windows | one DPAPI-encrypted map of all values in `flutter_secure_storage.dat` in the application support directory (DPAPI CurrentUser) | the C++ ATL libraries of Visual Studio Build Tools to build; an interactive logon to use it |
| Web | the plugin's experimental WebCrypto wrapping in `localStorage` | not recommended; see below |

### macOS

The data-protection keychain needs the `keychain-access-groups` entitlement, which needs a provisioning profile, so a
signed app. Add it to both `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>keychain-access-groups</key>
<array/>
```

An empty array gives the app its default access group (team ID and bundle ID). List a group
(`<string>$(AppIdentifierPrefix)com.example.shared</string>`) only to share the session with another app of the same
team, and pass it as `groupId` in your own `MacOsOptions`. On a free developer account Xcode embeds a development
profile for the building Mac only, so such a build does not run on other Macs.

An unsigned build (or one without the entitlement) gets `errSecMissingEntitlement`. It uses the legacy file-based
keychain instead, which needs no entitlement:

```dart
SecureAuthStorage(
  storage: const FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: SecureAuthStorage.keychainService,
      usesDataProtectionKeychain: false,
    ),
  ),
)
```

Items of the two keychains are separate: switching loses the stored sessions.

#### Signed integration tests

`example/` is a macOS app (`dev.upcode.firebaseAuthSecureStorageExample`, team `DKY2FBVP6L`) with the
`keychain-access-groups` entitlement. Its integration tests (`example/integration_test`) use `SecureAuthStorage`
alone, against the real data-protection keychain: a write with the package defaults (a build without the
entitlement fails there with `errSecMissingEntitlement`), a round trip, two namespaces kept apart, both cases of a
move from a `FileAuthStorage` (the file's session moves and the file is deleted; a session already in the keychain wins, and a
sign-out deletes both), and a last check that no entry written by the run is left in the keychain.

The workflow `.github/workflows/secure_storage_signed_macos.yml` runs them on a GitHub-hosted macOS runner (all six
passed on its first run), on a push to main that touches this package (`example/` included) or the workflow, and by
hand. Never on a pull request. Its job uses the `signing` environment, which only accepts main and waits for the owner's approval. It has no secrets
and no notarization credentials, and it uploads nothing: no artifact, no build output, no keychain.

* Google Cloud is reached by Workload Identity Federation: `google-github-actions/auth` exchanges the job's GitHub
  OIDC token for a short-lived token of a service account that can only read the bucket of fastlane match, and
  exports it as Application Default Credentials.
* `fastlane match developer_id --readonly` fetches the Developer ID Application certificate and the Developer ID
  profile `match Direct dev.upcode.firebaseAuthSecureStorageExample macos` from that bucket. A development profile
  runs only on the Macs registered in it, and each hosted runner is a new Mac; a Developer ID profile runs on any
  Mac. match does not encrypt a Google Cloud Storage backend (no `MATCH_PASSWORD`), and in readonly mode it never
  signs in to App Store Connect. The certificate's private key exists only in that private bucket, which only this
  job reads, without a key: from main, in the `signing` environment, after the owner's approval.
* The dependencies are resolved before the key is fetched: `flutter pub get --enforce-lockfile` fails if
  `pubspec.lock` would change, and the `pod install` of a configuration-only build must leave `Podfile.lock` as
  committed. The test run then uses `--no-pub`. The build hooks of the dependencies (and the CocoaPods and Xcode build
  phases) run while the key is in the keychain, so the committed lock files are the guard: they decide which code
  runs next to the key. No dependency update merges without the owner reviewing the diff of `pubspec.lock` and
  `Podfile.lock` of `example/`.
* match imports into a staging keychain, deleted in the same step, and exports the files; the key is imported into
  the signing keychain with `codesign` as its only trusted application and the partition list `apple-tool:,apple:`
  (match itself would also trust `security`, `productbuild` and `productsign`, and add `codesign:`), and the exported
  files are deleted. Both keychains have a random password and are deleted at the end of the job, even when a step
  fails. Before the build, the job checks that the profile is the expected one and grants the app's keychain group in
  `keychain-access-groups`, so a wrong profile fails with that message rather than as a failed launch.
* The job writes `macos/Runner/Configs/Signing.local.xcconfig` (manual signing with `Developer ID Application`
  and that profile, and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`, because a Developer ID profile does not allow the
  `get-task-allow` entitlement that Xcode adds to a Debug build) and runs `flutter test integration_test -d macos`.

Changes to `firebase_auth_providers_dart`, `firebase_app_dart` or `secure_flow`, which the example resolves through
`pubspec_overrides.yaml`, do not start the job; run it by hand after such a change.

To run them yourself, on a Mac signed in to Xcode with an Apple ID that can sign for the app:

```sh
cd example
flutter test integration_test -d macos
```

Local builds keep automatic development signing: `macos/Runner/Configs/Signing.xcconfig` signs for team
`DKY2FBVP6L`, but `flutter` does not let Xcode create the profile (`-allowProvisioningUpdates`): open `macos/Runner.xcworkspace` in Xcode once and build
the Runner scheme, which creates the development profile and registers the Mac. In another team, put your own
settings in `macos/Runner/Configs/Signing.local.xcconfig` (ignored by git), which replaces those of
`Signing.xcconfig`:

```
DEVELOPMENT_TEAM = <your team ID>
PRODUCT_BUNDLE_IDENTIFIER = <a bundle ID of your team>
```

The entitlement names `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`, so it follows. A build without signing
cannot run the tests: an ad-hoc signature cannot carry the entitlement, and the first write fails with
`errSecMissingEntitlement`. The tests write only keys that contain the id of the run, under the Keychain service
`firebase_auth_secure_storage` of the example app, and delete them.

### iOS

The default accessibility is `unlocked`: the session cannot be read or written while the device is locked. An app
that refreshes tokens in the background passes its own storage with
`IOSOptions(accountName: SecureAuthStorage.keychainService, accessibility: KeychainAccessibility.first_unlock)`.

### Android

The plugin's defaults (`AndroidOptions()`): no `EncryptedSharedPreferences` (deprecated, and migrated away from by
the plugin since 10.0), values encrypted with AES-GCM under a key wrapped by the Android Keystore, and
`resetOnError: true`.

Auto Backup copies the encrypted values but not the Keystore key, so after a restore on another device they cannot be
decrypted ("Failed to unwrap key"). The plugin then erases its storage (`resetOnError`), which signs the user out (and
deletes the app's own `flutter_secure_storage` values too). Keep the values out of the backup, as the plugin's README
says: set `android:allowBackup="false"` in `AndroidManifest.xml`, or exclude the `FlutterSecureStorage` shared
preferences in your backup rules.

### Windows

`flutter_secure_storage_windows` keeps every value in one map, encrypted with DPAPI for the current user, in
`flutter_secure_storage.dat` of the application support directory, and also asks the legacy Credential Manager
storage of earlier versions on each read and write. DPAPI needs an interactive logon of the user: in an SSH session or
a Windows service, `CryptProtectData` and `CryptUnprotectData` fail with `E_ACCESSDENIED` (`isUnavailable`). When it
cannot decrypt the file, the plugin deletes it, so starting an app over SSH after a desktop session can lose the
stored sessions. Use a `FileAuthStorage` for programs that run without a desktop session.

### Web

Browsers have no secure store: `localStorage` is readable by every script of the origin, and the plugin's wrapping key
lives in the same origin. Prefer `InMemoryAuthStorage` or `WebAuthStorage.session` of `firebase_auth_providers_dart`
(see the doc of `AuthStorage`).

## Tests

`flutter test` runs the unit tests against a fake of the plugin's method channel
(`plugins.it_nomads.com/flutter_secure_storage`), so the calls go through the real `FlutterSecureStorage` and the
errors arrive as the `PlatformException`s the native plugins send. They cover the keys and the default namespace, the
options per platform, each error remedy, and every migration path. The Windows implementation is Dart (FFI), not that
channel: it keeps one DPAPI-encrypted map in `flutter_secure_storage.dat` and calls the legacy C++ Credential Manager
path over the channel on every read and write. Its errors are tested by shape only, with an exception whose
`toString()` is that of `WindowsException` of `package:win32` 6.x; DPAPI itself never runs in the tests.

The integration tests of `example/` are for the real macOS keychain, in a signed build; see
[Signed integration tests](#signed-integration-tests).

In your own tests, `FlutterSecureStorage.setMockInitialValues({})` replaces the platform with an in-memory one.
