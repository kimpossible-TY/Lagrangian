#!/bin/bash
# Refresh all managed Readers as one transaction, then verify every document.
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
SRC="$HOME/Developer/lagrangian"
DATA="$HOME/Library/Application Support/Lagrangian/reader"
ENGINE="$HOME/Applications/Lagrangian.app/Contents/MacOS/flow-engine"
cd "${READER_SRC:-$SRC}"
echo "$(date) reader source: $PWD"
python3 - "$DATA" "$ENGINE" <<'PY'
import json, os, shutil, subprocess, sys, tempfile, time, urllib.parse, urllib.request
from pathlib import Path

data, engine = Path(sys.argv[1]), sys.argv[2]
launcher, config = data / 'bin/flow-reader', data / 'config.json'
def run(*args):
    return subprocess.check_output([str(a) for a in args], text=True)
def profiles():
    return json.loads(run(launcher, '--profiles'))['profiles']
def jobs(items):
    result = {}
    for profile in items:
        result.setdefault(profile['label'], profile)
    return list(result.values())
def control(action, items, best_effort=False):
    errors = []
    for profile in jobs(items):
        command = 'stop-shared' if action == 'stop' and profile.get('shared') else action
        try:
            run(launcher, '--control', command, profile['id'])
        except Exception as error:
            errors.append(error)
    if errors and not best_effort:
        raise errors[0]
def verify(items):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    attempts = max(1, int(os.environ.get('READER_VERIFY_ATTEMPTS', '20')))
    interval = max(0.0, float(os.environ.get('READER_VERIFY_INTERVAL', '3')))
    for profile in items:
        path = '/d/' + urllib.parse.quote(profile['id'], safe='') + '/' if profile.get('shared') else '/'
        url = 'http://127.0.0.1:%s%s' % (profile['port'], path)
        for attempt in range(attempts):
            try:
                with opener.open(url, timeout=3) as response:
                    if response.status == 200:
                        break
            except Exception:
                pass
            if attempt == attempts - 1:
                raise RuntimeError('Reader not answering: ' + profile['id'])
            time.sleep(interval)

original = profiles()
services = json.loads(config.read_text())['services']
# Both files are replaced by install.py; config.previous.json only holds the last install.
with tempfile.TemporaryDirectory(prefix='reader-refresh-') as temporary:
    backup = Path(temporary)
    shutil.copy2(config, backup / 'config.json')
    shutil.copy2(launcher, backup / 'flow-reader')
    try:
        control('stop', original)
        for service in services:
            args = [sys.executable, 'tools/flow-reader/install.py', '--profile', service['parentID'],
                    '--port', str(service['port']), '--engine', engine, '--no-prune']
            if service.get('publicURL'):
                args += ['--public-url', service['publicURL']]
            if service.get('development'):
                args += ['--development']
            subprocess.run(args, check=True)
        updated = profiles()
        control('start', updated)
        verify(updated)
    except BaseException:
        # Stop any newly started jobs before restoring the old launcher and config.
        try:
            control('stop', profiles(), best_effort=True)
        except Exception as error:
            print('Could not enumerate updated Readers: %s' % error, file=sys.stderr)
        shutil.copy2(backup / 'config.json', config)
        shutil.copy2(backup / 'flow-reader', launcher)
        try:
            control('start', original)
        except Exception as error:
            print('Could not restart previous Readers: %s' % error, file=sys.stderr)
        raise
prune = subprocess.run(
    [sys.executable, 'tools/flow-reader/install.py', '--prune-only', '--data', str(data)],
    check=False,
)
if prune.returncode != 0:
    print('Warning: Reader release pruning exited with status %s' % prune.returncode, file=sys.stderr)
print('All Readers refreshed and verified')
PY
