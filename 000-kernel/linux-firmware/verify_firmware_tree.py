#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path, PurePosixPath


_CHUNK_SIZE = 1024 * 1024


def ensure_within(root: Path, path: Path, description: str) -> None:
    try:
        path.relative_to(root)
    except ValueError as error:
        raise SystemExit(f"{description} escapes the firmware root: {path}") from error


def logical_path(root: Path, name: str) -> Path:
    parsed = PurePosixPath(name)
    if parsed.is_absolute() or ".." in parsed.parts or not parsed.parts:
        raise SystemExit(f"invalid logical firmware path: {name!r}")
    path = root.joinpath(*parsed.parts)
    ensure_within(root, path, "logical firmware path")
    return path


def resolve_entry(root: Path, path: Path) -> Path:
    try:
        resolved = path.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise SystemExit(f"cannot resolve firmware path {path}: {error}") from error
    ensure_within(root, resolved, "resolved firmware path")
    return resolved


def verify_link(root: Path, path: Path) -> None:
    target = os.readlink(path)
    if not target:
        raise SystemExit(f"empty firmware link target: {path}")
    if os.path.isabs(target):
        raise SystemExit(f"absolute firmware link target: {path} -> {target}")

    lexical_target = Path(os.path.normpath(path.parent / target))
    ensure_within(root, lexical_target, "firmware link target")
    resolved = resolve_entry(root, path)
    if path.name.endswith(".zst"):
        if not resolved.is_file():
            raise SystemExit(f"firmware file link does not resolve to a file: {path}")
    elif not resolved.is_dir():
        raise SystemExit(f"firmware directory link does not resolve to a directory: {path}")


def walk_tree(root: Path) -> tuple[int, int]:
    regular_files = 0
    links = 0
    for directory, dirnames, filenames in os.walk(root, followlinks=False):
        directory_path = Path(directory)
        retained_directories: list[str] = []
        for name in dirnames:
            path = directory_path / name
            if path.is_symlink():
                verify_link(root, path)
                links += 1
            elif path.is_dir():
                retained_directories.append(name)
            else:
                raise SystemExit(f"unsupported firmware directory entry: {path}")
        dirnames[:] = retained_directories

        for name in filenames:
            path = directory_path / name
            if path.is_symlink():
                verify_link(root, path)
                links += 1
                continue
            if not path.is_file():
                raise SystemExit(f"unsupported firmware file type: {path}")
            if path.suffix != ".zst":
                raise SystemExit(f"uncompressed firmware file remains in package tree: {path}")
            regular_files += 1
    return regular_files, links


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(_CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest()


def verify_selection_report(root: Path, report_path: Path) -> int:
    verified = 0
    for line_number, raw_line in enumerate(report_path.read_text().splitlines(), 1):
        if not raw_line:
            continue
        fields = raw_line.split("\t")
        if len(fields) != 3:
            raise SystemExit(
                f"malformed firmware selection report line {line_number}: {raw_line}"
            )
        status, request, selected = fields
        if status not in {"exact", "fallback"}:
            continue
        selected_path = logical_path(root, selected + ".zst")
        resolved = resolve_entry(root, selected_path)
        if not resolved.is_file():
            raise SystemExit(
                f"selected firmware does not resolve to a file: {request} -> {selected}"
            )
        verified += 1
    return verified


def verify_dedup_report(root: Path, report_path: Path) -> int:
    verified = 0
    for line_number, raw_line in enumerate(report_path.read_text().splitlines(), 1):
        if not raw_line:
            continue
        fields = raw_line.split("\t")
        if len(fields) != 4:
            raise SystemExit(
                f"malformed firmware deduplication report line {line_number}: {raw_line}"
            )
        duplicate, canonical, expected_digest, raw_size = fields
        try:
            expected_size = int(raw_size)
        except ValueError as error:
            raise SystemExit(
                f"invalid firmware deduplication size on line {line_number}: {raw_size}"
            ) from error
        duplicate_path = logical_path(root, duplicate)
        canonical_path = logical_path(root, canonical)
        if not duplicate_path.is_symlink():
            raise SystemExit(f"deduplicated firmware path is not a link: {duplicate}")
        if not canonical_path.is_file() or canonical_path.is_symlink():
            raise SystemExit(f"deduplication canonical is not a regular file: {canonical}")
        if resolve_entry(root, duplicate_path) != resolve_entry(root, canonical_path):
            raise SystemExit(
                f"deduplicated firmware path resolves to the wrong target: {duplicate}"
            )
        if canonical_path.stat().st_size != expected_size:
            raise SystemExit(f"deduplication size changed for canonical firmware: {canonical}")
        if digest_file(canonical_path) != expected_digest:
            raise SystemExit(f"deduplication digest mismatch for canonical firmware: {canonical}")
        verified += 1
    return verified


def main() -> int:
    if len(sys.argv) not in (2, 3, 4):
        raise SystemExit(
            "usage: verify_firmware_tree.py FIRMWARE_ROOT "
            "[SELECTION_REPORT [DEDUP_REPORT]]"
        )
    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        raise SystemExit(f"firmware root is not a directory: {root}")

    regular_files, links = walk_tree(root)
    selected = verify_selection_report(root, Path(sys.argv[2])) if len(sys.argv) >= 3 else 0
    deduplicated = verify_dedup_report(root, Path(sys.argv[3])) if len(sys.argv) == 4 else 0
    print(
        "verified firmware tree: "
        f"{regular_files} regular files, {links} links, "
        f"{selected} selected paths, {deduplicated} deduplicated paths"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
