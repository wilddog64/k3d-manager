"""Isolation primitives for acceptance child processes."""
import os
import re
import shutil
import subprocess
from pathlib import Path
from urllib.parse import urlsplit

BLOCKED_PORTS = {9091, 19094, 7443}


def validate_url(url):
    parsed = urlsplit(url)
    try:
        port = parsed.port
    except ValueError as exc:
        raise RuntimeError("invalid child URL") from exc
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "::1"} or not port or port in BLOCKED_PORTS:
        raise RuntimeError("refused child URL")
    return url


def prepare(run_dir):
    scratch = run_dir / "home"
    scratch.mkdir(mode=0o700, exist_ok=True)
    if scratch.resolve() == Path.home().resolve():
        raise RuntimeError("scratch HOME equals real HOME")
    stub = run_dir / "stubs"
    stub.mkdir(mode=0o700, exist_ok=True)
    for name in ("launchctl", "kubectl", "security", "docker", "git", "curl"):
        script = stub / name
        script.write_text('#!/bin/sh\nprintf "%s %s\\n" "$0" "$*" >> "$K3DM_STUB_LOG"\n[ "$1" = push ] && exit 1\nexit 0\n')
        script.chmod(0o700)
    return scratch, stub


def child_env(run_dir, explicit=None):
    scratch, stub = prepare(run_dir)
    parent_path = os.environ.get("PATH", "/usr/bin:/bin")
    env = {key: os.environ[key] for key in ("LANG", "TMPDIR") if key in os.environ}
    env.update(PATH=f"{stub}:{parent_path}", HOME=str(scratch), K3DM_STUB_LOG=str(run_dir / "stub.log"))
    env.update(explicit or {})
    return env


def run(argv, run_dir, explicit=None, **kwargs):
    return subprocess.run(list(map(str, argv)), shell=False, env=child_env(run_dir, explicit), text=True, capture_output=True, **kwargs)


def validate_text_url(url):
    return validate_url(url)
