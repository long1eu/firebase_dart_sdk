#!/usr/bin/env bash
# Builds the playground into build/web: the page, its styles, and the program
# compiled with dart2js (main.dart.js) and dart2wasm (main.mjs, main.wasm).
# The folder is the whole site: put it on any static host, at the root or
# under a sub-path.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build/web
mkdir -p build/web
dart pub get
dart compile js -O2 --no-source-maps -o build/web/main.dart.js web/main.dart
dart compile wasm -O2 --no-source-maps -o build/web/main.wasm web/main.dart
cp web/index.html web/styles.css web/bootstrap.js web/favicon.svg build/web/
# Not needed by the site: the dependency list of dart2js, and the wasm support
# check of dart2wasm (bootstrap.js has the same check inline).
rm -f build/web/*.deps build/web/main.support.js
ls -l build/web
