#!/usr/bin/env python3
"""Stage fixed k3d-manager helpers with no-follow opens and atomic replacement."""

import hashlib
import errno
import os
import secrets
import stat
import sys

HELPERS = (
    ("update-hosts-entry.sh", "k3dm-update-hosts-entry"),
    ("k3dm-vault-ca-trust-supervisor", "k3dm-vault-ca-trust-supervisor"),
    ("k3dm-browser-listener-relay", "k3dm-browser-listener-relay"),
    ("k3dm-browser-listener-supervisor", "k3dm-browser-listener-supervisor"),
)
DESTINATION = "/Library/PrivilegedHelperTools"


def _require_trusted_directory(path, owner):
    info = os.stat(path, follow_symlinks=False)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != owner or info.st_mode & 0o022:
        raise ValueError(f"untrusted privileged-helper directory: {path}")
    parent = os.path.dirname(path)
    parent_info = os.stat(parent, follow_symlinks=False)
    if not stat.S_ISDIR(parent_info.st_mode) or parent_info.st_uid != owner or parent_info.st_mode & 0o022:
        raise ValueError(f"untrusted privileged-helper parent: {parent}")


def install_helpers(source_dir, destination_dir=DESTINATION, owner=None, group=None):
    owner = os.geteuid() if owner is None else owner
    group = os.getegid() if group is None else group
    if os.geteuid() != owner:
        raise ValueError("helper installation must run as the expected owner")
    _require_trusted_directory(destination_dir, owner)
    directory_fd = os.open(destination_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        directory_info = os.fstat(directory_fd)
        if directory_info.st_uid != owner or directory_info.st_mode & 0o022:
            raise ValueError("privileged-helper directory changed during validation")
        for source_name, destination_name in HELPERS:
            source_path = os.path.join(source_dir, source_name)
            source_fd = os.open(source_path, os.O_RDONLY | os.O_NOFOLLOW)
            temp_name = f".k3dm-stage-{secrets.token_hex(12)}"
            try:
                source_info = os.fstat(source_fd)
                if not stat.S_ISREG(source_info.st_mode):
                    raise ValueError(f"helper source is not a regular file: {source_name}")
                target_fd = os.open(
                    temp_name,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                    0o700,
                    dir_fd=directory_fd,
                )
                source_hash = hashlib.sha256()
                try:
                    while True:
                        chunk = os.read(source_fd, 131072)
                        if not chunk:
                            break
                        source_hash.update(chunk)
                        view = memoryview(chunk)
                        while view:
                            written = os.write(target_fd, view)
                            view = view[written:]
                    os.fchown(target_fd, owner, group)
                    os.fchmod(target_fd, 0o755)
                    os.fsync(target_fd)
                    target_info = os.fstat(target_fd)
                    if (not stat.S_ISREG(target_info.st_mode) or target_info.st_uid != owner
                            or target_info.st_gid != group or stat.S_IMODE(target_info.st_mode) != 0o755):
                        raise ValueError(f"staged helper metadata is invalid: {source_name}")
                finally:
                    os.close(target_fd)
                staged_fd = os.open(temp_name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory_fd)
                try:
                    staged_hash = hashlib.sha256()
                    while True:
                        chunk = os.read(staged_fd, 131072)
                        if not chunk:
                            break
                        staged_hash.update(chunk)
                    if staged_hash.digest() != source_hash.digest():
                        raise ValueError(f"staged helper bytes differ from source: {source_name}")
                finally:
                    os.close(staged_fd)
                os.replace(temp_name, destination_name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
                installed_info = os.stat(destination_name, dir_fd=directory_fd, follow_symlinks=False)
                if (not stat.S_ISREG(installed_info.st_mode) or installed_info.st_uid != owner
                        or installed_info.st_gid != group or stat.S_IMODE(installed_info.st_mode) != 0o755):
                    raise ValueError(f"installed helper metadata is invalid: {destination_name}")
                installed_fd = os.open(destination_name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory_fd)
                try:
                    installed_hash = hashlib.sha256()
                    while True:
                        chunk = os.read(installed_fd, 131072)
                        if not chunk:
                            break
                        installed_hash.update(chunk)
                    if installed_hash.digest() != source_hash.digest():
                        raise ValueError(f"installed helper bytes differ from source: {destination_name}")
                finally:
                    os.close(installed_fd)
            finally:
                os.close(source_fd)
                try:
                    os.unlink(temp_name, dir_fd=directory_fd)
                except FileNotFoundError:
                    pass
        try:
            os.fsync(directory_fd)
        except OSError as exc:
            # Some macOS filesystem providers reject directory fsync; file fsync and
            # atomic rename still provide the required integrity for this operation.
            if exc.errno not in (errno.EINVAL, errno.ENOTSUP, errno.EOPNOTSUPP, errno.EBADF):
                raise
    finally:
        os.close(directory_fd)


def main(argv):
    if os.geteuid() != 0 or len(argv) != 1 or not os.path.isabs(argv[0]):
        print("refusing unexpected privileged-helper install request", file=sys.stderr)
        return 2
    try:
        install_helpers(argv[0], owner=0, group=0)
    except (OSError, ValueError) as exc:
        print(f"privileged-helper installation refused: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
