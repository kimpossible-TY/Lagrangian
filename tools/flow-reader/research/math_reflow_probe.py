"""Build an isolated MathJax line-breaking probe from accepted Reader HTML.

This is a renderer evaluation, not a production renderer or a fidelity gate.
The corpus retains complete outer MathML roots, including embedded SVG.
"""

import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil


class MathRoots(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.source = source
        self.offsets = [0, *(m.end() for m in re.finditer("\n", source))]
        self.depth = 0
        self.roots = []

    def source_offset(self):
        row, column = self.getpos()
        return self.offsets[row - 1] + column

    def handle_starttag(self, tag, attrs):
        if tag == "math":
            if self.depth == 0:
                self.start = self.source_offset()
                self.display = dict(attrs).get("display", "inline")
            self.depth += 1

    def handle_endtag(self, tag):
        if tag == "math":
            self.depth -= 1
            if self.depth == 0:
                end = self.source.index(">", self.source_offset()) + 1
                self.roots.append({"index": len(self.roots), "display": self.display,
                                   "mathml": self.source[self.start:end]})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("document", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mathjax", type=Path, required=True,
                        help="Extracted mathjax@4.1.3 package directory")
    parser.add_argument("--font", type=Path, required=True,
                        help="Extracted @mathjax/mathjax-newcm-font@4.1.3 directory")
    args = parser.parse_args()
    for package in (args.mathjax, args.font):
        metadata = json.loads((package / "package.json").read_text())
        if metadata["version"] != "4.1.3":
            parser.error("This probe records MathJax/font version 4.1.3 only")
    source = args.document.read_text()
    corpus = MathRoots(source)
    corpus.feed(source)
    args.output.mkdir(parents=True, exist_ok=True)
    for package, name in ((args.mathjax, "mathjax"), (args.font, "mathjax-newcm")):
        destination = args.output / "vendor" / name
        if package.resolve() != destination.resolve():
            shutil.copytree(package, destination, dirs_exist_ok=True)
    report = {"sourceSha256": hashlib.sha256(source.encode()).hexdigest(),
              "mathjaxVersion": "4.1.3", "roots": corpus.roots}
    (args.output / "corpus.json").write_text(json.dumps(report, ensure_ascii=False))
    for name in ("math-reflow.html", "math-reflow.js"):
        shutil.copyfile(Path(__file__).with_name(name), args.output / name)
    print(json.dumps({"outerMathRoots": len(corpus.roots),
                      "displayMathRoots": sum(x["display"] == "block" for x in corpus.roots),
                      "sourceSha256": report["sourceSha256"]}))


if __name__ == "__main__":
    main()
