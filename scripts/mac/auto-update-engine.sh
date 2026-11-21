#!/bin/bash
# Auto-install newest successful flow-engine build from main (any event).
set -Eeuo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
REPO=kimpossible-TY/Lagrangian
SRC="$HOME/Developer/lagrangian"
STATE="$HOME/Library/Application Support/Lagrangian/last-installed-run"
STATUS="$HOME/Library/Application Support/Lagrangian/pipeline-status.json"
APP="$HOME/Applications/Lagrangian.app"
ATTEMPTS="$HOME/Library/Application Support/Lagrangian/update-attempts"

# fetch-engine rejects a symlink destination. Override with LAGRANGIAN_ENGINE_CACHE.
# The default is on the Developer SSD. Do not fall back to ~/Library/Caches,
# which is a symlink.
ENGINE_CACHE_CONFIGURED="${LAGRANGIAN_ENGINE_CACHE:-/Volumes/devSSD/Developer/.cache/lagrangian-engines}"
LOGIN_LABEL=io.github.kimpossible-ty.tinymist-flow.login
LOGIN_PLIST="$HOME/Library/LaunchAgents/${LOGIN_LABEL}.plist"

engine_cache_root() {
  local configured="$ENGINE_CACHE_CONFIGURED" resolved dev rootdev check_device=0
  if [[ ! -e "$configured" && ! -L "$configured" ]]; then
    echo "$(date) engine cache is unavailable: $configured is missing" >&2
    return 1
  fi
  if ! resolved=$(realpath "$configured"); then
    echo "$(date) engine cache is unavailable: could not resolve $configured" >&2
    return 1
  fi
  if [[ ! -d "$resolved" ]]; then
    echo "$(date) engine cache is unavailable: $resolved is not a real directory" >&2
    return 1
  fi
  # Only the Developer SSD path must be a different device from /. A custom
  # cache outside /Volumes/devSSD is accepted as a real directory.
  case "$configured" in
    /Volumes/devSSD|/Volumes/devSSD/*) check_device=1 ;;
  esac
  case "$resolved" in
    /Volumes/devSSD|/Volumes/devSSD/*) check_device=1 ;;
  esac
  if (( check_device == 1 )); then
    dev=$(stat -f %d "$resolved")
    rootdev=$(stat -f %d /)
    if [[ "$dev" == "$rootdev" ]]; then
      echo "$(date) engine cache is unavailable: $resolved is on the boot volume (is the SSD mounted?)" >&2
      return 1
    fi
  fi
  printf '%s\n' "$resolved"
}

stage() { python3 - "$STATUS" "$1" "$2" "${id:-}" "${3:-}" <<'PY'
import json,sys,time,os
p,st,state,run,msg=sys.argv[1:6]
try: d=json.load(open(p))
except Exception: d={}
if st=="detect" and state=="running": d={"project":"lagrangian","run":run,"startedAt":time.strftime("%Y-%m-%dT%H:%M:%S%z"),"stages":{}}
d.setdefault("stages",{})[st]={"state":state,"at":time.strftime("%Y-%m-%dT%H:%M:%S%z"),"message":msg}
d["run"]=run or d.get("run"); d["current"]=st; d["state"]=state; d["updatedAt"]=time.strftime("%Y-%m-%dT%H:%M:%S%z")
tmp=p+".tmp"; json.dump(d,open(tmp,"w"),ensure_ascii=False,indent=2); os.replace(tmp,p)
PY
}
# Claim at install start, after the engine-cache preflight and before download.
# A persistent, atomic claim prevents launchd relaunches (or interruption) from
# reinstalling the same run. Retry requires explicit operator action; a newer
# successful run gets an independent claim. Never infer completion from a claim.
begin_attempt() { python3 - "$ATTEMPTS" "$1" <<'PYCODE'
import json,os,sys,time
from pathlib import Path
root,run=Path(sys.argv[1]),sys.argv[2]
if not run.isdigit(): raise ValueError('Invalid run ID')
root.mkdir(mode=0o700,parents=True,exist_ok=True)
path=root/run
try: path.mkdir(mode=0o700)
except FileExistsError: sys.exit(75)
record=path/'state.json'
with record.open('x') as stream:
    json.dump({'run':run,'phase':'claimed','state':'in_progress',
               'updatedAt':time.strftime('%Y-%m-%dT%H:%M:%S%z')},stream)
    stream.flush(); os.fsync(stream.fileno())
PYCODE
}
record_attempt() { python3 - "$ATTEMPTS" "$id" "$1" "$2" "${3:-}" <<'PYCODE'
import json,os,sys,tempfile,time
from pathlib import Path
root,run,phase,state,message=sys.argv[1:]
if not run.isdigit(): raise ValueError('Invalid run ID')
path=Path(root)/run
if path.is_symlink() or not path.is_dir(): raise RuntimeError('Missing attempt claim')
try: previous=json.loads((path/'state.json').read_text())
except (OSError,ValueError): previous={}
package_verified=previous.get('packageVerified',False) or (phase=='package' and state=='verified')
package_at=previous.get('packageVerifiedAt')
if phase=='package' and state=='verified': package_at=time.strftime('%Y-%m-%dT%H:%M:%S%z')
fd,tmp=tempfile.mkstemp(prefix='.state-',dir=path)
try:
    with os.fdopen(fd,'w') as stream:
        json.dump({'run':run,'phase':phase,'state':state,'message':message,
                   'packageVerified':package_verified,'packageVerifiedAt':package_at,
                   'updatedAt':time.strftime('%Y-%m-%dT%H:%M:%S%z')},stream)
        stream.flush(); os.fsync(stream.fileno())
    os.replace(tmp,path/'state.json')
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PYCODE
}
notify() { osascript -e "display notification \"$1\" with title \"Lagrangian\"" >/dev/null 2>&1 || true; }
failed() {
  local code="$1" line="$2"
  trap - ERR
  record_attempt "$CUR" failed "exit $code at updater line $line; automatic retry blocked" || true
  stage "$CUR" failed "exit $code at updater line $line" || true
  echo "$(date) install of run $id FAILED at $CUR (exit $code, line $line)"
  notify "빌드 $id 설치 실패 (로그 확인)"
  exit "$code"
}
# One lsof txt block must list both this file's inode and its path.
# A missing inode, a different path, inode and path in different ftxt blocks,
# or an lsof failure or timeout is not a match. Inode is Path.stat().st_ino.
# verify_services uses this for the login pid and each preview pid.
# process_maps_binary is a thin wrapper so tests can call the same helper.
PROCESS_MAPS_PY=$(cat <<'PY'
def process_maps_binary(pid, binary):
    # Keep the caller's path spelling. Path() would collapse '//' and miss lsof.
    text=str(binary)
    if not str(pid) or not text: return False
    try: inode='i'+str(Path(text).stat().st_ino)
    except OSError: return False
    try:
        mapped=subprocess.check_output(['lsof','-a','-p',str(pid),'-d','txt','-FnDi'],text=True,timeout=15)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return False
    name='n'+text
    return any(inode in block.splitlines() and name in block.splitlines() for block in mapped.split('ftxt\n')[1:])
PY
)
process_maps_binary() {
  python3 - "$1" "$2" <<PY
${PROCESS_MAPS_PY}
import subprocess, sys
from pathlib import Path
sys.exit(0 if process_maps_binary(sys.argv[1], sys.argv[2]) else 1)
PY
}
verify_services() {
  local script
  script=$(cat <<'PY'
import hashlib,json,os,re,subprocess,sys,urllib.parse,urllib.request
from pathlib import Path
mode,app,sha,snapshot,label=sys.argv[1:]
app=Path(app); native=app/'Contents/MacOS/Lagrangian'
def run(*args):
    return subprocess.check_output([str(a) for a in args],text=True,timeout=15).strip()
def data(*args): return json.loads(run(*args))
def require(ok,message):
    if not ok: raise RuntimeError(message)
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs): return None
def http(port,path="/"):
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    with opener.open(f'http://127.0.0.1:{int(port)}{path}',timeout=3) as response:
        require(response.status==200,f'HTTP readiness failed on port {port}')
if mode=='snapshot':
    active=[]
    for profile in data(native,'--profiles')['profiles']:
        state=data(native,'--status',profile['id'])
        if state['running'] and state.get('managedByApp'):
            active.append({'id':profile['id'],'port':profile['port']})
    launcher=Path.home()/'Library/Application Support/Lagrangian/reader/bin/flow-reader'
    readers=[{'id':p['id'],'port':p['port'],'shared':bool(p.get('shared'))}
             for p in data(launcher,'--profiles')['profiles']]
    Path(snapshot).write_text(json.dumps({'previews':active,'readers':readers}))
    sys.exit(0)
manifest=json.loads((app/'Contents/Resources/release.json').read_text())
require(manifest['sourceRevision']==sha,'Installed app revision does not match selected run')
engine=app/'Contents/MacOS/flow-engine'
require(hashlib.sha256(engine.read_bytes()).hexdigest()==manifest['engineSHA256'],
        'Installed engine checksum mismatch')
# A matching process anywhere is insufficient: check the registered login PID.
login=run('launchctl','print',f'gui/{os.getuid()}/{label}')
match=re.search(r'^\s*pid = ([0-9]+)$',login,re.M)
require(match is not None,'Background login job has no PID; inspect launchd/AMFI logs')
login_pid=match.group(1)
command=run('ps','-ww','-p',login_pid,'-o','command=')
require(command==str(native)+' --background','Unexpected background login process')
# Always map the login pid onto the installed binary. The same helper checks
# each preview: one ftxt block must contain both the inode and the path.
require(process_maps_binary(login_pid, native),'Background login process does not map the installed app binary')
expected=json.loads(Path(snapshot).read_text())
for profile in expected['previews']:
    state=data(native,'--status',profile['id'])
    require(state['running'] and state.get('managedByApp'),'Preview is not running: '+profile['id'])
    require(process_maps_binary(state['pid'], engine),
            'Preview does not map the installed engine: '+profile['id'])
    http(profile['port'])
if mode=='complete':
    launcher=Path.home()/'Library/Application Support/Lagrangian/reader/bin/flow-reader'
    profiles=data(launcher,'--profiles')['profiles']
    require(sorted((p['id'],p['port'],bool(p.get('shared'))) for p in profiles)==
            sorted((p['id'],p['port'],p['shared']) for p in expected['readers']),
            'Reader service set changed during update')
    for profile in profiles:
        plan=data(launcher,'--launch-plan',profile['id'])
        serve=Path(plan['arguments'][1])
        release=serve.parents[2]
        # The shared host argv omits document options. Ask its installed manager
        # for the same per-document arguments used by the shared server.
        sys.path.insert(0,str(serve.parent))
        from flow_reader.services.manager import ReaderManager
        manager=ReaderManager(launcher.parents[1])
        resolved=manager.profile(profile['id'])
        require(resolved is not None,'Reader profile missing: '+profile['id'])
        arguments=manager.document_arguments(resolved)
        require('--engine' in arguments and arguments[arguments.index('--engine')+1]==str(engine),
                'Reader engine path mismatch: '+profile['id'])
        release_manifest=json.loads((release/'release.json').read_text())
        require(release_manifest['revision']==sha,'Reader revision mismatch: '+profile['id'])
        state=data(launcher,'--status',profile['id'])
        require(state['running'] and state.get('managedByApp'),'Reader is not running: '+profile['id'])
        command=run('ps','-ww','-p',str(state['pid']),'-o','command=')
        require(str(serve) in command,'Reader is running a previous release: '+profile['id'])
        path='/d/'+urllib.parse.quote(profile['id'],safe='')+'/' if profile.get('shared') else '/'
        http(profile['port'],path)
print('Verified '+('app, engine and Reader' if mode=='complete' else 'app and engine'))
PY
)
  python3 - "$1" "$APP" "$sha" "$WT/active-previews.json" "$LOGIN_LABEL" <<PY
${PROCESS_MAPS_PY}
${script}
PY
}
# Read the login job pid into LOGIN_AGENT_PID (empty when print fails or has no pid).
# Output goes to a file: a failing print inside $(...) would inherit the install
# ERR trap (set -E) and record a false failure.
read_login_agent_pid() {
  local target="$1" rc=0 line out
  LOGIN_AGENT_PID=""
  out=$(mktemp "${TMPDIR:-/tmp}/login-agent-print.XXXXXX")
  launchctl print "$target" >"$out" 2>/dev/null || rc=$?
  if (( rc == 0 )); then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^[[:space:]]*pid\ =\ ([0-9]+)$ ]]; then
        LOGIN_AGENT_PID="${BASH_REMATCH[1]}"
      fi
    done <"$out"
  fi
  rm -f "$out"
}
# Success when the job has a pid and it is not the pre-kickstart pid.
# An empty old pid means there was no process to replace.
login_agent_is_replacement() {
  local target="$1" old_pid="$2"
  read_login_agent_pid "$target"
  [[ -n "$LOGIN_AGENT_PID" ]] || return 1
  [[ -z "$old_pid" || "$LOGIN_AGENT_PID" != "$old_pid" ]]
}
# Wait up to `seconds` seconds, checking once a second. Not a spawn retry.
# The last action is a replacement-pid check, so a late spawn is not a failure.
poll_login_agent_pid() {
  local target="$1" seconds="$2" old_pid="$3" waited=0
  while (( waited < seconds )); do
    sleep 1
    waited=$((waited + 1))
    if login_agent_is_replacement "$target" "$old_pid"; then
      return 0
    fi
  done
  return 1
}
# bootout can return while launchd still reports the job. Print failure or empty
# output means unloaded. 100 checks at 0.1s is the 10s budget.
wait_login_agent_unloaded() {
  local target="$1" waited=0 rc out
  out=$(mktemp "${TMPDIR:-/tmp}/login-agent-print.XXXXXX")
  while (( waited < 100 )); do
    rc=0
    launchctl print "$target" >"$out" 2>/dev/null || rc=$?
    if (( rc != 0 )) || ! grep -q '[^[:space:]]' "$out"; then
      rm -f "$out"
      return 0
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  rm -f "$out"
  echo "$(date) login-agent still loaded after 10s; not bootstrapping $target" >&2
  return 1
}
login_restart_failed() {
  local uid="$1" plist="$2"
  echo "$(date) login-agent spawn failed after kickstart -k, a second kickstart, and bootout/enable/bootstrap (inspect launchd/AMFI logs)" >&2
  echo "$(date) RECOVERY: launchctl enable gui/${uid}/${LOGIN_LABEL} && launchctl bootstrap gui/${uid} '${plist}'" >&2
  return 1
}
# bootout, wait until unloaded, enable, bootstrap. One full-cycle retry.
# A still-loaded job is not bootstrapped. The final bootstrap failure is returned.
bootstrap_login_agent() {
  local target="$1" plist="$2" uid="$3" attempt
  if [[ ! -f "$plist" ]]; then
    echo "$(date) login-agent plist missing or invalid: $plist" >&2
    return 1
  fi
  if ! plutil -lint -s "$plist"; then
    echo "$(date) login-agent plist missing or invalid: $plist" >&2
    return 1
  fi
  attempt=0
  while (( attempt < 2 )); do
    attempt=$((attempt + 1))
    launchctl bootout "$target" || true
    if ! wait_login_agent_unloaded "$target"; then
      return 1
    fi
    if ! launchctl enable "$target"; then
      echo "$(date) login-agent enable returned non-zero (attempt ${attempt}/2)" >&2
      if (( attempt < 2 )); then
        continue
      fi
      return 1
    fi
    if launchctl bootstrap "gui/${uid}" "$plist"; then
      return 0
    fi
    echo "$(date) login-agent bootstrap returned non-zero (attempt ${attempt}/2)" >&2
  done
  return 1
}
# kickstart -k can lose a newly signed login agent to a Launch Constraint
# Violation. The previous pid must not satisfy the check. Worst case is about
# 50s: initial sleep 3, poll 10, poll 5, an unload wait of up to 10s on each
# of two bootstrap cycles, poll 5 after bootstrap, then one kickstart without
# -k and poll 5. verify_services still checks the PID, command line, and
# binary inode.
restart_login_agent() {
  local uid target plist old_pid
  uid=$(id -u)
  target="gui/${uid}/${LOGIN_LABEL}"
  plist="$LOGIN_PLIST"
  read_login_agent_pid "$target"
  old_pid="$LOGIN_AGENT_PID"

  launchctl kickstart -k "$target" || echo "$(date) login-agent kickstart -k returned non-zero; waiting for spawn"
  sleep 3
  if login_agent_is_replacement "$target" "$old_pid"; then
    return 0
  fi
  echo "$(date) login-agent has no replacement pid after kickstart -k; polling up to 10s"
  if poll_login_agent_pid "$target" 10 "$old_pid"; then
    return 0
  fi

  echo "$(date) login-agent still has no replacement pid; kickstart without -k"
  launchctl kickstart "$target" || echo "$(date) login-agent kickstart without -k returned non-zero"
  if poll_login_agent_pid "$target" 5 "$old_pid"; then
    return 0
  fi

  echo "$(date) login-agent still has no replacement pid; bootout/enable/bootstrap"
  if ! bootstrap_login_agent "$target" "$plist" "$uid"; then
    login_restart_failed "$uid" "$plist" || true
    return 1
  fi
  if poll_login_agent_pid "$target" 5 "$old_pid"; then
    return 0
  fi

  echo "$(date) login-agent still has no replacement pid after bootstrap; kickstart without -k"
  launchctl kickstart "$target" || echo "$(date) login-agent kickstart without -k returned non-zero"
  if poll_login_agent_pid "$target" 5 "$old_pid"; then
    return 0
  fi

  login_restart_failed "$uid" "$plist" || true
  return 1
}
install_run() (
# The parent clears errexit only while it captures this status. Turn it back
# on so a failed command still runs the ERR trap instead of continuing.
set -Eeuo pipefail
local id="$1" cache claim_rc=0
# Preflight outside the ERR trap. A failing command substitution under set -E
# runs failed() twice; reuse this path for fetch-engine --dest.
if ! cache=$(engine_cache_root); then
  echo "$(date) engine cache is unavailable; skipping the claim for run $id and retrying later"
  return 0
fi
# This conditional wraps only the claim helper, not install_run: ERR/errexit
# must remain enabled for every actual installation/verification command.
# The claim is taken here, after the cache preflight and before download.
begin_attempt "$id" || claim_rc=$?
if [[ "$claim_rc" == 75 ]]; then
  echo "$(date) run $id already attempted; automatic reinstall blocked (inspect update-attempts)"
  return 0
fi
if [[ "$claim_rc" != 0 ]]; then
  # The parent dedupes the notification. This subshell cannot remember LAST_*.
  echo "$(date) run $id claim failed with exit $claim_rc (permissions or invalid id); no claim was recorded"
  return 76
fi
CUR=detect
trap 'failed "$?" "$LINENO"' ERR
echo "$(date) new run $id"
notify "새 빌드 $id 발견, 설치 시작"
stage detect running
stage detect done
CUR=download
sha=$(gh run view "$id" -R "$REPO" --json headSha -q .headSha)
WT=$(mktemp -d /tmp/lagrangian-run-XXXXXX)
git -C "$SRC" fetch -q origin
git -C "$SRC" worktree add -q --detach "$WT" "$sha"
cleanup_wt() { git -C "$SRC" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"; git -C "$SRC" worktree prune; }
trap cleanup_wt EXIT
cd "$WT"
stage download running
engine=$(python3 scripts/flow-app.py fetch-engine --run-id "$id" --dest "$cache/$id")
reader=$(python3 scripts/fetch-reader-bundle.py --run-id "$id")
echo "$(date) run $id sha $sha reader bundle $reader"
stage download done; CUR=package; stage package running
app=$(python3 scripts/flow-app.py build --engine "$engine" | tail -1)
verify_services snapshot
python3 scripts/flow-app.py install "$app"
python3 scripts/flow-app.py verify "$APP" >/dev/null
# Package replacement is durable but does NOT mean activation succeeded.
record_attempt package verified "App files verified; activation and Reader readiness still pending"
stage package done; CUR=restart; stage restart running
restart_login_agent
verify_services engine
echo "$(date) restarted background app"
stage restart done; CUR=reader; stage reader running
READER_SRC="$reader" "$HOME/Library/Application Support/Lagrangian/refresh-reader-engine.sh"
verify_services complete
stage reader done; CUR=done
record_attempt reader verified "App, engine and Reader readiness passed"
# Commit only after engine, background app and Reader checks all passed.
# Keep the existing marker on every failure; replace a complete file atomically.
python3 - "$STATE" "$id" <<'PY'
import os,sys,tempfile
from pathlib import Path
path=Path(sys.argv[1]); temporary=None
try:
    fd,temporary=tempfile.mkstemp(prefix=path.name+'.',dir=path.parent)
    with os.fdopen(fd,'w') as stream:
        stream.write(sys.argv[2]+'\n'); stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary,path)
finally:
    if temporary and os.path.exists(temporary): os.unlink(temporary)
PY
record_attempt complete done "Successful installed-run marker committed"
echo "$(date) installed run $id"
stage done done
notify "빌드 $id 설치 완료"

)

# One iteration returns immediately after a successful watch so selection is
# refreshed before installation. Errors and idle iterations use the normal delay.
watch_iteration() {
  local running success installed rc id
  NEXT_DELAY=60
  if ! running=$(gh run list -R "$REPO" -w flow-engine.yml -b main -s in_progress -L 1 --json databaseId -q '.[] | .databaseId'); then
    echo "$(date) could not look up in-progress runs; retrying"
    return
  fi
  if ! success=$(gh run list -R "$REPO" -w flow-engine.yml -b main -s success -L 1 --json databaseId -q '.[] | .databaseId'); then
    echo "$(date) could not look up successful runs; retrying"
    return
  fi
  installed=$(cat "$STATE" 2>/dev/null || true)
  # Reject malformed responses rather than risking an unintended install.
  if [[ ( -n "$running" && ! "$running" =~ ^[0-9]+$ ) || ( -n "$success" && ! "$success" =~ ^[0-9]+$ ) || ( -n "$installed" && ! "$installed" =~ ^[0-9]+$ ) ]]; then
    echo "$(date) invalid run ID or installed marker; retrying"
    return
  fi
  running=${running:-0}; success=${success:-0}; installed=${installed:-0}
  if (( running > installed && running > success )); then
    # The list endpoint may briefly lag behind a completed watch.
    if [[ "${LAST_WATCHED:-}" == "$running" ]]; then
      NEXT_DELAY=5
      return
    fi
    echo "$(date) watching run $running"
    if gh run watch "$running" -R "$REPO" --exit-status; then
      echo "$(date) run $running succeeded; checking for newer runs"
      LAST_WATCHED="$running"
      NEXT_DELAY=0
    else
      echo "$(date) watch for run $running failed or run did not succeed; retrying detection"
    fi
  elif (( success > installed )); then
    LAST_WATCHED=""
    if [[ -e "$ATTEMPTS/$success" || -L "$ATTEMPTS/$success" ]]; then
      # Keep the failure and its last phase visible. Do not reset pipeline status,
      # show another notification, or retry package replacement automatically.
      if [[ "${LAST_BLOCKED:-}" != "$success" ]]; then
        echo "$(date) run $success already attempted; automatic reinstall blocked"
        LAST_BLOCKED="$success"
      fi
      return
    fi
    # 76 is a claim error. Any other non-zero status is fatal: failed() already
    # ran inside the install subshell, and that status must still stop the updater.
    # install_run's own preflight is the cache check before begin_attempt.
    # `cmd || rc=$?` would suppress the subshell ERR trap and could continue
    # after a failed install, including writing last-installed-run.
    rc=0
    set +e
    install_run "$success"
    rc=$?
    set -e
    if [[ "$rc" == 76 ]]; then
      if [[ "${LAST_CLAIM_ERROR:-}" != "$success" ]]; then
        echo "$(date) run $success claim failed (permissions or invalid id); no claim was recorded"
        id="$success"
        stage detect failed "claim failed (permissions or invalid id); no claim was recorded" || true
        notify "빌드 $success 클레임 실패" || true
        LAST_CLAIM_ERROR="$success"
      fi
      NEXT_DELAY=60
      return 0
    fi
    if [[ "$rc" != 0 ]]; then
      return "$rc"
    fi
    # 60s when install_run returns 0, including an immediate claim hold
    # (exit 75) and a cache preflight miss. Catch-up of a still-newer
    # successful run waits out this delay.
    # A successful gh run watch above leaves NEXT_DELAY at 0.
    NEXT_DELAY=60
  fi
}

main() {
  while true; do
    watch_iteration
    if (( NEXT_DELAY > 0 )); then sleep "$NEXT_DELAY"; fi
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main; fi
