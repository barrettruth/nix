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
from pathlib import Path
from typing import Literal

HOME = os.path.expanduser("~")

ManagedKind = Literal["role", "action"]


class MuxError(Exception):
    pass


@dataclass(frozen=True)
class ManagedCommandSpec:
    name: str
    kind: ManagedKind
    key: str
    always_visible: bool = False


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


def quote_sh(value: str) -> str:
    return shlex.quote(value)


def canonical_name(name: str) -> str:
    match name:
        case "code":
            return "edit"
        case _:
            return name


@lru_cache(maxsize=1)
def managed_commands() -> tuple[ManagedCommandSpec, ...]:
    commands = (
        ManagedCommandSpec("ai", "role", "a", always_visible=True),
        ManagedCommandSpec("edit", "role", "e", always_visible=True),
        ManagedCommandSpec("shell", "role", "s", always_visible=True),
        ManagedCommandSpec("git", "action", "g", always_visible=True),
        ManagedCommandSpec("run", "action", "r"),
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
def justfile_path(root: str) -> str:
    for name in ("Justfile", "justfile", ".justfile"):
        path = os.path.join(root, name)
        if os.path.isfile(path):
            return path
    return ""


@lru_cache(maxsize=None)
def just_recipes_for_root(root: str) -> frozenset[str]:
    if shutil.which("just") is None:
        return frozenset()
    if not (justfile := justfile_path(root)):
        return frozenset()
    if not (
        summary := maybe_output(
            ["just", "--justfile", justfile, "--working-directory", root, "--summary"]
        )
    ):
        return frozenset()
    return frozenset(summary.split())


def visible_commands_for_root(root: str) -> list[ManagedCommandSpec]:
    recipes = just_recipes_for_root(root)
    return [
        command
        for command in managed_commands()
        if command.always_visible or command.name in recipes
    ]


def picker_target_root(token: str = "") -> str:
    if picker_mode() == "open":
        return os.environ["_ROOT"]
    kind, _, value = token.partition(":")
    if kind == "proj" and value:
        return value
    return os.environ["_ROOT"]


def picker_visible_commands(token: str = "") -> list[ManagedCommandSpec]:
    return visible_commands_for_root(picker_target_root(token))


def scope_from_root(root: str) -> str:
    return "~" if root == HOME else base_name(root)


def get_root_from_path(path: str) -> str:
    if root := maybe_output(["git", "-C", path, "rev-parse", "--show-toplevel"]):
        return root
    return HOME if path == HOME else path


def get_managed_scope() -> str:
    if scope := maybe_output(["tmux", "show-options", "-wgv", "@mux_scope"]):
        return scope
    if not maybe_output(["tmux", "show-options", "-wgv", "@mux_root"]):
        return ""
    _, sep, scope = tmux_output("display-message", "-p", "#{window_name}").partition(
        "@"
    )
    return scope if sep else ""


def get_root() -> str:
    if scope := get_managed_scope():
        if (
            root := maybe_output(["tmux", "show-options", "-wgv", "@mux_root"])
        ) and scope_from_root(root) == scope:
            return root
        path = tmux_output("display-message", "-p", "#{pane_start_path}")
    else:
        path = tmux_output("display-message", "-p", "#{pane_current_path}")
    return get_root_from_path(path)


def set_window_option(target: str | None, name: str, value: str) -> None:
    args = ["set-option"]
    if target:
        args.extend(["-t", target])
    args.extend(["-w", name, value])
    _ = tmux(*args)


def set_window_meta(
    target: str | None,
    kind: ManagedKind,
    name: str,
    scope: str,
    root: str,
) -> None:
    set_window_option(target, "@mux_kind", kind)
    set_window_option(target, "@mux_name", name)
    set_window_option(target, "@mux_scope", scope)
    set_window_option(target, "@mux_root", root)


def run_in_root(root: str, command: str) -> str:
    return "" if not command else f"cd {quote_sh(root)} && {command}"


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


def command_for_pane(target: str | None, root: str, command: str) -> str:
    return command if pane_path(target) == root else run_in_root(root, command)


def send_keys(target: str | None, *keys: str) -> None:
    args = ["send-keys"]
    if target:
        args.extend(["-t", target])
    args.extend(keys)
    _ = tmux(*args)


def send_cmd(target: str | None, root: str, command: str) -> None:
    send_keys(target, "C-u", "C-l", command_for_pane(target, root, command), "Enter")


def schedule_initial_cmd(target: str, command: str, channel: str = "") -> None:
    if channel:
        payload = f"tmux wait-for {quote_sh(channel)}; tmux send-keys -t {quote_sh(target)} {quote_sh(command)} Enter"
    else:
        payload = f"tmux send-keys -t {quote_sh(target)} {quote_sh(command)} Enter"
    _ = tmux("run-shell", "-b", payload)


def new_window_info_for_scope(
    window_name: str,
    root: str,
    command: str,
    kind: ManagedKind,
    name: str,
) -> tuple[str, str]:
    scope = scope_from_root(root)
    args = [
        "new-window",
        "-P",
        "-F",
        "#{window_index}\t#{pane_id}",
        "-c",
        root,
        "-n",
        window_name,
    ]
    if command:
        args.append(command)
    info = tmux_output(*args)
    index, _, pane_id = info.partition("\t")
    set_window_meta(f":{index}", kind, name, scope, root)
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
    kind: ManagedKind,
    name: str,
    root: str,
    command: str = "",
) -> None:
    scope = scope_from_root(root)
    window_name = window_name_for(name, scope)
    index = window_index_for_name(window_name)
    current_index = current_window_index()

    if index and index == current_index:
        set_window_meta(None, kind, name, scope, root)
        if command and is_pane_idle():
            send_cmd(None, root, command)
        return

    if is_adoptable():
        if index:
            _ = tmux("kill-window", "-t", f":{index}")
        _ = tmux("rename-window", window_name)
        set_window_meta(None, kind, name, scope, root)
        if command:
            send_cmd(None, root, command)
        return

    if index:
        _ = tmux("select-window", "-t", f":{index}")
        set_window_meta(f":{index}", kind, name, scope, root)
        if command and is_pane_idle(f":{index}"):
            send_cmd(f":{index}", root, command)
        return

    if command:
        channel = new_ready_channel()
        _, pane_id = new_window_info_for_scope(
            window_name, root, initial_shell_command(channel), kind, name
        )
        schedule_initial_cmd(pane_id, command, channel)
        return

    _ = new_window_info_for_scope(window_name, root, "", kind, name)


def role_command_for(name: str) -> str | None:
    match canonical_name(name):
        case "ai":
            return "devin"
        case "edit":
            return "nvim ."
        case "shell":
            return ""
        case _:
            return None


def ensure_role_dependencies(name: str) -> None:
    match canonical_name(name):
        case "ai":
            ensure_command("devin")
        case "edit":
            ensure_command("nvim")
        case _:
            return


def run_command_for_scope(scope: str) -> str | None:
    # TODO: move to justifle
    match scope:
        case "neovim":
            return "make"
        case "tmux":
            return 'make -j "$(nproc)" -C build'
        case "delta":
            return "nix develop -c pnpm dev"
        case "barrettruth.com":
            return "pnpm dev"
        case _:
            return None


def build_command_for_scope(scope: str) -> str | None:
    # TODO: move to just
    match scope:
        case "tmux":
            return 'make -j "$(nproc)" -C build'
        case _:
            return None


def action_command_for_root(name: str, root: str) -> str | None:
    name = canonical_name(name)
    # TODO: move to just, checking for `[Jj]ustfile first`
    match name:
        case "git":
            return 'nvim -c "Git|only"'
        case action if action in managed_just_action_names():
            if not justfile_path(root):
                return None
            if action not in just_recipes_for_root(root):
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
        open_role_in_root(name, get_root())
    except MuxError as exc:
        _ = tmux("display-message", str(exc))
        return 1
    return 0


def open_role_in_root(name: str, root: str) -> None:
    name = canonical_name(name)
    if not (role := command_for_name(name)) or role.kind != "role":
        raise MuxError(f"mux: unknown role '{name}'")
    ensure_role_dependencies(name)
    if (command := role_command_for(name)) is None:
        raise MuxError(f"mux: unknown role '{name}'")
    spawn_or_focus_managed("role", name, root, command)


def open_action(name: str) -> int:
    try:
        open_action_in_root(name, get_root())
    except MuxError as exc:
        _ = tmux("display-message", str(exc))
        return 1
    return 0


def open_action_in_root(name: str, root: str) -> None:
    name = canonical_name(name)
    if not (action := command_for_name(name)) or action.kind != "action":
        raise MuxError(f"mux: no action '{name}' for '{scope_from_root(root)}'")
    scope = scope_from_root(root)
    if name == "git" and not git_ok(root, "rev-parse", "--is-inside-work-tree"):
        raise MuxError("Not a git repository")
    if (command := action_command_for_root(name, root)) is None:
        raise MuxError(f"mux: no action '{name}' for '{scope}'")
    spawn_or_focus_managed("action", name, root, command)


def picker_mode() -> str:
    mode_file = os.environ.get("_MF")
    if not mode_file:
        return "open"
    try:
        return Path(mode_file).read_text(encoding="utf-8") or "open"
    except FileNotFoundError:
        return "open"


def set_picker_mode(mode: str) -> None:
    _ = Path(os.environ["_MF"]).write_text(mode, encoding="utf-8")


def color_escape(hex_code: str) -> str:
    code = hex_code.lstrip("#")
    return f"\033[38;2;{int(code[0:2], 16)};{int(code[2:4], 16)};{int(code[4:6], 16)}m"


def picker_prompt() -> str:
    return f"@{os.environ['_SCOPE']}> " if picker_mode() == "open" else "open> "


def picker_header(token: str = "") -> str:
    accent = color_escape(os.environ.get("_ACCENT", "7aa2f7"))
    reset = "\033[0m"
    mode = picker_mode()
    parts = [
        f"{accent}{display_key(command.key)}{reset} {command.name}"
        for command in picker_visible_commands(token)
    ]
    match mode:
        case "open":
            parts.append(f"{accent}^O{reset} projects")
        case _:
            parts.append(f"{accent}^O{reset} windows")
    return f":: {' '.join(parts)}"


def picker_binding_actions(token: str = "") -> str:
    actions = [f"unbind({fzf_key(command.key)})" for command in managed_commands()]
    for command in picker_visible_commands(token):
        actions.append(f"rebind({fzf_key(command.key)})")
    return "+".join(actions)


def format_open_entry(label: str, token: str, window_name: str = "") -> str:
    accent = color_escape(os.environ.get("_ACCENT", "7aa2f7"))
    reset = "\033[0m"
    index = window_index_for_name(window_name) if window_name else ""
    if index:
        muted = color_escape(os.environ.get("_FGALT", "666666"))
        return f"{accent}{label}{reset} {muted}*{index}{reset}\t{token}"
    return f"{label}{reset}\t{token}"


def list_open_entries() -> str:
    scope = os.environ["_SCOPE"]
    root = os.environ["_ROOT"]
    lines: list[str] = []
    for command in visible_commands_for_root(root):
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
    accent = color_escape(os.environ.get("_ACCENT", "7aa2f7"))
    reset = "\033[0m"
    scope = os.environ["_SCOPE"]
    lines: list[str] = []
    for directory in projects.splitlines():
        if not directory:
            continue
        if (
            maybe_output(["git", "-C", directory, "rev-parse", "--show-toplevel"])
            != directory
        ):
            continue
        name = base_name(directory)
        if name == scope:
            lines.append(f"{accent}{name}{reset}\tproj:{directory}")
        else:
            lines.append(f"{name}\tproj:{directory}")
    return "\n".join(lines) + ("\n" if lines else "")


def picker_list() -> str:
    return list_open_entries() if picker_mode() == "open" else list_project_entries()


def toggle_picker_mode(target_mode: str) -> None:
    set_picker_mode("open" if picker_mode() == target_mode else target_mode)


def dispatch_picker_action(value: str) -> int:
    mode, _, rest = value.partition(":")
    match mode:
        case "role":
            return open_role(rest)
        case "action":
            return open_action(rest)
        case "proj":
            try:
                open_role_in_root("edit", rest)
            except MuxError as exc:
                _ = tmux("display-message", str(exc))
                return 1
            return 0
        case _:
            return 0


def picker_open_target(kind: str, name: str, input_value: str) -> int:
    if picker_mode() == "open":
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
                open_role_in_root(name, directory)
            except MuxError as exc:
                _ = tmux("display-message", str(exc))
                return 1
            return 0
        case "action":
            try:
                open_action_in_root(name, directory)
            except MuxError as exc:
                _ = tmux("display-message", str(exc))
                return 1
            return 0
        case _:
            return 0


def show_picker(start_mode: str = "open") -> int:
    ensure_command("fzf")
    os.environ["_MF"] = f"{os.environ.get('XDG_RUNTIME_DIR', '/tmp')}/mux-picker-mode"
    set_picker_mode(start_mode)
    os.environ["_ROOT"] = get_root()
    os.environ["_SCOPE"] = scope_from_root(os.environ["_ROOT"])
    os.environ["_ACCENT"] = (
        maybe_output(["tmux", "show", "-gv", "@accent"]).replace("#", "") or "7aa2f7"
    )
    os.environ["_FGALT"] = (
        maybe_output(["tmux", "show", "-gv", "@fgAlt"]).replace("#", "") or "666666"
    )
    command = [
        "fzf",
        "--reverse",
        "--ansi",
        "--no-info",
        "--no-scrollbar",
        "--header",
        picker_header(),
        "--prompt",
        picker_prompt(),
        "--pointer",
        "▌",
        "--color",
        f"header:#{os.environ['_FGALT']},prompt:#{os.environ['_ACCENT']},separator:#{os.environ['_FGALT']}",
        "--separator",
        "",
        "--delimiter",
        "\t",
        "--with-nth",
        "1",
        "--accept-nth",
        "2",
        "--bind",
        "result:transform-header(mux _header {2})+transform(mux _bindings {2})",
        "--bind",
        "focus:transform-header(mux _header {2})+transform(mux _bindings {2})",
        "--bind",
        "ctrl-o:execute-silent(mux _toggle proj)+reload(mux _list)+transform-header(mux _header {2})+transform-prompt(mux _prompt)+transform(mux _bindings {2})",
        "--bind",
        "enter:become(mux _dispatch {2})",
    ]
    for managed in managed_commands():
        command.extend(
            [
                "--bind",
                (
                    f"{fzf_key(managed.key)}:become("
                    f"mux _picker_open {managed.kind} {managed.name} {{2}})"
                ),
            ]
        )
    return subprocess.run(
        command, input=picker_list(), text=True, env=os.environ.copy(), check=False
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
    indicator = (
        "#{?pane_in_mode,[mouse#{@c}copy],[mouse]}"
        if tmux_output("show-options", "-gv", "mouse") == "on"
        else "#{?pane_in_mode,[copy],}"
    )
    sessions = maybe_output(["tmux", "ls", "-F", "#{session_id}\t#{session_name}"])
    parts: list[str] = []
    lines = [line for line in sessions.splitlines() if line]
    total = len(lines)
    for index, line in enumerate(lines):
        session_id, _, session_name = line.partition("\t")
        key = session_key(index, total)
        star = f"#{{?#{{==:#S,{session_name}}},#[fg=#{{@accent}}]*#[default],}}"
        parts.append(
            f"#[range=session|{session_id}]{star}{key}#[fg=#{{@accent}}]:#[default]{session_name}#[norange]"
        )
    bar_content = " │ ".join(parts)
    _ = tmux("set", "-g", "status-left-length", "80")
    _ = tmux("set", "-g", "status-right-length", "80")
    _ = tmux("set", "-g", "status-left", " ")
    _ = tmux(
        "set",
        "-g",
        "window-status-format",
        "#[range=window|#{window_index}]#{?window_last_flag,#[fg=#{@accent}]-#[default],}#{window_index}#[fg=#{@accent}]:#[default]#{window_name}#[norange]",
    )
    _ = tmux(
        "set",
        "-g",
        "window-status-current-format",
        "#[range=window|#{window_index}]#[fg=#{@accent}]*#[default]#{window_index}#[fg=#{@accent}]:#[default]#{window_name}#[norange]",
    )
    _ = tmux("set", "-g", "window-status-separator", " │ ")
    _ = tmux("set", "-g", "@bar-content", f"{indicator} {bar_content} ")
    return 0


def apply_managed_binds() -> int:
    for key in ("a", "b", "c", "e", "g", "r", "s", "t"):
        _ = tmux(
            "unbind-key",
            tmux_key(key),
            check=False,
            stderr=subprocess.DEVNULL,
        )
    for command in managed_commands():
        _ = tmux("bind-key", tmux_key(command.key), "run", f"mux {command.name}")
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
        case ["_prompt"]:
            _ = sys.stdout.write(picker_prompt())
            return 0
        case ["_header"]:
            _ = sys.stdout.write(picker_header())
            return 0
        case ["_header", token]:
            _ = sys.stdout.write(picker_header(token))
            return 0
        case ["_bindings"]:
            _ = sys.stdout.write(picker_binding_actions())
            return 0
        case ["_bindings", token]:
            _ = sys.stdout.write(picker_binding_actions(token))
            return 0
        case ["_list"]:
            _ = sys.stdout.write(picker_list())
            return 0
        case ["_toggle", mode]:
            toggle_picker_mode(mode)
            return 0
        case ["_dispatch", value]:
            return dispatch_picker_action(value)
        case ["_picker_open", kind, name, value]:
            return picker_open_target(kind, name, value)
        case ["switch"]:
            return usage_error("switch requires a slot")
        case ["role"]:
            return usage_error("role requires a name")
        case ["action"]:
            return usage_error("action requires a name")
        case ["_toggle"]:
            return usage_error("_toggle requires a mode")
        case ["_dispatch"]:
            return usage_error("_dispatch requires a value")
        case ["_bindings", *_]:
            return usage_error("_bindings accepts at most one token")
        case ["_picker_open"] | ["_picker_open", _] | ["_picker_open", _, _]:
            return usage_error("_picker_open requires kind, name, and value")
        case [command, *_]:
            return usage_error(f"unknown command: {command}")
        case _:
            pass

    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
