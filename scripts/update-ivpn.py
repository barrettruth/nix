#!/usr/bin/env python3

import base64
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Any, cast
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent.parent
PIN = ROOT / "pkgs/ivpn-bin/default.nix"
PUBLIC_KEY = ROOT / "pkgs/ivpn-bin/update-public.pem"
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


def run(*args: str, timeout: int = 30) -> str:
    return subprocess.run(
        args, check=True, stdout=subprocess.PIPE, text=True, timeout=timeout
    ).stdout.strip()


def object_from_json(data: str | bytes) -> dict[str, Any]:
    value: object = json.loads(data)
    if not isinstance(value, dict):
        raise ValueError("Expected a JSON object")
    return cast(dict[str, Any], value)


def fetch(url: str) -> bytes:
    with urlopen(url, timeout=30) as response:
        if not response.geturl().startswith("https://"):
            raise ValueError("Refusing an insecure redirect")
        data: bytes = response.read(1024 * 1024 + 1)
    if len(data) > 1024 * 1024:
        raise ValueError("Update metadata exceeds the size limit")
    return data


def verify(path: Path, signature_url: str, work: Path) -> None:
    signature = base64.b64decode(b"".join(fetch(signature_url).split()), validate=True)
    signature_file = work / "signature.bin"
    signature_file.write_bytes(signature)
    run(
        "openssl",
        "dgst",
        "-sha256",
        "-verify",
        str(PUBLIC_KEY),
        "-signature",
        str(signature_file),
        str(path),
        timeout=60,
    )


def replace_once(pattern: str, replacement: str, text: str) -> str:
    updated, count = re.subn(pattern, replacement, text, flags=re.MULTILINE)
    if count != 1:
        raise ValueError("The IVPN pin format changed; refusing a partial update")
    return updated


def main() -> None:
    if len(sys.argv) != 1:
        raise ValueError("Usage: update-ivpn.py")
    for command in ("gh", "nix", "openssl"):
        if shutil.which(command) is None:
            raise ValueError(f"Missing dependency: {command}")

    original = PIN.read_text()
    match = re.search(r'^  version = "([0-9.]+)";$', original, re.MULTILINE)
    if match is None or not VERSION.fullmatch(match[1]):
        raise ValueError("Cannot identify the current IVPN version")
    current = match[1]
    release = object_from_json(
        run("gh", "api", "repos/ivpn/desktop-app/releases/latest")
    )
    version = str(release["tag_name"]).removeprefix("v")
    if not VERSION.fullmatch(version) or release["draft"] or release["prerelease"]:
        raise ValueError("The latest release is not a stable IVPN version")
    if tuple(map(int, version.split("."))) <= tuple(map(int, current.split("."))):
        print(f"update: IVPN already at {current}")
        return
    published = datetime.fromisoformat(
        str(release["published_at"]).replace("Z", "+00:00")
    )
    if datetime.now(timezone.utc) - published < timedelta(days=7):
        print(f"update: IVPN {version} is less than seven days old; keeping {current}")
        return

    hashes: dict[str, str] = {}
    with tempfile.TemporaryDirectory(prefix="ivpn-update-") as directory:
        work = Path(directory)
        for system, suffix, metadata_name in (
            ("aarch64-darwin", "-arm64", "update_arm64.json"),
            ("x86_64-darwin", "", "update.json"),
        ):
            metadata_url = f"https://repo.ivpn.net/macos/{metadata_name}"
            data = fetch(metadata_url)
            metadata_file = work / metadata_name
            metadata_file.write_bytes(data)
            verify(metadata_file, metadata_url + ".sign.sha256.base64", work)
            metadata = object_from_json(data)["generic"]
            url = f"https://repo.ivpn.net/macos/bin/IVPN-{version}{suffix}.dmg"
            signature_url = url + ".sign.sha256.base64"
            if (
                metadata["version"] != version
                or metadata["downloadLink"] != url
                or metadata["signature"] != signature_url
            ):
                raise ValueError(
                    f"The published {system} download does not match the release"
                )
            artifact = object_from_json(
                run("nix", "store", "prefetch-file", "--json", url, timeout=600)
            )
            verify(Path(artifact["storePath"]), signature_url, work)
            digest = str(artifact["hash"])
            if not re.fullmatch(r"sha256-[A-Za-z0-9+/]{43}=", digest):
                raise ValueError("Unexpected Nix hash format")
            hashes[system] = digest

    updated = replace_once(
        r'^  version = "[0-9.]+";$', f'  version = "{version}";', original
    )
    for system, digest in hashes.items():
        updated = replace_once(
            rf'(^    {re.escape(system)} = \{{\n[^}}]*?      hash = ")[^"]+(";)',
            rf"\g<1>{digest}\g<2>",
            updated,
        )
    if PIN.read_text() != original:
        raise ValueError(
            "The IVPN pin changed during download; refusing to overwrite it"
        )
    with tempfile.NamedTemporaryFile(mode="w", dir=PIN.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(updated)
            output.flush()
            os.fchmod(output.fileno(), stat.S_IMODE(PIN.stat().st_mode))
            temporary.replace(PIN)
        finally:
            temporary.unlink(missing_ok=True)
    print(f"update: IVPN {current} -> {version}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"update-ivpn: {error}", file=sys.stderr)
        sys.exit(1)
