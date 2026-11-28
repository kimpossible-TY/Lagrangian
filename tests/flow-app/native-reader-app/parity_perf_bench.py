"""Compile and run the same offscreen AppKit benchmark on either worktree.

The legacy scroll metric includes display; scroll-handler, foreign-bounds and
same-value-layout metrics time synchronous work without forcing display. Each
metric reports the median of five runs with 500 steps per run (n in the JSON).
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]


def main():
    with tempfile.TemporaryDirectory(prefix='parity-perf-') as temporary:
        out = Path(temporary)
        cache = out / 'cache'
        cache.mkdir()
        registry = json.loads((ROOT / 'apps/macos/sources.json').read_text())
        sources = [ROOT / 'apps/macos' / name for group in ('core', 'native', 'app')
                   for name in registry[group] if name != 'main.swift']
        env = dict(os.environ, TMPDIR=str(out), CLANG_MODULE_CACHE_PATH=str(cache), SWIFT_MODULECACHE_PATH=str(cache))
        binary = out / 'bench'
        subprocess.run(['swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors',
                        '-target', 'arm64-apple-macosx13.0', '-module-cache-path', str(cache),
                        *map(str, sources), str(Path(__file__).with_name('ParityPerfBench.swift')), '-o', str(binary)],
                       cwd=ROOT, env=env, check=True, timeout=240)
        subprocess.run([str(binary)], cwd=ROOT, env=env, check=True, timeout=900)


if __name__ == '__main__':
    main()
