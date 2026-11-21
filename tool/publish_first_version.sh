#!/usr/bin/env bash
# Publishes a package to pub.dev by hand, from a clean copy of origin/main.
#
# pub.dev allows automated publishing (publish.yml) only for a package that already exists, so the
# FIRST version of a new package goes out with this script. Later versions go out by tag.
#
# Usage: tool/publish_first_version.sh <package name> [git ref]      (ref default: origin/main)
#   e.g. tool/publish_first_version.sh firebase_storage_dart
#
# What it does:
#   1. finds the package directory in the repository by its pubspec name;
#   2. exports that directory at <ref> into a temporary folder (no local edits, no
#      pubspec_overrides.yaml, so every dependency resolves from pub.dev as users get it);
#   3. checks that CHANGELOG.md has a heading for the pubspec version;
#   4. runs `pub get` and `pub publish --dry-run` (flutter for Flutter packages);
#   5. runs `pub publish`, which shows the archive and asks y/N. Publishing cannot be undone.
#
# DRY_RUN=1 stops after step 4.
#
# It never reads or prints credentials; pub uses the login of whoever runs it.
set -euo pipefail

name="${1:-}"
ref="${2:-origin/main}"
if [ -z "$name" ]; then
  echo "Usage: $0 <package name> [git ref]" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
git fetch --quiet origin

dir=""
while IFS= read -r pubspec; do
  if [ "$(git show "$ref:$pubspec" | sed -n 's/^name: *//p' | head -1)" = "$name" ]; then
    dir="$(dirname "$pubspec")"
    break
  fi
done < <(git ls-tree -r --name-only "$ref" | grep -E '(^|/)pubspec\.yaml$')

if [ -z "$dir" ]; then
  echo "No package named $name at $ref." >&2
  exit 1
fi

work="$(mktemp -d)"
cleanup() { if command -v trash >/dev/null; then trash "$work"; else rm -r "$work"; fi; }
trap cleanup EXIT
git archive "$ref" "$dir" | tar -x -C "$work"
cd "$work/$dir"
rm -f pubspec_overrides.yaml

version="$(sed -n 's/^version: *//p' pubspec.yaml | head -1)"
if ! grep -Eq "^## \\[?${version//./\\.}\\]?( |$)" CHANGELOG.md; then
  echo "CHANGELOG.md of $name has no '## $version' heading." >&2
  exit 1
fi

if grep -Eq '^\s*sdk:\s*flutter\s*$' pubspec.yaml; then pub=(flutter pub); else pub=(dart pub); fi

echo "Package:  $name $version"
echo "From:     $ref:$dir ($(git -C "$root" rev-parse --short "$ref"))"
echo "Tool:     ${pub[*]}"
echo
"${pub[@]}" get
"${pub[@]}" publish --dry-run
echo
if [ "${DRY_RUN:-}" = 1 ]; then
  echo "The dry run passed (DRY_RUN=1: nothing published)."
  exit 0
fi
echo "The dry run passed. pub now shows the archive and asks for confirmation."
"${pub[@]}" publish
