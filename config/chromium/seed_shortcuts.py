import json
import sys
from pathlib import Path


EXTENSION_ID = "demmbkpegigoeiappcbliinlijmeoaop"
BINDINGS = {
    "toggle-overlay": "Ctrl+Period",
    "toggle-overlay-new-tab": "Ctrl+Shift+Period",
    "switch-workspace-1": "Ctrl+Shift+1",
    "switch-workspace-2": "Ctrl+Shift+2",
    "switch-workspace-3": "Ctrl+Shift+3",
    "switch-workspace-4": "Ctrl+Shift+4",
}


def update_preferences(path_str: str, platform: str) -> None:
    prefs_path = Path(path_str)
    data = json.loads(prefs_path.read_text())
    extensions = data.setdefault("extensions", {})
    commands = extensions.setdefault("commands", {})
    for key, value in list(commands.items()):
        if value.get("extension") != EXTENSION_ID:
            continue
        if not key.startswith(f"{platform}:"):
            continue
        shortcut = key.split(":", 1)[1]
        if BINDINGS.get(value.get("command_name")) != shortcut:
            del commands[key]
    for command_name, shortcut in BINDINGS.items():
        commands[f"{platform}:{shortcut}"] = {
            "command_name": command_name,
            "extension": EXTENSION_ID,
            "global": False,
        }
    settings = extensions.setdefault("settings", {}).setdefault(EXTENSION_ID, {})
    command_settings = settings.setdefault("commands", {})
    for key in list(command_settings):
        if key not in BINDINGS and key != "toggle-dark":
            del command_settings[key]
    for command_name, shortcut in BINDINGS.items():
        command_settings[command_name] = {
            "suggested_key": shortcut,
            "was_assigned": True,
        }
    if "toggle-dark" in command_settings:
        command_settings["toggle-dark"] = {
            "suggested_key": "",
            "was_assigned": True,
        }
    prefs_path.write_text(json.dumps(data, separators=(",", ":")))


def main() -> int:
    platform = sys.argv[1]
    for path_str in sys.argv[2:]:
        update_preferences(path_str, platform)
    return 0


raise SystemExit(main())
