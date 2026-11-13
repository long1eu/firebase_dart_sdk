#!/usr/bin/env bash
# Prints the failed tests of a `dart test --reporter expanded` log with the first lines of
# each error, so that the cause is visible in a terminal or CI log without opening the file.
#
# Usage: tool/print_test_failures.sh <log file> [max lines per failure, default 25]
LOG="$1"
MAX="${2:-25}"
[ -f "$LOG" ] || { echo "No log file $LOG"; exit 1; }
# The browser runs redraw the progress line with carriage returns.
tr '\r' '\n' <"$LOG" | awk -v max="$MAX" '
  /^[0-9]+:[0-9]+ \+[0-9]+/ {
    printing = 0
    if ($0 ~ / \[E\]$/) {
      line = $0
      sub(/^[0-9:]+ [^:]*: /, "", line)
      sub(/ \[E\]$/, "", line)
      if (!(line in seen)) { seen[line] = 1; print "  failed: " line; printing = 1; n = 0 }
    }
    next
  }
  printing && n < max { if ($0 != "") { print "    " $0; n++ } }
'
