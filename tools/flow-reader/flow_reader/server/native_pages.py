"""Immutable PDF full-snapshot delivery from the existing accepted HTML owner.

Compilation is serialized separately from publication. Neither a caller's digest
nor PDF text/coordinates grants source authority. Only the captured accepted
snapshot and a stable union of HTML/PDF inputs can publish.
"""
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import threading
from subprocess import TimeoutExpired
from uuid import uuid4

from flow_reader.compiler.execution import CompileRequest
from flow_reader.compiler.inputs import input_fingerprint, source_signature
from flow_reader.errors import RevisionChanged
from flow_reader.services.accepted_snapshot import AcceptedSnapshot

CAPABILITY = "original-pdf-full-v1"
MAX_PDF = 16 * 1024 * 1024


@dataclass(frozen=True)
class Publication:
    snapshot: AcceptedSnapshot
    service: str
    dependencies: frozenset[str]
    stamp: tuple
    fingerprint: str
    pdf_dependencies: str
    data: bytes
    digest: str
    sequence: int


class NativePageService:
    def __init__(self, state, native):
        self.state, self.native = state, native
        self.incarnation = str(uuid4())
        self.sequence = 0
        self.accepted = None
        self.compile_lock = threading.Lock()

    def query(self, query):
        request = self.native.query(query)
        if request['capabilities'] != [CAPABILITY]:
            raise ValueError('Unsupported page capabilities')
        # Reuse target/scope/UUID/schema validation without semantic importing.
        self.native.target({**request, 'capabilities': ['semantic-tree-v1']})
        return request

    def current(self, publication):
        from flow_reader.server.native_reader import service_id
        return (not self.state.renderer.closed and publication.service == service_id(self.state.focus.service)
                and publication.snapshot.current(self.state)
                and publication.stamp == source_signature(self.state.project, publication.dependencies)
                and publication.fingerprint == input_fingerprint(self.state.project, publication.dependencies))

    def publication(self, request, connected=lambda: True):
        from flow_reader.server.native_reader import service_id
        state = self.state
        if not connected():
            raise OSError("Page client disconnected")
        with state.lock:
            self.query_target(request)
            snapshot = AcceptedSnapshot.capture(state, request['revision'])
            if snapshot is None or not snapshot.current(state):
                raise RevisionChanged('Accepted page inputs changed')
            service = service_id(state.focus.service)
            if self.accepted and self.accepted.snapshot == snapshot and self.current(self.accepted):
                return self.accepted
        # No UI/publication lock held during Project.execute. A busy request is
        # bounded unavailable; it does not build an unbounded compiler queue.
        if not self.compile_lock.acquire(blocking=False):
            raise OSError('Page compiler busy')
        try:
            dependencies = set(snapshot.dependencies)
            for _ in range(3):
                if not connected():
                    raise OSError("Page client disconnected")
                before = source_signature(state.project, dependencies)
                fingerprint = input_fingerprint(state.project, dependencies)
                project = state.project
                result = project.execute(CompileRequest(compiler=project.compiler,
                    root=project.root, packages=project.packages, target='pdf',
                    entry=project.root / project.entry,
                    fonts=tuple((project.root / font).resolve() for font in project.fonts),
                    timestamp=0, timeout=90, purpose='native-original-pages'))
                if result.returncode or not result.artifact:
                    raise OSError('Original PDF compilation failed')
                if len(result.artifact) > MAX_PDF or not result.artifact.startswith(b'%PDF-'):
                    raise ValueError('Original PDF budget/format')
                discovered = frozenset(str((project.root / path).resolve())
                    for path in result.dependencies if Path(path).name != '<stdin>')
                union = set(snapshot.dependencies) | set(discovered)
                if union != dependencies:
                    dependencies = union
                    continue
                if (before != source_signature(project, dependencies)
                        or fingerprint != input_fingerprint(project, dependencies)):
                    raise RevisionChanged('PDF dependencies changed during compilation')
                candidate = Publication(snapshot, service, frozenset(dependencies), before,
                    fingerprint, input_fingerprint(project, discovered), result.artifact,
                    hashlib.sha256(result.artifact).hexdigest(), self.sequence + 1)
                with state.lock:
                    self.query_target(request)
                    if not connected() or not self.current(candidate):
                        raise RevisionChanged('Original page publication changed')
                    self.sequence += 1
                    self.accepted = candidate
                    return candidate
            raise RevisionChanged('PDF dependency graph did not stabilize')
        except TimeoutExpired as error:
            raise OSError("Original PDF compilation timed out") from error
        finally:
            self.compile_lock.release()

    def query_target(self, request):
        self.native.target({**request, 'capabilities': ['semantic-tree-v1']})

    def manifest(self, query, connected=lambda: True):
        with self.state.lock:
            request = self.query(query)
        publication = self.publication(request, connected)
        with self.state.lock:
            self.query_target(request)
            if not self.current(publication):
                raise RevisionChanged('Page manifest stale')
            value = self.native.envelope(request, schemaVersion=1,
                capability=CAPABILITY, publicationID=self.incarnation,
                sequence=publication.sequence, inputFingerprint=publication.fingerprint,
                htmlInputFingerprint=publication.snapshot.inputs,
                pdfInputFingerprint=publication.pdf_dependencies,
                pdfSHA256=publication.digest, byteCount=len(publication.data),
                resource=f'api/native-pages/{self.incarnation}/{publication.sequence}.pdf',
                sourceAnchors='unsupported', delivery='immutable-pdf-full-reset')
            return json.dumps(value, separators=(',', ':')).encode()

    def resource(self, query, identifier):
        with self.state.lock:
            request = self.query(query)
            publication = self.accepted
            if (publication is None or identifier != f'{self.incarnation}/{publication.sequence}.pdf'
                    or publication.snapshot.revision != request['revision']
                    or not self.current(publication)):
                raise RevisionChanged('Page resource stale')
            if hashlib.sha256(publication.data).hexdigest() != publication.digest:
                raise ValueError('Page resource corrupted')
            return publication.data
