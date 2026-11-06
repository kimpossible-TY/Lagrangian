#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")/../.."
source scripts/mac/auto-update-engine.sh
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/autoupdate-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
STATE="$TEST_DIR/last-installed-run"
EVENTS="$TEST_DIR/events"
printf '100\n' > "$STATE"
: > "$EVENTS"
RUNNING=''; SUCCESS=100; WATCH_RESULT=0; LIST_ERROR=0
gh() {
  if [[ "$1 $2" == 'run list' ]]; then
    (( LIST_ERROR == 0 )) || return 1
    case " $* " in
      *' -s in_progress '*) printf '%s\n' "$RUNNING" ;;
      *' -s success '*) printf '%s\n' "$SUCCESS" ;;
      *) return 1 ;;
    esac
  elif [[ "$1 $2" == 'run watch' ]]; then
    [[ "$*" == "run watch $3 -R kimpossible-TY/Lagrangian --exit-status" ]]
    printf 'watch %s\n' "$3" >> "$EVENTS"
    return "$WATCH_RESULT"
  else
    return 1
  fi
}
install_run() { printf 'install %s\n' "$1" >> "$EVENTS"; printf '%s\n' "$1" > "$STATE"; }
expect() {
  local expected="$1" actual
  actual=$(cat "$EVENTS")
  if [[ "$actual" != "$expected" ]]; then
    printf 'Expected: <%s>\nActual: <%s>\n' "$expected" "$actual" >&2
    exit 1
  fi
  : > "$EVENTS"
}
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 60 ]]
RUNNING=102; SUCCESS=101
watch_iteration; expect 'watch 102'; [[ "$NEXT_DELAY" == 0 ]]
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 5 ]]
# A newer run arriving during watch supersedes the successful watched run.
RUNNING=103; SUCCESS=102
watch_iteration; expect 'watch 103'
RUNNING=''; SUCCESS=103
watch_iteration; expect 'install 103'
watch_iteration; expect ''
RUNNING=104; WATCH_RESULT=1
watch_iteration; expect 'watch 104'; [[ "$NEXT_DELAY" == 60 ]]
RUNNING=''; SUCCESS=103; WATCH_RESULT=0
watch_iteration; expect ''
# A cancelled newer run permits an uninstalled successful predecessor.
RUNNING=106; SUCCESS=105; WATCH_RESULT=1
watch_iteration; expect 'watch 106'
RUNNING=''; WATCH_RESULT=0
watch_iteration; expect 'install 105'
# Catch up on an already successful run, and do not roll back to an older one.
SUCCESS=107
watch_iteration; expect 'install 107'
SUCCESS=104
watch_iteration; expect ''
# Failed lookup and malformed state must never install.
SUCCESS=106; LIST_ERROR=1
watch_iteration; expect ''
LIST_ERROR=0; printf 'invalid\n' > "$STATE"
watch_iteration; expect ''
printf 'auto-update watch regression passed\n'
python3 scripts/mac/test-reader-refresh.py
