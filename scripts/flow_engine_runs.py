#!/usr/bin/env python3
"""Select a successful flow-engine.yml run.

``scripts/flow-app.py`` fetch-engine, ``scripts/reuse-engine-artifact.py``, and
``scripts/fetch-reader-bundle.py`` share this lookup. Pass one run id to
fetch-engine and fetch-reader-bundle so the engine and the reader come from
that same run.
"""

import json
import subprocess

WORKFLOW_FILE = 'flow-engine.yml'
WORKFLOW_NAME = 'Flow engine'
LIST_FIELDS = 'databaseId,headSha,conclusion,createdAt,url,headBranch,event,workflowName'
VIEW_FIELDS = 'databaseId,headSha,conclusion,status,url,headBranch,workflowName'


def parse_sha(value):
    """Return a 40-character lowercase commit SHA or raise ValueError."""
    text = str(value or '').strip().lower()
    if len(text) != 40 or any(char not in '0123456789abcdef' for char in text):
        raise ValueError('headSha must be 40 lowercase hex characters')
    return text


def invoke_gh(args, runner=None):
    """Run ``gh`` with ``args`` (no leading gh). ``runner`` receives those args."""
    if runner is not None:
        return runner(args)
    completed = subprocess.run(['gh', *args], check=False, text=True, capture_output=True)
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or '').strip()
        raise RuntimeError('gh ' + ' '.join(args[:4]) + ' failed: ' + detail)
    return completed.stdout


def json_gh(args, runner=None):
    raw = invoke_gh(args, runner)
    try:
        return json.loads(raw or 'null')
    except json.JSONDecodeError as error:
        raise ValueError('gh ' + ' '.join(args[:3]) + ' did not return JSON') from error


def _valid_branch(branch):
    if not branch or str(branch).startswith('-') or any(char.isspace() for char in str(branch)):
        raise ValueError('Branch name is not valid')
    return branch


def list_successful_runs(repo, branch=None, commit=None, limit=30, runner=None):
    """Newest successful flow-engine.yml runs, optionally for one branch or commit."""
    if branch is not None:
        branch = _valid_branch(branch)
    args = [
        'run', 'list', '--repo', repo, '--workflow', WORKFLOW_FILE,
        '--status', 'success', '--limit', str(limit),
        '--json', LIST_FIELDS,
    ]
    if branch:
        args.extend(['--branch', branch])
    if commit:
        args.extend(['--commit', commit])
    runs = json_gh(args, runner)
    if not isinstance(runs, list):
        raise ValueError('gh run list did not return a list')
    return sorted(
        runs,
        key=lambda run: (run.get('createdAt') or '', str(run.get('databaseId') or '')),
        reverse=True,
    )


def view_run(repo, run_id, runner=None):
    """Return one successful Flow engine run, or raise ValueError."""
    record = json_gh([
        'run', 'view', str(run_id), '--repo', repo, '--json', VIEW_FIELDS,
    ], runner)
    if not isinstance(record, dict) or not record.get('databaseId'):
        raise ValueError('gh run view did not return run ' + str(run_id))
    if record.get('workflowName') != WORKFLOW_NAME:
        raise ValueError('Run ' + str(run_id) + ' is not a flow-engine.yml run')
    if record.get('conclusion') != 'success':
        raise ValueError('Run ' + str(run_id) + ' is not a successful flow-engine.yml run')
    record['headSha'] = parse_sha(record.get('headSha'))
    return record


def select_run(repo, run_id=None, head_sha=None, branch=None, runner=None, limit=30):
    """Resolve ``--run-id``, ``--head-sha``, and ``--branch`` to one successful run.

    A numeric ``run_id`` is viewed and checked. With ``branch`` and no run id,
    the newest successful run on that branch is used, and ``head_sha`` further
    requires that commit. ``head_sha`` alone searches by commit. Passing
    ``branch`` together with ``run_id`` requires the run's branch to match.
    """
    if run_id is not None and not str(run_id).isdigit():
        raise ValueError('Run id must be the numeric GitHub Actions run id')
    if head_sha is not None:
        head_sha = parse_sha(head_sha)
    if branch is not None:
        branch = _valid_branch(branch)
    if run_id is None and branch is not None:
        runs = list_successful_runs(repo, branch=branch, limit=limit, runner=runner)
        if head_sha is not None:
            runs = [item for item in runs if parse_sha(item.get('headSha')) == head_sha]
        if not runs:
            target = 'branch ' + branch + (' at ' + head_sha if head_sha else '')
            raise ValueError('No successful ' + WORKFLOW_FILE + ' run for ' + target)
        run_id = str(runs[0]['databaseId'])
    elif run_id is None and head_sha is not None:
        runs = list_successful_runs(repo, commit=head_sha, limit=limit, runner=runner)
        runs = [item for item in runs if parse_sha(item.get('headSha')) == head_sha]
        if not runs:
            raise ValueError('No successful ' + WORKFLOW_FILE + ' run for commit ' + head_sha)
        run_id = str(runs[0]['databaseId'])
    if run_id is None:
        raise ValueError('Pass --run-id, --head-sha, or --branch')
    record = view_run(repo, run_id, runner)
    if head_sha is not None and record['headSha'] != head_sha:
        raise ValueError(
            'headSha mismatch: run ' + str(run_id) + ' is ' + record['headSha'] + ', expected ' + head_sha
        )
    if branch is not None and record.get('headBranch') != branch:
        raise ValueError('Run ' + str(run_id) + ' is on ' + str(record.get('headBranch')) + ', not ' + branch)
    return record
