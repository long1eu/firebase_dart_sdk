#!/usr/bin/env bash
# Builds the page into build/web: the page, its styles, and the program
# compiled with dart2wasm (main.mjs, main.wasm), the default, and dart2js
# (main.dart.js), the fallback.
# The folder is the whole site: put it on any static host, at the root or
# under a sub-path.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build/web
mkdir -p build/web
dart pub get
dart compile wasm -O2 --no-source-maps -o build/web/main.wasm web/main.dart
dart compile js -O2 --no-source-maps -o build/web/main.dart.js web/main.dart
cp web/index.html web/styles.css web/bootstrap.js build/web/
rm -f build/web/*.deps build/web/main.support.js
ls -l build/web
