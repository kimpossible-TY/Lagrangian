"""Reuse Typst's incremental cache for revision-bound graphical requests."""

import atexit
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import uuid

from build import ContentAudit, prepare_packages
from content import namespace_svg_ids, normalize_math_html
from figures import stamp_canvas_identities


class DynamicCompiler:
    """One serialized worker, owned and closed by the Reader service.

    The dependency file is Typst watch's completion barrier: it is written
    after export and diagnostics. A request nonce in the HTML additionally
    prevents a prior or source-triggered compilation satisfying a new request.
    All mutable files live outside the user's project and installed packages.
    """

    def __init__(self, project, output):
        self.project = project
        self.temporary = tempfile.TemporaryDirectory(prefix="dynamic-", dir=output)
        self.work = Path(self.temporary.name)
        self.process = None
        self.log = None
        self.requests = 0
        try:
            prepare_packages(project.packages.resolve(), self.work / "packages")
            self.request = self.work / "packages/local/flow-inputs/0.1.0/requests.json"
            self.dependencies = self.work / "dependencies.json"
            self.document = self.work / "document.html"
            self.root = self.work / "root"
            self.root.mkdir()
            for child in project.root.resolve().iterdir():
                (self.root / child.name).symlink_to(child, target_is_directory=child.is_dir())
            self.log = (self.work / "compile.log").open("w+b", buffering=0)
            atexit.register(self.close)
        except BaseException:
            self.close()
            raise

    def compile(self, **arguments):
        self.requests += 1
        token = uuid.uuid4().hex
        payload = {"token": token, **arguments}
        self.dependencies.unlink(missing_ok=True)
        offset = (self.work / "compile.log").stat().st_size
        pending = self.request.with_suffix(".tmp")
        pending.write_text(json.dumps(payload, separators=(",", ":")))
        pending.replace(self.request)
        if self.process is None:
            project = self.project
            command = [project.compiler, "watch", "--features", "html", "--no-serve",
                       "--diagnostic-format", "short", "--root", str(self.root),
                       "--deps", str(self.dependencies), "--package-path", str(self.work / "packages"),
                       "--input", "flow-reader=true", "--input", "flow-live=true"]
            if project.semantic_canvases:
                command.extend(["--input", "flow-native-labels=true"])
            for font in project.fonts:
                command.extend(["--font-path", str((project.root / font).resolve())])
            wrapper = ('#import "@local/flow-reader:0.1.0": apply-reader\n'
                       '#import "@local/flow-inputs:0.1.0": inputs\n'
                       '#show: apply-reader\n'
                       f'#include {json.dumps("/" + project.relative_entry(), ensure_ascii=False)}\n'
                       '#html.elem("span", attrs: ("data-flow-request": inputs().token), [])\n')
            entry = self.root / (".flow-reader-" + token + ".typ")
            entry.write_text(wrapper)
            command.extend([str(entry), str(self.document)])
            self.process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=self.log,
                                            stderr=subprocess.STDOUT, cwd=project.root)
        deadline = time.monotonic() + 90
        retry_at = time.monotonic() + 0.25
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise ValueError("Incremental compiler exited")
            if self.dependencies.exists():
                try:
                    completed = self.dependencies.stat().st_mtime_ns
                    json.loads(self.dependencies.read_text())
                    diagnostic = (self.work / "compile.log").read_bytes()[offset:].decode()
                    if "compiled with errors" in diagnostic:
                        raise ValueError("Incremental compilation failed")
                    exported = self.document.stat().st_mtime_ns
                    content = self.document.read_text()
                    if (completed >= exported and self.document.stat().st_mtime_ns == exported
                            and self.dependencies.stat().st_mtime_ns == completed
                            and f'data-flow-request="{token}"' in content
                            and content.rstrip().endswith("</html>")):
                        return self.validate(content, diagnostic)
                except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError):
                    pass  # Typst is still writing the completion record.
            # Watch installs its dependency watches after writing the first
            # completion record. Recover a request that arrived in that gap.
            if time.monotonic() >= retry_at:
                diagnostic = (self.work / "compile.log").read_bytes()[offset:].decode(errors="replace")
                if "compiling ..." not in diagnostic or self.dependencies.exists():
                    os.utime(self.request, None)
                retry_at = time.monotonic() + 0.25
            time.sleep(0.02)
        raise TimeoutError("Incremental compiler timed out")

    @staticmethod
    def validate(content, diagnostic):
        allowed = {"html export is under active development and incomplete",
                   "page set rule was ignored during HTML export",
                   "pdf-marker-tag was ignored during HTML export"}
        warnings = re.findall(r"(?:^|\n).*?warning: (.*)", diagnostic)
        if set(warnings) - allowed or re.search(r"(?:^|\n).*?error: ", diagnostic):
            raise ValueError("Incremental compilation has unhandled diagnostics")
        content = stamp_canvas_identities(normalize_math_html(namespace_svg_ids(content)))
        audit = ContentAudit()
        audit.feed(content)
        if not audit.report()["contentGatePassed"]:
            raise ValueError("Incremental compilation failed the content gate")
        return content

    def close(self):
        atexit.unregister(self.close)
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
            self.process = None
        if self.log is not None:
            self.log.close()
        self.temporary.cleanup()
