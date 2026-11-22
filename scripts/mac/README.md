# Mac engine updater

The launchd job runs the updater continuously. It checks for `flow-engine.yml`
runs on `main` every 60 seconds while idle, watches a newer in-progress run
with `gh run watch`, and rechecks before installing the newest successful run.
GitHub or watch errors are logged and retried. Installation failures still exit
so launchd can restart the process. A failed or interrupted run is not
automatically retried. The last-installed-run marker stays unchanged until a
later run fully succeeds.

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

The engine cache must be a real directory. The fetch destination cannot be a
symlink. The default is `/Volumes/devSSD/Developer/.cache/lagrangian-engines`.
Override it with `LAGRANGIAN_ENGINE_CACHE`. A launchd override belongs in the
job's EnvironmentVariables; see `dev.lagrangian.engine-autoupdate.plist.example`.
When that volume is missing, the updater skips the claim and retries later.

The login-agent restart cap is about 50 seconds worst case, and a failure logs
a dated RECOVERY command (`launchctl enable gui/<uid>/<label> && launchctl bootstrap gui/<uid> '<plist>'`).

After `install_run` returns — a successful install, an already-claimed hold, or
any other return from the install attempt — `watch_iteration` sets the next
delay to 60 seconds. That keeps an immediate return (for example claim exit 75)
from looping hot. Catch-up of a still-newer successful run waits those 60
seconds. After a successful `gh run watch`, the next delay is still 0 so
selection can refresh immediately.

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
