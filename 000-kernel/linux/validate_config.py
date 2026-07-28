#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path


def parse_config(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if line.startswith("CONFIG_") and "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            values[line[2:-11]] = "n"
    return values


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: validate_config.py FRAGMENT CONFIG")

    fragment_path = Path(sys.argv[1])
    config_path = Path(sys.argv[2])
    requested = parse_config(fragment_path)
    actual = parse_config(config_path)
    mismatches = [
        (key, expected, actual.get(key, "missing"))
        for key, expected in requested.items()
        if actual.get(key) != expected
    ]

    if mismatches:
        print("kernel configuration does not satisfy the policy fragment:", file=sys.stderr)
        for key, expected, observed in mismatches:
            print(
                f"  {key}: requested {expected}, observed {observed}",
                file=sys.stderr,
            )
        return 1

    print(f"validated {len(requested)} kernel policy entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
