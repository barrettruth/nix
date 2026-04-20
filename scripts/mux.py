#!/usr/bin/env python

import os
import shlex
import shutil
import subprocess
import sys
import time
from collections.abc import Sequence
from pathlib import Path
from typing import Literal

HOME = os.path.expanduser("~")

RoleName = Literal["ai", "code", "shell"]
ActionName = Literal["git", "run", "build"]
ManagedKind = Literal["role", "action"]
ActionPolicy = Literal["keep", "close", "keep_on_fail"]


class MuxError(Exception):
    pass


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
    policy: ActionPolicy,
) -> None:
    set_window_option(target, "@mux_kind", kind)
    set_window_option(target, "@mux_name", name)
    set_window_option(target, "@mux_scope", scope)
    set_window_option(target, "@mux_root", root)
    set_window_option(target, "@mux_policy", policy)


def run_in_root(root: str, command: str) -> str:
    return "" if not command else f"cd {quote_sh(root)} && {command}"


def shell_path() -> str:
    return os.environ.get("SHELL", "/bin/sh")


def initial_shell_command(channel: str = "") -> str:
    shell = shell_path()
    if channel:
        return f"exec env PURE_FIX=0 MUX_READY_CHANNEL={quote_sh(channel)} {quote_sh(shell)} -i"
    return f"exec env PURE_FIX=0 {quote_sh(shell)} -i"


def close_action_command(root: str, command: str) -> str:
    shell = shell_path()
    payload = run_in_root(root, command)
    return f"exec env PURE_FIX=0 {quote_sh(shell)} -ic {quote_sh(payload)}"


def keep_on_fail_action_command(root: str, command: str) -> str:
    shell = shell_path()
    payload = (
        f'{run_in_root(root, command)}; kof_status=$?; if [ "$kof_status" -eq 0 ]; '
        f'then tmux kill-window -t "$TMUX_PANE"; exit 0; fi; exec env PURE_FIX=0 {quote_sh(shell)} -i'
    )
    return f"exec env PURE_FIX=0 {quote_sh(shell)} -ic {quote_sh(payload)}"


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
    policy: ActionPolicy,
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
    set_window_meta(f":{index}", kind, name, scope, root, policy)
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
    policy: ActionPolicy = "keep",
) -> None:
    scope = scope_from_root(root)
    window_name = window_name_for(name, scope)
    index = window_index_for_name(window_name)
    current_index = current_window_index()

    if index and index == current_index:
        set_window_meta(None, kind, name, scope, root, policy)
        if command and is_pane_idle():
            send_cmd(None, root, command)
        return

    if is_adoptable():
        if index:
            _ = tmux("kill-window", "-t", f":{index}")
        _ = tmux("rename-window", window_name)
        set_window_meta(None, kind, name, scope, root, policy)
        if command:
            send_cmd(None, root, command)
        return

    if index:
        _ = tmux("select-window", "-t", f":{index}")
        set_window_meta(f":{index}", kind, name, scope, root, policy)
        if command and is_pane_idle(f":{index}"):
            send_cmd(f":{index}", root, command)
        return

    if command:
        channel = new_ready_channel()
        _, pane_id = new_window_info_for_scope(
            window_name, root, initial_shell_command(channel), kind, name, policy
        )
        schedule_initial_cmd(pane_id, command, channel)
        return

    _ = new_window_info_for_scope(window_name, root, "", kind, name, policy)


def spawn_action_close(name: str, root: str, command: str) -> None:
    scope = scope_from_root(root)
    window_name = window_name_for(name, scope)
    index = window_index_for_name(window_name)
    if index:
        _ = tmux("select-window", "-t", f":{index}")
        set_window_meta(f":{index}", "action", name, scope, root, "close")
        return
    _ = new_window_info_for_scope(
        window_name, root, close_action_command(root, command), "action", name, "close"
    )


def spawn_action_keep_on_fail(name: str, root: str, command: str) -> None:
    scope = scope_from_root(root)
    window_name = window_name_for(name, scope)
    _ = new_window_info_for_scope(
        window_name,
        root,
        keep_on_fail_action_command(root, command),
        "action",
        name,
        "keep_on_fail",
    )


def role_command_for(name: str) -> str | None:
    match name:
        case "ai":
            return "devin"
        case "code":
            return "nvim ."
        case "shell":
            return ""
        case _:
            return None


def ensure_role_dependencies(name: str) -> None:
    match name:
        case "ai":
            ensure_command("devin")
        case "code":
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


def action_policy_for(name: str) -> ActionPolicy | None:
    match name:
        case "git":
            return "close"
        case "run" | "build":
            return "keep"
        case _:
            return None


def action_command_for_root(name: str, root: str) -> str | None:
    scope = scope_from_root(root)
    # TODO: move to just, checking for `[Jj]ustfile first`
    match name:
        case "git":
            return 'nvim -c "Git|only"'
        case "run":
            return run_command_for_scope(scope)
        case "build":
            return build_command_for_scope(scope)
        case _:
            return None


def list_action_names_for_root(root: str) -> list[ActionName]:
    names: list[ActionName] = ["git"]
    for action in ("run", "build"):
        if action_command_for_root(action, root):
            names.append(action)
    return names


def usage_error(message: str) -> int:
    _ = sys.stderr.write(f"mux: {message}\n")
    return 1


def open_role(name: str) -> int:
    try:
        open_role_in_root(name, get_root())
    except MuxError as exc:
        _ = tmux("display-message", str(exc))
        return 1
    return 0


def open_role_in_root(name: str, root: str) -> None:
    ensure_role_dependencies(name)
    if (command := role_command_for(name)) is None:
        raise MuxError(f"mux: unknown role '{name}'")
    spawn_or_focus_managed("role", name, root, command, "keep")


def open_action(name: str) -> int:
    try:
        open_action_in_root(name, get_root())
    except MuxError as exc:
        _ = tmux("display-message", str(exc))
        return 1
    return 0


def open_action_in_root(name: str, root: str) -> None:
    scope = scope_from_root(root)
    if name == "git" and not git_ok(root, "rev-parse", "--is-inside-work-tree"):
        raise MuxError("Not a git repository")
    if (command := action_command_for_root(name, root)) is None:
        raise MuxError(f"mux: no action '{name}' for '{scope}'")
    if (policy := action_policy_for(name)) is None:
        raise MuxError(f"mux: bad policy for '{name}'")
    match policy:
        case "keep":
            spawn_or_focus_managed("action", name, root, command, policy)
        case "close":
            spawn_action_close(name, root, command)
        case "keep_on_fail":
            spawn_action_keep_on_fail(name, root, command)
        case _:
            raise MuxError(f"mux: bad policy '{policy}' for '{name}'")


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


def picker_header() -> str:
    accent = color_escape(os.environ.get("_ACCENT", "7aa2f7"))
    reset = "\033[0m"
    match picker_mode():
        case "open":
            return (
                f":: {accent}^A{reset} ai {accent}^C{reset} code {accent}^S{reset} shell "
                f"{accent}^R{reset} run {accent}^G{reset} git {accent}^X{reset} kill {accent}^O{reset} projects"
            )
        case _:
            return (
                f":: {accent}^A{reset} ai {accent}^C{reset} code {accent}^S{reset} shell "
                f"{accent}^R{reset} run {accent}^G{reset} git {accent}^O{reset} windows"
            )


def format_open_entry(
    label: str, token: str, window_name: str = "", policy: str = ""
) -> str:
    accent = color_escape(os.environ.get("_ACCENT", "7aa2f7"))
    muted = color_escape(os.environ.get("_FGALT", "666666"))
    reset = "\033[0m"
    index = window_index_for_name(window_name) if window_name else ""
    suffix = f" {muted}[{policy}]{reset}" if policy else ""
    if index:
        return f"{accent}{label}{reset}{suffix} {muted}*{index}{reset}\t{token}"
    return f"{label}{suffix}{reset}\t{token}"


def list_open_entries() -> str:
    scope = os.environ["_SCOPE"]
    root = os.environ["_ROOT"]
    lines = [
        format_open_entry("ai", "role:ai", window_name_for("ai", scope)),
        format_open_entry("code", "role:code", window_name_for("code", scope)),
        format_open_entry("shell", "role:shell", window_name_for("shell", scope)),
    ]
    for action in list_action_names_for_root(root):
        if (policy := action_policy_for(action)) is None:
            continue
        window_name = window_name_for(action, scope) if policy == "keep" else ""
        lines.append(format_open_entry(action, f"action:{action}", window_name, policy))
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


def kill_picker_target(value: str) -> None:
    kind, _, name = value.partition(":")
    window_name = window_name_for(name, os.environ["_SCOPE"])
    if kind in {"role", "action"}:
        _ = tmux(
            "kill-window",
            "-t",
            f"={window_name}",
            check=False,
            stderr=subprocess.DEVNULL,
        )


def dispatch_picker_action(value: str) -> int:
    mode, _, rest = value.partition(":")
    match mode:
        case "role":
            return open_role(rest)
        case "action":
            return open_action(rest)
        case "proj":
            try:
                open_role_in_root("code", rest)
            except MuxError as exc:
                _ = tmux("display-message", str(exc))
                return 1
            return 0
        case "kill":
            kill_picker_target(rest)
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
        "ctrl-o:execute-silent(mux _toggle proj)+reload(mux _list)+transform-header(mux _header)+transform-prompt(mux _prompt)",
        "--bind",
        "enter:become(mux _dispatch {2})",
        "--bind",
        "ctrl-a:become(mux _picker_open role ai {2})",
        "--bind",
        "ctrl-d:become(mux _picker_open role code {2})",
        "--bind",
        "ctrl-s:become(mux _picker_open role shell {2})",
        "--bind",
        "ctrl-r:become(mux _picker_open action run {2})",
        "--bind",
        "ctrl-g:become(mux _picker_open action git {2})",
        "--bind",
        "ctrl-x:execute-silent(mux _dispatch kill:{2})+reload(mux _list)+transform-header(mux _header)",
    ]
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
        case ["switch", slot]:
            return switch_session(slot)
        case ["role", name]:
            return open_role(name)
        case ["action", name]:
            return open_action(name)
        case [("ai" | "code" | "shell") as command]:
            return open_role(command)
        case ["code"]:
            _ = sys.stderr.write("mux: unknown role: code\n")
            return 1
        case ["git"]:
            return open_action("git")
        case ["run"]:
            return open_action("run")
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
        case ["_picker_open"] | ["_picker_open", _] | ["_picker_open", _, _]:
            return usage_error("_picker_open requires kind, name, and value")
        case [command, *_]:
            return usage_error(f"unknown command: {command}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
