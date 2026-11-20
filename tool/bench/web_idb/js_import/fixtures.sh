#!/bin/sh
# Generates the fixtures of the browser tests of importJsSdkCache with the real JS SDK (static/fixtures.js has what
# each one holds) into cloud_firestore/cloud_firestore_dart/test/browser/js_sdk_cache_fixtures/<name>.json.
#
# Usage: fixtures.sh <port of an emulator with open rules> [port of the rules emulator of start_auth_emulators.sh]
#   tool/start_private_emulator.sh 8404; tool/start_auth_emulators.sh 9297 8297
#   tool/bench/web_idb/js_import/fixtures.sh 8404 8297
#
# The JS SDK is loaded as ES modules straight from tool/interop/node_modules (`cd tool/interop && npm install`), with
# an import map (static/fixtures.html): no bundler. Headless Chrome runs on a new profile (/tmp/js_fixtures_profile),
# on the origin 127.0.0.1:8766. Prints the page title at the end ("done: ..." or "error: ...").
OPEN_PORT="$1"
RULES_PORT="$2"
[ -n "$OPEN_PORT" ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
MODULES="$ROOT/tool/interop/node_modules"
OUT="$ROOT/cloud_firestore/cloud_firestore_dart/test/browser/js_sdk_cache_fixtures"
[ -d "$MODULES/@firebase/firestore" ] || { echo "$MODULES has no JS SDK: cd tool/interop && npm install"; exit 1; }
mkdir -p "$OUT" || exit 1

cd "$HERE/static" || exit 1
MODULES="$MODULES" OUT="$OUT" python3 -I -c '
import http.server, os, re
MODULES = os.environ["MODULES"]
OUT = os.environ["OUT"]
class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".js": "text/javascript", ".mjs": "text/javascript"}
    def translate_path(self, path):
        if path.startswith("/node_modules/"):
            return os.path.join(MODULES, path[len("/node_modules/"):].split("?")[0])
        return super().translate_path(path)
    def do_POST(self):
        m = re.fullmatch(r"/fixture/([a-z_0-9]+)", self.path)
        if not m:
            self.send_response(404); self.end_headers(); return
        body = self.rfile.read(int(self.headers["Content-Length"]))
        with open(os.path.join(OUT, m.group(1) + ".json"), "wb") as f:
            f.write(body + b"\n")
        self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", 8766), H).serve_forever()
' &
S=$!
rm -rf /tmp/js_fixtures_profile
QUERY="open=$OPEN_PORT"
[ -n "$RULES_PORT" ] && QUERY="$QUERY&rules=$RULES_PORT"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --no-first-run \
  --remote-debugging-port=9334 --user-data-dir=/tmp/js_fixtures_profile \
  "http://127.0.0.1:8766/fixtures.html?$QUERY" >/dev/null 2>&1 &
C=$!
RES=TIMEOUT
for i in $(seq 1 240); do
  sleep 0.5
  T=$(curl -s http://127.0.0.1:9334/json | python3 -I -c 'import json,sys
for t in json.load(sys.stdin):
    if t.get("type")=="page": print(t["title"])' 2>/dev/null | head -1)
  case "$T" in ""|start*|http*) ;; *) RES="$T"; break;; esac
done
echo "$RES"
kill $C $S 2>/dev/null
wait $C 2>/dev/null
case "$RES" in done*) exit 0;; *) exit 1;; esac
