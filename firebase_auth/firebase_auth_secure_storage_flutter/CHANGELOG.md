## 0.1.0

- First version: `SecureAuthStorage`, an `AuthStorage` of `firebase_auth_providers_dart` on top of
  `flutter_secure_storage` 11.2, for `FirebaseUserAuth` and for `FirebaseAuthDart.use(storageFor:)` of
  `firebase_auth_dart_platform`, whose default storage it is. `FirebaseUserAuth` uses it only when passed.
- Keys are stored as `<namespace>/<key>`. The default namespace is unique per program and stable:
  `firebase_auth_secure_storage:<app>`, where `<app>` is a SHA-256 prefix of the executable path on macOS, Linux and
  Windows, `sandbox` on Android and iOS and `web` on the web; `namespace` overrides it. On iOS and macOS the items
  use the fixed Keychain service `firebase_auth_secure_storage`. macOS uses the data-protection keychain, which needs
  the `keychain-access-groups` entitlement; Android uses the plugin's defaults.
- The constructor does no I/O; the namespace and the store are first used at the first read or write.
- Every exception of the plugin becomes a `SecureAuthStorageException` that names the platform, the operation and a
  remedy (Linux without a Secret Service or with a locked keyring, a missing macOS entitlement, a locked iOS device,
  an Android Keystore failure, a missing plugin). There is no fallback to a file. `isUnavailable` says whether the
  store cannot be used at all in this run (no plugin, no Secret Service, a locked Linux keyring, a missing keychain
  entitlement, no keychain, DPAPI refusing `CryptProtectData` or `CryptUnprotectData` with `E_ACCESSDENIED` on Windows without an interactive logon)
  rather than failing for one value. The Windows remedy says that DPAPI needs an interactive logon (an SSH session or
  a service has none) for that case, and names `flutter_secure_storage.dat` for the others.
- `migrateFrom`: a key missing in the secure store is moved from the given storage (read, write, read back and
  compare, then delete there); a sign-out deletes it there too. A failed read or delete of the old storage goes to
  `onMigrationIssue`; a failed secure write is rethrown and a read-back mismatch throws
  `SecureAuthStorageMigrationException`, both leaving the old storage unchanged.
- `example/` is a macOS app with the `keychain-access-groups` entitlement, whose integration tests run
  `SecureAuthStorage` against the real data-protection keychain: a write with the defaults, a round trip, separate
  namespaces, both cases of a move from a `FileAuthStorage`, and no entry left behind. The workflow
  `secure_storage_signed_macos.yml` runs them in a signed build on main (on a push and by hand), with a Developer ID
  certificate and profile from fastlane match (readonly, Workload Identity Federation, no secrets) and the owner's
  approval; all six tests passed on its first run. The key is fetched only after the dependencies are resolved from the
  committed lock files.
