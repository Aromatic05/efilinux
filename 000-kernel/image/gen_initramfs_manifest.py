#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import stat
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable, Iterator


@dataclass(frozen=True)
class OwnershipRule:
    path: PurePosixPath
    uid: int
    gid: int

    def applies_to(self, candidate: PurePosixPath) -> bool:
        return candidate == self.path or self.path in candidate.parents


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a deterministic gen_init_cpio manifest for the EFILinux rootfs."
    )
    parser.add_argument("--rootfs", required=True, type=Path)
    parser.add_argument("--devices", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def reject_whitespace(value: str, description: str) -> None:
    if any(character.isspace() for character in value):
        raise ValueError(f"{description} contains whitespace unsupported by gen_init_cpio: {value}")


def path_exists_without_following_ancestor_symlinks(rootfs: Path, path: PurePosixPath) -> bool:
    current = rootfs
    for index, component in enumerate(path.parts[1:]):
        current = current / component
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            return False
        if index + 1 < len(path.parts[1:]) and stat.S_ISLNK(metadata.st_mode):
            return False
    return True


def parse_home_ownership_rules(rootfs: Path) -> list[OwnershipRule]:
    passwd_path = rootfs / "etc/passwd"
    homes: dict[PurePosixPath, set[tuple[int, int]]] = {}

    with passwd_path.open(encoding="utf-8") as passwd_file:
        for line_number, raw_line in enumerate(passwd_file, start=1):
            line = raw_line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split(":")
            if len(fields) != 7:
                raise ValueError(f"invalid passwd entry at {passwd_path}:{line_number}")
            _, _, uid_text, gid_text, _, home_text, _ = fields
            home = PurePosixPath(home_text)
            if not home.is_absolute() or home == PurePosixPath("/"):
                continue
            if not path_exists_without_following_ancestor_symlinks(rootfs, home):
                continue
            homes.setdefault(home, set()).add((int(uid_text), int(gid_text)))

    rules = [
        OwnershipRule(path=home, uid=next(iter(owners))[0], gid=next(iter(owners))[1])
        for home, owners in homes.items()
        if len(owners) == 1
    ]
    return sorted(rules, key=lambda rule: len(rule.path.parts), reverse=True)


def ownership_for(path: PurePosixPath, rules: Iterable[OwnershipRule]) -> tuple[int, int]:
    for rule in rules:
        if rule.applies_to(path):
            return rule.uid, rule.gid
    return 0, 0


def walk_rootfs(rootfs: Path) -> Iterator[tuple[Path, PurePosixPath, os.stat_result]]:
    def visit(directory: Path, archive_directory: PurePosixPath) -> Iterator[tuple[Path, PurePosixPath, os.stat_result]]:
        with os.scandir(directory) as entries:
            ordered_entries = sorted(entries, key=lambda entry: os.fsencode(entry.name))
        for entry in ordered_entries:
            source = Path(entry.path)
            archive_path = archive_directory / entry.name
            metadata = source.lstat()
            yield source, archive_path, metadata
            if stat.S_ISDIR(metadata.st_mode):
                yield from visit(source, archive_path)

    yield from visit(rootfs, PurePosixPath("/"))


def format_mode(mode: int) -> str:
    return f"{stat.S_IMODE(mode):04o}"


def manifest_line(
    source: Path,
    archive_path: PurePosixPath,
    metadata: os.stat_result,
    ownership_rules: Iterable[OwnershipRule],
) -> str:
    archive_name = archive_path.as_posix()
    reject_whitespace(archive_name, "archive path")
    uid, gid = ownership_for(archive_path, ownership_rules)
    mode = format_mode(metadata.st_mode)

    if stat.S_ISREG(metadata.st_mode):
        source_name = str(source.absolute())
        reject_whitespace(source_name, "source path")
        return f"file {archive_name} {source_name} {mode} {uid} {gid}"
    if stat.S_ISDIR(metadata.st_mode):
        return f"dir {archive_name} {mode} {uid} {gid}"
    if stat.S_ISLNK(metadata.st_mode):
        target = os.readlink(source)
        reject_whitespace(target, "symbolic-link target")
        return f"slink {archive_name} {target} {mode} {uid} {gid}"
    if stat.S_ISFIFO(metadata.st_mode):
        return f"pipe {archive_name} {mode} {uid} {gid}"
    if stat.S_ISSOCK(metadata.st_mode):
        return f"sock {archive_name} {mode} {uid} {gid}"
    raise ValueError(f"unsupported rootfs entry type: {source}")


def read_device_entries(device_manifest: Path) -> list[str]:
    entries: list[str] = []
    with device_manifest.open(encoding="utf-8") as manifest_file:
        for line_number, raw_line in enumerate(manifest_file, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split()
            if len(fields) != 8 or fields[0] != "nod":
                raise ValueError(
                    f"unsupported entry at {device_manifest}:{line_number}; expected nod"
                )
            reject_whitespace(fields[1], "device path")
            entries.append(" ".join(fields))
    return entries


def write_manifest(output: Path, lines: Iterable[str]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    content = "\n".join(lines) + "\n"
    if output.exists() and output.read_text(encoding="utf-8") == content:
        return

    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output_file:
            output_file.write(content)
        temporary.chmod(0o644)
        temporary.replace(output)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def main() -> None:
    arguments = parse_arguments()
    rootfs = arguments.rootfs.absolute()
    devices = arguments.devices.absolute()
    output = arguments.output.absolute()

    if not rootfs.is_dir():
        raise ValueError(f"rootfs directory does not exist: {rootfs}")
    if not devices.is_file():
        raise ValueError(f"device manifest does not exist: {devices}")
    if not (rootfs / "etc/passwd").is_file():
        raise ValueError(f"rootfs passwd database does not exist: {rootfs / 'etc/passwd'}")

    ownership_rules = parse_home_ownership_rules(rootfs)
    lines = [
        manifest_line(source, archive_path, metadata, ownership_rules)
        for source, archive_path, metadata in walk_rootfs(rootfs)
    ]
    lines.extend(read_device_entries(devices))
    write_manifest(output, lines)


if __name__ == "__main__":
    main()
