#!/usr/bin/env python3

from __future__ import annotations

import fnmatch
import posixpath
import re
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


_VERSIONED_UCODE = re.compile(r"^(?P<stem>.+)-(?P<version>[0-9]+)\.ucode$")


@dataclass(frozen=True)
class FirmwareLink:
    alias: str
    raw_target: str
    target: str


class Selection:
    def __init__(self) -> None:
        self.directories: list[str] = []
        self.prefixes: list[tuple[str, str]] = []
        self.files: set[str] = set()
        self.globs: list[str] = []
        self.versioned_fallbacks: list[str] = []

    def matches(self, path: str) -> bool:
        if path in self.files:
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

    def allows_versioned_fallback(self, path: str) -> bool:
        name = PurePosixPath(path).name
        return any(name.startswith(prefix) for prefix in self.versioned_fallbacks)


def normalize_firmware_path(path: str) -> str:
    if not path or path.startswith("/"):
        raise ValueError(f"firmware path must be relative: {path!r}")
    normalized = posixpath.normpath(path)
    if normalized in ("", ".", "..") or normalized.startswith("../"):
        raise ValueError(f"firmware path escapes the firmware root: {path!r}")
    return normalized


def normalize_link_target(alias: str, target: str) -> str:
    if target.startswith("/"):
        raise ValueError(f"absolute firmware link target is not allowed: {alias} -> {target}")
    parent = posixpath.dirname(alias)
    return normalize_firmware_path(posixpath.join(parent, target))


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
        elif kind == "versioned-fallback" and len(parts) == 2:
            selection.versioned_fallbacks.append(parts[1])
        else:
            raise SystemExit(f"invalid firmware manifest entry: {raw_line}")

    return selection


def load_links(path: Path) -> dict[str, FirmwareLink]:
    links: dict[str, FirmwareLink] = {}
    for raw_line in path.read_text(errors="replace").splitlines():
        if not raw_line.startswith("Link: "):
            continue
        link = raw_line.removeprefix("Link: ")
        alias, separator, raw_target = link.partition(" -> ")
        alias = alias.strip()
        raw_target = raw_target.strip()
        if not separator or not alias or not raw_target:
            continue
        try:
            alias = normalize_firmware_path(alias)
            target = normalize_link_target(alias, raw_target)
        except ValueError as error:
            raise SystemExit(str(error)) from error
        record = FirmwareLink(alias, raw_target, target)
        previous = links.get(alias)
        if previous is not None and previous != record:
            raise SystemExit(f"conflicting firmware links for {alias}")
        links[alias] = record
    return links


def matching_link(path: str, links: dict[str, FirmwareLink]) -> FirmwareLink | None:
    candidates = [
        record
        for alias, record in links.items()
        if path == alias or path.startswith(alias + "/")
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda record: (len(record.alias), record.alias))


def resolve_link_path(path: str, links: dict[str, FirmwareLink]) -> str:
    try:
        current = normalize_firmware_path(path)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    seen = {current}

    for _ in range(len(links) + 1):
        record = matching_link(current, links)
        if record is None:
            return current
        suffix = current[len(record.alias) :].lstrip("/")
        next_path = record.target
        if suffix:
            next_path = posixpath.join(next_path, suffix)
        try:
            current = normalize_firmware_path(next_path)
        except ValueError as error:
            raise SystemExit(str(error)) from error
        if current in seen:
            raise SystemExit(f"firmware link cycle while resolving {path}: {current}")
        seen.add(current)

    raise SystemExit(f"firmware link chain is too deep while resolving {path}")


def parse_versioned_ucode(path: str) -> tuple[str, str, int] | None:
    parsed = PurePosixPath(path)
    match = _VERSIONED_UCODE.fullmatch(parsed.name)
    if match is None:
        return None
    parent = "" if str(parsed.parent) == "." else str(parsed.parent)
    return parent, match.group("stem"), int(match.group("version"))


def available_logical_files(
    archive_paths: set[str],
    exclusions: Selection,
    links: dict[str, FirmwareLink],
) -> set[str]:
    available = {
        path for path in archive_paths if not exclusions.matches(path)
    }
    for alias in links:
        target = resolve_link_path(alias, links)
        if target not in archive_paths:
            continue
        if exclusions.matches(alias) or exclusions.matches(target):
            continue
        available.add(alias)
    return available


def resolve_versioned_fallbacks(
    selection: Selection,
    exclusions: Selection,
    archive_paths: set[str],
    links: dict[str, FirmwareLink],
) -> list[tuple[str, str, str]]:
    logical_files = available_logical_files(archive_paths, exclusions, links)
    indexed: dict[tuple[str, str], list[tuple[int, str]]] = {}

    for path in logical_files:
        parsed = parse_versioned_ucode(path)
        if parsed is None:
            continue
        parent, stem, version = parsed
        indexed.setdefault((parent, stem), []).append((version, path))

    report: list[tuple[str, str, str]] = []
    for request in sorted(selection.files):
        target = resolve_link_path(request, links)
        if exclusions.matches(request) or exclusions.matches(target):
            report.append(("excluded", request, "-"))
            continue
        if target in archive_paths:
            report.append(("exact", request, request))
            continue
        if not selection.allows_versioned_fallback(request):
            report.append(("unresolved", request, "-"))
            continue

        parsed = parse_versioned_ucode(request)
        if parsed is None:
            report.append(("unresolved", request, "-"))
            continue
        parent, stem, requested_version = parsed
        candidates = [
            (version, path)
            for version, path in indexed.get((parent, stem), [])
            if version <= requested_version
        ]
        if not candidates:
            report.append(("unresolved", request, "-"))
            continue

        _, fallback = max(candidates, key=lambda candidate: (candidate[0], candidate[1]))
        selection.files.add(fallback)
        report.append(("fallback", request, fallback))

    return report


def selected_archive_targets(
    selection: Selection,
    exclusions: Selection,
    archive_paths: set[str],
    links: dict[str, FirmwareLink],
) -> set[str]:
    targets: set[str] = set()

    for logical_path in archive_paths | set(links):
        if not selection.matches(logical_path):
            continue
        target = resolve_link_path(logical_path, links)
        if exclusions.matches(logical_path) or exclusions.matches(target):
            continue
        if target in archive_paths:
            targets.add(target)

    for request in selection.files:
        target = resolve_link_path(request, links)
        if exclusions.matches(request) or exclusions.matches(target):
            continue
        if target in archive_paths:
            targets.add(target)

    return targets


def write_report(path: Path, records: list[tuple[str, str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as report:
        for status, request, resolution in records:
            report.write(f"{status}\t{request}\t{resolution}\n")


def main() -> int:
    if len(sys.argv) not in (5, 6):
        raise SystemExit(
            "usage: select_members.py INCLUDE_MANIFEST EXCLUDE_MANIFEST "
            "ARCHIVE_PREFIX WHENCE [REPORT]"
        )

    selection = load_manifest(Path(sys.argv[1]))
    exclusions = load_manifest(Path(sys.argv[2]))
    archive_prefix = sys.argv[3].rstrip("/") + "/"
    links = load_links(Path(sys.argv[4]))
    report_path = Path(sys.argv[5]) if len(sys.argv) == 6 else None

    archive_members = [line.rstrip("\n") for line in sys.stdin]
    archive_paths = {
        member[len(archive_prefix) :]
        for member in archive_members
        if member.startswith(archive_prefix)
        and not member.endswith("/")
    }
    report = resolve_versioned_fallbacks(
        selection,
        exclusions,
        archive_paths,
        links,
    )
    if report_path is not None:
        write_report(report_path, report)

    selected_targets = selected_archive_targets(
        selection,
        exclusions,
        archive_paths,
        links,
    )
    for archive_member in archive_members:
        if not archive_member.startswith(archive_prefix):
            continue
        relative_path = archive_member[len(archive_prefix) :]
        if relative_path.endswith("/"):
            continue
        if relative_path == "WHENCE" or relative_path in selected_targets:
            print(archive_member)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
