#!/bin/sh
# The interop check of the IndexedDB engine against the official JS SDK, both ways, on one database, one SDK at a time
# (interop_check.mjs). Needs a Firestore emulator already running (default port 8395), Chrome (CHROME names the
# binary when it is not in the usual place), Node, and the npm packages of package-lock.json (`npm ci` here, run by
# this script when node_modules is missing: the firebase JS SDK and esbuild). Builds the two pages, then prints
# PASS/FAIL per check, and exits non-zero when one failed. CI runs it (the "IndexedDB cache interop" job).
#
#   tool/bench/web_idb/js_import/interop_check.sh [emulator port] [parts, e.g. ABCD]
set -e
cd "$(dirname "$0")"
[ -d node_modules/firebase ] || npm ci --silent --no-audit --no-fund
npx esbuild interop.js --bundle --platform=browser --main-fields=browser,module,main --conditions=browser \
  --outfile=static/interop.bundle.js --log-level=warning
(cd .. && dart pub get >/dev/null && dart compile js -O1 js_import/interop_engine.dart \
  -o js_import/static/interop_engine.js >/dev/null)
exec node interop_check.mjs "${1:-8395}" "${2:-ABCD}"
