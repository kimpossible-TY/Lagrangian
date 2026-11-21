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

# Canonical engine cache on the Developer SSD. The default
# ~/Library/Caches/Lagrangian/engines path is a symlink, and fetch-engine
# rejects non-canonical destinations. Do not fall back to that path.
ENGINE_CACHE_CONFIGURED="/Volumes/devSSD/Developer/.cache/lagrangian-engines"

engine_cache_root() {
  local configured="$ENGINE_CACHE_CONFIGURED"
  if [[ ! -e "$configured" ]]; then
    echo "$(date) engine cache is unavailable: $configured is missing (is the SSD mounted?)" >&2
    return 1
  fi
  local resolved
  if ! resolved=$(realpath "$configured"); then
    echo "$(date) engine cache is unavailable: could not resolve $configured (is the SSD mounted?)" >&2
    return 1
  fi
  if [[ -L "$resolved" || ! -d "$resolved" ]]; then
    echo "$(date) engine cache is unavailable: $resolved is not a real directory (is the SSD mounted?)" >&2
    return 1
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
verify_services() { python3 - "$1" "$APP" "$sha" "$WT/active-previews.json" <<'PY'
import hashlib,json,os,re,subprocess,sys,urllib.parse,urllib.request
from pathlib import Path
mode,app,sha,snapshot=sys.argv[1:]
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
login=run('launchctl','print',f'gui/{os.getuid()}/io.github.kimpossible-ty.tinymist-flow.login')
match=re.search(r'^\s*pid = ([0-9]+)$',login,re.M)
require(match is not None,'Background login job has no PID; inspect launchd/AMFI logs')
command=run('ps','-ww','-p',match.group(1),'-o','command=')
require(command==str(native)+' --background','Unexpected background login process')
expected=json.loads(Path(snapshot).read_text())
for profile in expected['previews']:
    state=data(native,'--status',profile['id'])
    require(state['running'] and state.get('managedByApp'),'Preview is not running: '+profile['id'])
    mapped=run('lsof','-a','-p',str(state['pid']),'-d','txt','-FnDi')
    inode=str(engine.stat().st_ino)
    require(any(('i'+inode) in block.splitlines() and ('n'+str(engine)) in block.splitlines()
                for block in mapped.split('ftxt\n')[1:]),
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
}
# launchctl print has a pid when the login agent is actually running.
login_agent_has_pid() {
  local target="$1" out
  if ! out=$(launchctl print "$target" 2>/dev/null); then
    return 1
  fi
  grep -Eq '^[[:space:]]*pid = [0-9]+$' <<<"$out"
}
# Wait up to `seconds` seconds, checking once a second. Not a spawn retry.
# The last action is a pid check, so a late spawn is not treated as failure.
poll_login_agent_pid() {
  local target="$1" seconds="$2" waited=0
  while (( waited < seconds )); do
    sleep 1
    waited=$((waited + 1))
    if login_agent_has_pid "$target"; then
      return 0
    fi
  done
  return 1
}
# kickstart -k can lose a newly signed login agent to a Launch Constraint
# Violation. Cap: wait, one kickstart without -k, then one bootout/enable/bootstrap.
# verify_services still checks the PID and command line afterward.
restart_login_agent() {
  local uid target plist
  uid=$(id -u)
  target="gui/${uid}/io.github.kimpossible-ty.tinymist-flow.login"
  plist="${HOME}/Library/LaunchAgents/io.github.kimpossible-ty.tinymist-flow.login.plist"

  launchctl kickstart -k "$target" || echo "$(date) login-agent kickstart -k returned non-zero; waiting for spawn"
  sleep 3
  if login_agent_has_pid "$target"; then
    return 0
  fi
  echo "$(date) login-agent has no pid after kickstart -k; polling up to 10s"
  if poll_login_agent_pid "$target" 10; then
    return 0
  fi

  echo "$(date) login-agent still has no pid; kickstart without -k"
  launchctl kickstart "$target" || echo "$(date) login-agent kickstart without -k returned non-zero"
  if poll_login_agent_pid "$target" 5; then
    return 0
  fi

  echo "$(date) login-agent still has no pid; bootout/enable/bootstrap"
  launchctl bootout "$target" || echo "$(date) login-agent bootout returned non-zero (not loaded or already unloaded); continuing"
  launchctl enable "$target" || echo "$(date) login-agent enable returned non-zero"
  launchctl bootstrap "gui/${uid}" "$plist" || echo "$(date) login-agent bootstrap returned non-zero"
  if poll_login_agent_pid "$target" 5; then
    return 0
  fi

  echo "$(date) login-agent spawn failed after kickstart -k, a second kickstart, and bootout/enable/bootstrap (inspect launchd/AMFI logs)" >&2
  return 1
}
install_run() (
local id="$1"
# This conditional wraps only the claim helper, not install_run: ERR/errexit
# must remain enabled for every actual installation/verification command.
if ! begin_attempt "$id"; then
  echo "$(date) run $id not claimed; no automatic reinstall (inspect update-attempts)"
  return 0
fi
CUR=detect
trap 'failed "$?" "$LINENO"' ERR
echo "$(date) new run $id"
notify "새 빌드 $id 발견, 설치 시작"
stage detect running
stage detect done
CUR=download
trap 'failed "$?" "$LINENO"' ERR
sha=$(gh run view "$id" -R "$REPO" --json headSha -q .headSha)
WT=$(mktemp -d /tmp/lagrangian-run-XXXXXX)
git -C "$SRC" fetch -q origin
git -C "$SRC" worktree add -q --detach "$WT" "$sha"
cleanup_wt() { git -C "$SRC" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"; git -C "$SRC" worktree prune; }
trap cleanup_wt EXIT
cd "$WT"
stage download running
cache=$(engine_cache_root)
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
record_attempt readiness verified "App, engine and Reader readiness passed"
# Commit only after engine, background app and Reader readiness all passed.
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
  local running success installed
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
    install_run "$success"
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
