import argparse
import hashlib
import io
import os
import struct
import subprocess
import sys
import zipfile

CRX_MAGIC = b"Cr24"
CRX_VERSION = 3
SIGNATURE_CONTEXT = b"CRX3 SignedData\x00"

FIELD_SHA256_WITH_RSA = 2
FIELD_SIGNED_HEADER_DATA = 10000
FIELD_PUBLIC_KEY = 1
FIELD_SIGNATURE = 2
FIELD_CRX_ID = 1

ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)


def varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def length_delimited(field: int, payload: bytes) -> bytes:
    return varint((field << 3) | 2) + varint(len(payload)) + payload


def openssl(args: list[str], stdin: bytes | None = None) -> bytes:
    result = subprocess.run(
        ["openssl", *args], input=stdin, capture_output=True, check=False
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr.decode(errors="replace"))
        raise SystemExit(f"openssl {args[0]} failed with {result.returncode}")
    return result.stdout


def public_key_der(key: str) -> bytes:
    return openssl(["pkey", "-in", key, "-pubout", "-outform", "DER"])


def extension_id(der: bytes) -> str:
    digest = hashlib.sha256(der).digest()[:16]
    return "".join(
        chr(ord("a") + (byte >> 4)) + chr(ord("a") + (byte & 0xF)) for byte in digest
    )


def deterministic_zip(source: str) -> bytes:
    paths: list[str] = []
    for directory, _, filenames in os.walk(source):
        paths.extend(os.path.join(directory, name) for name in filenames)

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(paths):
            info = zipfile.ZipInfo(os.path.relpath(path, source), date_time=ZIP_EPOCH)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(path, "rb") as handle:
                archive.writestr(info, handle.read())
    return buffer.getvalue()


def build_crx(key: str, source: str) -> bytes:
    der = public_key_der(key)
    signed_header_data = length_delimited(
        FIELD_CRX_ID, hashlib.sha256(der).digest()[:16]
    )
    archive = deterministic_zip(source)

    signature = openssl(
        ["dgst", "-sha256", "-sign", key],
        SIGNATURE_CONTEXT
        + struct.pack("<I", len(signed_header_data))
        + signed_header_data
        + archive,
    )

    proof = length_delimited(FIELD_PUBLIC_KEY, der) + length_delimited(
        FIELD_SIGNATURE, signature
    )
    header = length_delimited(FIELD_SHA256_WITH_RSA, proof) + length_delimited(
        FIELD_SIGNED_HEADER_DATA, signed_header_data
    )

    return CRX_MAGIC + struct.pack("<II", CRX_VERSION, len(header)) + header + archive


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Pack an unpacked extension directory into a signed CRX3 archive."
    )
    parser.add_argument("--key", required=True, help="PEM private key to sign with")
    parser.add_argument("--source", help="unpacked extension directory")
    parser.add_argument("--output", help="path to write the .crx to")
    parser.add_argument(
        "--print-id",
        action="store_true",
        help="print the extension id the key produces and exit",
    )
    args = parser.parse_args()

    if args.print_id:
        print(extension_id(public_key_der(args.key)))
        return

    if not args.source or not args.output:
        parser.error("--source and --output are required unless --print-id is given")

    crx = build_crx(args.key, args.source)
    with open(args.output, "wb") as handle:
        handle.write(crx)


if __name__ == "__main__":
    main()
