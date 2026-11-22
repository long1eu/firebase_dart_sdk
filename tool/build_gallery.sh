#!/usr/bin/env bash
# Builds the web gallery into build/gallery: one folder per web example that exists, and an index.html
# that lists them. Each page is compiled with dart2wasm (the default build) and dart2js (the fallback), as
# the build.sh of examples/playground does; the first compile error stops the script.
# No deploy step, and no network use besides `dart pub get`. The sqlite3.wasm download of web_app's SQLite
# cache is not done: that cache is off in the gallery.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
out="$root/build/gallery"

# name|title|one line
examples=(
  "playground|Firestore playground|The Firestore client on a memory cache with its network off: queries, snapshots and queued writes."
  "web_app|Firestore web app|A real-time list on Firestore, a Lite page and a Cloud Storage page; needs an emulator or a project."
  "rtdb_web_app|Realtime Database web app|The Realtime Database client in a browser app."
  "rtdb_playground|Realtime Database playground|The real client against a simulated server in the page: offline writes, catch-up and rollback."
)

rm -rf "$out"
mkdir -p "$out"
cards=""

for entry in "${examples[@]}"; do
  IFS='|' read -r name title line <<<"$entry"
  dir="$root/examples/$name"
  [ -f "$dir/web/index.html" ] || continue
  echo "== $name"
  (
    cd "$dir"
    dart pub get
    mkdir -p "$out/$name"
    for main in web/*.dart; do
      base="$(basename "$main" .dart)"
      dart compile wasm -O2 --no-source-maps -o "$out/$name/$base.wasm" "$main"
      dart compile js -O2 --no-source-maps -o "$out/$name/$base.dart.js" "$main"
    done
    for file in web/*; do
      case "$file" in *.dart) ;; *) cp "$file" "$out/$name/" ;; esac
    done
  )
  rm -f "$out/$name"/*.deps "$out/$name"/*.support.js
  cards+="    <li><a href=\"$name/\"><strong>$title</strong></a><span>$line</span></li>"$'\n'
done

cat >"$out/index.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="Content-Security-Policy"
        content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
  <meta name="color-scheme" content="light dark">
  <title>Firebase Dart SDK: web examples</title>
  <style>
    :root { --bg: #f6f7f9; --panel: #fff; --text: #1c2430; --muted: #5a6575; --line: #d6dbe3; --accent: #1a5fb4; color-scheme: light dark; }
    @media (prefers-color-scheme: dark) {
      :root { --bg: #14181e; --panel: #1d232b; --text: #e4e8ee; --muted: #a0aab8; --line: #333c48; --accent: #7fb0f0; }
    }
    * { box-sizing: border-box; }
    body { margin: 0; padding: 1rem; background: var(--bg); color: var(--text); font: 16px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
    main { max-width: 44rem; margin: 0 auto; }
    h1 { font-size: 1.5rem; margin: 0 0 0.25rem; }
    p { color: var(--muted); margin: 0 0 1rem; }
    ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 0.75rem; }
    li { display: grid; gap: 0.2rem; background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 0.8rem 1rem; }
    li span { color: var(--muted); }
    a { color: var(--accent); font-size: 1.1rem; }
    a:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px; }
  </style>
</head>
<body>
  <main>
    <h1>Firebase Dart SDK: web examples</h1>
    <p>Pure-Dart clients compiled to WebAssembly or JavaScript. Each page is static files.</p>
    <ul>
${cards}    </ul>
  </main>
</body>
</html>
HTML
ls "$out"
