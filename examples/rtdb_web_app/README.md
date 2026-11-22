# rtdb_web_app

- **Product:** Realtime Database (`firebase_database_dart`)
- **Platform:** web (`package:web`, no Flutter)
- **Backend:** emulator (start it from the repository root with `tool/start_database_emulator.sh` (port 9100)), or your own project (none by default)
- **Run:** `./build.sh`, serve `build/web`, open `index.html?emulator=127.0.0.1:9100`
- **CI:** `tool/test_all.sh` runs `dart pub get` and `dart analyze` here; nothing in CI compiles it
- **Web gallery:** yes, `tool/build_gallery.sh` compiles it with dart2wasm and dart2js and copies `web/*`

A browser app in plain Dart on the pure-Dart Realtime Database client:

- a live list at `rtdb_web_app/items` (`onChildAdded`, `onChildChanged`, `onChildRemoved`);
- a form that pushes an item (`push().set(...)`, with `ServerValue.timestamp`);
- a connection indicator from `.info/connected` (`FirebaseDatabase.onConnected`);
- a **Go offline / Go online** button (`goOffline()`, `goOnline()`): items added while offline show in the
  list at once (in italics) and are sent when the page goes online;
- a **Connect your own emulator or project** panel.

## Connect your own emulator or project

With no parameters the page connects to nothing and asks for an emulator host. Give one of:

| Parameter | Meaning |
| --- | --- |
| `?emulator=127.0.0.1:9100` | A Realtime Database emulator on this machine (`localhost` also works). `project=` is optional (default `demo-example`). |
| `?databaseUrl=...&apiKey=...&project=...` | Your project: `https://<name>.firebaseio.com` or `https://<name>.firebasedatabase.app`. |

The same fields are in the panel. Nothing is stored unless you tick **Remember in this browser**
(`localStorage`; **Forget stored settings** removes it). Nothing leaves the browser except to that
database: the page has no server of its own, and its Content-Security-Policy (a `<meta>` tag in
`web/index.html`) limits `connect-src` to `*.firebaseio.com`, `*.firebasedatabase.app` and loopback
(`127.0.0.1`, `localhost`, over http and ws). Your database rules decide what a visitor may read and write.

## Status

The page uses the real connection (`FirebaseDatabase(app, emulatorHost: ..., databaseUrl: ...)` in
`web/main.dart`). I could not verify that this page was served and used against an emulator; the
package's own browser tests run the client in a browser (see `firebase_database_dart/README.md`).

## Build

```sh
./build.sh
```

`build.sh` writes `build/web`: the page, `bootstrap.js`, the dart2wasm build (`main.mjs`, `main.wasm`, used when
the browser can run it) and the dart2js build (`main.dart.js`, the fallback). `?compiler=js` or `?compiler=wasm`
picks one. The Content-Security-Policy has `'wasm-unsafe-eval'` for the WebAssembly build; without it the page
falls back to dart2js. Dependencies come from this repository (`dependency_overrides` in `pubspec.yaml`).
