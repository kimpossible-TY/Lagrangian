#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")/../.."
source scripts/mac/auto-update-engine.sh
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/autoupdate-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
# Cache preflight runs before install. Keep it off the Developer SSD so the
# boot-volume device check stays out of these fixtures.
case "$TEST_DIR" in
  /Volumes/devSSD|/Volumes/devSSD/*) echo "TEST_DIR must not be on /Volumes/devSSD" >&2; exit 1 ;;
esac
mkdir -p "$TEST_DIR/engine-cache"
ENGINE_CACHE_CONFIGURED="$TEST_DIR/engine-cache"
STATE="$TEST_DIR/last-installed-run"
STATUS="$TEST_DIR/pipeline-status.json"
ATTEMPTS="$TEST_DIR/update-attempts"
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
saved_install_run=$(declare -f install_run)
saved_begin_attempt=$(declare -f begin_attempt)
saved_notify=$(declare -f notify)
saved_stage=$(declare -f stage)
eval "$(printf '%s\n' "$saved_stage" | sed '1s/^stage /real_stage /')"
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
# A persistent failed/interrupted run is held across updater processes.
printf '107\n' > "$STATE"
mkdir -p "$ATTEMPTS/108"
SUCCESS=108
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 60 ]]
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 60 ]]
# A separate newer successful run is not suppressed by the hold.
SUCCESS=109
watch_iteration; expect 'install 109'
# Failed lookup and malformed state must never install.
SUCCESS=106; LIST_ERROR=1
watch_iteration; expect ''
LIST_ERROR=0; printf 'invalid\n' > "$STATE"
watch_iteration; expect ''
# A missing cache must not install or claim. The real install_run preflight,
# not a watch_iteration copy, is what skips begin_attempt.
eval "$saved_install_run"
printf '1\n' > "$STATE"
RUNNING=''; SUCCESS=2; WATCH_RESULT=0
ENGINE_CACHE_CONFIGURED="$TEST_DIR/missing-engine-cache"
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 60 ]]
[[ ! -e "$ATTEMPTS/2" ]]
mkdir -p "$TEST_DIR/engine-cache"
ENGINE_CACHE_CONFIGURED="$TEST_DIR/engine-cache"
# A non-75 claim error is logged by install_run and notified once per run.
: > "$TEST_DIR/notify-log"
: > "$TEST_DIR/stage-log"
notify() { printf '%s\n' "$1" >> "$TEST_DIR/notify-log"; }
stage() { printf '%s\n' "$*" >> "$TEST_DIR/stage-log"; real_stage "$@"; }
begin_attempt() { return 1; }
printf '1\n' > "$STATE"
SUCCESS=110
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 60 ]]
[[ ! -e "$ATTEMPTS/110" ]]
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 60 ]]
[[ "$(grep -c . "$TEST_DIR/notify-log")" == 1 ]]
[[ "$(grep -c . "$TEST_DIR/stage-log")" == 1 ]]
grep -q '클레임 실패' "$TEST_DIR/notify-log"
eval "$saved_begin_attempt"
eval "$saved_notify"
eval "$saved_stage"
install_run() { printf 'install %s\n' "$1" >> "$EVENTS"; printf '%s\n' "$1" > "$STATE"; }
printf 'auto-update watch regression passed\n'

# Real install_run through watch_iteration. The gh stub fails `gh run view`,
# which is the first command after a successful claim. A subshell keeps the
# updater's set -e exit from aborting this script.
eval "$saved_install_run"
printf '100\n' > "$STATE"
RUNNING=''; SUCCESS=201; WATCH_RESULT=0; LIST_ERROR=0
ENGINE_CACHE_CONFIGURED="$TEST_DIR/engine-cache"
: > "$TEST_DIR/s1-launch.log"
: > "$TEST_DIR/s1-git.log"
notify() { :; }
launchctl() { printf '%s\n' "$*" >> "$TEST_DIR/s1-launch.log"; return 1; }
git() { printf '%s\n' "$*" >> "$TEST_DIR/s1-git.log"; return 1; }
rc=0
set +e
(watch_iteration)
rc=$?
set -e
[[ "$rc" != 0 ]]
[[ -f "$ATTEMPTS/201/state.json" ]]
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$ATTEMPTS/201/state.json")" == failed ]]
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["phase"])' "$ATTEMPTS/201/state.json")" == download ]]
[[ "$(cat "$STATE")" == "100" ]]
if grep -E -q 'kickstart|bootout' "$TEST_DIR/s1-launch.log"; then
  echo 'restart_login_agent ran after a failed install' >&2
  exit 1
fi
if [[ -s "$TEST_DIR/s1-git.log" ]]; then
  echo 'git ran after the post-claim failure' >&2
  exit 1
fi
unset -f launchctl git
eval "$saved_notify"
install_run() { printf 'install %s\n' "$1" >> "$EVENTS"; printf '%s\n' "$1" > "$STATE"; }
printf 'auto-update install failure leaves the marker unchanged\n'

rc=0
begin_attempt 9001 || rc=$?
[[ "$rc" == 0 ]]
[[ -f "$ATTEMPTS/9001/state.json" ]]
rc=0
begin_attempt 9001 || rc=$?
[[ "$rc" == 75 ]]
rc=0
begin_attempt 'not-a-run' || rc=$?
[[ "$rc" != 0 && "$rc" != 75 ]]
[[ ! -e "$ATTEMPTS/not-a-run" ]]

rc=0
ENGINE_CACHE_CONFIGURED="$TEST_DIR/missing-cache-root"
engine_cache_root >/dev/null || rc=$?
[[ "$rc" == 1 ]]
printf 'not-a-directory\n' > "$TEST_DIR/cache-file"
ENGINE_CACHE_CONFIGURED="$TEST_DIR/cache-file"
rc=0
engine_cache_root >/dev/null || rc=$?
[[ "$rc" == 1 ]]
mkdir -p "$TEST_DIR/real-cache"
ln -s "$TEST_DIR/real-cache" "$TEST_DIR/cache-link"
ENGINE_CACHE_CONFIGURED="$TEST_DIR/cache-link"
cache_out=$(engine_cache_root)
[[ "$cache_out" == "$(realpath "$TEST_DIR/real-cache")" ]]
[[ "$cache_out" != "$TEST_DIR/cache-link" ]]

LOGIN_PLIST="$TEST_DIR/login.plist"
printf 'plist\n' > "$LOGIN_PLIST"
uid=$(id -u)
target="gui/${uid}/${LOGIN_LABEL}"
plist="$LOGIN_PLIST"
LAUNCH_LOG="$TEST_DIR/launch.log"
STUB_MODE=full
STUB_PRINTS=0
STUB_LOADED=1
STUB_BOOTSTRAPS=0
STUB_BOOTSTRAP_FAILS=2
STUB_PLUTIL_RC=0
launchctl() {
  printf 'launchctl' >> "$LAUNCH_LOG"
  local arg
  for arg in "$@"; do
    printf ' %s' "$arg" >> "$LAUNCH_LOG"
  done
  printf '\n' >> "$LAUNCH_LOG"
  case "$1" in
    print)
      STUB_PRINTS=$((STUB_PRINTS + 1))
      case "$STUB_MODE" in
        early)
          if (( STUB_PRINTS >= 2 )); then
            printf 'state = running\npid = 200\n'
          else
            printf 'state = running\n'
          fi
          ;;
        poll)
          if (( STUB_PRINTS >= 3 )); then
            printf 'state = running\npid = 201\n'
          else
            printf 'state = running\n'
          fi
          ;;
        pidonly)
          printf 'pid = 7\n'
          ;;
        old)
          # The pid stays in force until kickstart without -k.
          if grep -qx "launchctl kickstart ${target}" "$LAUNCH_LOG"; then
            printf 'state = running\npid = 99\n'
          else
            printf 'state = running\npid = 42\n'
          fi
          ;;
        *)
          if (( STUB_LOADED == 0 )); then
            return 1
          fi
          printf 'state = running\n'
          ;;
      esac
      ;;
    bootout)
      if [[ "$STUB_MODE" != "stuck" ]]; then
        STUB_LOADED=0
      fi
      ;;
    bootstrap)
      STUB_BOOTSTRAPS=$((STUB_BOOTSTRAPS + 1))
      if (( STUB_BOOTSTRAPS <= STUB_BOOTSTRAP_FAILS )); then
        return 1
      fi
      STUB_LOADED=1
      ;;
    kickstart|enable) ;;
    *) return 1 ;;
  esac
}
sleep() { printf 'sleep %s\n' "$1" >> "$LAUNCH_LOG"; }
plutil() {
  printf 'plutil' >> "$LAUNCH_LOG"
  local arg
  for arg in "$@"; do
    printf ' %s' "$arg" >> "$LAUNCH_LOG"
  done
  printf '\n' >> "$LAUNCH_LOG"
  return "$STUB_PLUTIL_RC"
}
reset_launch() {
  : > "$LAUNCH_LOG"
  STUB_PRINTS=0
  STUB_LOADED=1
  STUB_BOOTSTRAPS=0
  STUB_BOOTSTRAP_FAILS=2
  STUB_PLUTIL_RC=0
  STUB_MODE="$1"
}
run_restart() {
  RESTART_RC=0
  restart_login_agent >"$TEST_DIR/restart-out" 2>"$TEST_DIR/restart-err" || RESTART_RC=$?
}
expect_log() {
  if ! diff -u "$1" "$LAUNCH_LOG"; then
    exit 1
  fi
}
log_count() {
  grep -c "$1" "$LAUNCH_LOG" || true
}
kickstart_until_second() {
  local i=0
  printf 'launchctl print %s\n' "$target"
  printf 'launchctl kickstart -k %s\n' "$target"
  printf 'sleep 3\n'
  printf 'launchctl print %s\n' "$target"
  while (( i < 10 )); do
    printf 'sleep 1\nlaunchctl print %s\n' "$target"
    i=$((i + 1))
  done
  printf 'launchctl kickstart %s\n' "$target"
}
kickstart_prefix() {
  local i=0
  kickstart_until_second
  while (( i < 5 )); do
    printf 'sleep 1\nlaunchctl print %s\n' "$target"
    i=$((i + 1))
  done
}
assert_recovery() {
  grep -q 'kickstart -k, a second kickstart, and bootout/enable/bootstrap' "$TEST_DIR/restart-err"
  grep -F -q "RECOVERY: launchctl enable gui/${uid}/${LOGIN_LABEL} && launchctl bootstrap gui/${uid} '${plist}'" "$TEST_DIR/restart-err"
}

bootstrap_cycle() {
  printf 'launchctl bootout %s\n' "$target"
  printf 'launchctl print %s\n' "$target"
  printf 'launchctl enable %s\n' "$target"
  printf 'launchctl bootstrap gui/%s %s\n' "$uid" "$plist"
}

reset_launch full
run_restart
[[ "$RESTART_RC" == 1 ]]
assert_recovery
{
  kickstart_prefix
  printf 'plutil -lint -s %s\n' "$plist"
  bootstrap_cycle
  bootstrap_cycle
} > "$TEST_DIR/expected-log"
expect_log "$TEST_DIR/expected-log"
[[ "$(log_count 'launchctl bootout ')" == 2 ]]
[[ "$(log_count 'launchctl bootstrap ')" == 2 ]]
[[ "$(log_count 'launchctl kickstart ')" == 2 ]]

reset_launch early
run_restart
[[ "$RESTART_RC" == 0 ]]
printf 'launchctl print %s\nlaunchctl kickstart -k %s\nsleep 3\nlaunchctl print %s\n' "$target" "$target" "$target" > "$TEST_DIR/expected-log"
expect_log "$TEST_DIR/expected-log"
if grep -q RECOVERY "$TEST_DIR/restart-err"; then
  echo 'early success logged a recovery command' >&2
  exit 1
fi
[[ "$(log_count 'launchctl bootout ')" == 0 ]]
[[ "$(log_count 'launchctl kickstart ')" == 1 ]]

reset_launch old
run_restart
[[ "$RESTART_RC" == 0 ]]
{
  kickstart_until_second
  printf 'sleep 1\nlaunchctl print %s\n' "$target"
} > "$TEST_DIR/expected-log"
expect_log "$TEST_DIR/expected-log"
[[ "$(log_count 'launchctl bootout ')" == 0 ]]
[[ "$(log_count 'launchctl kickstart -k ')" == 1 ]]
[[ "$(log_count 'launchctl kickstart ')" == 2 ]]

reset_launch poll
run_restart
[[ "$RESTART_RC" == 0 ]]
printf 'launchctl print %s\nlaunchctl kickstart -k %s\nsleep 3\nlaunchctl print %s\nsleep 1\nlaunchctl print %s\n' "$target" "$target" "$target" "$target" > "$TEST_DIR/expected-log"
expect_log "$TEST_DIR/expected-log"
[[ "$(log_count 'launchctl kickstart ')" == 1 ]]
[[ "$(log_count 'launchctl bootout ')" == 0 ]]

reset_launch missing
LOGIN_PLIST="$TEST_DIR/missing-login.plist"
plist="$LOGIN_PLIST"
run_restart
[[ "$RESTART_RC" == 1 ]]
assert_recovery
kickstart_prefix > "$TEST_DIR/expected-log"
expect_log "$TEST_DIR/expected-log"
[[ "$(log_count 'launchctl bootout ')" == 0 ]]
[[ "$(log_count 'plutil ')" == 0 ]]
grep -q 'plist missing or invalid' "$TEST_DIR/restart-err"

reset_launch invalid
LOGIN_PLIST="$TEST_DIR/login.plist"
plist="$LOGIN_PLIST"
STUB_PLUTIL_RC=1
run_restart
[[ "$RESTART_RC" == 1 ]]
assert_recovery
{
  kickstart_prefix
  printf 'plutil -lint -s %s\n' "$plist"
} > "$TEST_DIR/expected-log"
expect_log "$TEST_DIR/expected-log"
[[ "$(log_count 'launchctl bootout ')" == 0 ]]
grep -q 'plist missing or invalid' "$TEST_DIR/restart-err"

# Bootstrap can succeed and still leave no replacement pid. One kickstart, then stop.
reset_launch full
STUB_BOOTSTRAP_FAILS=1
LOGIN_PLIST="$TEST_DIR/login.plist"
plist="$LOGIN_PLIST"
run_restart
[[ "$RESTART_RC" == 1 ]]
assert_recovery
{
  kickstart_prefix
  printf 'plutil -lint -s %s\n' "$plist"
  bootstrap_cycle
  bootstrap_cycle
  i=0
  while (( i < 5 )); do
    printf 'sleep 1\nlaunchctl print %s\n' "$target"
    i=$((i + 1))
  done
  printf 'launchctl kickstart %s\n' "$target"
  i=0
  while (( i < 5 )); do
    printf 'sleep 1\nlaunchctl print %s\n' "$target"
    i=$((i + 1))
  done
} > "$TEST_DIR/expected-log"
expect_log "$TEST_DIR/expected-log"
[[ "$(log_count 'launchctl kickstart ')" == 3 ]]
[[ "$(log_count 'launchctl bootstrap ')" == 2 ]]

# A job that stays loaded is not bootstrapped.
reset_launch stuck
run_restart
[[ "$RESTART_RC" == 1 ]]
assert_recovery
[[ "$(log_count 'launchctl bootout ')" == 1 ]]
[[ "$(log_count 'launchctl bootstrap ')" == 0 ]]
[[ "$(log_count 'launchctl enable ')" == 0 ]]
[[ "$(log_count '^sleep 0.1$')" == 100 ]]
grep -q 'still loaded after 10s' "$TEST_DIR/restart-err"

# A pid-only print is still a pid. The same pid is not a replacement.
reset_launch pidonly
read_login_agent_pid "$target"
[[ "$LOGIN_AGENT_PID" == "7" ]]
if login_agent_is_replacement "$target" 7; then
  echo 'same pid counted as replacement' >&2
  exit 1
fi
login_agent_is_replacement "$target" ""
login_agent_is_replacement "$target" 8

inode_file="$TEST_DIR/login-bin"
printf 'binary\n' > "$inode_file"
# Not named inode: login_process_maps_binary locals that name, and a stub
# would see the unset local under set -u.
expected_inode=$(stat -f %i "$inode_file")
lsof() {
  case "$LSOF_MODE" in
    match) printf 'p1\nftxt\ni%s\nn%s\n' "$expected_inode" "$inode_file" ;;
    wrong-path) printf 'ftxt\ni%s\nn%s\n' "$expected_inode" "$inode_file.other" ;;
    missing-inode) printf 'ftxt\ni0\nn%s\n' "$inode_file" ;;
    split) printf 'ftxt\ni%s\nftxt\nn%s\n' "$expected_inode" "$inode_file" ;;
    *) return 1 ;;
  esac
}
LSOF_MODE=match
login_process_maps_binary 42 "$inode_file"
LSOF_MODE=wrong-path
if login_process_maps_binary 42 "$inode_file"; then
  echo 'wrong path mapped as the installed binary' >&2
  exit 1
fi
LSOF_MODE=missing-inode
if login_process_maps_binary 42 "$inode_file"; then
  echo 'missing inode mapped as the installed binary' >&2
  exit 1
fi
LSOF_MODE=split
if login_process_maps_binary 42 "$inode_file"; then
  echo 'inode and path in different blocks mapped as a match' >&2
  exit 1
fi
unset -f lsof

printf 'auto-update login and cache checks passed\n'
python3 scripts/mac/test-reader-refresh.py
