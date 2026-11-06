#!/bin/bash
# Reinstall each reader with the engine bundled in Lagrangian.app, restart it, verify HTTP 200.
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
SRC="$HOME/Developer/lagrangian"
CFG="$HOME/Library/Application Support/Lagrangian/reader/config.json"
ENGINE="$HOME/Applications/Lagrangian.app/Contents/MacOS/flow-engine"
LAUNCHER="$HOME/Library/Application Support/Lagrangian/reader/bin/flow-reader"
cd "${READER_SRC:-$SRC}"
echo "$(date) reader source: $PWD"
python3 - "$CFG" <<'PY' | while IFS=$'\t' read -r parent port url id; do
import json,sys
for s in json.load(open(sys.argv[1]))["services"]:
    print(s["parentID"], s["port"], s.get("publicURL",""), s["id"], sep="\t")
PY
  echo "$(date) refreshing reader $id with app engine"
  args=(--profile "$parent" --port "$port" --engine "$ENGINE" --start)
  [ -n "$url" ] && args+=(--public-url "$url")
  "$LAUNCHER" --control stop "$id"
  if ! python3 tools/flow-reader/install.py "${args[@]}"; then
    echo "$(date) install failed for $id, restarting previous release"
    "$LAUNCHER" --control start "$id" || true
    exit 1
  fi
  ok=
  for i in $(seq 1 20); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/")" = 200 ] && { ok=1; break; }
    sleep 3
  done
  [ -n "$ok" ] || { echo "$(date) reader $id not answering on $port"; exit 1; }
  echo "$(date) reader $id OK on $port"
done
