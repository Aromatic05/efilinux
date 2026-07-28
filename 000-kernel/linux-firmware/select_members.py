#!/usr/bin/env python3

from __future__ import annotations

import fnmatch
import sys
from pathlib import Path


class Selection:
    def __init__(self) -> None:
        self.directories: list[str] = []
        self.prefixes: list[tuple[str, str]] = []
        self.files: set[str] = set()
        self.globs: list[str] = []

    def matches(self, path: str) -> bool:
        if path == "WHENCE" or path in self.files:
            return True
        if any(path.startswith(directory) for directory in self.directories):
            return True
        if any(
            path.startswith(parent + prefix)
            and "/" not in path[len(parent) :]
            for parent, prefix in self.prefixes
        ):
            return True
        return any(fnmatch.fnmatchcase(path, pattern) for pattern in self.globs)


def load_manifest(path: Path) -> Selection:
    selection = Selection()

    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        parts = line.split()
        kind = parts[0]
        if kind == "directory" and len(parts) == 2:
            selection.directories.append(parts[1].rstrip("/") + "/")
        elif kind == "prefix" and len(parts) == 3:
            selection.prefixes.append((parts[1].rstrip("/") + "/", parts[2]))
        elif kind == "file" and len(parts) == 2:
            selection.files.add(parts[1])
        elif kind == "glob" and len(parts) == 2:
            selection.globs.append(parts[1])
        else:
            raise SystemExit(f"invalid firmware manifest entry: {raw_line}")

    return selection


def load_links(path: Path) -> dict[str, str]:
    links: dict[str, str] = {}
    for raw_line in path.read_text(errors="replace").splitlines():
        if not raw_line.startswith("Link: "):
            continue
        link = raw_line.removeprefix("Link: ")
        alias, separator, target = link.partition(" -> ")
        if separator and alias and target:
            links[alias] = target
    return links


def expand_link_targets(
    selection: Selection,
    exclusions: Selection,
    links: dict[str, str],
) -> set[str]:
    targets: set[str] = set()
    changed = True
    while changed:
        changed = False
        for alias, target in links.items():
            if exclusions.matches(alias) or exclusions.matches(target):
                continue
            if not (selection.matches(alias) or alias in targets):
                continue
            if target not in targets:
                targets.add(target)
                changed = True
    return targets


def main() -> int:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: select_members.py INCLUDE_MANIFEST EXCLUDE_MANIFEST "
            "ARCHIVE_PREFIX WHENCE"
        )

    selection = load_manifest(Path(sys.argv[1]))
    exclusions = load_manifest(Path(sys.argv[2]))
    archive_prefix = sys.argv[3].rstrip("/") + "/"
    link_targets = expand_link_targets(
        selection,
        exclusions,
        load_links(Path(sys.argv[4])),
    )

    for raw_member in sys.stdin:
        archive_member = raw_member.rstrip("\n")
        if not archive_member.startswith(archive_prefix):
            continue
        relative_path = archive_member[len(archive_prefix) :]
        if relative_path.endswith("/"):
            continue
        if exclusions.matches(relative_path):
            continue
        if selection.matches(relative_path) or relative_path in link_targets:
            print(archive_member)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
