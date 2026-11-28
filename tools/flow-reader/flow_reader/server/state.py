"""Atomic publication and status of the last accepted saved document."""
from collections import OrderedDict
from dataclasses import replace
import gzip
import hashlib
import json
from pathlib import Path
import tempfile
import threading
import time
from flow_reader.compiler.build import compile_document_source_map, compile_project
from flow_reader.compiler.inputs import input_fingerprint, source_signature
from flow_reader.compiler.project import document_identity
from flow_reader.document.sections import split_document
from flow_reader.rendering.service import DynamicRenderer
from flow_reader.services.codex_context import FocusStore
from flow_reader.services.selection import SelectionActions
from flow_reader.services.editor_sync import EditorAttachments, NeovimEditor, UNSPECIFIED_EDITOR
from flow_reader.services.navigation import SavedSourceNavigation
from flow_reader.services.edit_location import SharedEditLocation
from flow_reader.services.source_history import source_snapshots
from flow_reader.services.source_mapping import edit_location
from flow_reader.services.accepted_snapshot import AcceptedSnapshot
from flow_reader.services.cross_project_refs import CatalogAvailability, PreviewImportCache
from flow_reader.compiler.pool import BrowserCompilePool
from flow_reader.compiler.diagnostics import CompilerDiagnostics
from flow_reader.server.compiler_assets import CompilerAssets


class ReaderState:
    def __init__(self, project, output, original_url, allow_incomplete, focus_file=None,
                 *, editor_server=None, nvim="nvim", change_file=None, source_history=None,
                 browser_compiler=None, chat_provider=None, chat_data=None,
                 source_map_retry_delay=2.0):
        self.project = project
        self.output = output
        self.original_url = original_url
        self.allow_incomplete = allow_incomplete
        self.editor_server = editor_server
        self.editor = NeovimEditor(editor_server, executable=nvim) if editor_server else None
        self.document_id = document_identity(project.root, project.entry)
        self.focus = FocusStore(focus_file or output / "focus.json", project, self.document_id)
        self.editor_attachments = EditorAttachments(output, self.document_id, self.focus.service)
        self.source_history = source_history
        self.shared_edit = (source_history.location if source_history else
                            SharedEditLocation(project.root, project.entry, change_file))
        self.shared_edit_stamp = None
        self.lock = threading.RLock()
        self.catalog_availability = CatalogAvailability()
        self.cross_project_imports = PreviewImportCache()
        self._paragraph_chat = None
        self.chat_provider, self.chat_data = chat_provider, chat_data
        self.accepted_inputs = None
        self.report = {}
        self.document = None
        self.compressed = None
        self.revision = None
        self.compiling = False
        self.closed = False
        self.source_map_retry_delay = source_map_retry_delay
        self.source_map_timer = None
        self.source_map_attempted = set()
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

    def _build_publication_payload(self, document, revision, source_map,
                                   source_navigation_map, dependencies):
        """Build identical transport payloads for initial and recovered mappings."""
        bundle = split_document(document.decode(), revision, source_map=source_map,
                                source_navigation_map=source_navigation_map)
        bundle.manifest["documentID"] = self.document_id
        bundle.manifest["service"] = self.focus.service
        edit_stamp = self.shared_edit.stamp()
        bundle.manifest["lastChange"] = self.shared_change(bundle, dependencies)
        compressed = gzip.compress(document)
        sections = {key: gzip.compress(value) for key, value in bundle.documents.items()}
        manifest = json.dumps(bundle.manifest, ensure_ascii=False).encode()
        return bundle, edit_stamp, compressed, sections, manifest, gzip.compress(manifest)

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
            inputs = input_fingerprint(self.project, self.dependencies)
            if source_stamp != source_signature(self.project, self.dependencies):
                raise ValueError("Sources changed before Reader publication")
            if self.source_history:
                sources = source_snapshots(self.project, self.dependencies)
                if source_stamp != source_signature(self.project, self.dependencies):
                    raise ValueError("Sources changed before Reader history registration")
                self.source_history.seed(sources)
            (bundle, edit_stamp, compressed, section_compressed,
             manifest_json, manifest_compressed) = self._build_publication_payload(
                document, report["revision"], report.get("sourceMap"),
                report.get("sourceNavigationMap"), self.dependencies)
            if source_stamp != source_signature(self.project, self.dependencies):
                raise ValueError("Sources changed before Reader navigation publication")
        with self.lock:
            self._cancel_source_map_recovery()
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
                self._schedule_source_map_recovery()

    def _cancel_source_map_recovery(self):
        """Called under the publication lock; running work loses its commit token."""
        if self.source_map_timer is not None:
            self.source_map_timer.cancel()
            self.source_map_timer = None

    def _schedule_source_map_recovery(self):
        """Schedule once reading can use the accepted document, under self.lock."""
        key = (self.revision, self.source_stamp)
        if (self.closed or self.compiling or not self.bundle or self.source_map_timer is not None
                or self.report.get("sourceMapStatus") != "unavailable"
                or key in self.source_map_attempted):
            return
        timer = threading.Timer(self.source_map_retry_delay, self._recover_source_map, args=(key,))
        timer.daemon = True
        self.source_map_timer = timer
        timer.start()

    def _recover_source_map(self, key):
        timer = threading.current_thread()
        try:
            with self.lock:
                if (self.closed or self.source_map_timer is not timer
                        or key != (self.revision, self.source_stamp)):
                    return
                snapshot = AcceptedSnapshot.capture(self, key[0])
                if snapshot is None or not snapshot.current(self):
                    return
                self.source_map_attempted.add(key)
                document, report = self.document, dict(self.report)
            frozen = report.get("compileInputs", {})
            if frozen.get("timestamp") is None or not isinstance(frozen.get("systemFonts"), bool):
                return
            # Overlay preparation, compiler execution and payload construction must
            # not hold up requests for the already accepted document.
            disk_report = json.loads((self.output / "report.json").read_text())
            recovered = compile_document_source_map(
                self.project, self.output, snapshot.dependencies, document.decode(),
                timestamp=frozen["timestamp"], system_fonts=frozen["systemFonts"])
            if recovered.get("sourceMapStatus") not in {"verified", "partial"}:
                return
            report.update(recovered)
            disk_report.update(recovered)
            (bundle, edit_stamp, compressed, sections,
             manifest, manifest_compressed) = self._build_publication_payload(
                document, snapshot.revision, report.get("sourceMap"),
                report.get("sourceNavigationMap"), snapshot.dependencies)
            # Preserve the on-disk report's revision/contentRevision schema. Only
            # mapping fields change; the served revision also stays unchanged.
            with tempfile.TemporaryDirectory(prefix="source-map-report-", dir=self.output) as temporary:
                staged_report = Path(temporary) / "report.json"
                staged_report.write_text(json.dumps(disk_report, ensure_ascii=False, indent=2) + "\n")
                with self.lock:
                    if (self.closed or self.source_map_timer is not timer
                            or self.bundle is not snapshot.bundle or not snapshot.current(self)):
                        return
                    staged_report.replace(self.output / "report.json")
                    self.report = report
                    self.bundle = bundle
                    self.compressed = compressed
                    self.section_compressed = sections
                    self.manifest_json = manifest
                    self.manifest_compressed = manifest_compressed
                    self.shared_edit_stamp = edit_stamp
                    self.asset_snapshots[snapshot.revision] = bundle.assets
        except (OSError, ValueError, RecursionError):
            # Optional recovery never makes an accepted document unavailable.
            pass
        finally:
            with self.lock:
                if self.source_map_timer is timer:
                    self.source_map_timer = None

    def compile(self):
        with self.lock:
            if self.closed:
                return
            self._cancel_source_map_recovery()
            self.compiling = True
        try:
            if self.source_history:
                # Save chronology survives failed compilation and has no viewer lifetime.
                self.source_history.observe()
            for attempt in range(3):
                before = source_signature(self.project, self.dependencies)
                report = compile_project(self.project, self.output)
                discovered = set(report.get("dependencies", []))
                if report["exitCode"] == 0 and discovered != self.dependencies:
                    # A successful compiler owns the complete dependency graph.
                    # Retire removed imports and paths from previous installed
                    # releases before capturing portable browser snapshots.
                    self.dependencies = discovered
                    continue
                self.dependencies.update(discovered)
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
                self._schedule_source_map_recovery()
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
            result = {key: self.report.get(key) for key in (
                "exitCode", "contentGatePassed", "unsupported", "compilerLossWarnings",
                "elapsedSeconds", "compiledAt", "sourceMapStatus",
            )} | {"revision": self.revision, "compiling": self.compiling,
                  "documentID": self.document_id,
                  "changeToken": (self.bundle.manifest.get("lastChange") or {}).get("token") if self.bundle else None,
                  "service": self.focus.service,
                   "editorServer": self.editor_server,
                   "editorAttachments": 1,
                  "originalURL": self.original_url, "development": self.allow_incomplete,
                  "semanticCanvases": self.project.semantic_canvases,
                  "graphics": self.graphics, "canvases": self.canvases, "decorations": self.decorations}
            packages = self.project.packages
        result["viewer"] = self.viewer_capabilities(packages)
        return result

    def viewer_capabilities(self, packages=None):
        return {"name": "Lagrangian Web Viewer",
                "crossProject": self.catalog_availability.check(packages if packages is not None else self.project.packages)}

    def render_graphics(self, revision, graphs):
        return self.renderer.render(revision, graphs, "graphics")

    def render_canvases(self, revision, canvases):
        return self.renderer.render(revision, canvases, "canvases")


    def close(self):
        with self.lock:
            self.closed = True
            self._cancel_source_map_recovery()
        if self._paragraph_chat:
            self._paragraph_chat.close()
        if self.compiler_pool:
            self.compiler_pool.close()
        try:
            if self.source_history:
                self.source_history.close()
        finally:
            self.renderer.close()

    @property
    def paragraph_chat(self):
        # Ordinary reading never opens an OAuth profile or conversation store.
        from flow_reader.services.paragraph_chat import ParagraphChat
        with self.lock:
            if self._paragraph_chat is None:
                self._paragraph_chat = ParagraphChat(self, directory=self.chat_data, provider=self.chat_provider)
            return self._paragraph_chat

    def locate(self, revision, fragments):
        return self.selection.locate(revision, fragments)

    def highlight(self, revision, fragments, expected_editor=UNSPECIFIED_EDITOR,
                  editor_attachment=UNSPECIFIED_EDITOR):
        return self.selection.highlight(revision, fragments, expected_editor, editor_attachment)

    def highlight_intent(self, request):
        return self.selection.highlight_intent(request)

    def source(self, revision, fragments):
        return self.navigation.source(revision, fragments)

    def source_text(self, revision, fragments):
        return self.navigation.source_text(revision, fragments)

    def cursor(self, revision, path, line, column):
        return self.navigation.cursor(revision, path, line, column)

    def save_focus(self, revision, fragments, service, viewer_id):
        return self.selection.save_focus(revision, fragments, service, viewer_id)

    def read_focus(self):
        return self.selection.read_focus()

    def render_dynamic(self, revision, requests, kind):
        return self.renderer.render(revision, requests, kind)
