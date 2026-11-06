#!/bin/bash
# Auto-install newest successful flow-engine build from main (any event).
set -Eeuo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
REPO=kimpossible-TY/Lagrangian
SRC="$HOME/Developer/lagrangian"
STATE="$HOME/Library/Application Support/Lagrangian/last-installed-run"
STATUS="$HOME/Library/Application Support/Lagrangian/pipeline-status.json"
APP="$HOME/Applications/Lagrangian.app"
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
notify() { osascript -e "display notification \"$1\" with title \"Lagrangian\"" >/dev/null 2>&1 || true; }
failed() {
  local code="$1" line="$2"
  trap - ERR
  stage "$CUR" failed "exit $code at updater line $line" || true
  echo "$(date) install of run $id FAILED at $CUR (exit $code, line $line)"
  notify "빌드 $id 설치 실패 (로그 확인)"
  exit "$code"
}
verify_services() { python3 - "$1" "$APP" "$sha" "$WT/active-previews.json" <<'PY'
import hashlib,json,os,re,subprocess,sys,urllib.request
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
def http(port):
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    with opener.open(f'http://127.0.0.1:{int(port)}/',timeout=3) as response:
        require(response.status==200,f'HTTP readiness failed on port {port}')
if mode=='snapshot':
    active=[]
    for profile in data(native,'--profiles')['profiles']:
        state=data(native,'--status',profile['id'])
        if state['running'] and state.get('managedByApp'):
            active.append({'id':profile['id'],'port':profile['port']})
    config=Path.home()/'Library/Application Support/Lagrangian/reader/config.json'
    readers=[{'id':p['id'],'port':p['port']} for p in json.loads(config.read_text())['services']]
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
    require(sorted((p['id'],p['port']) for p in profiles)==
            sorted((p['id'],p['port']) for p in expected['readers']),
            'Reader service set changed during update')
    for profile in profiles:
        plan=data(launcher,'--launch-plan',profile['id'])
        arguments=plan['arguments']
        require('--engine' in arguments and arguments[arguments.index('--engine')+1]==str(engine),
                'Reader engine path mismatch: '+profile['id'])
        serve=Path(plan['arguments'][1])
        release=serve.parents[2]
        release_manifest=json.loads((release/'release.json').read_text())
        require(release_manifest['revision']==sha,'Reader revision mismatch: '+profile['id'])
        state=data(launcher,'--status',profile['id'])
        require(state['running'] and state.get('managedByApp'),'Reader is not running: '+profile['id'])
        command=run('ps','-ww','-p',str(state['pid']),'-o','command=')
        require(str(serve) in command,'Reader is running a previous release: '+profile['id'])
        http(profile['port'])
print('Verified '+('app, engine and Reader' if mode=='complete' else 'app and engine'))
PY
}
install_run() (
local id="$1"
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
engine=$(python3 scripts/flow-app.py fetch-engine --run-id "$id")
reader=$(python3 scripts/fetch-reader-bundle.py --run-id "$id")
echo "$(date) run $id sha $sha reader bundle $reader"
stage download done; CUR=package; stage package running
app=$(python3 scripts/flow-app.py build --engine "$engine" | tail -1)
verify_services snapshot
python3 scripts/flow-app.py install "$app"
python3 scripts/flow-app.py verify "$APP" >/dev/null
stage package done; CUR=restart; stage restart running
launchctl kickstart -k "gui/$(id -u)/io.github.kimpossible-ty.tinymist-flow.login"
sleep 3
verify_services engine
echo "$(date) restarted background app"
stage restart done; CUR=reader; stage reader running
READER_SRC="$reader" "$HOME/Library/Application Support/Lagrangian/refresh-reader-engine.sh"
verify_services complete
stage reader done; CUR=done
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
    install_run "$success"
    NEXT_DELAY=0
  fi
}

main() {
  while true; do
    watch_iteration
    if (( NEXT_DELAY > 0 )); then sleep "$NEXT_DELAY"; fi
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main; fi
