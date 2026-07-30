#!/usr/bin/env python3

from __future__ import annotations

import argparse
import configparser
import fnmatch
import os
import sys
from pathlib import Path

KEEP_DIRECTORIES = (
    "16/actions",
    "16/apps",
    "16/devices",
    "16/emblems",
    "16/places",
    "16/status",
    "22/panel",
    "24/animations",
    "32/apps",
    "32/status",
    "48/apps",
    "128/places",
    "scalable/apps",
    "scalable/devices",
    "scalable/mimetypes",
    "scalable/places",
    "scalable/status",
    "symbolic/actions",
    "symbolic/apps",
    "symbolic/categories",
    "symbolic/devices",
    "symbolic/emblems",
    "symbolic/emotes",
    "symbolic/mimetypes",
    "symbolic/places",
    "symbolic/status",
)

FILTERED_DIRECTORIES = {
    "16/actions": "actions",
    "16/apps": "applications",
    "22/panel": "panel",
    "32/apps": "applications",
    "48/apps": "applications",
    "scalable/apps": "applications",
    "symbolic/apps": "applications",
}

PRESERVED_TOP_LEVEL = {
    "AUTHORS",
    "COPYING",
    "cursors",
    "index.theme",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Reduce a Qogir installation to EFI Linux runtime coverage"
    )
    parser.add_argument("--theme", type=Path, required=True)
    parser.add_argument("--applications", type=Path, required=True)
    parser.add_argument("--actions", type=Path, required=True)
    parser.add_argument("--panel", type=Path, required=True)
    return parser.parse_args()


def read_patterns(path: Path) -> tuple[str, ...]:
    patterns: list[str] = []
    for line_number, raw_line in enumerate(path.read_text().splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "/" in line or line in {".", ".."}:
            raise ValueError(f"unsafe icon pattern in {path}:{line_number}: {line}")
        patterns.append(line)
    if not patterns:
        raise ValueError(f"icon policy is empty: {path}")
    return tuple(patterns)


def icon_name(path: Path) -> str:
    name = path.name
    for suffix in (".symbolic.svg", ".symbolic.png", ".svg", ".png", ".xpm"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return path.stem


def matches(path: Path, patterns: tuple[str, ...]) -> bool:
    name = icon_name(path)
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in patterns)


def resolve_inside_theme(theme: Path, path: Path) -> Path:
    link = Path(os.readlink(path))
    if link.is_absolute():
        target = Path(os.path.normpath(link))
    else:
        target = Path(os.path.abspath(path.parent / link))
    try:
        target.relative_to(theme)
    except ValueError as error:
        raise ValueError(f"icon link escapes the theme: {path} -> {target}") from error
    return target


def add_tree(paths: set[Path], root: Path) -> None:
    paths.add(root)
    if root.is_dir() and not root.is_symlink():
        paths.update(root.rglob("*"))


def collect_keep_set(
    theme: Path,
    policies: dict[str, tuple[str, ...]],
) -> set[Path]:
    keep: set[Path] = set()
    pending: list[Path] = []

    for name in PRESERVED_TOP_LEVEL:
        path = theme / name
        if not path.exists() and not path.is_symlink():
            raise ValueError(f"required Qogir payload is missing: {name}")
        add_tree(keep, path)

    for relative_directory in KEEP_DIRECTORIES:
        directory = theme / relative_directory
        if not directory.is_dir():
            raise ValueError(f"required Qogir directory is missing: {relative_directory}")
        keep.add(directory)
        policy_name = FILTERED_DIRECTORIES.get(relative_directory)
        for entry in directory.iterdir():
            if policy_name is None:
                add_tree(keep, entry)
            elif matches(entry, policies[policy_name]):
                add_tree(keep, entry)

    pending.extend(path for path in keep if path.is_symlink())
    while pending:
        path = pending.pop()
        target = resolve_inside_theme(theme, path)
        if not target.exists() and not target.is_symlink():
            raise ValueError(f"selected icon has a missing target: {path}")
        if target in keep:
            continue
        add_tree(keep, target)
        if target.is_symlink():
            pending.append(target)

    for path in list(keep):
        parent = path.parent
        while parent != theme:
            keep.add(parent)
            parent = parent.parent
    keep.add(theme)
    return keep


def remove_unselected_entries(theme: Path, keep: set[Path]) -> None:
    paths = sorted(theme.rglob("*"), key=lambda path: len(path.parts), reverse=True)
    for path in paths:
        if path in keep:
            continue
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.is_dir():
            path.rmdir()

def rewrite_index(theme: Path) -> None:
    index = theme / "index.theme"
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.optionxform = str
    with index.open(encoding="utf-8") as stream:
        parser.read_file(stream)

    if "Icon Theme" not in parser:
        raise ValueError("Qogir index.theme has no Icon Theme section")

    missing_sections = [directory for directory in KEEP_DIRECTORIES if directory not in parser]
    if missing_sections:
        raise ValueError(
            "Qogir index.theme lacks retained directory sections: "
            + ", ".join(missing_sections)
        )

    for section in list(parser.sections()):
        if section != "Icon Theme" and section not in KEEP_DIRECTORIES:
            parser.remove_section(section)
    theme_section = parser["Icon Theme"]
    theme_section["Inherits"] = "hicolor"
    theme_section["Directories"] = ",".join(KEEP_DIRECTORIES)
    theme_section["DesktopDefault"] = "48"
    theme_section["DesktopSizes"] = "16,32,48"
    theme_section["ToolbarDefault"] = "16"
    theme_section["ToolbarSizes"] = "16"
    theme_section["MainToolbarDefault"] = "16"
    theme_section["MainToolbarSizes"] = "16"
    theme_section["SmallDefault"] = "16"
    theme_section["SmallSizes"] = "16"
    theme_section["PanelDefault"] = "22"
    theme_section["PanelSizes"] = "22"
    theme_section["DialogDefault"] = "32"
    theme_section["DialogSizes"] = "16,32,48"

    temporary = index.with_suffix(".theme.new")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        parser.write(stream, space_around_delimiters=False)
    temporary.replace(index)


def validate(theme: Path) -> None:
    for directory in KEEP_DIRECTORIES:
        path = theme / directory
        if not path.is_dir() or not any(path.iterdir()):
            raise ValueError(f"retained Qogir directory is empty: {directory}")

    for path in theme.rglob("*"):
        if not path.is_symlink():
            continue
        resolve_inside_theme(theme, path)
        if not path.exists():
            raise ValueError(f"Qogir contains a broken symbolic link: {path}")

    required_icons = (
        "scalable/apps/org.xfce.terminal.svg",
        "scalable/apps/org.xfce.thunar.svg",
        "scalable/apps/org.xfce.settings.manager.svg",
        "scalable/devices/drive-harddisk.svg",
        "scalable/mimetypes/application-pdf.svg",
        "128/places/folder.svg",
        "symbolic/actions/edit-copy-symbolic.svg",
        "symbolic/status/network-wireless-signal-excellent-symbolic.svg",
        "cursors/left_ptr",
    )
    missing = [relative for relative in required_icons if not (theme / relative).exists()]
    if missing:
        raise ValueError("required Qogir icons were pruned: " + ", ".join(missing))


def main() -> int:
    args = parse_args()
    theme = args.theme.resolve()
    if not (theme / "index.theme").is_file():
        raise ValueError(f"not a Qogir theme tree: {theme}")

    policies = {
        "applications": read_patterns(args.applications),
        "actions": read_patterns(args.actions),
        "panel": read_patterns(args.panel),
    }
    keep = collect_keep_set(theme, policies)
    remove_unselected_entries(theme, keep)
    rewrite_index(theme)
    validate(theme)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, configparser.Error) as error:
        print(f"prune-theme: {error}", file=sys.stderr)
        raise SystemExit(1)
