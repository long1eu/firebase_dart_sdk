# rtdb_web_app

- **Product:** Realtime Database (`firebase_database_dart`)
- **Platform:** web (`package:web`, no Flutter)
- **Backend:** emulator (start it from the repository root with `tool/start_database_emulator.sh` (port 9100)), or your own project (none by default)
- **Run:** `dart compile js -O2 -o build/web/main.dart.js web/main.dart`, copy `web/*` next to it, serve the folder, open `index.html?emulator=127.0.0.1:9100`
- **CI:** compile (`dart compile js`) and `dart analyze`
- **Web gallery:** -

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

The client's real connection is not merged yet: `FirebaseDatabase(app)` throws at run time until it is.
The page compiles; it has not been served or run against an emulator.

## Build

```sh
dart pub get
dart compile js -O2 -o build/web/main.dart.js web/main.dart
```

Dependencies come from this repository (`dependency_overrides` in `pubspec.yaml`).
