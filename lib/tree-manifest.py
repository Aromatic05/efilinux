#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import stat
import sys
from collections.abc import Iterator


_CHUNK_SIZE = 1024 * 1024
_CONTROL_CHARACTERS = {"\t", "\r", "\n"}


def _entry_type(mode: int) -> str:
    if stat.S_ISREG(mode):
        return "regular file"
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISLNK(mode):
        return "symbolic link"
    if stat.S_ISCHR(mode):
        return "character special file"
    if stat.S_ISBLK(mode):
        return "block special file"
    if stat.S_ISFIFO(mode):
        return "fifo"
    if stat.S_ISSOCK(mode):
        return "socket"
    raise ValueError(f"unsupported file type: {mode:#o}")


def _sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        while chunk := source.read(_CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest()


def _walk(root: str) -> Iterator[tuple[bytes, str, str]]:
    pending = [root]
    entries: list[tuple[bytes, str, str]] = []

    while pending:
        directory = pending.pop()
        with os.scandir(directory) as iterator:
            for entry in iterator:
                path = entry.path
                relative = os.path.relpath(path, root)
                if any(character in relative for character in _CONTROL_CHARACTERS):
                    raise ValueError(
                        f"package path contains a control character: {relative!r}"
                    )
                entries.append((os.fsencode(relative), relative, path))
                if entry.is_dir(follow_symlinks=False):
                    pending.append(path)

    yield from sorted(entries, key=lambda item: item[0])


def _record(relative: str, path: str) -> str:
    metadata = os.lstat(path)
    mode = metadata.st_mode
    file_type = _entry_type(mode)
    permissions = format(stat.S_IMODE(mode), "o")
    major = format(os.major(metadata.st_rdev), "x")
    minor = format(os.minor(metadata.st_rdev), "x")
    stat_data = (
        f"{file_type}|{permissions}|{metadata.st_uid}|{metadata.st_gid}|"
        f"{major}|{minor}"
    )

    if stat.S_ISREG(mode):
        payload = _sha256(path)
    elif stat.S_ISLNK(mode):
        payload = os.readlink(path)
    elif stat.S_ISDIR(mode):
        payload = "-"
    else:
        payload = f"{metadata.st_size}|{int(metadata.st_mtime)}"

    return f"{relative}\t{stat_data}\t{payload}\n"


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: tree-manifest.py DIRECTORY OUTPUT", file=sys.stderr)
        return 2

    root = os.path.abspath(sys.argv[1])
    output = os.path.abspath(sys.argv[2])
    temporary = f"{output}.tmp.{os.getpid()}"

    if not os.path.isdir(root):
        print(f"tree manifest source is missing: {root}", file=sys.stderr)
        return 1

    try:
        with open(
            temporary,
            "w",
            encoding="utf-8",
            errors="surrogateescape",
            newline="\n",
        ) as destination:
            for _, relative, path in _walk(root):
                destination.write(_record(relative, path))
        os.replace(temporary, output)
    except Exception as error:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        print(f"tree manifest failed: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
