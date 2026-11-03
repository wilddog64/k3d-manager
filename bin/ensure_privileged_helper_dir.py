#!/usr/bin/python3 -I
"""Create or validate the fixed macOS privileged-helper directory."""

import os
import stat
import sys

HELPER_DIRECTORY = "/Library/PrivilegedHelperTools"


def ensure_directory(path, owner):
    if not os.path.isabs(path) or path == "/":
        raise ValueError("helper directory path must be absolute")
    parent = os.path.dirname(path)
    parent_info = os.stat(parent, follow_symlinks=False)
    if not stat.S_ISDIR(parent_info.st_mode) or parent_info.st_uid != owner or parent_info.st_mode & 0o022:
        raise ValueError("helper directory parent must be trusted and non-writable")
    try:
        info = os.stat(path, follow_symlinks=False)
    except FileNotFoundError:
        os.mkdir(path, 0o755)
        info = os.stat(path, follow_symlinks=False)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != owner or info.st_mode & 0o022:
        raise ValueError("privileged-helper directory must be a non-writable directory owned by root")


def main(argv):
    if os.geteuid() != 0 or argv != [HELPER_DIRECTORY]:
        print("refusing unexpected privileged-helper directory", file=sys.stderr)
        return 2
    try:
        ensure_directory(HELPER_DIRECTORY, 0)
    except (OSError, ValueError) as exc:
        print(f"privileged-helper directory refused: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
