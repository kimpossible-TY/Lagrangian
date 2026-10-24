"""Atomic publication and status of the last accepted saved document."""
from collections import OrderedDict
from dataclasses import replace
import gzip
import hashlib
import json
import threading
import time
from flow_reader.compiler.build import compile_project
from flow_reader.compiler.inputs import input_fingerprint, source_signature
from flow_reader.document.sections import split_document
from flow_reader.rendering.service import DynamicRenderer
from flow_reader.services.codex_context import FocusStore
from flow_reader.services.selection import SelectionActions
from flow_reader.services.editor_sync import NeovimEditor, UNSPECIFIED_EDITOR
from flow_reader.services.navigation import SavedSourceNavigation
from flow_reader.services.edit_location import SharedEditLocation
from flow_reader.services.source_history import source_snapshots
from flow_reader.services.source_mapping import edit_location
from flow_reader.services.accepted_snapshot import AcceptedSnapshot
from flow_reader.compiler.pool import BrowserCompilePool
from flow_reader.compiler.diagnostics import CompilerDiagnostics
from flow_reader.server.compiler_assets import CompilerAssets


class ReaderState:
    def __init__(self, project, output, original_url, allow_incomplete, focus_file=None,
                 *, editor_server=None, nvim="nvim", change_file=None, source_history=None,
                 browser_compiler=None):
        self.project = project
        self.output = output
        self.original_url = original_url
        self.allow_incomplete = allow_incomplete
        self.editor_server = editor_server
        self.editor = NeovimEditor(editor_server, executable=nvim) if editor_server else None
        self.document_id = hashlib.sha256(
            json.dumps([str(project.root), str(project.relative_entry())]).encode()).hexdigest()[:24]
        self.focus = FocusStore(focus_file or output / "focus.json", project, self.document_id)
        self.source_history = source_history
        self.shared_edit = (source_history.location if source_history else
                            SharedEditLocation(project.root, project.entry, change_file))
        self.shared_edit_stamp = None
        self.lock = threading.RLock()
        self.accepted_inputs = None
        self.report = {}
        self.document = None
        self.compressed = None
        self.revision = None
        self.compiling = False
        self.source_stamp = None
        self.renderer = DynamicRenderer(self)
        self.selection = SelectionActions(self)
        self.navigation = SavedSourceNavigation(self)
        self.prewarm = False
        self.graphics = {}
        self.canvases = []
        self.decorations = {}
        self.bundle = None
        self.section_compressed = {}
        self.asset_snapshots = OrderedDict()
        self.manifest_json = None
        self.manifest_compressed = None
        self.dependencies = set()
        self.accepted_dependencies = set()
        self.watch_stamp = None
        self.compiler_assets = CompilerAssets(browser_compiler) if browser_compiler else None
        self.compiler_pool = None
        self.compiler_diagnostics = None
        if self.compiler_assets:
            def dependencies():
                with self.lock:
                    return set(self.dependencies)
            self.compiler_pool = BrowserCompilePool(project, dependencies, self.compiler_assets.engine)
            self.project = replace(project, execute=self.compiler_pool)
            self.compiler_diagnostics = CompilerDiagnostics(self)
        try:
            self.dependencies.update(json.loads((output / "report.json").read_text()).get("dependencies", []))
        except (OSError, ValueError):
            pass

    def load_result(self, source_stamp):
        report = json.loads((self.output / "report.json").read_text())
        accepted = report["exitCode"] == 0 and (report["contentGatePassed"] or self.allow_incomplete)
        if accepted:
            # Dynamic CeTZ programs can change without changing placeholder HTML.
            # The served revision therefore includes the accepted input snapshot.
            report["contentRevision"] = report["revision"]
            report["revision"] = hashlib.sha256(
                (report["revision"] + json.dumps(source_stamp)).encode()).hexdigest()
            document = (self.output / "document.html").read_bytes()
            bundle = split_document(document.decode(), report["revision"], source_map=report.get("sourceMap"),
                                    source_navigation_map=report.get("sourceNavigationMap"))
            bundle.manifest["documentID"] = self.document_id
            bundle.manifest["service"] = self.focus.service
            inputs = input_fingerprint(self.project, self.dependencies)
            if source_stamp != source_signature(self.project, self.dependencies):
                raise ValueError("Sources changed before Reader publication")
            if self.source_history:
                sources = source_snapshots(self.project, self.dependencies)
                if source_stamp != source_signature(self.project, self.dependencies):
                    raise ValueError("Sources changed before Reader history registration")
                self.source_history.seed(sources)
            edit_stamp = self.shared_edit.stamp()
            change = self.shared_change(bundle, self.dependencies)
            if source_stamp != source_signature(self.project, self.dependencies):
                raise ValueError("Sources changed before Reader navigation publication")
            bundle.manifest["lastChange"] = change
            compressed = gzip.compress(document)
            section_compressed = {key: gzip.compress(value) for key, value in bundle.documents.items()}
            manifest_json = json.dumps(bundle.manifest, ensure_ascii=False).encode()
            manifest_compressed = gzip.compress(manifest_json)
        with self.lock:
            self.report = report
            if accepted:
                self.document = document
                self.compressed = compressed
                self.bundle = bundle
                self.shared_edit_stamp = edit_stamp
                self.section_compressed = section_compressed
                self.manifest_json = manifest_json
                self.manifest_compressed = manifest_compressed
                self.asset_snapshots[report["revision"]] = bundle.assets
                while len(self.asset_snapshots) > 3:
                    self.asset_snapshots.popitem(last=False)
                self.revision = report["revision"]
                self.source_stamp = source_stamp
                self.accepted_dependencies = set(self.dependencies)
                self.accepted_inputs = inputs
                self.graphics = report.get("graphics", {})
                self.canvases = report.get("canvases", [])
                self.decorations = report.get("decorations", {})
                self.renderer.invalidate()
                if self.compiler_pool:
                    self.compiler_pool.record(executor="publication", purpose="document", status="published",
                                              revision=self.revision[:12])

    def compile(self):
        with self.lock:
            self.compiling = True
        try:
            if self.source_history:
                # Save chronology survives failed compilation and has no viewer lifetime.
                self.source_history.observe()
            for attempt in range(3):
                before = source_signature(self.project, self.dependencies)
                report = compile_project(self.project, self.output)
                discovered = set(report.get("dependencies", []))
                new_dependencies = discovered - self.dependencies
                self.dependencies.update(discovered)
                if new_dependencies and report["exitCode"] == 0:
                    # Discover the dependency graph once, then compile against a
                    # measured before/after snapshot of every newly found input.
                    continue
                after = source_signature(self.project, self.dependencies)
                self.watch_stamp = before
                if before != after:
                    raise ValueError("Sources changed during compilation; waiting for a stable save")
                self.load_result(after)
                self.watch_stamp = after
                break
            else:
                raise ValueError("The source dependency graph did not stabilize")
        except Exception as error:
            with self.lock:
                self.report = {"exitCode": 1, "contentGatePassed": False, "error": str(error),
                               "compiledAt": time.time()}
        finally:
            with self.lock:
                self.compiling = False
        if self.prewarm and self.revision and self.report.get("contentGatePassed") and not self.renderer.closed:
            threading.Thread(target=self.renderer.warm, daemon=True).start()

    def shared_change(self, bundle, dependencies):
        edit = self.shared_edit.read()
        if edit["status"] != "located":
            return None
        try:
            location = edit_location(self.project, dependencies, bundle, edit)
        except (OSError, ValueError):
            return None
        if location["status"] != "located":
            return None
        passage = next((part for part in bundle.passages if part["key"] == location.get("key")), None)
        target = location.get("target") or (passage["id"] if passage else None)
        if bundle.manifest["anchors"].get(target) != location["section"]:
            return None
        return {"token": edit["token"], "key": location.get("key"), "target": target,
                "section": location["section"], "revision": bundle.manifest["revision"]}

    def refresh_shared_change(self):
        """The engine may persist its edit after our accepted HTML compilation."""
        with self.lock:
            stamp = self.shared_edit.stamp()
            if self.compiling or not self.bundle or stamp == self.shared_edit_stamp:
                return
            snapshot = AcceptedSnapshot.capture(self, self.revision)
            if snapshot is None or not snapshot.current(self):
                return
            change = self.shared_change(snapshot.bundle, snapshot.dependencies)
            if not snapshot.current(self):
                return
            self.shared_edit_stamp = stamp
            self.bundle.manifest["lastChange"] = change
            self.manifest_json = json.dumps(self.bundle.manifest, ensure_ascii=False).encode()
            self.manifest_compressed = gzip.compress(self.manifest_json)

    def public(self):
        self.refresh_shared_change()
        with self.lock:
            return {key: self.report.get(key) for key in (
                "exitCode", "contentGatePassed", "unsupported", "compilerLossWarnings",
                "elapsedSeconds", "compiledAt",
            )} | {"revision": self.revision, "compiling": self.compiling,
                  "documentID": self.document_id,
                  "changeToken": (self.bundle.manifest.get("lastChange") or {}).get("token") if self.bundle else None,
                  "service": self.focus.service,
                  "editorServer": self.editor_server,
                  "originalURL": self.original_url, "development": self.allow_incomplete,
                  "semanticCanvases": self.project.semantic_canvases,
                  "graphics": self.graphics, "canvases": self.canvases, "decorations": self.decorations}

    def render_graphics(self, revision, graphs):
        return self.renderer.render(revision, graphs, "graphics")

    def render_canvases(self, revision, canvases):
        return self.renderer.render(revision, canvases, "canvases")


    def close(self):
        if self.compiler_pool:
            self.compiler_pool.close()
        try:
            if self.source_history:
                self.source_history.close()
        finally:
            self.renderer.close()

    def locate(self, revision, fragments):
        return self.selection.locate(revision, fragments)

    def highlight(self, revision, fragments, expected_editor=UNSPECIFIED_EDITOR):
        return self.selection.highlight(revision, fragments, expected_editor)

    def highlight_intent(self, request):
        return self.selection.highlight_intent(request)

    def source(self, revision, fragments):
        return self.navigation.source(revision, fragments)

    def cursor(self, revision, path, line, column):
        return self.navigation.cursor(revision, path, line, column)

    def save_focus(self, revision, fragments, service, viewer_id):
        return self.selection.save_focus(revision, fragments, service, viewer_id)

    def read_focus(self):
        return self.selection.read_focus()

    def render_dynamic(self, revision, requests, kind):
        return self.renderer.render(revision, requests, kind)
