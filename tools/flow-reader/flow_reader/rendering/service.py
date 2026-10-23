"""Bounded dynamic paint cache and incremental worker lifecycle."""
from collections import OrderedDict
import hashlib
import json
from pathlib import Path
import tempfile
import threading
from flow_reader.compiler.build import compile_project
from flow_reader.compiler.dynamic import DynamicCompiler
from flow_reader.compiler.inputs import source_signature
from flow_reader.errors import RevisionChanged
from flow_reader.rendering.graphics import extract_graphics, validate_geometry
from flow_reader.rendering.canvases import extract_canvases, validate_canvases
from flow_reader.rendering.decorations import extract_decorations, validate_decorations


class DynamicRenderer:
    def __init__(self, state):
        self.state = state
        self.graphic_cache = OrderedDict()
        self.component_cache = OrderedDict()
        self.graphic_lock = threading.Lock()
        self.dynamic_compiler = None
        self.dynamic_revision = None
        self.closed = False

    def invalidate(self):
        """Called while holding the accepted state's lock."""
        self.graphic_cache.clear()
        self.component_cache.clear()

    def warm(self):
        if self.state.compiler_pool and self.state.compiler_pool.available():
            return
        with self.graphic_lock:
            if self.closed or self.dynamic_revision == self.state.revision:
                return
            try:
                self.dynamic(self.state.revision).compile()
            except (OSError, ValueError, TimeoutError):
                self.reset_dynamic()

    def reset_dynamic(self):
        if self.dynamic_compiler is not None:
            self.dynamic_compiler.close()
            self.dynamic_compiler = None
        self.dynamic_revision = None

    def dynamic(self, revision):
        if self.closed:
            raise ValueError("Reader is stopping")
        if (self.dynamic_revision != revision or
                (self.dynamic_compiler is not None and self.dynamic_compiler.requests >= 256)):
            self.reset_dynamic()
            self.dynamic_compiler = DynamicCompiler(self.state.project, self.state.output,
                                                    system_fonts=self.state.compiler_pool is None)
            self.dynamic_revision = revision
        return self.dynamic_compiler

    def close(self):
        self.closed = True
        worker = self.dynamic_compiler
        if worker is not None and worker.process is not None and worker.process.poll() is None:
            worker.process.terminate()
        with self.graphic_lock:
            self.reset_dynamic()

    def render(self, revision, requests, kind):
        with self.state.lock:
            if not self.state.revision or revision != self.state.revision:
                raise RevisionChanged("The document revision has changed")
            validate, known = {"graphics": (validate_geometry, self.state.graphics),
                               "canvases": (validate_canvases, self.state.canvases),
                               "decorations": (validate_decorations, self.state.decorations)}[kind]
            geometry = validate(requests, known)
            stamp = self.state.source_stamp
            dependencies = set(self.state.accepted_dependencies)
        key = hashlib.sha256(json.dumps([kind, revision, geometry], sort_keys=True).encode()).hexdigest()
        component_keys = {identifier: json.dumps([kind, revision, identifier, layout], sort_keys=True)
                          for identifier, layout in geometry.items()}
        cached = {}
        with self.graphic_lock:
            with self.state.lock:
                if self.state.revision != revision:
                    raise RevisionChanged("The document revision has changed")
                if key in self.graphic_cache:
                    self.graphic_cache.move_to_end(key)
                    return self.graphic_cache[key]
                for identifier, component_key in component_keys.items():
                    if component_key in self.component_cache:
                        cached[identifier] = self.component_cache[component_key]
                        self.component_cache.move_to_end(component_key)
                if cached:
                    geometry = {identifier: layout for identifier, layout in geometry.items()
                                if identifier not in cached}
                    if not geometry:
                        return {"revision": revision, kind: cached}
            if stamp != source_signature(self.state.project, dependencies):
                raise RevisionChanged("Saved sources have changed")
            with tempfile.TemporaryDirectory(prefix=f"{kind}-", dir=self.state.output) as temporary:
                work = Path(temporary)
                arguments = {"geometry" if kind == "graphics" else kind: geometry}
                content = None
                if not (self.state.compiler_pool and self.state.compiler_pool.available()):
                    try:
                        content = self.dynamic(revision).compile(**arguments)
                    except (OSError, ValueError, TimeoutError):
                        self.reset_dynamic()
                if content is None:
                    if self.closed:
                        raise ValueError("Reader is stopping")
                    report = compile_project(self.state.project, work, **arguments)
                    if not report["contentGatePassed"]:
                        raise ValueError(f"{kind.capitalize()} compilation failed")
                    content = (work / "document.html").read_text()
                extract = {"graphics": extract_graphics, "canvases": extract_canvases,
                           "decorations": extract_decorations}[kind]
                drawings = extract(content, geometry, key[:16])
            if stamp != source_signature(self.state.project, dependencies):
                raise RevisionChanged("Saved sources changed during graphical rendering")
            result = {"revision": revision, kind: cached | drawings}
            with self.state.lock:
                if self.state.revision != revision:
                    raise RevisionChanged("The document revision has changed")
                for identifier, drawing in drawings.items():
                    self.component_cache[component_keys[identifier]] = drawing
                while len(self.component_cache) > 256:
                    self.component_cache.popitem(last=False)
                self.graphic_cache[key] = result
                while len(self.graphic_cache) > 48:
                    self.graphic_cache.popitem(last=False)
            return result
