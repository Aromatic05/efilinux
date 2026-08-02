#!/usr/bin/env python3

from __future__ import annotations

import os
import posixpath
import sys
from pathlib import Path, PurePosixPath

from select_members import FirmwareLink, load_links, resolve_link_path


def filesystem_path(root: Path, relative_path: str) -> Path:
    return root.joinpath(*PurePosixPath(relative_path).parts)


def has_ancestor(alias: str, ancestors: set[str]) -> bool:
    return any(alias.startswith(ancestor + "/") for ancestor in ancestors)


def create_link(link_path: Path, target: str) -> None:
    link_path.parent.mkdir(parents=True, exist_ok=True)
    if os.path.lexists(link_path):
        raise SystemExit(f"firmware link path already exists: {link_path}")
    os.symlink(target, link_path)


def relative_target(alias: str, final_target: str) -> str:
    parent = posixpath.dirname(alias) or "."
    return posixpath.relpath(final_target, parent)


def materialize_links(whence: Path, root: Path) -> None:
    links = load_links(whence)
    directory_links: list[tuple[FirmwareLink, str]] = []
    file_links: list[tuple[FirmwareLink, str]] = []

    for record in links.values():
        final_target = resolve_link_path(record.alias, links)
        target_file = filesystem_path(root, final_target + ".zst")
        target_directory = filesystem_path(root, final_target)
        if target_file.is_file():
            file_links.append((record, final_target))
        elif target_directory.is_dir():
            directory_links.append((record, final_target))

    selected_directories: set[str] = set()
    for record, final_target in sorted(
        directory_links,
        key=lambda item: (item[0].alias.count("/"), item[0].alias),
    ):
        if has_ancestor(record.alias, selected_directories):
            continue
        create_link(
            filesystem_path(root, record.alias),
            relative_target(record.alias, final_target),
        )
        selected_directories.add(record.alias)

    for record, final_target in sorted(file_links, key=lambda item: item[0].alias):
        if has_ancestor(record.alias, selected_directories):
            continue
        create_link(
            filesystem_path(root, record.alias + ".zst"),
            relative_target(record.alias, final_target) + ".zst",
        )


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: materialize_links.py WHENCE FIRMWARE_ROOT")
    whence = Path(sys.argv[1])
    root = Path(sys.argv[2])
    if not root.is_dir():
        raise SystemExit(f"firmware root is not a directory: {root}")
    materialize_links(whence, root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
