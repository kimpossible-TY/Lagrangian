# Mac engine updater

The launchd job runs the updater continuously. It checks for `flow-engine.yml`
runs on `main` every 60 seconds while idle, watches a newer in-progress run
with `gh run watch`, and rechecks before installing the newest successful run.
GitHub or watch errors are logged and retried. Installation failures exit the
process; launchd restarts it and the installed-run marker remains unchanged.
The installer still uses the checkout at `~/Developer/lagrangian` and requires
its existing GitHub authentication and the installed reader refresh script.

Run the isolated regression from the repository root:

```sh
bash scripts/mac/test-auto-update-engine.sh
```

## Apply after merge

These are operator steps for the Mac, **after the PR merges**. Do not run them
while an installation is in progress. Check the updater log and pipeline status
first. Use a checkout containing the merged files; check the example plist's
absolute paths for the target account before copying it.

```sh
support="$HOME/Library/Application Support/Lagrangian"
plist="$HOME/Library/LaunchAgents/dev.lagrangian.engine-autoupdate.plist"
backup="$HOME/Library/Application Support/Lagrangian/autoupdate-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
cp -p "$support/auto-update-engine.sh" "$backup/"
cp -p "$plist" "$backup/"
launchctl bootout "gui/$(id -u)" "$plist"
cp scripts/mac/auto-update-engine.sh "$support/auto-update-engine.sh"
chmod 755 "$support/auto-update-engine.sh"
cp scripts/mac/dev.lagrangian.engine-autoupdate.plist.example "$plist"
plutil -lint "$plist"
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl print "gui/$(id -u)/dev.lagrangian.engine-autoupdate"
```

Inspect `~/Library/Logs/lagrangian-engine-autoupdate.log` and
`pipeline-status.json` after a successful main run. `bootout` stops the job;
`bootstrap` loads it and `RunAtLoad` starts the loop. Keep the backup path for
rollback. To restore, first stop the job with the same `bootout` command, copy
both files from that backup to their original paths, then `bootstrap` the
restored plist. The marker and application data are retained during rollback.
