#!/bin/sh
# Serves static/ on 127.0.0.1:8765 and opens the page given as $1 in headless Chrome with one fixed profile
# (/tmp/idb_profile) so every page shares the IndexedDB of the origin. Prints the page title once it no longer
# starts with "start" (pages set document.title to report), or "TIMEOUT".
# Usage: run_page.sh index.html | run_page.sh "index.html?c=wasm"
#
# The same port and profile as js_import/run_page.sh: both pages are on one origin and share its IndexedDB.
# Build first: see engine_page.dart.
cd "$(dirname "$0")/static" || exit 1
python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 &
S=$!
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --no-first-run \
  --remote-debugging-port=9333 --user-data-dir=/tmp/idb_profile "http://127.0.0.1:8765/$1" >/dev/null 2>&1 &
C=$!
RES=TIMEOUT
for i in $(seq 1 60); do
  sleep 0.5
  T=$(curl -s http://127.0.0.1:9333/json | python3 -I -c 'import json,sys
for t in json.load(sys.stdin):
    if t.get("type")=="page": print(t["title"])' 2>/dev/null | head -1)
  case "$T" in ""|start*|http*) ;; *) RES="$T"; break;; esac
done
sleep 1
echo "$RES"
kill $C $S 2>/dev/null
wait $C 2>/dev/null
