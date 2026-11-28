# Mac engine updater

The launchd job runs the updater continuously. It checks for `flow-engine.yml`
runs on `main` every 60 seconds while idle, watches the newest queued or
in-progress run with `gh run watch`, and rechecks before installing the newest
successful run. A successful watch refreshes selection immediately. If the
run lists still lag behind that watch, selection waits 5 seconds up to 6 times
before considering an older uninstalled success. These are list catch-up
retries, not repeated `gh run watch` calls. GitHub or watch errors are logged
and retried on the idle interval. After a claim is taken, an
installation failure makes `watch_iteration` return that failure status, and
the updater's `set -e` ends the process so launchd KeepAlive can restart it.
The last-installed-run marker stays unchanged, and that run is not retried
automatically.

A newer successful run supersedes an installation before app replacement,
including during engine fetch, reader-bundle fetch or app build. Each running
step checks for a newer success at the interval set by
`LAGRANGIAN_SUPERSEDE_POLL_SECONDS` (default 30 seconds). The supervisor stops
the step's process group and discovered descendants; the run ends as
superseded (exit 77), and selection runs again without delay.

During a supervised installation step, SIGTERM, SIGINT or SIGHUP to the main
updater process is forwarded as SIGTERM through `install_run` and the step
supervisor. The supervisor terminates the step process group and discovered
descendants and stops any in-flight newer-run query process group. The updater
waits for cleanup and exits 143, 130 or 129 respectively. Cleanup sends SIGTERM
during an approximately one-second grace period, then SIGKILL, and reaps the direct child.
Further signals during cleanup preserve the first signal's exit code. Outside
an installation, during `gh run watch` or the idle sleep, the signal ends the
updater directly because no installation step is running.
When signaled outside a supervised step, the body's foreground children (git,
app install/verify, launchctl) are not forwarded the signal and may survive;
the body's EXIT trap still cleans up the worktree.

The claim for a run is
`$HOME/Library/Application Support/Lagrangian/update-attempts/<run>/state.json`.
It is recorded at install start, after the engine-cache preflight and before
download. Inspect that file, then retry the same run by removing the claim
directory:

```sh
rm -r "$HOME/Library/Application Support/Lagrangian/update-attempts/<run>"
```

That removal leaves the last-installed-run marker unchanged. GitHub “Re-run”
reuses the same run database id, so an existing claim still holds; delete that
claim directory to retry the same run. Claims are not pruned automatically.
An operator may delete the oldest completed claim directories (phase
`complete`, state `done`) to reclaim space, and must leave a failed or held
claim in place unless the intent is a manual retry. A superseded claim may
also be deleted: that run was not installed and needs no manual retry because
the newer success is selected automatically. Deleting its claim makes the same
run eligible again only if it is selected again.

For a superseded run, `state.json` has `state: "superseded"`, `phase` naming
the interrupted stage, and a `message` naming the newer successful run.
`pipeline-status.json` records top-level `state: "superseded"`, `current`
naming that stage, and `stages[<stage>].state: "superseded"`. The successful
last-installed-run marker stays unchanged until an installation completes.

The engine cache must be a real directory. The fetch destination cannot be a
symlink. The default is `/Volumes/devSSD/Developer/.cache/lagrangian-engines`.
Override it with `LAGRANGIAN_ENGINE_CACHE`. A launchd override belongs in the
job's EnvironmentVariables; see `dev.lagrangian.engine-autoupdate.plist.example`.
When that volume is missing, the updater skips the claim and retries later.

The login-agent restart cap is about 50 seconds worst case, and a failure logs
a dated RECOVERY command (`launchctl enable gui/<uid>/<label> && launchctl bootstrap gui/<uid> '<plist>'`).

`install_run` results control the next `watch_iteration` delay:

| Return code | Meaning | Watcher action |
| --- | --- | --- |
| 0 | Installation completed and successful marker committed | Select again immediately; no delay |
| 74 | Engine-cache preflight failed; claim skipped | Wait 60 seconds |
| 75 | Run already claimed; automatic reinstall blocked | Wait 60 seconds |
| 76 | Claim failed (for example, permissions or invalid run ID); no claim recorded | Report once per run in this process, then wait 60 seconds |
| 77 | Superseded by a newer successful run | Select again immediately; no delay |
| Any other status | Installation or verification failure | Return that status; `set -e` ends the updater and launchd KeepAlive restarts it |

The watcher also checks for existing claims before calling `install_run`;
that hold uses the same 60-second idle interval. Catch-up after a successful
install or superseded run refreshes selection immediately.

The installer still uses the checkout at `~/Developer/lagrangian` and requires
its existing GitHub authentication and the installed reader refresh script.

Run the isolated regression from the repository root:

```sh
bash scripts/mac/test-auto-update-engine.sh
```

## Release retention

App rollback backups (`$HOME/Library/Application Support/Lagrangian/releases/`,
with the active app at `$HOME/Applications/Lagrangian.app`) and installed Reader
releases (`$HOME/Library/Application Support/Lagrangian/reader/releases/`) must
stay on the internal SSD (never symlink `releases/` or `reader/releases/` to
`/Volumes/devSSD`). App updates prune `releases/` after replacement, health
checks (unless `--defer-health-check` is passed), and metadata writes succeed,
keeping only the single immediate rollback bundle referenced by
`previous-release.json` (and removing older backups and `*-failed`
directories). Reader pruning keeps the active release (`bin/flow-reader` and
configured `browserCompiler`), the immediate rollback release
(`previous-release.json` / `config.previous.json`), and any release still
referenced by a running process; standalone `tools/flow-reader/install.py` runs
prune after install unless `--no-prune` is passed.

During a Reader refresh, `refresh-reader-engine.sh` passes `--no-prune` to
`tools/flow-reader/install.py` for each service and runs
`tools/flow-reader/install.py --prune-only --data "$DATA"` once after all
Readers start and pass HTTP verification. Even before the installed
`refresh-reader-engine.sh` is updated, `install.py` preserves the prior rollback
release (`previous-release.json`) across consecutive same-release installs.

## Apply after merge

These are operator steps for the Mac, **after the PR merges**. Do not run them
while an installation is in progress. Check the updater log and pipeline status
first. Use a checkout containing the merged files; check the example plist's
absolute paths for the target account before copying it. Copying
`scripts/mac/refresh-reader-engine.sh` into `$support/` activates deferred
post-verify pruning for multi-service refreshes.

```sh
support="$HOME/Library/Application Support/Lagrangian"
plist="$HOME/Library/LaunchAgents/dev.lagrangian.engine-autoupdate.plist"
backup="$HOME/Library/Application Support/Lagrangian/autoupdate-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
cp -p "$support/auto-update-engine.sh" "$support/refresh-reader-engine.sh" "$backup/"
cp -p "$plist" "$backup/"
launchctl bootout "gui/$(id -u)" "$plist"
cp scripts/mac/auto-update-engine.sh scripts/mac/refresh-reader-engine.sh "$support/"
chmod 755 "$support/auto-update-engine.sh" "$support/refresh-reader-engine.sh"
cp scripts/mac/dev.lagrangian.engine-autoupdate.plist.example "$plist"
plutil -lint "$plist"
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl print "gui/$(id -u)/dev.lagrangian.engine-autoupdate"
```

Inspect `~/Library/Logs/lagrangian-engine-autoupdate.log` and
`pipeline-status.json` after a successful main run. `bootout` stops the job;
`bootstrap` loads it and `RunAtLoad` starts the loop. Keep the backup path for
rollback. To restore, first stop the job with the same `bootout` command, copy
both scripts and the plist from that backup to their original paths, then `bootstrap` the
restored plist. The marker and application data are retained during rollback.
