## 0.1.0

- First version: `SecureAuthStorage`, an `AuthStorage` of `firebase_auth_providers_dart` for command line tools and
  servers, on the secret store of the system through `dart:ffi`: generic-password items of the macOS login keychain
  (Security.framework), the Secret Service through libsecret (loaded with `dlopen`) on Linux, and one file per key
  encrypted with DPAPI for the current user in `%LOCALAPPDATA%` on Windows. `SecretStore` is the interface of the
  store, for another store or a fake.
- Keys are stored as `<namespace>/<key>`, with the default namespace of `firebase_auth_secure_storage_flutter` on
  desktop (a SHA-256 prefix of the executable path); `namespace` overrides it, and programs run with `dart run` should
  pass one.
- The constructor does no I/O. `isAvailable()` writes, reads back and deletes a probe entry and returns false only
  when the store cannot be used at all in this run.
- Every failure becomes a `SecureAuthStorageException` with the platform, the operation, the native function and
  status, and a remedy; `isUnavailable` says whether the store as a whole cannot be used (no library, no Secret
  Service, a locked Linux collection, no keychain, DPAPI refusing access without an interactive logon). No stored
  value is ever printed or put in an exception, and nothing is written anywhere else instead.
- `migrateFrom` moves a session from another storage with the rules of the Flutter package (read, write, read back
  and compare, then delete there; a sign-out deletes it there too).
- Tested: unit tests with fakes of the store; the integration tests ran on macOS only. Linux and Windows are
  untested.
