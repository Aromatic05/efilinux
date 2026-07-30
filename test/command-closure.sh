#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command python3
[[ -d "$EFILINUX_ROOTFS" ]] || die "rootfs is missing"

python3 - "$EFILINUX_ROOTFS" <<'PY'
from pathlib import Path
import os
import re
import shlex
import sys

root = Path(sys.argv[1])
errors: list[str] = []

def target(path: str) -> Path:
    return root / path.lstrip('/')

def require_path(path: str, source: Path, kind: str) -> None:
    candidate = target(path)
    if not candidate.exists():
        errors.append(f"{kind} missing: {path} (referenced by /{source.relative_to(root)})")

def resolve_command(command: str) -> bool:
    if command.startswith('/'):
        return target(command).exists()
    return any((root / directory / command).exists() for directory in ('usr/bin', 'usr/sbin', 'bin', 'sbin'))

# Every executable script must have an interpreter that exists in the image.
for path in sorted(root.rglob('*')):
    if path.is_symlink() or not path.is_file() or not os.access(path, os.X_OK):
        continue
    try:
        first = path.open('rb').readline(4096).decode(errors='ignore').strip()
    except OSError:
        continue
    if not first.startswith('#!'):
        continue
    try:
        words = shlex.split(first[2:].strip())
    except ValueError:
        errors.append(f"invalid shebang: /{path.relative_to(root)}")
        continue
    if not words:
        errors.append(f"empty shebang: /{path.relative_to(root)}")
        continue
    interpreter = words[0]
    if interpreter == '/usr/bin/env':
        if len(words) < 2 or not resolve_command(words[1]):
            errors.append(f"shebang command missing: {words[1] if len(words) > 1 else '<missing>'} (/{path.relative_to(root)})")
    elif not target(interpreter).exists():
        errors.append(f"shebang interpreter missing: {interpreter} (/{path.relative_to(root)})")

# Entrypoints exposed by the desktop/session and D-Bus must resolve.
entry_roots = [
    root / 'etc/xdg/autostart',
    root / 'usr/share/applications',
    root / 'usr/share/xsessions',
    root / 'usr/share/dbus-1/services',
    root / 'usr/share/dbus-1/system-services',
]
for directory in entry_roots:
    if not directory.exists():
        continue
    for path in sorted(directory.rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            lines = path.read_text(errors='ignore').splitlines()
        except OSError:
            continue
        try_exec = None
        exec_value = None
        for line in lines:
            if line.startswith('TryExec='):
                try_exec = line.split('=', 1)[1].strip()
            elif line.startswith('Exec='):
                exec_value = line.split('=', 1)[1].strip()
        if try_exec and not resolve_command(try_exec):
            # Optional desktop entries with TryExec are intentionally hidden.
            continue
        if not exec_value:
            continue
        try:
            command = shlex.split(exec_value)[0]
        except (ValueError, IndexError):
            errors.append(f"invalid Exec line: /{path.relative_to(root)}")
            continue
        command = re.sub(r'%[fFuUdDnNickvm]', '', command)
        if command and not resolve_command(command):
            errors.append(f"desktop/service command missing: {command} (/{path.relative_to(root)})")

# Inittab process paths are unconditional boot dependencies.
inittab = root / 'etc/inittab'
if inittab.exists():
    for line in inittab.read_text(errors='ignore').splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split(':', 3)
        if len(fields) != 4 or not fields[3]:
            continue
        try:
            command = shlex.split(fields[3])[0]
        except (ValueError, IndexError):
            errors.append(f"invalid inittab command: {line}")
            continue
        if not resolve_command(command):
            errors.append(f"inittab command missing: {command}")

# Absolute udev helper paths must resolve after merged-/usr symlinks.
rules = root / 'usr/lib/udev/rules.d'
if rules.exists():
    for path in sorted(rules.glob('*.rules')):
        text = path.read_text(errors='ignore')
        for absolute in re.findall(r'(?<![A-Za-z0-9_.-])(/(?:usr/)?(?:s?bin|libexec)/[A-Za-z0-9_+.,:@%=-]+)', text):
            require_path(absolute, path, 'udev helper')

critical = [
    'agetty', 'mcookie', 'deallocvt', 'xauth', 'xinit', 'Xorg', 'xrdb',
    'xmodmap', 'startxfce4', 'xfce4-session', 'xfsettingsd', 'xfwm4',
    'xfce4-panel', 'xfdesktop', 'ethtool',
]
for command in critical:
    if not resolve_command(command):
        errors.append(f"critical command missing: {command}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
print(f"validated command closure for {len(critical)} critical commands")
PY

log "Executable interpreter, boot, desktop, D-Bus, and udev command closure passed"
