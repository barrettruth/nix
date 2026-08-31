#!/usr/bin/env python3

from __future__ import annotations

import argparse
import fcntl
import json
import math
import os
import re
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Literal, NotRequired, TypedDict, cast

Backend = Literal["codex", "devin"]


class RecoveryError(Exception):
    pass


class ProcessDetails(TypedDict):
    pid: int
    ppid: int
    state: str
    start_ticks: int
    executable: str
    cwd: str | None
    tty: str | None
    args: list[str]
    command: str


class StatusResult(TypedDict):
    ok: bool
    backend: Backend
    session_id: str
    lock: str
    status: Literal["in_use", "available"]
    holder: ProcessDetails | None
    resume: str


class ReleaseResult(TypedDict):
    ok: bool
    backend: Backend
    session_id: str
    lock: str
    action: str
    resume: str
    pid: NotRequired[int]
    signal: NotRequired[Literal["TERM", "KILL"]]
    holder: NotRequired[ProcessDetails]


class Arguments(argparse.Namespace):
    command: Literal["status", "release", "resume"] = "status"
    session_id: str = ""
    json: bool = False
    timeout: float = 5.0


Result = StatusResult | ReleaseResult


def data_home() -> Path:
    value = os.environ.get("XDG_DATA_HOME")
    return Path(value).expanduser() if value else Path.home() / ".local" / "share"


def codex_home() -> Path:
    value = os.environ.get("CODEX_HOME")
    return Path(value).expanduser() if value else Path.home() / ".codex"


def validate_session_id(session_id: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", session_id):
        raise RecoveryError(f"invalid session ID: {session_id!r}")


def devin_lock_path(session_id: str) -> Path:
    validate_session_id(session_id)
    return data_home() / "devin" / "cli" / "session_locks" / f"{session_id}.lock"


def codex_lock_path(session_id: str) -> Path:
    validate_session_id(session_id)
    return codex_home() / "thread-writer-locks" / f"{session_id}.lock"


def backend_for(session_id: str) -> Backend:
    devin_path = devin_lock_path(session_id)
    codex_path = codex_lock_path(session_id)
    devin_exists = devin_path.exists()
    codex_exists = codex_path.exists()
    if devin_exists and codex_exists:
        raise RecoveryError(
            f"session ID {session_id!r} has both Devin and Codex lock files"
        )
    if codex_exists:
        return "codex"
    if devin_exists:
        return "devin"
    if re.fullmatch(
        r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
        session_id,
    ):
        return "codex"
    return "devin"


def lock_path(session_id: str, backend: Backend) -> Path:
    if backend == "codex":
        return codex_lock_path(session_id)
    return devin_lock_path(session_id)


def lock_is_held(path: Path) -> bool:
    try:
        descriptor = os.open(path, os.O_RDONLY)
    except FileNotFoundError:
        return False
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        return False
    finally:
        os.close(descriptor)


DARWIN = sys.platform == "darwin"


def command_output(command: list[str]) -> str:
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=5.0, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout


def ps_output(pid: int, fields: str) -> str:
    return command_output(["ps", "-o", fields, "-p", str(pid)]).strip()


def darwin_stat(pid: int) -> tuple[int, int, str]:
    value = ps_output(pid, "ppid=,stat=,lstart=")
    if not value:
        raise RecoveryError(f"process {pid} no longer exists")
    fields = value.split(maxsplit=2)
    if len(fields) < 3:
        raise RecoveryError(f"cannot parse process state for PID {pid}")
    try:
        started = time.strptime(fields[2].strip(), "%a %b %d %H:%M:%S %Y")
        return int(fields[0]), int(time.mktime(started)), fields[1]
    except (OverflowError, ValueError):
        raise RecoveryError(f"cannot parse process state for PID {pid}") from None


def proc_stat(pid: int) -> tuple[int, int, str]:
    if DARWIN:
        return darwin_stat(pid)
    try:
        value = Path(f"/proc/{pid}/stat").read_text()
    except (FileNotFoundError, ProcessLookupError):
        raise RecoveryError(f"process {pid} no longer exists") from None
    close = value.rfind(")")
    if close < 0:
        raise RecoveryError(f"cannot parse process state for PID {pid}")
    fields = value[close + 2 :].split()
    if len(fields) < 20:
        raise RecoveryError(f"cannot parse process state for PID {pid}")
    return int(fields[1]), int(fields[19]), fields[0]


def process_executable(pid: int) -> str:
    if DARWIN:
        return ps_output(pid, "comm=")
    try:
        value = os.readlink(f"/proc/{pid}/exe")
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return ""
    return value.removesuffix(" (deleted)")


def process_is_devin(pid: int) -> bool:
    return Path(process_executable(pid)).name == "devin"


def process_is_codex(pid: int) -> bool:
    return Path(process_executable(pid)).name in {"codex", ".codex-wrapped"}


def process_is_backend(pid: int, backend: Backend) -> bool:
    if backend == "codex":
        return process_is_codex(pid)
    return process_is_devin(pid)


def darwin_holds(pid: int, path: Path) -> bool:
    output = command_output(["lsof", "-t", "--", str(path)])
    for line in output.split():
        try:
            if int(line) == pid:
                return True
        except ValueError:
            continue
    return False


def process_holds(pid: int, path: Path) -> bool:
    if DARWIN:
        return darwin_holds(pid, path)
    directory = Path(f"/proc/{pid}/fd")
    try:
        descriptors = list(directory.iterdir())
    except (FileNotFoundError, PermissionError):
        return False
    for descriptor in descriptors:
        try:
            if os.path.samefile(descriptor, path):
                return True
        except (FileNotFoundError, PermissionError, OSError):
            continue
    return False


def processes_with_open_file(path: Path) -> set[int]:
    if DARWIN:
        result: set[int] = set()
        for line in command_output(["lsof", "-t", "--", str(path)]).split():
            try:
                result.add(int(line))
            except ValueError:
                continue
        return result
    result = set()
    for directory in Path("/proc").glob("[0-9]*/fd"):
        try:
            pid = int(directory.parent.name)
        except ValueError:
            continue
        if process_holds(pid, path):
            result.add(pid)
    return result


def read_link(path: str) -> str | None:
    try:
        return os.readlink(path)
    except (FileNotFoundError, PermissionError, OSError):
        return None


def process_args(pid: int) -> list[str]:
    if DARWIN:
        value = command_output(["ps", "-ww", "-o", "args=", "-p", str(pid)]).strip()
        if not value:
            return []
        try:
            return shlex.split(value)
        except ValueError:
            return value.split()
    try:
        command = Path(f"/proc/{pid}/cmdline").read_bytes().rstrip(b"\0").split(b"\0")
    except (FileNotFoundError, PermissionError, OSError):
        command = []
    return [item.decode(errors="replace") for item in command]


def process_cwd(pid: int) -> str | None:
    if DARWIN:
        output = command_output(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"])
        for line in output.splitlines():
            if line.startswith("n"):
                return line[1:]
        return None
    return read_link(f"/proc/{pid}/cwd")


def process_tty(pid: int) -> str | None:
    if DARWIN:
        value = ps_output(pid, "tty=")
        return f"/dev/{value}" if value and value != "??" else None
    return read_link(f"/proc/{pid}/fd/0")


def process_details(pid: int) -> ProcessDetails:
    ppid, started, state = proc_stat(pid)
    args = process_args(pid)
    return {
        "pid": pid,
        "ppid": ppid,
        "state": state,
        "start_ticks": started,
        "executable": process_executable(pid),
        "cwd": process_cwd(pid),
        "tty": process_tty(pid),
        "args": args,
        "command": shlex.join(args),
    }


def devin_lock_holder(path: Path) -> ProcessDetails | None:
    for _ in range(3):
        if not lock_is_held(path):
            return None
        try:
            raw_pid = path.read_text().strip()
            pid = int(raw_pid)
        except FileNotFoundError:
            return None
        except (ValueError, OSError):
            time.sleep(0.05)
            continue
        if pid > 1 and process_is_devin(pid) and process_holds(pid, path):
            try:
                return process_details(pid)
            except RecoveryError:
                pass
        time.sleep(0.05)
    if not lock_is_held(path):
        return None
    raise RecoveryError(
        f"{path} is locked, but its recorded PID is not a validated Devin lock holder"
    )


def codex_lock_holder(path: Path) -> ProcessDetails | None:
    for _ in range(3):
        if not lock_is_held(path):
            return None
        pids = {
            pid
            for pid in processes_with_open_file(path)
            if pid > 1 and process_is_codex(pid) and process_holds(pid, path)
        }
        if len(pids) == 1:
            try:
                return process_details(pids.pop())
            except RecoveryError:
                pass
        elif len(pids) > 1:
            values = ", ".join(str(pid) for pid in sorted(pids))
            raise RecoveryError(
                f"{path} has multiple validated Codex processes with the lock file open: {values}"
            )
        time.sleep(0.05)
    if not lock_is_held(path):
        return None
    raise RecoveryError(
        f"{path} is locked, but its holder is not a validated Codex process"
    )


def lock_holder(path: Path, backend: Backend) -> ProcessDetails | None:
    if backend == "codex":
        return codex_lock_holder(path)
    return devin_lock_holder(path)


def ancestor_pids() -> set[int]:
    result: set[int] = set()
    pid = os.getpid()
    while pid > 1 and pid not in result:
        result.add(pid)
        try:
            pid = proc_stat(pid)[0]
        except RecoveryError:
            break
    return result


def has_backend_ancestor(backend: Backend) -> bool:
    return any(
        process_is_backend(pid, backend)
        for pid in ancestor_pids()
        if pid != os.getpid()
    )


def same_process(pid: int, started: int) -> bool:
    try:
        return proc_stat(pid)[1] == started
    except RecoveryError:
        return False


def wait_for_release(path: Path, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not lock_is_held(path):
            return True
        time.sleep(0.05)
    return not lock_is_held(path)


def status(session_id: str) -> StatusResult:
    backend = backend_for(session_id)
    path = lock_path(session_id, backend)
    holder = lock_holder(path, backend)
    return {
        "ok": True,
        "backend": backend,
        "session_id": session_id,
        "lock": str(path),
        "status": "in_use" if holder else "available",
        "holder": holder,
        "resume": f"/resume {session_id}",
    }


def release(session_id: str, timeout: float) -> ReleaseResult:
    if not math.isfinite(timeout) or timeout < 0:
        raise RecoveryError("timeout must be a finite non-negative number")
    backend = backend_for(session_id)
    path = lock_path(session_id, backend)
    holder = lock_holder(path, backend)
    if holder is None:
        return {
            "ok": True,
            "backend": backend,
            "session_id": session_id,
            "lock": str(path),
            "action": "already_available",
            "resume": f"/resume {session_id}",
        }
    pid = holder["pid"]
    started = holder["start_ticks"]
    if pid in ancestor_pids():
        raise RecoveryError(
            f"refusing to terminate PID {pid}: it is the {backend.capitalize()} session executing this recovery"
        )
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        if wait_for_release(path, 1.0):
            return {
                "ok": True,
                "backend": backend,
                "session_id": session_id,
                "lock": str(path),
                "action": "released_during_recovery",
                "pid": pid,
                "resume": f"/resume {session_id}",
            }
        raise RecoveryError(f"PID {pid} exited, but {path} is still locked") from None
    except PermissionError:
        raise RecoveryError(
            f"permission denied while sending TERM to PID {pid}"
        ) from None
    escalated = False
    if not wait_for_release(path, timeout):
        current = lock_holder(path, backend)
        if current is None:
            pass
        elif current["pid"] != pid or not same_process(pid, started):
            raise RecoveryError(
                f"a different process acquired {path}; refusing to send another signal"
            )
        else:
            try:
                os.kill(pid, signal.SIGKILL)
                escalated = True
            except ProcessLookupError:
                pass
            except PermissionError:
                raise RecoveryError(
                    f"permission denied while sending KILL to PID {pid}"
                ) from None
            if not wait_for_release(path, 2.0):
                raise RecoveryError(f"PID {pid} did not release {path} after KILL")
    return {
        "ok": True,
        "backend": backend,
        "session_id": session_id,
        "lock": str(path),
        "action": "terminated",
        "pid": pid,
        "signal": "KILL" if escalated else "TERM",
        "holder": holder,
        "resume": f"/resume {session_id}",
    }


def emit(result: Result, as_json: bool) -> None:
    if as_json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return
    if "status" in result:
        print(f"{result['session_id']} ({result['backend']}): {result['status']}")
        holder = result.get("holder")
        if holder:
            print(f"holder: PID {holder['pid']} {holder['command']}")
        return
    print(f"{result['session_id']} ({result['backend']}): {result['action']}")
    pid = result.get("pid")
    if pid is not None:
        print(f"holder: PID {pid} via {result.get('signal', 'none')}")
    print(result["resume"])


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="recover")
    commands = value.add_subparsers(dest="command", required=True)
    for name in ("status", "release", "resume"):
        command = commands.add_parser(name)
        _ = command.add_argument("session_id")
        _ = command.add_argument("--json", action="store_true")
        if name in ("release", "resume"):
            _ = command.add_argument("--timeout", type=float, default=5.0)
    return value


def arguments() -> Arguments:
    return cast(Arguments, parser().parse_args())


def main() -> int:
    args = arguments()
    try:
        if args.command == "status":
            emit(status(args.session_id), args.json)
            return 0
        if args.command == "release":
            emit(release(args.session_id, args.timeout), args.json)
            return 0
        backend = backend_for(args.session_id)
        if has_backend_ancestor(backend):
            raise RecoveryError(
                f"automatic resume cannot replace a running {backend.capitalize()} CLI; use `recover release {args.session_id}` and then `/resume {args.session_id}`"
            )
        result = release(args.session_id, args.timeout)
        if args.json:
            emit(result, True)
        else:
            print(f"{args.session_id}: {result['action']}; resuming", flush=True)
        if backend == "codex":
            os.execvp("codex", ["codex", "resume", args.session_id])
        os.execvp("devin", ["devin", "--resume", args.session_id])
    except RecoveryError as error:
        result = {"ok": False, "error": str(error)}
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            print(f"recover: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
