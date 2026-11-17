#!/usr/bin/env python3
"""NR10 offline proof exporter. No server, source writer, installation or GUI.

Run --help. A fresh caller-selected directory retains real compiler artifacts.
Missing prerequisites, compiler/import/oracle failures exit nonzero; no smoke fallback.
"""
from __future__ import annotations
import argparse
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


class Node:
    def __init__(self, tag, attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def text(self):
        return "".join(c if isinstance(c, str) else c.text() for c in self.children)

    def walk(self):
        yield self
        for c in self.children:
            if isinstance(c, Node):
                yield from c.walk()


class Tree(HTMLParser):
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}

    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.root = Node("root")
        self.stack = [self.root]
        self.feed(html)
        if len(self.stack) != 1:
            raise ValueError("unclosed HTML")

    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs)
        self.stack[-1].children.append(n)
        if tag not in self.VOID:
            self.stack.append(n)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in self.VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if len(self.stack) == 1 or self.stack[-1].tag != tag:
            raise ValueError("malformed HTML end: " + tag[:40])
        self.stack.pop()

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def offsets(text):
    u8, u16 = [0], [0]
    for c in text:
        u8.append(u8[-1] + len(c.encode()))
        u16.append(u16[-1] + len(c.encode("utf-16-le")) // 2)
    return {"scalars": [ord(c) for c in text], "cpToUTF8": u8, "cpToUTF16": u16}


def translate(documents, revision):
    """Translate ordered section bodies, never reconstruct visible text from passages.

    Display equals normalized HTML text nodes except explicit hard-object placeholders.
    Every supported inline carries half-open UTF16 positions into that exact string.
    """
    blocks, diagnostics = [], []
    for section, html in documents.items():
        tree = Tree(html.decode())
        body = next(n for n in tree.root.walk() if n.tag == "body")
        for n in body.children:
            if isinstance(n, str):
                if n.strip():
                    raise ValueError("unknown unwrapped body text")
                continue
            role = {"h1": "heading", "h2": "heading", "p": "paragraph", "table": "table", "figure": "figure"}.get(n.tag)
            if role is None:
                raise ValueError("unknown body node: " + n.tag[:40])
            bid = revision[:12] + ":" + str(len(blocks))
            text, inlines, objects = "", [], []

            def append(value):
                nonlocal text
                text += value

            def emit(node):
                if isinstance(node, str):
                    append(node)
                    return
                start = len(text.encode("utf-16-le")) // 2
                if node.tag in {"math", "table", "figure"}:
                    kind = node.tag
                    append("[" + kind + "]")
                    all_nodes = list(node.walk())
                    objects.append({"id": bid + ":object:" + str(len(objects)), "kind": kind,
                                    "fallback": "[" + kind + "]", "capability": "unsupported",
                                    "normalizedText": node.text(), "attributes": node.attrs,
                                    "resources": [x.attrs["src"] for x in all_nodes if "src" in x.attrs],
                                    "cells": [x.text() for x in all_nodes if x.tag in {"th", "td"}],
                                    "captions": [x.text() for x in all_nodes if x.tag == "figcaption"]})
                    diagnostics.append({"code": "unsupported-" + kind, "block": bid})
                elif node.tag in {"p", "h1", "h2", "em", "strong", "a", "span", "br"}:
                    if node.tag == "br":
                        append("\n")
                    for c in node.children:
                        emit(c)
                else:
                    raise ValueError("unknown inline node: " + node.tag[:40])
                end = len(text.encode("utf-16-le")) // 2
                inlines.append({"role": node.tag, "rangeUTF16": [start, end], "attributes": node.attrs})

            emit(n)
            blocks.append({"id": bid, "parent": "document", "order": len(blocks), "section": section,
                           "role": role, "text": text, "display": text, "offsets": offsets(text),
                           "inlines": inlines, "objects": objects,
                           "anchors": [x.attrs["id"] for x in n.walk() if "id" in x.attrs],
                           "sourceCorrespondence": "ambiguous" if text.startswith("Repeated paragraph") else "unavailable"})
    if len(diagnostics) > 32:
        raise ValueError("diagnostic limit")
    return blocks, diagnostics


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", type=Path, required=True, help="Fresh directory outside checkout")
    p.add_argument("--packages", type=Path, required=True, help="Existing local package root (read only)")
    p.add_argument("--cache", type=Path, required=True, help="Existing Typst package cache (copied; read only)")
    p.add_argument("--compiler", default="typst", help="Preinstalled Typst, never built or downloaded")
    p.add_argument("--derived-source", type=Path, required=True)
    a = p.parse_args()
    out = a.output.resolve()
    if out.is_relative_to(REPO) or out.exists():
        p.error("output must be a fresh directory outside checkout")
    out.mkdir(parents=True)
    commands = []

    def command(argv):
        r = subprocess.run(argv, text=True, capture_output=True)
        commands.append({"command": argv, "exit": r.returncode, "stdout": r.stdout[:8000], "stderr": r.stderr[:8000]})
        if r.returncode:
            raise ValueError("prerequisite command failed: " + argv[0])
        return r.stdout.strip()

    try:
        compiler = shutil.which(a.compiler)
        if not compiler or not shutil.which("sandbox-exec") or not a.packages.is_dir() or not a.cache.is_dir():
            raise ValueError("missing compiler/sandbox/local packages/cache")
        derived = json.loads(a.derived_source.read_text())
        for name, expected in derived["docfiles"].items():
            if digest(REPO / name) != expected:
                raise ValueError("derived documentation digest mismatch")
        ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", derived["derivedSHA"], "HEAD"], cwd=REPO)
        if ancestor.returncode:
            raise ValueError("derived SHA is not ancestor")
        environment = {"os": platform.platform(), "architecture": platform.machine(), "python": sys.version,
                       "typstVersion": command([compiler, "--version"]), "compilerSHA256": digest(compiler),
                       "swiftVersion": command(["swiftc", "--version"]),
                       "sdk": command(["xcrun", "--show-sdk-path"]),
                       "sdkVersion": command(["xcrun", "--show-sdk-version"]),
                       "swiftDriverSHA256": digest(shutil.which("swiftc")),
                       "swiftCompilerSHA256": digest(command(["xcrun", "--find", "swiftc"])),
                       "typliteSHA256": digest(shutil.which("typlite")) if shutil.which("typlite") else None,
                       "typliteVersion": "not exposed by --version; not used in compile_project path"}
        command([compiler, "compile", "--help"])
        if shutil.which("typlite"):
            command(["typlite", "--help"])
        shutil.copytree(a.cache, out / "cache", symlinks=False)
        os.environ["TYPST_PACKAGE_CACHE_PATH"] = str(out / "cache")
        os.environ["TYPST_PACKAGE_PATH"] = str(a.packages.resolve())
        wrapper = out / "offline-typst"
        # Deny network and all writes to original sources/cache, including inherited env overrides.
        profile = '(version 1)(allow default)(deny network*)' + ''.join(
            '(deny file-write* (subpath ' + json.dumps(str(x.resolve())) + '))'
            for x in (REPO, a.cache, a.packages))
        wrapper.write_text('#!' + sys.executable + '\nimport json, os, sys\n' +
                           'with open(' + repr(str(out / "compiler-argv.jsonl")) + ', "a") as log: log.write(json.dumps(sys.argv[1:]) + "\\n")\n' +
                           'os.execv("/usr/bin/sandbox-exec", ["sandbox-exec", "-p", ' + repr(profile) + ', ' + repr(compiler) + '] + sys.argv[1:])\n')
        wrapper.chmod(0o700)
        root = out / "source"
        root.mkdir()
        source = HERE / "fixtures/representation-minimal.typ"
        oracle_path = HERE / "fixtures/representation-minimal.expect.json"
        shutil.copyfile(source, root / "main.typ")
        oracle = json.loads(oracle_path.read_text())
        raw = source.read_bytes()
        if raw.count(b"\r\n") != oracle["sourceCRLFCount"] or raw.count(b"\t") != oracle["sourceTabCount"]:
            raise ValueError("raw source CRLF/tab oracle mismatch")
        sys.path.insert(0, str(REPO / "tools/flow-reader"))
        from flow_reader.compiler.build import compile_project
        from flow_reader.compiler.project import Project, document_identity
        from flow_reader.compiler.execution import local_compile
        from flow_reader.document.sections import split_document

        def execute(request):
            result = local_compile(request)
            commands.append({"operation": "local_compile", "compiler": str(wrapper), "actualCompiler": compiler,
                             "root": str(request.root), "packages": str(request.packages), "target": request.target,
                             "inputs": request.inputs, "systemFonts": request.system_fonts,
                             "flags": ["compile", "--jobs", "1", "--root", "<root>", "--package-path", "<overlay>",
                                       "--deps", "<temporary dependencies.json>", "--features", "html", "--input", "flow-reader=true", "-", "<temporary document.html>"],
                             "exit": result.returncode, "stderr": result.stderr[:8000]})
            return result

        project = Project(root, Path("main.typ"), a.packages.resolve(), compiler=str(wrapper), execute=execute)
        report = compile_project(project, out / "compiled", map_sources=False)
        if report["exitCode"] or not report["contentGatePassed"]:
            raise ValueError("real compiler/content gate failed")
        normalized = (out / "compiled/document.html").read_text()
        bundle = split_document(normalized, report["revision"], max_blocks=2, max_chars=1000)
        save(out / "manifest.json", bundle.manifest)
        save(out / "passages.json", bundle.passages)
        for folder, items in (("sections", bundle.documents), ("assets", bundle.assets)):
            (out / folder).mkdir()
            for name, data in items.items():
                (out / folder / name).write_bytes(data.encode() if isinstance(data, str) else data)
        blocks, diagnostics = translate(bundle.documents, report["revision"])
        if [b["role"] for b in blocks] != oracle["roles"] or [b["text"] for b in blocks] != oracle["texts"]:
            save(out / "observed-blocks.json", blocks)
            raise ValueError("ordered role/text oracle mismatch")
        if len(bundle.documents) < 2 or not bundle.assets:
            raise ValueError("missing actual transport boundary/figure asset")
        anchors = {k: i for i, b in enumerate(blocks) for k in b["anchors"]}
        for anchor, index in oracle["anchors"].items():
            if anchors.get(anchor) != index or anchor not in bundle.manifest["anchors"]:
                raise ValueError("anchor oracle mismatch")
        source_hashes = {str(x.relative_to(REPO)): digest(x) for x in HERE.rglob("*") if x.is_file()}
        module_hashes = {str(REPO / f): digest(REPO / f) for f in (
            "tools/flow-reader/flow_reader/compiler/build.py", "tools/flow-reader/flow_reader/compiler/project.py",
            "tools/flow-reader/flow_reader/compiler/execution.py", "tools/flow-reader/flow_reader/compiler/audit.py",
            "tools/flow-reader/flow_reader/document/sections.py", "tools/flow-reader/flow_reader/document/passages.py")}
        deps = {s: digest(s) if Path(s).is_file() else "unavailable" for s in report["dependencies"]}
        if "unavailable" in deps.values():
            raise ValueError("unavailable actual compiler dependency fingerprint")
        packages = {str(x.relative_to(a.packages.resolve())): digest(x) for x in sorted(a.packages.resolve().rglob("*")) if x.is_file()}
        artifacts = {str(x.relative_to(out)): digest(x) for folder in (out / "compiled", out / "sections", out / "assets") for x in sorted(folder.rglob("*")) if x.is_file()}
        artifacts.update({n: digest(out / n) for n in ("manifest.json", "passages.json")})
        def identity(value, origin, source):
            return {"value": value, "origin": origin, "source": source}
        model = {"proofSchema": 1, "requiredCapabilities": ["native-text", "unsupported-placeholders"], "coverage": "real-compiler; offline headless proof only",
                 "identity": {"document": identity(document_identity(root, Path("main.typ")), "observed-local-project", "Project.document_identity(temp root, entry)"),
                              "service": identity("nr10-offline-synthetic", "synthetic-fixture", "no service launched or observed"),
                              "revision": identity(report["revision"], "observed-compiler-output", "compile_project normalized HTML SHA256"),
                              "input": identity(digest(source), "observed-local-bytes", "controlled fixture SHA256; not server authority")},
                 "generation": 1, "units": {"ranges": "half-open UTF16", "codepoint": "Unicode scalar", "bytes": "UTF8", "carets": "extended-grapheme endpoints", "source": "raw UTF8 bytes/CRLF preserved", "display": "exact text with explicit object placeholders", "canonical": "normalized HTML scalar sequence"},
                 "blocks": blocks, "anchors": anchors, "diagnostics": diagnostics,
                 "provenance": {"derived": derived, "testRevision": command(["git", "-C", str(REPO), "rev-parse", "HEAD"]),
                                "testFiles": source_hashes, "modules": module_hashes, "fixtureSHA256": digest(source),
                                "oracleSHA256": digest(oracle_path), "artifacts": artifacts, "dependencies": deps,
                                "localPackageFiles": packages, "environment": environment, "compilerExit": report["exitCode"],
                                "fingerprintScope": "controlled source, listed repository package bytes/dependencies, compiler, normalized artifacts; system font files observed by Swift; no whole host or live service fingerprint",
                                "sourceMap": "unavailable: map_sources=False; no exact source mapping claim", "oracleReview": oracle["reviewStatus"]}}
        save(out / "native.json", model)
        # Parser rejection is a real importer negative, not a synthetic 'pass' label.
        try:
            translate({"s": b"<html><body><unknown>lost?</unknown></body></html>"}, "negative")
        except ValueError:
            unknown_rejected = True
        else:
            raise ValueError("unknown importer node accepted")
        save(out / "export-summary.json", {"status": "technical-pass", "coverage": "real-compiler", "compilerExit": report["exitCode"], "blocks": len(blocks), "sections": len(bundle.documents), "assets": len(bundle.assets), "unknownImporterRejected": unknown_rejected, "oracleFinalReview": "pending", "exit": 0})
        print(json.dumps({"status": "technical-pass", "output": str(out), "blocks": len(blocks), "sections": len(bundle.documents), "assets": len(bundle.assets)}))
        return 0
    except Exception as e:
        save(out / "export-summary.json", {"status": "blocked", "exit": 1, "error": str(e)[:400], "coverage": "real-compiler required; no smoke substitution"})
        print(json.dumps({"status": "blocked", "error": str(e)[:400]}))
        return 1
    finally:
        save(out / "commands.json", commands)


if __name__ == "__main__":
    sys.exit(main())
