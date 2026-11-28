## 0.1.0

- `KeyValueStore`: the persistent key-value storage of the installation record, with an atomic `update`
  and a `changes` stream.
- `MemoryKeyValueStore`: a store in memory, for tests and short-lived tools.
- `FileKeyValueStore` (`io.dart`): one file per key, atomic writes, one owning process per directory
  (OS lock), a private directory on Linux and macOS.
- `IndexedDbKeyValueStore` (`web.dart`): an IndexedDB database shared by the tabs of an origin, with
  change announcements on a `BroadcastChannel`.
- `FirebaseInstallations`: `getId`, `getToken`, `getIdAndToken`, `delete`, `onIdChange` and `close`;
  registration in the background, token refresh with less than one hour left, recovery when the
  server forgets the installation, markers shared between tabs, and an in-memory record when the store
  cannot be written.
- One retry after 1 s on a 5xx or a transport error; a 24 h block after 400 or 403; exponential backoff
  after 429 and other failures.
- A 409 on create starts a backoff window and recovers once per call with a new FID; a 3xx and a create answered 401
  or 404 also feed the backoff; any other 4xx is `invalid-response`.
- `FirebaseInstallationsException` with the codes in `firebaseInstallationsExceptionCodes`.
- Response caps, refused redirects, a 10 s deadline per request and 60 s per call; no token, API key or
  request body in a log line or an error message.
