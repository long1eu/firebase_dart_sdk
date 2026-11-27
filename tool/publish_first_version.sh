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
#      pubspec_overrides.yaml in it or in its example, so every dependency resolves from pub.dev
#      as users get it);
#   3. checks that CHANGELOG.md has a heading for the pubspec version and that this version is not on
#      pub.dev yet;
#   4. runs `pub get` and `pub publish --dry-run` (flutter for Flutter packages);
#   5. runs `pub publish`, which shows the archive and asks y/N. Publishing cannot be undone.
#
# DRY_RUN=1 stops after step 4. Without a terminal (a '!' command in Claude Code, CI) pub cannot
# ask y/N: then it publishes only with CONFIRM=publish, which is the confirmation, and otherwise
# stops after the dry run.
#
# KEEP_OVERRIDE="<package> [<package> ...]" is for two packages of this repository that need each
# other, where the first one cannot resolve the second from pub.dev yet (firebase_database_dart has a
# dev dependency on firebase_database_dart_sqlite, which depends on it). With it the script exports
# the whole repository at <ref>, deletes every pubspec_overrides.yaml as always, and then writes one
# into the package with only the named packages, by path into that export. It publishes only when
# each named package is a dev dependency: an override of a real dependency is for DRY_RUN=1 alone
# (a rehearsal before the first package is out), and pub marks it with a hint. Without
# KEEP_OVERRIDE the script does what it always did.
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

# Prints the directory of the package named $1 at $ref, or nothing.
dir_of() {
  local pubspec
  while IFS= read -r pubspec; do
    if [ "$(git -C "$root" show "$ref:$pubspec" | sed -n 's/^name: *//p' | head -1)" = "$1" ]; then
      dirname "$pubspec"
      return
    fi
  done < <(git -C "$root" ls-tree -r --name-only "$ref" | grep -E '(^|/)pubspec\.yaml$')
}

dir="$(dir_of "$name")"
if [ -z "$dir" ]; then
  echo "No package named $name at $ref." >&2
  exit 1
fi

keep=()
read -r -a keep <<<"${KEEP_OVERRIDE:-}"

work="$(mktemp -d)"
cleanup() { if command -v trash >/dev/null; then trash "$work"; else rm -r "$work"; fi; }
trap cleanup EXIT
if [ "${#keep[@]}" -eq 0 ]; then
  git archive "$ref" "$dir" | tar -x -C "$work"
  cd "$work/$dir"
  find . -name pubspec_overrides.yaml -type f -delete
else
  git archive "$ref" | tar -x -C "$work"
  find "$work" -name pubspec_overrides.yaml -type f -delete
  cd "$work/$dir"
  # The names below `dependencies:` (not dev_dependencies) of this package.
  real="$(awk '/^[a-z_]+:/ { in_deps = ($1 == "dependencies:") } in_deps && /^  [a-z0-9_]+:/ { sub(":.*", "", $1); print $1 }' pubspec.yaml)"
  echo "dependency_overrides:" >pubspec_overrides.yaml
  for kept in "${keep[@]}"; do
    kept_dir="$(dir_of "$kept")"
    if [ -z "$kept_dir" ]; then
      echo "KEEP_OVERRIDE: no package named $kept at $ref." >&2
      exit 1
    fi
    if grep -qx "$kept" <<<"$real" && [ "${DRY_RUN:-}" != 1 ]; then
      echo "KEEP_OVERRIDE: $kept is a dependency of $name, not a dev dependency. An archive resolved" >&2
      echo "against a local path is not published; this is for DRY_RUN=1 only." >&2
      exit 1
    fi
    printf '  %s:\n    path: %s\n' "$kept" "$work/$kept_dir" >>pubspec_overrides.yaml
  done
fi

version="$(sed -n 's/^version: *//p' pubspec.yaml | head -1)"
if ! grep -Eq "^## \\[?${version//./\\.}\\]?( |$)" CHANGELOG.md; then
  echo "CHANGELOG.md of $name has no '## $version' heading." >&2
  exit 1
fi

# A version that is already on pub.dev cannot be published again: stop before building anything.
status="$(curl -s -o /dev/null -w '%{http_code}' "https://pub.dev/api/packages/$name/versions/$version")"
if [ "$status" = 200 ]; then
  echo "$name $version is already on pub.dev. Is the version bump merged into $ref? (git pull)" >&2
  exit 1
fi

if grep -Eq '^\s*sdk:\s*flutter\s*$' pubspec.yaml; then pub=(flutter pub); else pub=(dart pub); fi

echo "Package:  $name $version"
echo "From:     $ref:$dir ($(git -C "$root" rev-parse --short "$ref"))"
echo "Tool:     ${pub[*]}"
if [ "${#keep[@]}" -gt 0 ]; then echo "Override: ${keep[*]} (by path, from the same export)"; fi
echo
"${pub[@]}" get
"${pub[@]}" publish --dry-run
echo
if [ "${DRY_RUN:-}" = 1 ]; then
  echo "The dry run passed (DRY_RUN=1: nothing published)."
  exit 0
fi
if [ -t 0 ]; then
  echo "The dry run passed. pub now shows the archive and asks for confirmation."
  "${pub[@]}" publish
elif [ "${CONFIRM:-}" = publish ]; then
  echo "The dry run passed. CONFIRM=publish: publishing $name $version without a prompt."
  "${pub[@]}" publish --force
else
  echo "The dry run passed, but there is no terminal to answer pub's y/N prompt (for example a"
  echo "'!' command in Claude Code). Nothing was published. To publish without the prompt, run:"
  echo "  CONFIRM=publish $0 $name${2:+ $2}"
  exit 3
fi
