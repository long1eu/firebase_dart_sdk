# ai_web

- **Product:** AI Logic (`firebase_ai_dart`)
- **Platform:** web (`package:web`, no Flutter)
- **Backend:** your own Firebase project with Firebase AI Logic turned on; there is no emulator for AI Logic
- **Run:** compile `web/main.dart` (see Build), serve the `build/web` folder (for example `python3 -m http.server -d build/web 8000` from this directory), open `http://localhost:8000/`, enter the API key, app id, project id and a model name, and press Connect
- **CI:** `tool/test_all.sh` runs `dart pub get` and `dart analyze` here; nothing in CI compiles or runs the page against a project
- **Web gallery:** yes, `tool/build_gallery.sh` compiles it with dart2wasm and dart2js and copies `web/*`

A browser app in plain Dart on the pure-Dart AI Logic client:

- a form for the API key, the app id and the project id of a web app of your project, a model name, the backend
  (Gemini Developer API or Agent Platform) and, for Agent Platform, the location;
- a prompt box and **Send**, which streams the answer into the page (`generateContentStream`);
- **Stop**, which aborts the request in the browser (`abortTrigger`). The service may still finish the request and
  bill it.

## What you need

- A web app registered in your Firebase project (project settings, "Your apps"): it gives you the **app id**
  (`1:<number>:web:<hash>`) and the **API key**.
- Firebase AI Logic turned on for the project (Firebase console, AI Logic), with the backend you choose set up.
- A model name your project can use. The page has no default: model names change between releases.
- An API key whose API restrictions allow the Firebase AI Logic API, and whose HTTP referrer restriction allows the
  address you serve this page from (referrer restrictions work on the web only).

## Billing and App Check

Every prompt is billed to your project. The API key of a web app is public, so anyone who has it can send prompts
to your project, up to its quota. Turn on App Check enforcement for AI Logic to limit that. This page sends no App
Check token: with enforcement on, its requests are refused. A page that ships to users needs an App Check provider
on the `FirebaseApp` (see the guide, [docs/guides/ai_logic.md](../../docs/guides/ai_logic.md)).

## Privacy

Nothing leaves the browser except to `firebasevertexai.googleapis.com`: the Content-Security-Policy (a `<meta>` tag
in `web/index.html`) allows no other host in `connect-src`. The page stores nothing: not the API key, the app id,
the project id, the prompt or the answer.

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
