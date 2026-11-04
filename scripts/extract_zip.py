#!/usr/bin/env python3
"""Safely unpack xrixuid.zip into an auditable repository directory.

Only handles archive contents as data; never runs extracted scripts.
"""
from __future__ import annotations

import pathlib
import shutil
import stat
import sys
import zipfile

ARCHIVE = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "xrixuid.zip")
DEST = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "unpacked")
MAX_FILES = 6000
MAX_TOTAL_BYTES = 175 * 1024 * 1024
MAX_FILE_BYTES = 40 * 1024 * 1024
EXCLUDED_PARTS = {
    ".git", ".github", "node_modules", ".venv", "venv", "__pycache__",
    ".next", ".cache", ".pytest_cache", "coverage", ".idea", ".vscode"
}
PRIVATE_NAMES = {
    ".env", ".env.local", ".env.production", ".env.development",
    ".npmrc", ".pypirc", "id_rsa", "id_ed25519", "credentials.json",
}
PRIVATE_SUFFIXES = (".pem", ".key", ".p12", ".pfx", ".sqlite", ".db", ".log",
                    ".bak", ".session")

if not ARCHIVE.is_file():
    sys.exit(f"Archive missing: {ARCHIVE}")
if DEST.exists() and not DEST.is_dir():
    sys.exit(f"Target is not a directory: {DEST}")
base = DEST.resolve()

with zipfile.ZipFile(ARCHIVE) as zf:
    entries = []
    total_size = 0
    for entry in zf.infolist():
        raw = entry.filename
        name = pathlib.PurePosixPath(raw)
        file_mode = (entry.external_attr >> 16) & 0xFFFF
        if (not raw or "\\" in raw or name.is_absolute()
                or ".." in name.parts or stat.S_ISLNK(file_mode)):
            sys.exit(f"Refusing unsafe ZIP member: {raw!r}")
        if entry.is_dir():
            continue
        if any(p.lower() in EXCLUDED_PARTS for p in name.parts):
            continue
        if (name.name.lower() in PRIVATE_NAMES
                or name.name.lower().startswith(".env.")
                or name.suffix.lower() in PRIVATE_SUFFIXES):
            print(f"Skipping potentially private file: {name}")
            continue
        if entry.file_size > MAX_FILE_BYTES:
            sys.exit(f"Oversized file: {name}")
        total_size += entry.file_size
        if total_size > MAX_TOTAL_BYTES:
            sys.exit("Uncompressed ZIP too large; manual review required.")
        if (base / str(name)).resolve().is_relative_to(base) is False:
            sys.exit(f"Unsafe destination path: {name}")
        entries.append((entry, name))
    if len(entries) > MAX_FILES:
        sys.exit("Too many files; manual review required.")
    print(f"Checked {len(entries)} files ({total_size:,} uncompressed bytes)")
    # Keep source tree in sync with the archive, without running included code.
    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True)
    for info, name in entries:
        target = DEST.joinpath(*name.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(info) as src, target.open("wb") as dst:
            shutil.copyfileobj(src, dst)
    for info, name in entries[:100]:
        print("EXTRACTED", name)
    if len(entries) > 100:
        print(f"... {len(entries) - 100} further files")
print(f"Done: {DEST}")
