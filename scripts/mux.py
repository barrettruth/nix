#!/usr/bin/env python

import os
import shlex
import shutil
import subprocess
import sys
import time
from collections.abc import Sequence
from dataclasses import dataclass
from functools import lru_cache
from typing import Literal

HOME = os.path.expanduser("~")

ManagedKind = Literal["role", "action"]
PickerMode = Literal["open", "proj"]


class MuxError(Exception):
    pass


@dataclass(frozen=True)
class ManagedCommandSpec:
    name: str
    kind: ManagedKind
    key: str
    always_visible: bool = False
    ephemeral: bool = False


def fail(message: str, code: int = 1) -> None:
    _ = sys.stderr.write(f"{message}\n")
    raise SystemExit(code)


def ensure_command(command: str) -> None:
    if shutil.which(command) is None:
        fail(f"mux: missing dependency: {command}")


def run(
    args: Sequence[str],
    *,
    check: bool = True,
    capture: bool = False,
    env: dict[str, str] | None = None,
    input_text: str | None = None,
    stderr: int | None = None,
) -> subprocess.CompletedProcess[str]:
    if capture:
        return subprocess.run(
            list(args),
            check=check,
            text=True,
            env=env,
            input=input_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE if stderr is None else stderr,
        )
    if stderr is not None:
        return subprocess.run(
            list(args),
            check=check,
            text=True,
            env=env,
            input=input_text,
            stderr=stderr,
        )
    return subprocess.run(
        list(args),
        check=check,
        text=True,
        env=env,
        input=input_text,
    )


def maybe_output(
    args: Sequence[str],
    *,
    env: dict[str, str] | None = None,
    stderr: int | None = None,
) -> str:
    result = subprocess.run(
        list(args),
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL if stderr is None else stderr,
        env=env,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.rstrip("\n")


def tmux(
    *args: str, check: bool = True, capture: bool = False, stderr: int | None = None
) -> subprocess.CompletedProcess[str]:
    return run(["tmux", *args], check=check, capture=capture, stderr=stderr)


def tmux_output(*args: str, stderr: int | None = None) -> str:
    return run(["tmux", *args], capture=True, stderr=stderr).stdout.rstrip("\n")


def git_ok(path: str, *args: str) -> bool:
    return (
        subprocess.run(
            ["git", "-C", path, *args],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
        ).returncode
        == 0
    )


def base_name(path: str) -> str:
    stripped = path.rstrip("/") or "/"
    return "/" if stripped == "/" else os.path.basename(stripped)


def display_path_parts(path: str) -> tuple[str, ...]:
    normalized = os.path.normpath(path)
    if normalized == HOME:
        return ("~",)
    home_prefix = f"{HOME}{os.sep}"
    if normalized.startswith(home_prefix):
        relative = normalized.removeprefix(home_prefix)
        return ("~", *(part for part in relative.split(os.sep) if part))
    parts = tuple(part for part in normalized.split(os.sep) if part)
    return ("/", *parts) if normalized.startswith(os.sep) else parts


def project_context_parts(path: str) -> tuple[str, ...]:
    parts = display_path_parts(path)
    return parts[:-1] or parts


def format_path_parts(parts: Sequence[str]) -> str:
    if not parts:
        return ""
    if parts[0] == "~":
        return "~" if len(parts) == 1 else f"~/{'/'.join(parts[1:])}"
    if parts[0] == "/":
        return "/" if len(parts) == 1 else f"/{'/'.join(parts[1:])}"
    return "/".join(parts)


def project_name_contexts(paths: Sequence[str]) -> dict[str, str]:
    if len(paths) < 2:
        return {}
    contexts = {path: project_context_parts(path) for path in paths}
    max_depth = max(len(parts) for parts in contexts.values())
    for depth in range(1, max_depth + 1):
        suffixes = {
            path: parts[-depth:] if len(parts) >= depth else parts
            for path, parts in contexts.items()
        }
        if len(set(suffixes.values())) == len(paths):
            return {
                path: format_path_parts(parts)
                for path, parts in suffixes.items()
            }
    return {path: format_path_parts(parts) for path, parts in contexts.items()}


def quote_sh(value: str) -> str:
    return shlex.quote(value)


def canonical_name(name: str) -> str:
    match name:
        case "code":
            return "edit"
        case "shell":
            return "prompt"
        case _:
            return name


@lru_cache(maxsize=1)
def managed_commands() -> tuple[ManagedCommandSpec, ...]:
    commands = (
        ManagedCommandSpec("ai", "role", "a", always_visible=True, ephemeral=True),
        ManagedCommandSpec("edit", "role", "e", always_visible=True, ephemeral=True),
        ManagedCommandSpec("prompt", "role", "p", always_visible=True),
        ManagedCommandSpec("git", "action", "g", always_visible=True, ephemeral=True),
        ManagedCommandSpec("run", "action", "r", ephemeral=True),
        ManagedCommandSpec("build", "action", "b"),
        ManagedCommandSpec("test", "action", "t"),
    )
    names: set[str] = set()
    keys: set[str] = set()
    for command in commands:
        if len(command.key) != 1 or not command.key.islower():
            raise ValueError(f"mux: bad key '{command.key}' for '{command.name}'")
        if command.name in names:
            raise ValueError(f"mux: duplicate command '{command.name}'")
        if command.key in keys:
            raise ValueError(f"mux: duplicate key '{command.key}'")
        names.add(command.name)
        keys.add(command.key)
    return commands


def command_for_name(name: str) -> ManagedCommandSpec | None:
    resolved = canonical_name(name)
    for command in managed_commands():
        if command.name == resolved:
            return command
    return None


def managed_just_action_names() -> tuple[str, ...]:
    return tuple(
        command.name
        for command in managed_commands()
        if command.kind == "action" and not command.always_visible
    )


def tmux_key(letter: str) -> str:
    return f"C-{letter}"


def fzf_key(letter: str) -> str:
    return f"ctrl-{letter}"


def display_key(letter: str) -> str:
    return f"^{letter.upper()}"


@lru_cache(maxsize=None)
def justfile_path(path: str) -> str:
    for name in ("Justfile", "justfile", ".justfile"):
        justfile = os.path.join(path, name)
        if os.path.isfile(justfile):
            return justfile
    return ""


@lru_cache(maxsize=None)
def just_recipes_for_path(path: str) -> frozenset[str]:
    if shutil.which("just") is None:
        return frozenset()
    if not (justfile := justfile_path(path)):
        return frozenset()
    if not (
        summary := maybe_output(
            ["just", "--justfile", justfile, "--working-directory", path, "--summary"]
        )
    ):
        return frozenset()
    return frozenset(summary.split())


def visible_commands_for_path(path: str) -> list[ManagedCommandSpec]:
    recipes = just_recipes_for_path(path)
    return [
        command
        for command in managed_commands()
        if command.always_visible or command.name in recipes
    ]


def current_path() -> str:
    return pane_path()


def scope_from_path(path: str) -> str:
    return "~" if path == HOME else base_name(path)


def run_in_path(path: str, command: str) -> str:
    return "" if not command else f"cd {quote_sh(path)} && {command}"


def shell_path() -> str:
    return os.environ.get("SHELL", "/bin/sh")


def initial_shell_command(channel: str = "") -> str:
    shell = shell_path()
    if channel:
        return f"exec env MUX_READY_CHANNEL={quote_sh(channel)} {quote_sh(shell)} -i"
    return f"exec {quote_sh(shell)} -i"


def new_ready_channel() -> str:
    return f"mux-ready-{os.getpid()}-{time.time_ns()}"


def window_name_for(name: str, scope: str) -> str:
    return f"{name}@{scope}"


def window_index_for_name(name: str) -> str:
    lines = maybe_output(
        ["tmux", "list-windows", "-F", "#{window_name}\t#{window_index}"]
    )
    for line in lines.splitlines():
        window_name, _, index = line.partition("\t")
        if window_name == name:
            return index
    return ""


def current_window_index() -> str:
    return tmux_output("display-message", "-p", "#{window_index}")


def pane_path(target: str | None = None) -> str:
    args = ["display-message"]
    if target:
        args.extend(["-t", target])
    args.extend(["-p", "#{pane_current_path}"])
    return tmux_output(*args)


def pane_command(target: str | None = None) -> str:
    args = ["display-message"]
    if target:
        args.extend(["-t", target])
    args.extend(["-p", "#{pane_current_command}"])
    return tmux_output(*args)


def command_for_pane(target: str | None, path: str, command: str) -> str:
    return command if pane_path(target) == path else run_in_path(path, command)


def send_keys(target: str | None, *keys: str) -> None:
    args = ["send-keys"]
    if target:
        args.extend(["-t", target])
    args.extend(keys)
    _ = tmux(*args)


def send_cmd(target: str | None, path: str, command: str) -> None:
    send_keys(target, "C-u", "C-l", command_for_pane(target, path, command), "Enter")


def schedule_initial_cmd(target: str, command: str, channel: str = "") -> None:
    if channel:
        payload = f"tmux wait-for {quote_sh(channel)}; tmux send-keys -t {quote_sh(target)} {quote_sh(command)} Enter"
    else:
        payload = f"tmux send-keys -t {quote_sh(target)} {quote_sh(command)} Enter"
    _ = tmux("run-shell", "-b", payload)


def new_window_info(window_name: str, path: str, command: str) -> tuple[str, str]:
    args = [
        "new-window",
        "-P",
        "-F",
        "#{window_index}\t#{pane_id}",
        "-c",
        path,
        "-n",
        window_name,
    ]
    if command:
        args.append(command)
    info = tmux_output(*args)
    index, _, pane_id = info.partition("\t")
    return index, pane_id


def is_adoptable() -> bool:
    shell = base_name(shell_path())
    name = tmux_output("display-message", "-p", "#{window_name}")
    command = pane_command()
    panes = int(tmux_output("display-message", "-p", "#{window_panes}") or "0")
    return panes == 1 and command == shell and name == shell


def is_pane_idle(target: str | None = None) -> bool:
    return pane_command(target) == base_name(shell_path())


def spawn_or_focus_managed(
    name: str, path: str, command: str = "", *, ephemeral: bool = False
) -> None:
    scope = scope_from_path(path)
    window_name = window_name_for(name, scope)
    index = window_index_for_name(window_name)
    current_index = current_window_index()

    if index and index == current_index:
        if command and not ephemeral and is_pane_idle():
            send_cmd(None, path, command)
        return

    if is_adoptable():
        if index:
            _ = tmux("kill-window", "-t", f":{index}")
        _ = tmux("rename-window", window_name)
        if command:
            send_cmd(None, path, f"exec {command}" if ephemeral else command)
        return

    if index:
        _ = tmux("select-window", "-t", f":{index}")
        if command and not ephemeral and is_pane_idle(f":{index}"):
            send_cmd(f":{index}", path, command)
        return

    if command:
        if ephemeral:
            _ = new_window_info(window_name, path, command)
            return
        channel = new_ready_channel()
        _, pane_id = new_window_info(window_name, path, initial_shell_command(channel))
        schedule_initial_cmd(pane_id, command, channel)
        return

    _ = new_window_info(window_name, path, "")


def role_command_for(name: str) -> str | None:
    match canonical_name(name):
        case "ai":
            return "codex"
        case "edit":
            return "nvim ."
        case "prompt":
            return ""
        case _:
            return None


def ensure_role_dependencies(name: str) -> None:
    match canonical_name(name):
        case "ai":
            ensure_command("codex")
        case "edit":
            ensure_command("nvim")
        case _:
            return


def action_command_for_root(name: str, root: str) -> str | None:
    name = canonical_name(name)
    match name:
        case "git":
            return 'nvim -c "Git|only"'
        case action if action in managed_just_action_names():
            if not justfile_path(root):
                return None
            if action not in just_recipes_for_path(root):
                return None
            return f"just {quote_sh(action)}"
        case _:
            return None


def usage_error(message: str) -> int:
    _ = sys.stderr.write(f"mux: {message}\n")
    return 1


def open_managed(name: str) -> int:
    if not (command := command_for_name(name)):
        return usage_error(f"unknown command: {name}")
    if command.kind == "role":
        return open_role(command.name)
    return open_action(command.name)


def open_role(name: str) -> int:
    try:
        open_role_in_dir(name, current_path())
    except MuxError as exc:
        _ = tmux("display-message", str(exc))
        return 1
    return 0


def open_role_in_dir(name: str, path: str) -> None:
    name = canonical_name(name)
    if not (role := command_for_name(name)) or role.kind != "role":
        raise MuxError(f"mux: unknown role '{name}'")
    ensure_role_dependencies(name)
    if (command := role_command_for(name)) is None:
        raise MuxError(f"mux: unknown role '{name}'")
    spawn_or_focus_managed(name, path, command, ephemeral=role.ephemeral)


def open_action(name: str) -> int:
    try:
        open_action_in_dir(name, current_path())
    except MuxError as exc:
        _ = tmux("display-message", str(exc))
        return 1
    return 0


def open_action_in_dir(name: str, path: str) -> None:
    name = canonical_name(name)
    if not (action := command_for_name(name)) or action.kind != "action":
        raise MuxError(f"mux: no action '{name}' for '{scope_from_path(path)}'")
    scope = scope_from_path(path)
    if name == "git" and not git_ok(path, "rev-parse", "--is-inside-work-tree"):
        raise MuxError("Not a git repository")
    if (command := action_command_for_root(name, path)) is None:
        raise MuxError(f"mux: no action '{name}' for '{scope}'")
    spawn_or_focus_managed(name, path, command, ephemeral=action.ephemeral)


def color_escape(hex_code: str) -> str:
    code = hex_code.lstrip("#")
    return f"\033[38;2;{int(code[0:2], 16)};{int(code[2:4], 16)};{int(code[4:6], 16)}m"


def tmux_color(option: str, default: str) -> str:
    return maybe_output(["tmux", "show", "-gv", option]).replace("#", "") or default


def picker_prompt(mode: PickerMode) -> str:
    return f"@{scope_from_path(current_path())}> " if mode == "open" else "open> "


def picker_header_commands(mode: PickerMode) -> list[ManagedCommandSpec]:
    if mode == "open":
        return visible_commands_for_path(current_path())
    return [command for command in managed_commands() if command.always_visible]


def picker_bind_commands(mode: PickerMode) -> list[ManagedCommandSpec]:
    if mode == "open":
        return picker_header_commands(mode)
    return list(managed_commands())


def picker_header(mode: PickerMode) -> str:
    accent = color_escape(tmux_color("@accent", "7aa2f7"))
    reset = "\033[0m"
    parts = [
        f"{accent}{display_key(command.key)}{reset} {command.name}"
        for command in picker_header_commands(mode)
    ]
    match mode:
        case "open":
            parts.append(f"{accent}^O{reset} projects")
        case _:
            parts.append(f"{accent}^O{reset} windows")
    return f":: {' '.join(parts)}"


def format_open_entry(label: str, token: str, window_name: str = "") -> str:
    accent = color_escape(tmux_color("@accent", "7aa2f7"))
    reset = "\033[0m"
    if window_name and window_index_for_name(window_name):
        return f"{accent}{label}{reset}\t{token}"
    return f"{label}{reset}\t{token}"


def format_project_entry(
    label: str, token: str, *, context: str = "", is_current: bool = False
) -> str:
    accent = color_escape(tmux_color("@accent", "7aa2f7"))
    muted = color_escape(tmux_color("@fgAlt", "666666"))
    reset = "\033[0m"
    prefix = f"{accent}{label}{reset}" if is_current else label
    suffix = f" {muted}· {context}{reset}" if context else ""
    return f"{prefix}{suffix}\t{token}"


def list_open_entries() -> str:
    path = current_path()
    scope = scope_from_path(path)
    lines: list[str] = []
    for command in visible_commands_for_path(path):
        if command.kind == "role":
            lines.append(
                format_open_entry(
                    command.name,
                    f"role:{command.name}",
                    window_name_for(command.name, scope),
                )
            )
            continue
        lines.append(
            format_open_entry(
                command.name,
                f"action:{command.name}",
                window_name_for(command.name, scope),
            )
        )
    return "\n".join(lines) + ("\n" if lines else "")


def list_project_entries() -> str:
    if not (projects := maybe_output(["zoxide", "query", "-l"])):
        return ""
    path = current_path()
    directories: list[str] = []
    for directory in projects.splitlines():
        if not directory:
            continue
        if (
            maybe_output(["git", "-C", directory, "rev-parse", "--show-toplevel"])
            != directory
        ):
            continue
        directories.append(directory)
    lines = [
        format_project_entry(
            format_path_parts(display_path_parts(directory)),
            f"proj:{directory}",
            is_current=directory == path,
        )
        for directory in directories
    ]
    return "\n".join(lines) + ("\n" if lines else "")


def picker_list(mode: PickerMode) -> str:
    return list_open_entries() if mode == "open" else list_project_entries()


def picker_mode_from_arg(mode: str) -> PickerMode | None:
    match mode:
        case "open" | "proj":
            return mode
        case _:
            return None


def dispatch_picker_action(value: str) -> int:
    mode, _, rest = value.partition(":")
    match mode:
        case "role":
            return open_role(rest)
        case "action":
            return open_action(rest)
        case "proj":
            try:
                open_role_in_dir("edit", rest)
            except MuxError as exc:
                _ = tmux("display-message", str(exc))
                return 1
            return 0
        case _:
            return 0


def picker_open_target(mode: PickerMode, kind: str, name: str, input_value: str) -> int:
    if mode == "open":
        match kind:
            case "role":
                return open_role(name)
            case "action":
                return open_action(name)
            case _:
                return 0
    submode, _, directory = input_value.partition(":")
    if submode != "proj":
        return 0
    match kind:
        case "role":
            try:
                open_role_in_dir(name, directory)
            except MuxError as exc:
                _ = tmux("display-message", str(exc))
                return 1
            return 0
        case "action":
            try:
                open_action_in_dir(name, directory)
            except MuxError as exc:
                _ = tmux("display-message", str(exc))
                return 1
            return 0
        case _:
            return 0


def show_picker(mode: PickerMode = "open") -> int:
    ensure_command("fzf")
    accent = tmux_color("@accent", "7aa2f7")
    fgalt = tmux_color("@fgAlt", "666666")
    toggle_command = "projects" if mode == "open" else "open"
    header = picker_header(mode)
    command = [
        "fzf",
        "--reverse",
        "--ansi",
        "--no-info",
        "--no-scrollbar",
        "--header",
        header,
        "--prompt",
        picker_prompt(mode),
        "--pointer",
        "▌",
        "--color",
        f"header:#{fgalt},prompt:#{accent},separator:#{fgalt}",
        "--separator",
        "",
        "--delimiter",
        "\t",
        "--with-nth",
        "1",
        "--accept-nth",
        "2",
        "--bind",
        f"ctrl-o:become(mux {toggle_command})",
        "--bind",
        "enter:become(mux _dispatch {2})",
    ]
    for managed in picker_bind_commands(mode):
        command.extend(
            [
                "--bind",
                (
                    f"{fzf_key(managed.key)}:become("
                    f"mux _picker_open {mode} {managed.kind} {managed.name} {{2}})"
                ),
            ]
        )
    return subprocess.run(
        command, input=picker_list(mode), text=True, env=os.environ.copy(), check=False
    ).returncode


def session_key(index: int, total: int) -> str:
    match index:
        case 0:
            return "H"
        case 1:
            return "J"
        case 2:
            return "K"
        case 3:
            return "L"
        case _:
            return "$" if index == total - 1 else "?"


def render_bar() -> int:
    sessions = maybe_output(["tmux", "ls", "-F", "#{session_name}"])
    parts: list[str] = []
    lines = [line for line in sessions.splitlines() if line]
    total = len(lines)
    for index, session_name in enumerate(lines):
        key = session_key(index, total)
        star = f"#{{?#{{==:#S,{session_name}}},#[fg=#{{@accent}}]*#[default],}}"
        parts.append(f"{star}{key}#[fg=#{{@accent}}]:#[default]{session_name}")
    bar_content = " ".join(parts)
    plain_content = " ".join(
        f"{session_key(index, total)}:{session_name}"
        for index, session_name in enumerate(lines)
    )
    status_right_length = max(80, len(plain_content) + 1)
    _ = tmux("set", "-g", "status-left-length", "80")
    _ = tmux("set", "-g", "status-right-length", str(status_right_length))
    _ = tmux("set", "-g", "status-left", " ")
    _ = tmux(
        "set",
        "-g",
        "window-status-format",
        "#{?window_last_flag,#[fg=#{@accent}]-#[default],}#{window_index}#[fg=#{@accent}]:#[default]#{window_name}",
    )
    _ = tmux(
        "set",
        "-g",
        "window-status-current-format",
        "#[fg=#{@accent}]*#[default]#{window_index}#[fg=#{@accent}]:#[default]#{window_name}",
    )
    _ = tmux("set", "-g", "window-status-separator", " ")
    _ = tmux("set", "-g", "@bar-content", f"{bar_content} ")
    return 0


def current_session_windows() -> list[str]:
    session_id = maybe_output(["tmux", "display-message", "-p", "#{session_id}"])
    args = ["tmux", "list-windows", "-F", "#{window_id}"]
    if session_id:
        args.extend(["-t", session_id])
    return [line for line in maybe_output(args).splitlines() if line]


def set_bar_border(pane_border_status: str) -> None:
    for window_id in current_session_windows():
        _ = tmux(
            "set-window-option",
            "-t",
            window_id,
            "pane-border-status",
            pane_border_status,
        )


def sync_bar_border() -> int:
    status = maybe_output(["tmux", "display-message", "-p", "#{status}"])
    set_bar_border("off" if status == "off" else "bottom")
    return 0


def toggle_bar() -> int:
    status = maybe_output(["tmux", "display-message", "-p", "#{status}"])
    if status == "off":
        _ = tmux("set", "status", "on")
        set_bar_border("bottom")
        _ = render_bar()
    else:
        set_bar_border("off")
        _ = tmux("refresh-client", "-S", check=False)
        _ = tmux("set", "status", "off")
        _ = render_bar()
    _ = tmux("refresh-client", "-S", check=False)
    return 0


def apply_managed_binds() -> int:
    for command in managed_commands():
        key = tmux_key(command.key)
        _ = tmux(
            "unbind-key",
            "-T",
            "prefix",
            key,
            check=False,
            stderr=subprocess.DEVNULL,
        )
        _ = tmux("bind-key", "-T", "prefix", key, "run", f"mux {command.name}")
    return 0


def switch_session(slot: str) -> int:
    sessions = [
        line for line in maybe_output(["tmux", "ls", "-F", "#S"]).splitlines() if line
    ]
    try:
        session = sessions[int(slot)]
    except (ValueError, IndexError):
        return 1
    _ = tmux("switch", "-t", session)
    return 0


def attach_or_new_session() -> int:
    if (
        subprocess.run(
            ["tmux", "attach"], check=False, stderr=subprocess.DEVNULL
        ).returncode
        == 0
    ):
        return 0
    return subprocess.run(["tmux", "new-session"], check=False).returncode


def main(argv: list[str]) -> int:
    ensure_command("tmux")

    match argv:
        case []:
            return attach_or_new_session()
        case ["bar"]:
            return render_bar()
        case ["toggle-bar"]:
            return toggle_bar()
        case ["sync-bar-border"]:
            return sync_bar_border()
        case ["_apply_binds"]:
            return apply_managed_binds()
        case ["switch", slot]:
            return switch_session(slot)
        case ["role", name]:
            return open_role(name)
        case ["action", name]:
            return open_action(name)
        case [name] if command_for_name(name):
            return open_managed(name)
        case ["run", name]:
            return open_action(name)
        case ["open"]:
            return show_picker("open")
        case ["projects"]:
            return show_picker("proj")
        case ["_dispatch", value]:
            return dispatch_picker_action(value)
        case ["_picker_open", mode, kind, name, value]:
            if not (picker_mode := picker_mode_from_arg(mode)):
                return usage_error("_picker_open requires mode open or proj")
            return picker_open_target(picker_mode, kind, name, value)
        case ["switch"]:
            return usage_error("switch requires a slot")
        case ["role"]:
            return usage_error("role requires a name")
        case ["action"]:
            return usage_error("action requires a name")
        case ["_dispatch"]:
            return usage_error("_dispatch requires a value")
        case ["_picker_open"] | ["_picker_open", _] | ["_picker_open", _, _] | ["_picker_open", _, _, _]:
            return usage_error("_picker_open requires mode, kind, name, and value")
        case [command, *_]:
            return usage_error(f"unknown command: {command}")
        case _:
            pass

    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
