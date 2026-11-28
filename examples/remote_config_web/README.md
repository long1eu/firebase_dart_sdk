# remote_config_web

- **Product:** Remote Config (`firebase_remote_config_dart`) on Installations (`firebase_installations_dart`)
- **Platform:** web (`package:web`, no Flutter)
- **Backend:** your own Firebase project; there is no emulator for Remote Config or Installations
- **Run:** compile `web/main.dart` (see Build), serve the `build/web` folder (for example `python3 -m http.server -d build/web 8000` from this directory), open `http://localhost:8000/`, enter the API key, app id and project id
- **CI:** `tool/test_all.sh` runs `dart pub get` and `dart analyze` here; nothing in CI compiles or runs the page against a project
- **Web gallery:** yes, `tool/build_gallery.sh` compiles it with dart2wasm and dart2js and copies `web/*`

A browser app in plain Dart on the pure-Dart Remote Config client:

- a form for the API key, the app id and the project id of a web app of your project;
- **Fetch and activate** (`fetchAndActivate()`), with the error code shown when the fetch fails;
- a table of every value (`getAll()`) with its source: `valueRemote`, `valueDefault` or `valueStatic`;
- the last fetch status and time and the fetched and active template versions (`info`);
- a log of realtime updates (`onConfigUpdated`): the keys that changed, after which the page activates them.

The installation (its id and tokens) is kept in this browser's IndexedDB (`IndexedDbKeyValueStore()`, database
`firebase_dart_kv`). Clear the site data of the page to start with a new installation.

## What you need

- A web app registered in your Firebase project (project settings, "Your apps"): it gives you the **app id**
  (`1:<number>:web:<hash>`) and the **API key** (it starts with `A` and has 39 characters). The number inside the
  app id is the project number that realtime updates need.
- A Remote Config template with at least one parameter, published.
- An API key without restrictions, or one whose HTTP referrer restriction allows the address you serve this page
  from (referrer restrictions work on the web only), and whose API restrictions allow the Firebase Installations
  API, the Firebase Remote Config API and the Firebase Remote Config Realtime API. Without the last one the log
  shows a `stream-error` with a 403.

## Privacy

Nothing leaves the browser except to `firebaseinstallations.googleapis.com`, `firebaseremoteconfig.googleapis.com`
and `firebaseremoteconfigrealtime.googleapis.com`: the Content-Security-Policy (a `<meta>` tag in `web/index.html`)
allows no other host in `connect-src`. The page stores no API key, app id or project id; it stores only the
installation record, in IndexedDB. The values of a Remote Config template are public: anyone with the API key and
app id can fetch them.

## Realtime updates

Publish a change in the Firebase console while the page is connected. After a few seconds the log shows the keys
that changed and the table shows the new values. The page listens from the moment it is connected, without a first
fetch. A hidden tab does not hold the stream open: it reconnects when the tab is visible again.

## Offline

Without a network, the table shows the defaults and the page shows the error code of the failed fetch
(`fetch-client-network`, or `installations-error` when the installation is not registered yet).

## Build

```sh
dart pub get
dart compile wasm -O2 --no-source-maps -o build/web/main.wasm web/main.dart
dart compile js -O2 --no-source-maps -o build/web/main.dart.js web/main.dart
cp web/index.html web/styles.css web/bootstrap.js build/web/
```

`bootstrap.js` starts the dart2wasm build (`main.mjs`, `main.wasm`) when the browser can run it and the dart2js build
(`main.dart.js`) otherwise; `?compiler=js` or `?compiler=wasm` picks one. The Content-Security-Policy has
`'wasm-unsafe-eval'` for the WebAssembly build; without it the page falls back to dart2js. Dependencies come from
this repository (`dependency_overrides` in `pubspec.yaml`).
