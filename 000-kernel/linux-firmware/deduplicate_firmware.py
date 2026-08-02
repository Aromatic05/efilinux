#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import posixpath
import sys
from collections import defaultdict
from pathlib import Path


_CHUNK_SIZE = 1024 * 1024


def relative_name(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def iter_regular_firmware(root: Path) -> list[Path]:
    files: list[Path] = []
    for directory, dirnames, filenames in os.walk(root, followlinks=False):
        directory_path = Path(directory)
        dirnames[:] = [
            name for name in dirnames if not (directory_path / name).is_symlink()
        ]
        for name in filenames:
            path = directory_path / name
            if path.is_symlink():
                continue
            if not path.is_file():
                raise SystemExit(f"unsupported firmware file type: {path}")
            if path.suffix == ".zst":
                files.append(path)
    return files


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(_CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_key(root: Path, path: Path) -> tuple[int, str]:
    name = relative_name(root, path)
    return len(name), name


def replace_with_relative_link(root: Path, duplicate: Path, canonical: Path) -> None:
    duplicate_name = relative_name(root, duplicate)
    canonical_name = relative_name(root, canonical)
    parent = posixpath.dirname(duplicate_name) or "."
    target = posixpath.relpath(canonical_name, parent)
    temporary = duplicate.with_name(f".{duplicate.name}.deduplicate-{os.getpid()}")
    if os.path.lexists(temporary):
        raise SystemExit(f"temporary deduplication path already exists: {temporary}")
    os.symlink(target, temporary)
    os.replace(temporary, duplicate)


def deduplicate(root: Path, report_path: Path) -> tuple[int, int]:
    files = iter_regular_firmware(root)
    by_size: dict[int, list[Path]] = defaultdict(list)
    for path in files:
        by_size[path.stat().st_size].append(path)

    records: list[tuple[str, str, str, int]] = []
    saved_bytes = 0
    for size, candidates in sorted(by_size.items()):
        if len(candidates) < 2:
            continue
        by_digest: dict[str, list[Path]] = defaultdict(list)
        for path in candidates:
            by_digest[digest_file(path)].append(path)
        for digest, duplicates in sorted(by_digest.items()):
            if len(duplicates) < 2:
                continue
            ordered = sorted(duplicates, key=lambda path: canonical_key(root, path))
            canonical = ordered[0]
            canonical_stat = canonical.stat()
            for duplicate in ordered[1:]:
                duplicate_stat = duplicate.stat()
                if (
                    duplicate_stat.st_dev == canonical_stat.st_dev
                    and duplicate_stat.st_ino == canonical_stat.st_ino
                ):
                    continue
                duplicate_name = relative_name(root, duplicate)
                canonical_name = relative_name(root, canonical)
                replace_with_relative_link(root, duplicate, canonical)
                records.append((duplicate_name, canonical_name, digest, size))
                saved_bytes += size

    report_path.parent.mkdir(parents=True, exist_ok=True)
    with report_path.open("w") as report:
        for duplicate, canonical, digest, size in sorted(records):
            report.write(f"{duplicate}\t{canonical}\t{digest}\t{size}\n")

    return len(records), saved_bytes


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: deduplicate_firmware.py FIRMWARE_ROOT REPORT")
    root = Path(sys.argv[1]).resolve()
    report_path = Path(sys.argv[2])
    if not root.is_dir():
        raise SystemExit(f"firmware root is not a directory: {root}")
    count, saved_bytes = deduplicate(root, report_path)
    print(f"deduplicated {count} firmware paths ({saved_bytes} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
