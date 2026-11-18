#!/usr/bin/env python3
"""Run Reader services from existing Flow project profiles, independently of PDF."""

from contextlib import contextmanager
from dataclasses import dataclass
import fcntl
import json
import hashlib
import math
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
import stat
import unicodedata
from urllib.parse import urlsplit
from urllib.request import Request, HTTPRedirectHandler, build_opener

from flow_reader.resources import READER_ROOT as HERE
from flow_reader.compiler.project import document_identity
from flow_reader.services.editor_sync import EditorAttachments, NativeEditorOperation
DEFAULT_DATA = Path.home() / "Library/Application Support/Lagrangian/reader"
LABEL_PREFIX = "io.github.kimpossible-ty.lagrangian.reader."
LEGACY_LABEL_PREFIX = "io.github.kimpossible-ty.tinymist-flow.reader."


class NoReaderRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        return None


def run(arguments, *, check=True, timeout=20):
    result = subprocess.run(list(map(str, arguments)), text=True, capture_output=True, timeout=timeout)
    if check and result.returncode:
        raise ValueError(result.stderr.strip() or result.stdout.strip() or "Command failed")
    return result.stdout


def atomic_write(path, content, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    try:
        with temporary.open("xb") as stream:
            os.chmod(temporary, mode)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


@dataclass(frozen=True)
class ReaderExecutables:
    """Concrete local operations supplied by a verified host, never config or HTTP."""
    python: str
    compiler: str
    flow_manager: str
    engine: str
    manager: str


class ReaderManager:
    def __init__(self, data=None, agents=None, *, executables=None):
        self.data = Path(data or os.environ.get("FLOW_READER_DATA_DIR", DEFAULT_DATA)).resolve()
        self.agents = Path(agents or Path.home() / "Library/LaunchAgents")
        self.executables = executables
        self.installed_launcher = self.data / "bin/flow-reader"
        self.launcher = Path(executables.manager) if executables is not None else self.installed_launcher

    @contextmanager
    def locked(self, *, timeout=0):
        self.data.mkdir(parents=True, exist_ok=True)
        with (self.data / "control.lock").open("a") as lock:
            deadline = time.monotonic() + timeout if timeout else None
            while True:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if deadline is None or time.monotonic() >= deadline:
                        raise
                    time.sleep(.02)
            yield

    def config(self):
        config = json.loads((self.data / "config.json").read_text())
        if config.get("schemaVersion") != 1 or not isinstance(config.get("services"), list):
            raise ValueError("Unsupported reader configuration")
        if self.executables is not None:
            # Keep schema/path declarations valid without consulting unused external
            # executables. Only these concrete operations can be substituted.
            for key in ("flowManager", "python", "compiler"):
                if not isinstance(config.get(key), str) or not Path(config[key]).is_absolute():
                    raise ValueError(f"Missing executable: {key}")
            if config.get("engine") and (not isinstance(config["engine"], str)
                                         or not Path(config["engine"]).is_absolute()):
                raise ValueError("Missing executable: engine")
            config = {**config, "flowManager": self.executables.flow_manager,
                      "python": self.executables.python, "compiler": self.executables.compiler,
                      "engine": self.executables.engine}
            if not self.launcher.is_absolute() or not os.access(self.launcher, os.X_OK):
                raise ValueError("Missing executable: reader manager")
        for key in ("flowManager", "python", "compiler"):
            path = Path(config.get(key, ""))
            if not path.is_absolute() or not os.access(path, os.X_OK):
                raise ValueError(f"Missing executable: {key}")
        if config.get("engine") and (not Path(config["engine"]).is_absolute()
                                     or not os.access(config["engine"], os.X_OK)):
            raise ValueError("Missing executable: engine")
        return config

    def shared_settings(self):
        shared = self.config().get("shared")
        if shared is None:
            return None
        if not isinstance(shared, dict):
            raise ValueError("Invalid shared Reader configuration")
        port = shared.get("port", 8769)
        proxy_port = shared.get("proxyPort")
        from flow_reader.services.homepage import public_reader_url
        public = shared.get("publicURL")
        if (type(port) is not int or not 1024 <= port <= 65535
                or bool(public) != (proxy_port is not None)
                or (public and not public_reader_url(public))
                or (proxy_port is not None and (not public or type(proxy_port) is not int
                    or not 1024 <= proxy_port <= 65535 or proxy_port == port))):
            raise ValueError("Invalid shared Reader ports or HTTPS origin")
        return {**shared, "port": port, "publicURL": public or "", "proxyPort": proxy_port}

    @staticmethod
    def document_url(profile, *, public=False):
        from flow_reader.services.homepage import document_prefix
        origin = profile.get("publicURL") if public else f"http://127.0.0.1:{profile['port']}/"
        if not origin:
            return None
        return origin.rstrip("/") + (document_prefix(profile["id"]) if profile.get("shared") else "/")

    def parent_profiles(self):
        """Read configured parents without a launch plan or lifecycle operation."""
        config = self.config()
        parents = json.loads(run([config["flowManager"], "--profiles"]))["profiles"]
        if not isinstance(parents, list):
            raise ValueError("Invalid Flow profiles")
        return parents

    def profiles(self):
        config = self.config()
        parents = self.parent_profiles()
        by_id = {profile["id"]: profile for profile in parents}
        ids, ports, result = set(by_id), {profile["port"] for profile in parents}, []
        focus_files = {str(Path(p["focusFile"]).resolve()) for p in parents if p.get("focusFile")}
        change_files = {}
        for service in config["services"]:
            identifier, parent_id = service.get("id"), service.get("parentID")
            if not isinstance(identifier, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", identifier) or identifier in ids:
                raise ValueError("Invalid or duplicate reader ID")
            if parent_id not in by_id:
                raise ValueError(f"Missing Flow parent profile: {parent_id}")
            port = service.get("port")
            if type(port) is not int or not 1024 <= port <= 65535 or port in ports:
                raise ValueError("Reader port conflicts with an existing Flow service")
            url = service.get("publicURL", "")
            if url:
                parsed = urlsplit(url)
                if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
                        or parsed.path not in {"", "/"} or parsed.query or parsed.fragment):
                    raise ValueError("Reader public URL must be an HTTPS origin")
            parent = by_id[parent_id]
            focus_file = Path(service.get("focusFile", str(self.data / "documents" / identifier / "focus.json")))
            if not focus_file.is_absolute() or str(focus_file.resolve()) in focus_files:
                raise ValueError("Reader focusFile must be absolute and separate from other services")
            focus_files.add(str(focus_file.resolve()))
            semantic_canvases = service.get("semanticCanvases", False)
            if type(semantic_canvases) is not bool:
                raise ValueError("Reader semanticCanvases must be a boolean")
            extra_fonts = service.get("extraFonts", [])
            if (not isinstance(extra_fonts, list) or len(extra_fonts) > 32
                    or any(not isinstance(font, str) or not font.strip() for font in extra_fonts)):
                raise ValueError("Reader extraFonts must contain at most 32 font paths")
            if parent_id not in change_files:
                plan = json.loads(run([config["flowManager"], "--launch-plan", parent_id]))
                if not isinstance(plan, dict) or ("environment" in plan and not isinstance(plan["environment"], dict)):
                    raise ValueError("Invalid Flow parent launch plan")
                environment = plan.get("environment", {})
                change_file = environment.get("TINYMIST_PREVIEW_CHANGE_FILE")
                if "TINYMIST_PREVIEW_CHANGE_FILE" in environment:
                    if not isinstance(change_file, str) or not Path(change_file).is_absolute():
                        raise ValueError("Flow parent changeFile must be absolute")
                    change_file = str(Path(change_file).resolve())
                change_files[parent_id] = change_file
            profile = {**parent, "id": identifier, "parentID": parent_id,
                       "name": parent["name"] + " · Reader", "port": port,
                       "focusFile": str(focus_file.resolve()),
                       "label": self.reader_label(identifier), "publicURL": url,
                       "originalURL": parent.get("publicURL") or f"http://127.0.0.1:{parent['port']}/",
                       "development": bool(service.get("development", False)),
                       "semanticCanvases": semantic_canvases,
                       "fonts": list(dict.fromkeys([*parent["fonts"], *extra_fonts]))}
            if change_files[parent_id]:
                profile["changeFile"] = change_files[parent_id]
            result.append(profile)
            ids.add(identifier)
            ports.add(port)
        shared = self.shared_settings()
        if shared:
            occupied = ports
            if shared["port"] in occupied or shared["proxyPort"] in occupied:
                raise ValueError("Shared Reader ports conflict with existing document ports")
            for profile in result:
                profile.update(legacyPort=profile["port"], legacyPublicURL=profile["publicURL"],
                               port=shared["port"], publicURL=shared["publicURL"], shared=True,
                               label=LABEL_PREFIX + "shared")
        return result

    def reader_label(self, identifier):
        """Retain a legacy launchd identity only when its persisted job exists."""
        legacy = self.agents / (LEGACY_LABEL_PREFIX + identifier + ".plist")
        prefix = LEGACY_LABEL_PREFIX if legacy.exists() else LABEL_PREFIX
        return prefix + identifier

    def profile(self, identifier):
        return next((profile for profile in self.profiles() if profile["id"] == identifier), None)

    def server_arguments(self, arguments):
        config = self.config()
        prefix = ([str(self.launcher), "--backend"] if self.executables is not None
                  else [config["python"], str(HERE / "serve.py")])
        return [*prefix, *arguments]

    def arguments(self, profile):
        if profile.get("shared"):
            self.document_arguments(profile)
            return self.server_arguments(["--managed", "--data", str(self.data)])
        return self.document_arguments(profile)

    def document_arguments(self, profile):
        """The existing per-document compiler plan, also used inside a shared host."""
        config = self.config()
        root = Path(profile["root"])
        entry = root / profile["entry"]
        if not entry.resolve().is_relative_to(root.resolve()) or not entry.is_file():
            raise ValueError("The Flow entrypoint must exist inside its project root")
        if not Path(profile["packages"]).is_dir():
            raise ValueError("The Flow package directory does not exist")
        arguments = self.server_arguments(["--root", str(root),
                     "--entry", profile["entry"], "--package-path", profile["packages"],
                     "--compiler", config["compiler"], "--output", str(self.data / "documents" / profile["id"]),
                     "--focus-file", profile["focusFile"],
                     "--original-url", profile["originalURL"], "--port", str(profile["port"]), "--watch"])
        if config.get("homepageURL"):
            from flow_reader.services.homepage import reader_url
            homepage = reader_url(config["homepageURL"])
            if not homepage:
                raise ValueError("Invalid Homepage origin")
            arguments.extend(["--homepage-url", homepage])
        engine = config.get("engine") or os.environ.get("FLOW_ENGINE_PATH")
        if profile.get("publicURL"):
            arguments.extend(["--public-url", profile["publicURL"]])
        if not engine:
            sibling = Path(config["flowManager"]).parent / "flow-engine"
            if os.access(sibling, os.X_OK):
                engine = str(sibling)
        if engine:
            arguments.extend(["--engine", engine])
        if config.get("browserCompiler"):
            directory = Path(config["browserCompiler"])
            if not (directory / "manifest.json").is_file():
                raise ValueError("The configured browser compiler is missing")
            arguments.extend(["--browser-compiler", str(directory)])
        if profile.get("changeFile"):
            arguments.extend(["--change-file", profile["changeFile"]])
        for font in profile["fonts"]:
            if not (root / font).exists():
                raise ValueError("A configured Flow font directory is missing")
            arguments.extend(["--font-path", font])
        if profile["development"]:
            arguments.append("--allow-incomplete")
        if profile.get("semanticCanvases"):
            arguments.append("--semantic-canvases")
        return arguments

    @staticmethod
    def _document_paths(root, entry, *, withdrawal=False):
        """Resolved spelling plus real scope/type, not an inode-only alias grant."""
        root = Path(root).resolve(strict=not withdrawal)
        entry = (root / entry).resolve(strict=not withdrawal)
        canonical = lambda path: Path(unicodedata.normalize("NFC", str(path)))
        canonical(entry).relative_to(canonical(root))
        root_info = root.stat() if root.exists() else None
        entry_info = entry.stat() if entry.exists() else None
        if ((root_info and not stat.S_ISDIR(root_info.st_mode))
                or (entry_info and not stat.S_ISREG(entry_info.st_mode))):
            raise ValueError("Managed document requires a directory and regular entry")
        if not withdrawal and (root_info is None or entry_info is None):
            raise ValueError("Managed document is missing")
        if root_info is not None and entry_info is not None:
            # Unicode spelling of the absolute entry may differ from root.
            # Verify the real directory at the canonical prefix boundary too.
            boundary = Path(*entry.parts[:len(root.parts)]).stat()
            if (boundary.st_dev, boundary.st_ino) != (root_info.st_dev, root_info.st_ino):
                raise ValueError("Entry is outside its actual project directory")
        return root, entry, root_info, entry_info

    def _match_document(self, root, entry, identifier=None, *, withdrawal=False):
        try:
            supplied = self._document_paths(root, entry, withdrawal=withdrawal)
        except (OSError, ValueError, RuntimeError) as error:
            raise ValueError("No managed HTML Reader matches this project and entry") from error
        matches = []
        for profile in self.profiles():
            if identifier is not None and profile["id"] != identifier:
                continue
            try:
                registered = self._document_paths(profile["root"], profile["entry"], withdrawal=withdrawal)
            except (OSError, ValueError, RuntimeError):
                continue
            if any(unicodedata.normalize("NFC", str(a)) != unicodedata.normalize("NFC", str(b))
                   for a, b in zip(supplied[:2], registered[:2])):
                continue
            # Missing-path spelling may select only a withdrawal, never attach,
            # descriptor publication or source authority. Existing paths must
            # still identify exactly the same actual directory and file.
            if any(a is not None and b is not None and
                   (a.st_dev, a.st_ino) != (b.st_dev, b.st_ino)
                   for a, b in zip(supplied[2:], registered[2:])):
                continue
            matches.append(profile)
        if not matches:
            raise ValueError("No managed HTML Reader matches this project and entry; configure its HTML profile first")
        if len(matches) != 1:
            raise ValueError("Multiple HTML Readers match this document; select --reader-service ID")
        return matches[0]

    def match_document(self, root, entry, identifier=None):
        return self._match_document(root, entry, identifier)

    @staticmethod
    def request(url, path, payload=None, *, timeout=2):
        request = Request(url + path, None if payload is None else json.dumps(payload).encode(),
                          {"Content-Type": "application/json"})
        with build_opener(NoReaderRedirect).open(request, timeout=timeout) as response:
            return json.loads(response.read(1024 * 1024))

    @staticmethod
    def operation_request(root, entry, identifier=None):
        # Stable lexical caller binding, not a new attach/source authority.
        # Do NOT consult current symlinks during operation withdrawal.
        # Prefix relative roots without reducing dot components: link/.. has
        # filesystem semantics which abspath/normpath would silently change.
        original_root = os.fspath(root)
        if not os.path.isabs(original_root): original_root = os.path.join(os.getcwd(), original_root)
        canonical = lambda p: unicodedata.normalize("NFC", p)
        return canonical(original_root), canonical(os.path.join(original_root, entry)), identifier

    @staticmethod
    def native_scope_identity(profile):
        return hashlib.sha256(json.dumps([profile["id"], document_identity(profile["root"], profile["entry"])],
                                         separators=(",", ":")).encode()).hexdigest()

    def native_scope(self, root, entry, identifier=None):
        request = self.operation_request(root, entry, identifier)
        request_binding = hashlib.sha256(json.dumps(request, separators=(",", ":")).encode()).hexdigest()
        try: profile = self.match_document(root, entry, identifier)
        except ValueError: return {"scope": None, "requestBinding": request_binding}
        return {"scope": self.native_scope_identity(profile), "requestBinding": request_binding}

    def native_operation(self, root, entry, operation, identifier=None):
        # Binding may survive missing/retargeted aliases. Actual document binding
        # is captured separately ONLY after normal registered-path validation.
        return NativeEditorOperation(self.data, operation, *self.operation_request(root, entry, identifier))

    def release_native_operation(self, root, entry, operation, identifier=None, deadline=None):
        owner = self.native_operation(root, entry, operation, identifier)
        if deadline is not None and (type(deadline) not in {int, float} or not math.isfinite(deadline)):
            raise ValueError("Invalid native cleanup deadline")
        budget = 2 if deadline is None else min(2, deadline - time.time() - .2)
        if budget <= 0: raise ValueError("Native cleanup deadline expired")
        with self.locked(timeout=budget):
            return {"released": owner.cancel()}

    def attach(self, root, entry, *, identifier=None, editor_server=None, nvim="nvim",
               owner_pid=None, control_file=None, native_editor_consent=False,
               native_editor_operation=None, native_editor_deadline=None, native_editor_expected_scope=None):
        """Reuse the normal HTML lifecycle/plan; never start a presentation-owned compiler."""
        if native_editor_consent:
            # Only the explicit local native composition opts in. HTTP has no
            # registration route, executable/address input or default-editor grant.
            if not editor_server or not Path(nvim).is_absolute() or not control_file:
                raise ValueError("Explicit native editor configuration is required")
            EditorAttachments.private(Path(control_file))
        if native_editor_expected_scope is not None:
            if (native_editor_operation is None or not isinstance(native_editor_expected_scope, str)
                    or not re.fullmatch(r"[0-9a-f]{64}", native_editor_expected_scope)):
                raise ValueError("Invalid expected native editor scope")
        profile = dict(self.match_document(root, entry, identifier))
        issuance_scope = self.native_scope_identity(profile) if native_editor_operation is not None else None
        if native_editor_expected_scope is not None and issuance_scope != native_editor_expected_scope:
            raise ValueError("Managed native editor scope changed before issuance")
        operation = None
        if native_editor_operation is not None:
            if not native_editor_consent:
                raise ValueError("Native operation requires explicit movement consent")
            operation = self.native_operation(root, entry, native_editor_operation, identifier)
            expected_document = document_identity(profile["root"], profile["entry"])
            with self.locked(timeout=1):
                actual_root, actual_entry, _, _ = self._document_paths(profile["root"], profile["entry"])
                if self.native_scope_identity(profile) != issuance_scope:
                    raise ValueError("Managed native editor scope changed before reservation")
                operation.reserve(profile["id"], expected_document, native_editor_deadline,
                    document_root=unicodedata.normalize("NFC", str(actual_root)),
                    document_entry=unicodedata.normalize("NFC", str(actual_entry)))
        elif native_editor_deadline is not None:
            raise ValueError("Native deadline requires an operation")
        def remaining():
            if operation is None: return 2
            return max(.001, min(2, operation.current()["deadline"] - time.time()))
        def file_identity():
            _, _, root_info, file_info = self._document_paths(profile["root"], profile["entry"])
            return (root_info.st_dev, root_info.st_ino, file_info.st_dev, file_info.st_ino,
                    file_info.st_size, file_info.st_mtime_ns, file_info.st_ctime_ns)
        original_file = file_identity() if operation else None
        def current_profile():
            current = self.match_document(root, entry, identifier)
            if current != profile or file_identity() != original_file or self.native_scope_identity(current) != issuance_scope:
                raise ValueError("Managed document/profile changed during native preparation")
            return current
        if self.job_pid(profile) is None:
            self.control("start", profile)
        url = self.document_url(profile)
        expected_document = document_identity(profile["root"], profile["entry"])
        deadline = time.monotonic() + (max(0, native_editor_deadline - time.time()) if operation else 15)
        while True:
            pid = self.job_pid(profile)
            try:
                state = self.request(url, "api/state", timeout=remaining()) if operation else self.request(url, "api/state")
                break
            except (OSError, ValueError):
                if time.monotonic() >= deadline:
                    raise ValueError("The managed HTML Reader did not become reachable") from None
                time.sleep(.1)
        if not isinstance(state, dict):
            raise ValueError("Invalid managed HTML Reader response")
        service = state.get("service")
        if (not pid or not isinstance(service, dict) or service.get("pid") != pid
                or type(service.get("startedAt")) is not int or state.get("documentID") != expected_document):
            raise ValueError("The HTML Reader port does not match the managed process and document")
        plan = {"url": url, "documentID": expected_document, "service": service}
        if editor_server:
            if state.get("editorAttachments") != 1:
                raise ValueError("The installed HTML Reader needs an upgrade for shared editor attachments; no separate Reader was started")
            attachments = EditorAttachments(self.data / "documents" / profile["id"], expected_document, service)
            with self.locked(timeout=2):
                if operation:
                    operation.current(); current_profile()
                token, path = attachments.register(editor_server, nvim, owner_pid, control_file,
                                                   jump_only=native_editor_consent, operation=operation)
            try:
                acknowledgment = (self.request(url, "api/editor-attachment", {"token": token}, timeout=remaining()) if operation
                                  else self.request(url, "api/editor-attachment", {"token": token}))
                if acknowledgment.get("connected") is not True:
                    raise ValueError("The HTML Reader rejected the editor attachment")
                if operation:
                    latest = self.request(url, "api/state", timeout=remaining())
                    if latest.get("service") != service or latest.get("documentID") != expected_document:
                        raise ValueError("Managed service incarnation changed during native preparation")
                    with self.locked(timeout=min(1, remaining())):
                        current_profile()
                        if self.job_pid(profile) != pid:
                            raise ValueError("Managed service changed during native preparation")
                        operation.issued()
            except BaseException:
                if operation:
                    with self.locked(timeout=1): operation.cancel()
                else: path.unlink(missing_ok=True)
                raise
            plan.update(editorAttachment=token, attachmentFile=str(path))
            if native_editor_consent:
                plan["nativeEditorActions"] = 1
            if operation:
                plan["nativeEditorOperation"] = operation.identifier
                plan["nativeEditorScope"] = issuance_scope
        return plan

    def native_editor_local(self, root, entry, token, *, identifier=None, descriptor=False):
        # These local-only operations neither probe/start a service nor accept an
        # arbitrary filesystem path. The token is the exact manager-issued lease.
        profile = self._match_document(root, entry, identifier, withdrawal=not descriptor)
        output = self.data / "documents" / profile["id"]
        with self.locked(timeout=2):
            if not descriptor and not (Path(profile["root"]) / profile["entry"]).is_file():
                # Source may have been renamed/deleted since this exact lease
                # was issued. Read only its bounded private local record, then
                # delegate retirement to the attachment owner. This documentID
                # is not an attachment/descriptor/source authorization proof.
                if not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{64}", token):
                    raise ValueError("Invalid native attachment token")
                directory = output / "editor-attachments"
                if not directory.exists():
                    return {"released": False}
                EditorAttachments.private(directory, directory=True)
                path = directory / (token + ".json")
                if not path.exists():
                    return {"released": False}
                EditorAttachments.private(path)
                if path.stat().st_size > 16384:
                    raise ValueError("Native registration exceeds its bound")
                document = json.loads(path.read_text()).get("documentID")
                if not isinstance(document, str) or not re.fullmatch(r"[0-9a-f]{24}", document):
                    raise ValueError("Invalid retired document identity")
            else:
                document = document_identity(profile["root"], profile["entry"])
            attachments = EditorAttachments(output, document, {})
            if not descriptor:
                return {"released": attachments.release_native(token)}
            # record() needs the original service identity only as data; it still
            # validates private storage, live owner, executable and control file.
            value = attachments.descriptor(token)
            directory = self.data / "native-editor-descriptors"
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            EditorAttachments.private(directory, directory=True)
            path = directory / (token + ".json")
            if path.exists():
                EditorAttachments.private(path)
                if json.loads(path.read_text()) != value:
                    raise ValueError("Preserve an existing different editor descriptor")
            else:
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, "w") as stream:
                    json.dump(value, stream)
            return {"descriptorFile": str(path)}

    def agent(self, profile):
        return {"Label": profile["label"], "ProgramArguments": ([str(self.launcher), "--serve-all"] if profile.get("shared")
                                      else [str(self.launcher), "--serve", profile["id"]]),
                "AssociatedBundleIdentifiers": ["io.github.kimpossible-ty.lagrangian"],
                "WorkingDirectory": str(self.data), "RunAtLoad": True, "KeepAlive": True,
                "ThrottleInterval": 10, "ProcessType": "Interactive",
                "EnvironmentVariables": {"FLOW_READER_DATA_DIR": str(self.data), "PYTHONDONTWRITEBYTECODE": "1"},
                "StandardOutPath": str(self.data / "logs" / (("shared" if profile.get("shared") else profile["id"]) + ".out.log")),
                "StandardErrorPath": str(self.data / "logs" / (("shared" if profile.get("shared") else profile["id"]) + ".err.log"))}

    def job_pid(self, profile, *, timeout=20):
        status = run(["/bin/launchctl", "print", f"gui/{os.getuid()}/{profile['label']}"], check=False, timeout=timeout)
        match = re.search(r"(?m)^\s*pid = (\d+)\s*$", status)
        return int(match[1]) if match else None

    def owns_agent(self, profile):
        path = self.agents / (profile["label"] + ".plist")
        if not path.exists():
            return False
        agent = plistlib.loads(path.read_bytes())
        arguments = agent.get("ProgramArguments") if isinstance(agent, dict) else None
        expected = self.agent(profile)["ProgramArguments"]
        if (not isinstance(arguments, list) or len(arguments) != len(expected)
                or arguments[1:] != expected[1:] or not isinstance(arguments[0], str)):
            return False
        # Preserve recognition of this same manager's installed launcher during
        # explicit host substitution; unrelated executables/documents still reject.
        launchers = [self.launcher, self.installed_launcher] if self.executables is not None else [self.launcher]
        if arguments[0] in [str(path) for path in launchers]:
            return True
        try:
            return any(Path(arguments[0]).resolve() == path.resolve() for path in launchers)
        except (OSError, RuntimeError):
            return False

    def wait_unloaded(self, target):
        # bootout can return while launchd still reports the terminating job.
        # A following start must not mistake that old PID for a running Reader.
        deadline = time.monotonic() + 10
        while run(["/bin/launchctl", "print", target], check=False).strip():
            if time.monotonic() >= deadline:
                raise ValueError("The Reader job has not finished stopping")
            time.sleep(.1)

    def control(self, action, profile):
        if action not in {"start", "stop", "restart", "stop-shared", "restart-shared"}:
            raise ValueError("Expected start, stop, restart, stop-shared, or restart-shared")
        if action.endswith("-shared"):
            if not profile.get("shared"):
                raise ValueError("Shared-job control requires a shared Reader profile")
            action = action.removesuffix("-shared")
        elif profile.get("shared") and action in {"stop", "restart"}:
            raise ValueError(f"Cannot {action} one document: this affects the shared Reader job and all documents; use --control {action}-shared {profile['id']} explicitly")
        with self.locked():
            target = f"gui/{os.getuid()}/{profile['label']}"
            path = self.agents / (profile["label"] + ".plist")
            pid = self.job_pid(profile)
            if (path.exists() or pid) and not self.owns_agent(profile):
                raise ValueError("The reader will not replace a LaunchAgent it does not own")
            if action == "stop":
                run(["/bin/launchctl", "disable", target])
                run(["/bin/launchctl", "bootout", target], check=False)
                self.wait_unloaded(target)
                return
            self.arguments(profile)
            owners = run(["/usr/sbin/lsof", "-nP", f"-iTCP:{profile['port']}", "-sTCP:LISTEN", "-t"], check=False)
            owner_ids = {int(value) for value in owners.split()}
            if owner_ids and owner_ids != {pid}:
                raise ValueError("Another process owns the reader port")
            if action == "start" and pid:
                return
            (self.data / "logs").mkdir(parents=True, exist_ok=True)
            atomic_write(path, plistlib.dumps(self.agent(profile)))
            run(["/bin/launchctl", "bootout", target], check=False)
            self.wait_unloaded(target)
            run(["/bin/launchctl", "enable", target])
            for attempt in range(5):
                try:
                    run(["/bin/launchctl", "bootstrap", f"gui/{os.getuid()}", path])
                    return
                except ValueError:
                    if attempt == 4:
                        raise
                    time.sleep(.3)


def main(argv=None, *, manager=None):
    arguments = sys.argv[1:] if argv is None else argv
    manager = manager if manager is not None else ReaderManager()
    if arguments == ["--serve-all"]:
        command = manager.server_arguments(["--managed", "--data", str(manager.data)])
        os.execv(command[0], command)
        return
    if arguments[:1] == ["--native-editor-scope"]:
        import argparse
        parser = argparse.ArgumentParser(description="Read exact native document/registered reader scope; no service effects")
        parser.add_argument("--root", required=True); parser.add_argument("--entry", default="main.typ")
        parser.add_argument("--reader-service"); parser.add_argument("--native-editor-deadline", type=float)
        options = parser.parse_args(arguments[1:])
        if options.native_editor_deadline is not None and (not math.isfinite(options.native_editor_deadline) or options.native_editor_deadline <= time.time()):
            raise ValueError("Native scope query deadline expired")
        print(json.dumps(manager.native_scope(options.root, options.entry, options.reader_service)))
        return
    if arguments[:1] == ["--release-native-editor-operation"]:
        import argparse
        parser = argparse.ArgumentParser(description="Withdraw exact local native operation")
        parser.add_argument("--root", required=True)
        parser.add_argument("--entry", default="main.typ")
        parser.add_argument("--reader-service")
        parser.add_argument("--native-editor-operation", required=True)
        parser.add_argument("--native-editor-deadline", type=float)
        options = parser.parse_args(arguments[1:])
        print(json.dumps(manager.release_native_operation(options.root, options.entry,
            options.native_editor_operation, options.reader_service, options.native_editor_deadline)))
        return
    if arguments[:1] in (["--release-native-editor"], ["--native-editor-descriptor"]):
        import argparse
        parser = argparse.ArgumentParser(description="Own local editor registration lifetime")
        parser.add_argument("--root", required=True)
        parser.add_argument("--entry", default="main.typ")
        parser.add_argument("--reader-service")
        parser.add_argument("--token", required=True)
        options = parser.parse_args(arguments[1:])
        print(json.dumps(manager.native_editor_local(options.root, options.entry, options.token,
            identifier=options.reader_service, descriptor=arguments[0] == "--native-editor-descriptor")))
        return
    if arguments[:1] == ["--attach"]:
        import argparse
        parser = argparse.ArgumentParser(description="Attach presentation to the managed HTML Reader")
        parser.add_argument("--root", required=True)
        parser.add_argument("--entry", default="main.typ")
        parser.add_argument("--reader-service")
        parser.add_argument("--editor-server")
        parser.add_argument("--nvim", default="nvim")
        parser.add_argument("--owner-pid", type=int)
        parser.add_argument("--control-file")
        parser.add_argument("--native-editor-consent", action="store_true")
        parser.add_argument("--native-editor-operation")
        parser.add_argument("--native-editor-expected-scope")
        parser.add_argument("--native-editor-deadline", type=float)
        options = parser.parse_args(arguments[1:])
        print(json.dumps(manager.attach(options.root, options.entry, identifier=options.reader_service,
                                       editor_server=options.editor_server, nvim=options.nvim,
                                       owner_pid=options.owner_pid, control_file=options.control_file,
                                       native_editor_consent=options.native_editor_consent,
                                       native_editor_operation=options.native_editor_operation,
                                       native_editor_deadline=options.native_editor_deadline,
                                       native_editor_expected_scope=options.native_editor_expected_scope)))
        return
    if arguments == ["--profiles"]:
        print(json.dumps({"schemaVersion": 1, "profiles": manager.profiles()}))
        return
    if not arguments or len(arguments) not in {2, 3}:
        raise ValueError("Commands: --profiles, --focus ID, --launch-plan ID, --agent-plist ID, --status ID, --serve ID, --control start|stop|restart|stop-shared|restart-shared ID")
    profile = manager.profile(arguments[-1])
    if profile is None:
        raise ValueError("Unknown reader profile")
    action = arguments[0]
    if len(arguments) != (3 if action == "--control" else 2):
        raise ValueError("Unexpected reader command arguments")
    if action == "--focus":
        from flow_reader.services.codex_context import read_reader
        pid = manager.job_pid(profile)
        if pid is None:
            print(json.dumps({"status": "not_ready", "service_matches": False,
                              "selection_usable": False, "needs_reselection": True}))
        else:
            print(json.dumps(read_reader(manager.document_url(profile), expected_pid=pid,
                                        project=profile["root"],
                                        document=Path(profile["root"]) / profile["entry"]), ensure_ascii=False))
    elif action == "--launch-plan":
        print(json.dumps({"arguments": manager.arguments(profile), "agent": manager.agent(profile)}))
    elif action == "--agent-plist":
        sys.stdout.buffer.write(plistlib.dumps(manager.agent(profile)))
    elif action == "--status":
        pid = manager.job_pid(profile)
        print(json.dumps({"id": profile["id"], "running": pid is not None, "pid": pid,
                          "label": profile["label"], "managedByApp": manager.owns_agent(profile),
                          "url": manager.document_url(profile, public=True) or manager.document_url(profile)}))
    elif action == "--serve":
        command = manager.arguments(profile)
        os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
        os.execv(command[0], command)
    elif action == "--control" and len(arguments) == 3:
        manager.control(arguments[1], profile)
    else:
        raise ValueError("Unknown reader command")


def cli(argv=None, *, manager=None):
    """Preserve the supported command's concise error and exit-code contract."""
    try:
        main(argv, manager=manager)
        return 0
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(cli())
