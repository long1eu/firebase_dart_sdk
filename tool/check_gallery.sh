#!/usr/bin/env bash
# Checks the web gallery that tool/build_gallery.sh wrote to build/gallery: for every example that script
# lists and that has web/index.html, each web/*.dart entry has its built <base>.dart.js, <base>.wasm and
# <base>.mjs, and every relative href and src of the built index.html names a file that exists. The root
# index.html must exist and link to each example folder. Prints the first missing path and exits 1.
#
# Usage: tool/check_gallery.sh        (run tool/build_gallery.sh first)
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
out="$root/build/gallery"

missing() {
  echo "check_gallery: missing $1" >&2
  exit 1
}

[ -d "$out" ] || missing "$out (run tool/build_gallery.sh first)"
[ -f "$out/index.html" ] || missing "$out/index.html"

# The example names are the first field of the entries of the `examples` array in build_gallery.sh.
names="$(sed -n 's/^  "\([a-z_]*\)|.*/\1/p' "$root/tool/build_gallery.sh")"
[ -n "$names" ] || missing "the example list in tool/build_gallery.sh"

checked=0
for name in $names; do
  src="$root/examples/$name"
  [ -f "$src/web/index.html" ] || continue
  dir="$out/$name"
  [ -d "$dir" ] || missing "$dir"
  grep -q "href=\"$name/\"" "$out/index.html" || missing "the link to $name/ in $out/index.html"
  for main in "$src"/web/*.dart; do
    base="$(basename "$main" .dart)"
    for ext in dart.js wasm mjs; do
      [ -f "$dir/$base.$ext" ] || missing "$dir/$base.$ext"
    done
  done
  [ -f "$dir/index.html" ] || missing "$dir/index.html"
  # Every href="..." and src="..." value, except absolute URLs, anchors, data URIs and query-only links.
  refs="$(grep -o -E '(href|src)="[^"]*"' "$dir/index.html" | sed -E 's/^[a-z]+="//; s/"$//')"
  while IFS= read -r ref; do
    case "$ref" in
    '' | '#'* | '?'* | './?'* | http:* | https:* | data:* | //*) continue ;;
    esac
    path="${ref%%[?#]*}"
    [ -e "$dir/$path" ] || missing "$dir/$path (referenced by $dir/index.html)"
  done <<<"$refs"
  checked=$((checked + 1))
done

# The smoke test waits for the playground's reject button by its label: a label changed in the page
# and not in tool/smoke_gallery.mjs fails here, before a browser starts.
labels="$(sed -n "s/^const REJECT_O[NF]* = '\\(.*\\)';\$/\\1/p" "$root/tool/smoke_gallery.mjs")"
[ "$(printf '%s\n' "$labels" | grep -c .)" -eq 2 ] ||
  missing "the two REJECT_ labels in tool/smoke_gallery.mjs"
while IFS= read -r label; do
  grep -q -F "'$label'" "$root/examples/rtdb_playground/web/main.dart" ||
    missing "the reject button label '$label' in examples/rtdb_playground/web/main.dart"
done <<<"$labels"

[ "$checked" -gt 0 ] || missing "any example folder under $out"
echo "check_gallery: $checked examples ok in $out"
