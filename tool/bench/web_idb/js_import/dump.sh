#!/bin/sh
# Dumps the JS SDK's database that writer.html left in the profile /tmp/idb_profile (origin 127.0.0.1:8765, the
# same as run_page.sh) to the file $1 (static/dump.js; the format is in its header). Usage, after building writer.js
# (see run_page.sh):
#   rm -rf /tmp/idb_profile; js_import/run_page.sh writer.html
#   js_import/dump.sh ../../../cloud_firestore/cloud_firestore_dart/test/browser/js_sdk_cache_fixture.json
OUT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "$0")/static" || exit 1
rm -f "$OUT"
OUT="$OUT" python3 -I -c '
import http.server, os
class H(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        with open(os.environ["OUT"], "wb") as f:
            f.write(body + b"\n")
        self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", 8765), H).serve_forever()
' &
S=$!
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --no-first-run \
  --remote-debugging-port=9333 --user-data-dir=/tmp/idb_profile "http://127.0.0.1:8765/dump.html" >/dev/null 2>&1 &
C=$!
for i in $(seq 1 60); do
  sleep 0.5
  [ -s "$OUT" ] && break
done
sleep 1
T=$(curl -s http://127.0.0.1:9333/json | python3 -I -c 'import json,sys
for t in json.load(sys.stdin):
    if t.get("type")=="page": print(t["title"])' 2>/dev/null | head -1)
echo "${T:-TIMEOUT}"
kill $C $S 2>/dev/null
wait $C 2>/dev/null
[ -s "$OUT" ]
