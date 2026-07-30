#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import stat
import tempfile
from pathlib import Path, PurePosixPath
from typing import Iterable, Iterator


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a deterministic gen_init_cpio manifest for the EFI Linux rootfs."
    )
    parser.add_argument("--rootfs", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def reject_whitespace(value: str, description: str) -> None:
    if any(character.isspace() for character in value):
        raise ValueError(f"{description} contains whitespace unsupported by gen_init_cpio: {value}")


def walk_rootfs(rootfs: Path) -> Iterator[tuple[Path, PurePosixPath, os.stat_result]]:
    def visit(
        directory: Path,
        archive_directory: PurePosixPath,
    ) -> Iterator[tuple[Path, PurePosixPath, os.stat_result]]:
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
) -> str:
    archive_name = archive_path.as_posix()
    reject_whitespace(archive_name, "archive path")
    uid = metadata.st_uid
    gid = metadata.st_gid
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
    if stat.S_ISCHR(metadata.st_mode):
        return (
            f"nod {archive_name} {mode} {uid} {gid} c "
            f"{os.major(metadata.st_rdev)} {os.minor(metadata.st_rdev)}"
        )
    if stat.S_ISBLK(metadata.st_mode):
        return (
            f"nod {archive_name} {mode} {uid} {gid} b "
            f"{os.major(metadata.st_rdev)} {os.minor(metadata.st_rdev)}"
        )
    raise ValueError(f"unsupported rootfs entry type: {source}")


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
    output = arguments.output.absolute()

    if not rootfs.is_dir():
        raise ValueError(f"rootfs directory does not exist: {rootfs}")
    if not (rootfs / "etc/passwd").is_file():
        raise ValueError(f"rootfs passwd database does not exist: {rootfs / 'etc/passwd'}")

    lines = [
        manifest_line(source, archive_path, metadata)
        for source, archive_path, metadata in walk_rootfs(rootfs)
    ]
    write_manifest(output, lines)


if __name__ == "__main__":
    main()
