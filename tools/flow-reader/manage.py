#!/usr/bin/env python3
"""Run Reader services from existing Flow project profiles, independently of PDF."""

from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
from urllib.parse import urlsplit

HERE = Path(__file__).resolve().parent
DEFAULT_DATA = Path.home() / "Library/Application Support/tinymist-flow/reader"
LABEL_PREFIX = "io.github.kimpossible-ty.tinymist-flow.reader."


def run(arguments, *, check=True):
    result = subprocess.run(list(map(str, arguments)), text=True, capture_output=True, timeout=20)
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


class ReaderManager:
    def __init__(self, data=None, agents=None):
        self.data = Path(data or os.environ.get("FLOW_READER_DATA_DIR", DEFAULT_DATA)).resolve()
        self.agents = Path(agents or Path.home() / "Library/LaunchAgents")
        self.launcher = self.data / "bin/flow-reader"

    @contextmanager
    def locked(self):
        self.data.mkdir(parents=True, exist_ok=True)
        with (self.data / "control.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            yield

    def config(self):
        config = json.loads((self.data / "config.json").read_text())
        if config.get("schemaVersion") != 1 or not isinstance(config.get("services"), list):
            raise ValueError("Unsupported reader configuration")
        for key in ("flowManager", "python", "compiler"):
            path = Path(config.get(key, ""))
            if not path.is_absolute() or not os.access(path, os.X_OK):
                raise ValueError(f"Missing executable: {key}")
        return config

    def profiles(self):
        config = self.config()
        parents = json.loads(run([config["flowManager"], "--profiles"]))["profiles"]
        by_id = {profile["id"]: profile for profile in parents}
        ids, ports, result = set(by_id), {profile["port"] for profile in parents}, []
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
            profile = {**parent, "id": identifier, "parentID": parent_id,
                       "name": parent["name"] + " · Reader", "port": port,
                       "label": LABEL_PREFIX + identifier, "publicURL": url,
                       "originalURL": parent.get("publicURL") or f"http://127.0.0.1:{parent['port']}/",
                       "development": bool(service.get("development", False))}
            result.append(profile)
            ids.add(identifier)
            ports.add(port)
        return result

    def profile(self, identifier):
        return next((profile for profile in self.profiles() if profile["id"] == identifier), None)

    def arguments(self, profile):
        config = self.config()
        root = Path(profile["root"])
        entry = root / profile["entry"]
        if not entry.resolve().is_relative_to(root.resolve()) or not entry.is_file():
            raise ValueError("The Flow entrypoint must exist inside its project root")
        if not Path(profile["packages"]).is_dir():
            raise ValueError("The Flow package directory does not exist")
        arguments = [config["python"], str(HERE / "serve.py"), "--root", str(root),
                     "--entry", profile["entry"], "--package-path", profile["packages"],
                     "--compiler", config["compiler"], "--output", str(self.data / "documents" / profile["id"]),
                     "--original-url", profile["originalURL"], "--port", str(profile["port"]), "--watch"]
        for font in profile["fonts"]:
            if not (root / font).exists():
                raise ValueError("A configured Flow font directory is missing")
            arguments.extend(["--font-path", font])
        if profile["development"]:
            arguments.append("--allow-incomplete")
        return arguments

    def agent(self, profile):
        return {"Label": profile["label"], "ProgramArguments": [str(self.launcher), "--serve", profile["id"]],
                "AssociatedBundleIdentifiers": ["io.github.kimpossible-ty.tinymist-flow"],
                "WorkingDirectory": str(self.data), "RunAtLoad": True, "KeepAlive": True,
                "ThrottleInterval": 10, "ProcessType": "Interactive",
                "EnvironmentVariables": {"FLOW_READER_DATA_DIR": str(self.data), "PYTHONDONTWRITEBYTECODE": "1"},
                "StandardOutPath": str(self.data / "logs" / (profile["id"] + ".out.log")),
                "StandardErrorPath": str(self.data / "logs" / (profile["id"] + ".err.log"))}

    def job_pid(self, profile):
        status = run(["/bin/launchctl", "print", f"gui/{os.getuid()}/{profile['label']}"], check=False)
        match = re.search(r"(?m)^\s*pid = (\d+)\s*$", status)
        return int(match[1]) if match else None

    def owns_agent(self, profile):
        path = self.agents / (profile["label"] + ".plist")
        if not path.exists():
            return False
        agent = plistlib.loads(path.read_bytes())
        return agent.get("ProgramArguments") == self.agent(profile)["ProgramArguments"]

    def control(self, action, profile):
        if action not in {"start", "stop", "restart"}:
            raise ValueError("Expected start, stop, or restart")
        with self.locked():
            target = f"gui/{os.getuid()}/{profile['label']}"
            path = self.agents / (profile["label"] + ".plist")
            pid = self.job_pid(profile)
            if (path.exists() or pid) and not self.owns_agent(profile):
                raise ValueError("The reader will not replace a LaunchAgent it does not own")
            if action == "stop":
                run(["/bin/launchctl", "disable", target])
                run(["/bin/launchctl", "bootout", target], check=False)
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
            run(["/bin/launchctl", "enable", target])
            for attempt in range(5):
                try:
                    run(["/bin/launchctl", "bootstrap", f"gui/{os.getuid()}", path])
                    return
                except ValueError:
                    if attempt == 4:
                        raise
                    time.sleep(.3)


def main(argv=None):
    arguments = sys.argv[1:] if argv is None else argv
    manager = ReaderManager()
    if arguments == ["--profiles"]:
        print(json.dumps({"schemaVersion": 1, "profiles": manager.profiles()}))
        return
    if not arguments or len(arguments) not in {2, 3}:
        raise ValueError("Commands: --profiles, --launch-plan ID, --agent-plist ID, --status ID, --serve ID, --control start|stop|restart ID")
    profile = manager.profile(arguments[-1])
    if profile is None:
        raise ValueError("Unknown reader profile")
    action = arguments[0]
    if len(arguments) != (3 if action == "--control" else 2):
        raise ValueError("Unexpected reader command arguments")
    if action == "--launch-plan":
        print(json.dumps({"arguments": manager.arguments(profile), "agent": manager.agent(profile)}))
    elif action == "--agent-plist":
        sys.stdout.buffer.write(plistlib.dumps(manager.agent(profile)))
    elif action == "--status":
        pid = manager.job_pid(profile)
        print(json.dumps({"id": profile["id"], "running": pid is not None, "pid": pid,
                          "label": profile["label"], "managedByApp": manager.owns_agent(profile),
                          "url": profile["publicURL"] or f"http://127.0.0.1:{profile['port']}/"}))
    elif action == "--serve":
        command = manager.arguments(profile)
        os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
        os.execv(command[0], command)
    elif action == "--control" and len(arguments) == 3:
        manager.control(arguments[1], profile)
    else:
        raise ValueError("Unknown reader command")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
