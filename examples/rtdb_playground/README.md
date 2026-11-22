# rtdb_playground

A browser page where you can try `firebase_database_dart`, the pure-Dart Realtime Database
client, with no backend and no Firebase project. It is plain Dart (`package:web`), compiled to
WebAssembly or JavaScript, and only static files. The page's Content-Security-Policy has
`connect-src 'self'`: it can connect to nothing but the host that serves it.

The client is the real one, created with `databaseWithFakeServer`. The server is
`SimServer` in `lib/sim_server.dart`: about 150 lines that watch `FakeDatabaseServer.requests`
and answer listens and gets from an in-memory JSON tree and acknowledge writes. **Rules are not
evaluated and this is not the real backend.**

What you can do: listen to a path, `set`, `update`, `push`, `remove` and run a transaction,
switch "server reachable" off to see local events at once and writes wait, switch it on to see
them catch up, and make the server reject the next write to see the rollback.

Build with `./build.sh` (output in `build/web`, not served by the script).
