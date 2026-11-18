#!/bin/zsh
# All browsers, one after the other, for docs/spikes/indexeddb_cache.md section 8.
D=~/fvm/versions/3.44.9/bin/cache/dart-sdk/bin/dart
cd ${0:a:h}
mkdir -p out
$D run.dart cache --browser=chrome --compilers=js,wasm --sizes=2000,20000 --runs=3 > out/cache_chrome.txt 2>&1
$D run.dart cache --browser=firefox --compilers=js --sizes=2000,20000 --runs=3 > out/cache_firefox.txt 2>&1
$D run.dart cache --browser=safari --compilers=js --sizes=2000,20000 --runs=3 > out/cache_safari.txt 2>&1
echo done > out/cache_done
