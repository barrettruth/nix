#!/usr/bin/env python3

import html
import re
import sys

XKB_TO_VK: dict[str, int] = {
    "TLDE": 50,
    "AE01": 18,
    "AE02": 19,
    "AE03": 20,
    "AE04": 21,
    "AE05": 23,
    "AE06": 22,
    "AE07": 26,
    "AE08": 28,
    "AE09": 25,
    "AE10": 29,
    "AE11": 27,
    "AE12": 24,
    "AD01": 12,
    "AD02": 13,
    "AD03": 14,
    "AD04": 15,
    "AD05": 17,
    "AD06": 16,
    "AD07": 32,
    "AD08": 34,
    "AD09": 31,
    "AD10": 35,
    "AD11": 33,
    "AD12": 30,
    "AC01": 0,
    "AC02": 1,
    "AC03": 2,
    "AC04": 3,
    "AC05": 5,
    "AC06": 4,
    "AC07": 38,
    "AC08": 40,
    "AC09": 37,
    "AC10": 41,
    "AC11": 39,
    "BKSL": 42,
    "AB01": 6,
    "AB02": 7,
    "AB03": 8,
    "AB04": 9,
    "AB05": 11,
    "AB06": 45,
    "AB07": 46,
    "AB08": 43,
    "AB09": 47,
    "AB10": 44,
}

KEYSYM: dict[str, str] = {
    "exclam": "!",
    "at": "@",
    "numbersign": "#",
    "dollar": "$",
    "percent": "%",
    "asciicircum": "^",
    "ampersand": "&",
    "asterisk": "*",
    "parenleft": "(",
    "parenright": ")",
    "minus": "-",
    "underscore": "_",
    "equal": "=",
    "plus": "+",
    "bracketleft": "[",
    "braceleft": "{",
    "bracketright": "]",
    "braceright": "}",
    "backslash": "\\",
    "bar": "|",
    "semicolon": ";",
    "colon": ":",
    "apostrophe": "'",
    "quotedbl": '"',
    "grave": "`",
    "asciitilde": "~",
    "comma": ",",
    "less": "<",
    "period": ".",
    "greater": ">",
    "slash": "/",
    "question": "?",
}

# us(colemak_dh) leaves these at their qwerty positions; baremak does not
# override them, so they carry no third level and fall back to levels 1-2.
US_FALLBACK: dict[str, tuple[str, str]] = {
    "TLDE": ("`", "~"),
    "AE01": ("1", "!"),
    "AE02": ("2", "@"),
    "AE03": ("3", "#"),
    "AE04": ("4", "$"),
    "AE05": ("5", "%"),
    "AE06": ("6", "^"),
    "AE07": ("7", "&"),
    "AE08": ("8", "*"),
    "AE09": ("9", "("),
    "AE10": ("0", ")"),
    "AE11": ("-", "_"),
    "AE12": ("=", "+"),
    "AD11": ("[", "{"),
    "AD12": ("]", "}"),
    "BKSL": ("\\", "|"),
    "AB10": ("/", "?"),
}

CONTROL: dict[int, str] = {36: "&#x000D;", 48: "&#x0009;", 49: " "}

KEY_RE = re.compile(r"key\s+<(\w+)>\s*\{\s*\[([^\]]*)\]\s*\}\s*;")


def symbol(name: str) -> str:
    name = name.strip()
    if name in KEYSYM:
        return KEYSYM[name]
    if len(name) == 1:
        return name
    raise SystemExit(f"baremak: unmapped keysym {name!r}")


def parse(source: str) -> dict[str, list[str]]:
    levels: dict[str, list[str]] = {}
    for match in KEY_RE.finditer(source):
        key: str = match[1]
        body: str = match[2]
        syms = [symbol(s) for s in body.split(",")]
        if len(syms) != 4:
            raise SystemExit(f"baremak: {key} has {len(syms)} levels, expected 4")
        if key not in XKB_TO_VK:
            raise SystemExit(f"baremak: no virtual key code for <{key}>")
        levels[key] = syms
    return levels


def key_map(index: int, level: int, levels: dict[str, list[str]]) -> str:
    rows = [f'    <keyMap index="{index}">']
    for key, code in sorted(XKB_TO_VK.items(), key=lambda kv: kv[1]):
        if key in levels:
            out = levels[key][level]
        elif key in US_FALLBACK:
            out = US_FALLBACK[key][level % 2]
        else:
            continue
        rows.append(
            f'      <key code="{code}" output="{html.escape(out, quote=True)}"/>'
        )
    for code, out in sorted(CONTROL.items()):
        rows.append(f'      <key code="{code}" output="{out}"/>')
    rows.append("    </keyMap>")
    return "\n".join(rows)


def main() -> None:
    levels = parse(sys.stdin.read())
    maps = "\n".join(key_map(i, i, levels) for i in range(4))
    print(f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE keyboard SYSTEM "file://localhost/System/Library/DTDs/KeyboardLayout.dtd">
<keyboard group="126" id="-19001" name="Baremak" maxout="1">
  <layouts>
    <layout first="0" last="17" modifiers="mods" mapSet="ANSI"/>
  </layouts>
  <modifierMap id="mods" defaultIndex="0">
    <keyMapSelect mapIndex="0">
      <modifier keys=""/>
    </keyMapSelect>
    <keyMapSelect mapIndex="1">
      <modifier keys="anyShift caps?"/>
      <modifier keys="caps"/>
    </keyMapSelect>
    <keyMapSelect mapIndex="2">
      <modifier keys="anyOption"/>
    </keyMapSelect>
    <keyMapSelect mapIndex="3">
      <modifier keys="anyShift caps? anyOption"/>
    </keyMapSelect>
  </modifierMap>
  <keyMapSet id="ANSI">
{maps}
  </keyMapSet>
</keyboard>""")


main()
