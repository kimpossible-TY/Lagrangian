"""Snapshot the real Reader candidate renderer for an isolated corpus audit.

The audit does not exercise publication, user selection, dynamic paint, or figures.
Those remain separate Reader/browser checks. All dependencies are bundled locally.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

from math_reflow_probe import MathRoots


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("document", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.document.read_text()
    roots = MathRoots(source)
    roots.feed(source)
    web = Path(__file__).resolve().parents[1] / "web"
    args.output.mkdir(parents=True, exist_ok=True)
    shutil.copytree(web, args.output, dirs_exist_ok=True)
    for name in ("math-runtime.html", "math-runtime.js"):
        shutil.copyfile(Path(__file__).with_name(name), args.output / name)
    (args.output / "source-style.css").write_text("\n".join(
        re.findall(r"<style\b[^>]*>(.*?)</style>", source, re.S)))
    corpus = {"sourceSha256": hashlib.sha256(source.encode()).hexdigest(),
              "rendererFiles": {name: hashlib.sha256((web / name).read_bytes()).hexdigest()
                                for name in ("math-renderer.js", "math-layout.js",
                                             "math-identity.js", "mathjax-loader.js", "reader.css")},
              "roots": roots.roots}
    (args.output / "corpus.json").write_text(json.dumps(corpus, ensure_ascii=False))
    print(json.dumps({"sourceSha256": corpus["sourceSha256"], "roots": len(roots.roots)}))


if __name__ == "__main__":
    main()
