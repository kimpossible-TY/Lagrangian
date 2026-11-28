#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/autoupdate-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home" LAGRANGIAN_ENGINE_CACHE="$TEST_DIR/engine-cache"
mkdir -p "$HOME"
source scripts/mac/auto-update-engine.sh
SRC="$TEST_DIR/source"; APP="$TEST_DIR/app"; LOGIN_PLIST="$TEST_DIR/login.plist"
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
RUNNING=''; QUEUED=''; SUCCESS=100; WATCH_RESULT=0; LIST_ERROR=0
gh() {
  if [[ "$1 $2" == 'run list' ]]; then
    (( LIST_ERROR == 0 )) || return 1
    [[ ! ( "${FAIL_STATUS:-}" == queued && " $* " == *' -s queued '* ) ]] || return 1
    case " $* " in
      *' -s in_progress '*) printf '%s\n' "$RUNNING" ;;
      *' -s queued '*) printf '%s\n' "$QUEUED" ;;
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
# Select the newest active run, including queued runs, and fail closed.
QUEUED=104; RUNNING=102; SUCCESS=101
watch_iteration; expect 'watch 104'; [[ "$NEXT_DELAY" == 0 ]]
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 5 ]]
FAIL_STATUS=queued
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 60 ]]
FAIL_STATUS=''
QUEUED=bad
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 60 ]]
QUEUED=''; LAST_WATCHED=''
RUNNING=102; SUCCESS=101
watch_iteration; expect 'watch 102'; [[ "$NEXT_DELAY" == 0 ]]
watch_iteration; expect ''; [[ "$NEXT_DELAY" == 5 ]]
# A newer run arriving during watch supersedes the successful watched run.
RUNNING=103; SUCCESS=102
watch_iteration; expect 'watch 103'
RUNNING=''; SUCCESS=103
watch_iteration; expect 'install 103'; [[ "$NEXT_DELAY" == 0 ]]
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
# Return codes distinguish a completed install from holds and superseding.
for code in 0 74 75 76 77; do
  install_run() { return "$code"; }
  SUCCESS=$((300 + code)); LAST_CLAIM_ERROR=''
  watch_iteration; expect ''
  case "$code" in 0|77) [[ "$NEXT_DELAY" == 0 ]] ;; *) [[ "$NEXT_DELAY" == 60 ]] ;; esac
done
printf 'auto-update watch regression passed\n'

# Real install_run through watch_iteration. The gh stub fails `gh run view`,
# which is the first command after a successful claim. A subshell keeps the
# updater's set -e exit from aborting this script. HOME, SRC, APP, and
# LOGIN_PLIST are redirected under TEST_DIR first so a fail-open regression
# cannot reach live services.
eval "$saved_install_run"
printf '100\n' > "$STATE"
RUNNING=''; SUCCESS=201; WATCH_RESULT=0; LIST_ERROR=0
ENGINE_CACHE_CONFIGURED="$TEST_DIR/engine-cache"
: > "$TEST_DIR/s1-launch.log"
: > "$TEST_DIR/s1-git.log"
notify() { :; }
launchctl() { printf '%s\n' "$*" >> "$TEST_DIR/s1-launch.log"; return 1; }
git() { printf '%s\n' "$*" >> "$TEST_DIR/s1-git.log"; return 1; }
saved_home="$HOME"
saved_src="$SRC"
saved_app="$APP"
saved_login_plist="$LOGIN_PLIST"
HOME="$TEST_DIR/home"
mkdir -p \
  "$HOME/Library/Application Support/Lagrangian" \
  "$HOME/Library/LaunchAgents" \
  "$HOME/Applications" \
  "$HOME/Developer/lagrangian"
SRC="$HOME/Developer/lagrangian"
APP="$HOME/Applications/Lagrangian.app"
LOGIN_PLIST="$HOME/Library/LaunchAgents/${LOGIN_LABEL}.plist"
cat > "$HOME/Library/Application Support/Lagrangian/refresh-reader-engine.sh" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$HOME/Library/Application Support/Lagrangian/refresh-reader-engine.sh"
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
HOME="$saved_home"
SRC="$saved_src"
APP="$saved_app"
LOGIN_PLIST="$saved_login_plist"
printf 'auto-update install failure leaves the marker unchanged\n'

# Exercise actual interruptible commands in an isolated fake worktree.
(
  eval "$saved_install_run"
  export FIXTURE="$TEST_DIR/interrupt" LAGRANGIAN_SUPERSEDE_POLL_SECONDS=0.1
  mkdir -p "$FIXTURE" "$FIXTURE/cache" "$FIXTURE/app"
  STATE="$FIXTURE/installed"; STATUS="$FIXTURE/status"; ATTEMPTS="$FIXTURE/attempts"
  HOME="$FIXTURE/home"; APP="$FIXTURE/app"; SRC="$FIXTURE/source"; LOGIN_PLIST="$FIXTURE/login.plist"; ENGINE_CACHE_CONFIGURED="$FIXTURE/cache"
  mkdir -p "$HOME"
  printf '10\n' > "$STATE"; printf 'untouched\n' > "$APP/sentinel"
  printf '20\n' > "$FIXTURE/success"
  cat > "$FIXTURE/flow-app.py" <<'PYCODE'
import os,signal,subprocess,sys,time
from pathlib import Path
root=Path(os.environ['FIXTURE']); command=sys.argv[1]
if command=='fetch-engine':
    if (root/'fail').exists(): sys.exit(int((root/'fail').read_text()))
    child=subprocess.Popen([sys.executable,'-c','import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'], start_new_session=True)
    def on_term(*args):
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        late=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)'], start_new_session=True)
        (root/'late-pid').write_text(str(late.pid))
        (root/'cleanup-exit').write_text('1')
        time.sleep(0.3)
        sys.exit(1)
    signal.signal(signal.SIGTERM, on_term)
    (root/'child-pid').write_text(str(os.getpid()))
    (root/'descendant-pid').write_text(str(child.pid))
    while True: time.sleep(1)
print('/fixture/result')
PYCODE
  gh() {
    case "$1 $2" in
      'run view') printf 'fake-sha\n' ;;
      'run list')
        case " $* " in
          *' -s success '*)
            if [[ -e "$FIXTURE/gh-hang" ]]; then printf 'hang\n' >> "$FIXTURE/polls"; /bin/sleep 30; fi
            if [[ -e "$FIXTURE/gh-error" ]]; then
              rm -f "$FIXTURE/gh-error"; printf 'error\n' >> "$FIXTURE/polls"; return 1
            fi
            printf 'ok\n' >> "$FIXTURE/polls"; cat "$FIXTURE/success" ;;
          *) printf '\n' ;;
        esac ;;
      *) return 1 ;;
    esac
  }
  git() {
    case " $* " in
      *' worktree add '*) mkdir -p "$WT/scripts"; cp "$FIXTURE/flow-app.py" "$WT/scripts/flow-app.py" ;;
      *' worktree remove '*) rm -rf "$WT" ;;
    esac
  }
  notify() { :; }
  # A failed lookup alone must not interrupt a step that later succeeds.
  WT="$FIXTURE"; id=20; CUR=download
  touch "$FIXTURE/gh-error"
  run_interruptible_step 20 "$FIXTURE/step-output" /bin/sleep 0.4
  grep -q '^error$' "$FIXTURE/polls"
  [[ ! -e "$FIXTURE/superseded-run" ]]
  # A stuck lookup must be cancelled when the step completes.
  touch "$FIXTURE/gh-hang"
  start=$SECONDS
  run_interruptible_step 20 "$FIXTURE/step-output" /bin/sleep 0.4
  (( SECONDS - start < 5 ))
  rm "$FIXTURE/gh-hang"
  # A failure while gh is blocked is returned immediately, with no marker.
  : > "$FIXTURE/polls"; touch "$FIXTURE/gh-hang"
  rc=0
  run_interruptible_step 20 "$FIXTURE/step-output" bash -c 'sleep 0.4; exit 9' || rc=$?
  [[ "$rc" == 9 && ! -e "$FIXTURE/superseded-run" ]]
  grep -q '^hang$' "$FIXTURE/polls"
  rm "$FIXTURE/gh-hang"
  printf '20\n' > "$FIXTURE/success"
  : > "$FIXTURE/polls"
  # Polling must survive an API error before detecting the newer run.
  touch "$FIXTURE/gh-error"
  (
    while [[ ! -s "$FIXTURE/descendant-pid" ]] || ! grep -q '^error$' "$FIXTURE/polls" 2>/dev/null; do /bin/sleep 0.05; done
    printf '21\n' > "$FIXTURE/success"
  ) & trigger=$!
  rc=0; set +e; install_run 20; rc=$?; set -e
  wait "$trigger"
  [[ "$rc" == 77 && "$(cat "$STATE")" == 10 && "$(cat "$APP/sentinel")" == untouched ]]
  [[ "$(cat "$FIXTURE/cleanup-exit")" == 1 ]]
  [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$ATTEMPTS/20/state.json")" == superseded ]]
  [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$STATUS")" == superseded ]]
  for pidfile in child-pid descendant-pid late-pid; do
    pid=$(cat "$FIXTURE/$pidfile")
    if kill -0 "$pid" 2>/dev/null && [[ "$(ps -o stat= -p "$pid")" != Z* ]]; then
      echo "surviving process $pid" >&2; exit 1
    fi
  done
  # A superseded result requests immediate selection of the newer success.
  install_run() { printf '%s\n' "$1" >> "$FIXTURE/installed-runs"; [[ "$1" != 20 ]] || return 77; }
  printf '20\n' > "$FIXTURE/success"; rm -rf "$ATTEMPTS/20"
  watch_iteration; [[ "$NEXT_DELAY" == 0 ]]
  printf '21\n' > "$FIXTURE/success"
  watch_iteration; [[ "$NEXT_DELAY" == 0 ]]
  [[ "$(cat "$FIXTURE/installed-runs")" == "$(printf '20\n21')" ]]
  # A real step failure invokes failed(), rather than being treated as stale.
  eval "$saved_install_run"
  printf '9\n' > "$FIXTURE/fail"
  printf '22\n' > "$FIXTURE/success"
  rc=0; set +e; install_run 22; rc=$?; set -e
  [[ "$rc" == 9 && "$(cat "$STATE")" == 10 ]]
  [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$ATTEMPTS/22/state.json")" == failed ]]
  # Actual command failures cannot masquerade as any reserved control result.
  for code in 74 75 76 77; do
    run=$((400 + code)); printf '%s\n' "$code" > "$FIXTURE/fail"
    printf '%s\n' "$run" > "$FIXTURE/success"
    rc=0; set +e; (watch_iteration); rc=$?; set -e
    [[ "$rc" != 0 && "$rc" != 74 && "$rc" != 75 && "$rc" != 76 && "$rc" != 77 ]]
    python3 - "$ATTEMPTS/$run/state.json" "$STATUS" "$code" <<'PYCODE'
import json,sys
attempt,status=map(lambda p: json.load(open(p)),sys.argv[1:3])
assert attempt['state']=='failed' and attempt['phase']=='download'
assert 'exit '+sys.argv[3]+' ' in attempt['message']
assert status['state']=='failed' and status['current']=='download'
PYCODE
  done
)
printf 'auto-update superseding and failure checks passed\n'

rc=0
begin_attempt 9001 || rc=$?
[[ "$rc" == 0 ]]
[[ -f "$ATTEMPTS/9001/state.json" ]]
rc=0
begin_attempt 9001 || rc=$?
[[ "$rc" == 75 ]]
rc=0
begin_attempt 'not-a-run' 2>/dev/null || rc=$?
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
# Python spawns lsof, so a shell function would not be visible. The stub is an
# executable on PATH and reads the case from the environment.
expected_inode=$(python3 -c 'import os,sys;print(os.stat(sys.argv[1]).st_ino)' "$inode_file")
stubbin="$TEST_DIR/bin"
mkdir -p "$stubbin"
cat > "$stubbin/lsof" <<'EOF'
#!/bin/bash
case "$LSOF_MODE" in
  match) printf 'p1\nftxt\ni%s\nn%s\n' "$EXPECTED_INODE" "$INODE_FILE" ;;
  wrong-path) printf 'ftxt\ni%s\nn%s\n' "$EXPECTED_INODE" "$INODE_FILE.other" ;;
  missing-inode) printf 'ftxt\ni0\nn%s\n' "$INODE_FILE" ;;
  split) printf 'ftxt\ni%s\nftxt\nn%s\n' "$EXPECTED_INODE" "$INODE_FILE" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stubbin/lsof"
export EXPECTED_INODE="$expected_inode" INODE_FILE="$inode_file" LSOF_MODE=match
saved_path="$PATH"
PATH="$stubbin:$PATH"
process_maps_binary 42 "$inode_file"
LSOF_MODE=wrong-path
if process_maps_binary 42 "$inode_file"; then
  echo 'wrong path mapped as the installed binary' >&2
  exit 1
fi
LSOF_MODE=missing-inode
if process_maps_binary 42 "$inode_file"; then
  echo 'missing inode mapped as the installed binary' >&2
  exit 1
fi
LSOF_MODE=split
if process_maps_binary 42 "$inode_file"; then
  echo 'inode and path in different blocks mapped as a match' >&2
  exit 1
fi
LSOF_MODE=fail
if process_maps_binary 42 "$inode_file"; then
  echo 'lsof failure mapped as the installed binary' >&2
  exit 1
fi
PATH="$saved_path"

printf 'auto-update login and cache checks passed\n'
python3 scripts/mac/test-reader-refresh.py
