#!/usr/bin/env python3
"""Republish a retained flow-engine artifact when engine inputs match.

fetch-engine downloads the artifact named flow-engine-darwin-arm64 and
requires flow-engine, flow-engine.sha256, and release.json beside each
other. This script never renames that artifact or writes into it. The input
hash is recorded in a separate artifact, flow-engine-input-<hash>, so a later
run can find a match without downloading the engine.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ENGINE_ARTIFACT = 'flow-engine-darwin-arm64'
MARKER_PREFIX = 'flow-engine-input-'
ENGINE_TARGET = 'aarch64-apple-darwin'
ENGINE_PROFILE = 'flow-release'


def marker_name(digest: str) -> str:
    if len(digest) != 64 or any(char not in '0123456789abcdef' for char in digest):
        raise ValueError('Engine input hash must be 64 lowercase hex characters')
    return MARKER_PREFIX + digest


def select_source_run(runs, digest, artifacts_for, current_run_id=''):
    """Return the newest successful run whose retained artifacts carry digest."""
    marker = marker_name(digest)
    current = str(current_run_id or '')
    ordered = sorted(runs, key=lambda run: (run.get('createdAt') or '', str(run.get('databaseId') or '')), reverse=True)
    for run in ordered:
        if run.get('conclusion') not in (None, 'success'):
            continue
        run_id = str(run.get('databaseId') or '')
        if not run_id or run_id == current:
            continue
        artifacts = artifacts_for(run_id)
        marker_expired = artifacts.get(marker)
        engine_expired = artifacts.get(ENGINE_ARTIFACT)
        if marker_expired is False and engine_expired is False:
            return run
    return None


def parse_engine_checksum(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if len(lines) != 1:
        raise ValueError('Engine checksum file must contain one SHA-256 line')
    token = lines[0].split()[0]
    if len(token) != 64 or any(char not in '0123456789abcdefABCDEF' for char in token):
        raise ValueError('Engine checksum file does not contain a SHA-256 digest')
    return token.lower()


def locate_payload(download: Path) -> Path:
    candidates = []
    for checksum in download.rglob('flow-engine.sha256'):
        parent = checksum.parent
        if (parent / 'flow-engine').is_file() and (parent / 'release.json').is_file() and (parent / 'Lagrangian.app').is_dir():
            candidates.append(parent)
    if len(candidates) != 1:
        raise ValueError('The downloaded artifact must contain one flow-engine, flow-engine.sha256, release.json, and Lagrangian.app')
    return candidates[0]


def verify_payload(payload: Path) -> str:
    """Check the fetch-engine contract without modifying the payload."""
    engine = payload / 'flow-engine'
    digest = hashlib.sha256(engine.read_bytes()).hexdigest()
    expected = parse_engine_checksum((payload / 'flow-engine.sha256').read_text())
    if digest != expected:
        raise ValueError('Engine SHA-256 mismatch: expected ' + expected + ', got ' + digest)
    manifest = json.loads((payload / 'release.json').read_text())
    recorded = str(manifest.get('engineInputSHA256', '')).lower()
    if recorded != digest:
        raise ValueError('Engine SHA-256 does not match release.json engineInputSHA256')
    build = manifest.get('engineBuild')
    if not isinstance(build, dict) or build.get('target') != ENGINE_TARGET or build.get('profile') != ENGINE_PROFILE:
        raise ValueError('release.json must record an aarch64-apple-darwin flow-release engineBuild')
    return digest


def _gh(args, repo_cwd=None):
    completed = subprocess.run(['gh', *args], check=False, text=True, capture_output=True, cwd=repo_cwd)
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or '').strip()
        raise RuntimeError('gh ' + ' '.join(args[:3]) + ' failed: ' + detail)
    return completed.stdout


def list_successful_runs(repo, branch, limit):
    raw = _gh([
        'run', 'list', '--repo', repo, '--workflow', 'flow-engine.yml',
        '--branch', branch, '--status', 'success', '--limit', str(limit),
        '--json', 'databaseId,createdAt,url,conclusion,event,headSha',
    ])
    runs = json.loads(raw or '[]')
    if not isinstance(runs, list):
        raise RuntimeError('gh run list did not return a list for ' + branch)
    return runs


def list_artifacts(repo, run_id):
    raw = _gh([
        'api', '--paginate', f'/repos/{repo}/actions/runs/{run_id}/artifacts',
        '--jq', '.artifacts[] | [.name, (.expired | tostring)] | @tsv',
    ])
    found = {}
    for line in raw.splitlines():
        name, _, expired = line.partition('\t')
        if name:
            found[name] = expired.strip() == 'true'
    return found


def set_output(key, value):
    print(f'{key}={value}')
    path = os.environ.get('GITHUB_OUTPUT')
    if path:
        with open(path, 'a', encoding='utf-8') as handle:
            handle.write(f'{key}={value}\n')


def summarize(text):
    path = os.environ.get('GITHUB_STEP_SUMMARY')
    if path:
        with open(path, 'a', encoding='utf-8') as handle:
            handle.write(text)
            if not text.endswith('\n'):
                handle.write('\n')


def download_payload(repo, run_id, dest: Path):
    if dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    _gh(['run', 'download', str(run_id), '--repo', repo, '--name', ENGINE_ARTIFACT, '--dir', str(dest)])
    payload = locate_payload(dest)
    # gh run download extracts artifact contents into --dir. The upload path
    # has to be that same directory so the republished layout stays flat.
    if payload.resolve() != dest.resolve():
        raise ValueError('Downloaded artifact layout is nested; refusing to rearrange it')
    return verify_payload(payload)


def main(argv=None):
    del argv
    digest = os.environ.get('ENGINE_INPUT_HASH', '').strip().lower()
    repo = os.environ.get('GITHUB_REPOSITORY', '').strip()
    if not repo:
        raise SystemExit('GITHUB_REPOSITORY is required')
    branches = [item for item in os.environ.get('ENGINE_REUSE_BRANCHES', 'main').split() if item]
    if not branches:
        raise SystemExit('ENGINE_REUSE_BRANCHES must name at least one branch')
    limit = int(os.environ.get('ENGINE_REUSE_LIMIT', '30'))
    if limit < 1:
        raise SystemExit('ENGINE_REUSE_LIMIT must be positive')
    current = os.environ.get('GITHUB_RUN_ID', '')
    seen = set()
    runs = []
    for branch in branches:
        if branch in seen:
            continue
        seen.add(branch)
        runs.extend(list_successful_runs(repo, branch, limit))
    match = select_source_run(runs, digest, lambda run_id: list_artifacts(repo, run_id), current)
    if match is None:
        set_output('hit', 'false')
        set_output('source_run', '')
        set_output('source_url', '')
        summarize('Engine input cache: miss. No retained `flow-engine-darwin-arm64` artifact carries this input hash.\n')
        print('engine-artifact-cache: miss', file=sys.stderr)
        return
    run_id = str(match['databaseId'])
    dest = Path(os.environ.get('ENGINE_ARTIFACT_DIR', 'dist/flow-engine-darwin-arm64'))
    engine_sha = download_payload(repo, run_id, dest)
    set_output('hit', 'true')
    set_output('source_run', run_id)
    set_output('source_url', match.get('url') or '')
    summarize(
        'Engine input cache: hit. Republishing run '
        + run_id + ' unchanged. Engine SHA-256 `' + engine_sha + '`.\n'
    )
    print('engine-artifact-cache: hit run ' + run_id + ' sha256 ' + engine_sha, file=sys.stderr)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, json.JSONDecodeError, OSError) as error:
        print('engine-artifact-cache: ' + str(error), file=sys.stderr)
        raise SystemExit(1) from error
