"""Pytest-wide hermeticity guard for offline k3d-manager tests."""

import ipaddress
import os
import shlex
import shutil
import socket
import subprocess
from pathlib import Path

import pytest


HERMETIC_BLOCKED = {
    "security",
    "kubectl",
    "argocd",
    "gh",
    "helm",
    "docker",
    "launchctl",
    "curl",
    "ssh",
    "scp",
}
HERMETIC_GIT_COMMANDS = {"fetch", "pull", "push", "clone", "ls-remote"}
_ORIGINAL_POPEN_INIT = subprocess.Popen.__init__


class HermeticViolation(RuntimeError):
    """Raised when a test attempts an unapproved external operation."""


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "external(reason): allow a deliberately live external call"
    )
    config._k3dm_hermetic_offenders = []


def pytest_terminal_summary(terminalreporter, exitstatus, config):
    del exitstatus
    offenders = getattr(config, "_k3dm_hermetic_offenders", [])
    if offenders:
        terminalreporter.write_sep("-", "hermetic violations (report mode)")
        for nodeid, command, rule in offenders:
            terminalreporter.write_line(f"{nodeid}: {command} ({rule})")


def _command_words(args):
    if isinstance(args, str):
        return shlex.split(args)
    return list(args) if args else []


def _under(path, roots):
    for root in roots:
        try:
            Path(path).resolve().relative_to(Path(root).resolve())
        except (ValueError, OSError):
            continue
        return True
    return False


def _allowed_executable(path, tmp_path, basetemp):
    tripwire_roots = list(Path(os.environ.get("TMPDIR", "/tmp")).glob("k3dm-tripwire.*"))
    return _under(path, (tmp_path, basetemp, *tripwire_roots))


def _remote_url(cwd, name="origin"):
    try:
        probe = _ORIGINAL_POPEN_INIT
        process = subprocess.Popen.__new__(subprocess.Popen)
        probe(
            process,
            ["git", "-C", str(cwd), "config", "--get", f"remote.{name}.url"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        result = process.communicate()[0].strip()
    except (OSError, subprocess.SubprocessError):
        return ""
    return result


def _is_remote_url(value):
    return value.startswith(("http://", "https://", "ssh://", "git@"))


def _git_parse(words, cwd):
    effective_cwd = Path(cwd).resolve()
    index = 1
    while index < len(words):
        word = words[index]
        if word == "-C" or word in {
            "-c",
            "--git-dir",
            "--work-tree",
            "--namespace",
            "--config-env",
        }:
            if word == "-C" and index + 1 < len(words):
                directory = Path(words[index + 1])
                if not directory.is_absolute():
                    directory = effective_cwd / directory
                effective_cwd = directory.resolve()
            index += 2
            continue
        if word.startswith("-"):
            index += 1
            continue
        return word, index, effective_cwd
    return "", -1, effective_cwd


def _git_remote_violation(words, cwd):
    if not words or os.path.basename(words[0]) != "git":
        return False
    subcommand, index, effective_cwd = _git_parse(words, cwd)
    if subcommand not in HERMETIC_GIT_COMMANDS:
        return False
    if any(_is_remote_url(word) for word in words[index + 1 :]):
        return True
    if subcommand == "clone":
        source = words[index + 1] if len(words) > index + 1 else ""
        if source and Path(source).expanduser().exists():
            return False
    remote_name = "origin"
    if subcommand in {"fetch", "pull", "push", "ls-remote"}:
        remote_name = next(
            (word for word in words[index + 1 :] if not word.startswith("-")),
            "origin",
        )
    remote = _remote_url(effective_cwd, remote_name)
    if not remote and remote_name != "origin":
        remote = _remote_url(effective_cwd)
    return _is_remote_url(remote)


def _network_violation(sock, address):
    if sock.family == socket.AF_UNIX:
        return False
    if sock.family not in (socket.AF_INET, socket.AF_INET6):
        return False
    host = address[0] if isinstance(address, tuple) else address
    if host == "localhost" or host == "::1":
        return False
    try:
        return not ipaddress.ip_address(host).is_loopback
    except ValueError:
        return True


@pytest.fixture(autouse=True)
def _hermetic(monkeypatch, request, tmp_path, tmp_path_factory):
    mode = os.environ.get("K3DM_HERMETIC", "enforce").lower()
    if mode == "off" or request.node.get_closest_marker("external"):
        yield
        return

    basetemp = tmp_path_factory.getbasetemp()

    def violation(command, rule):
        current_mode = os.environ.get("K3DM_HERMETIC", mode).lower()
        message = (
            f"hermetic: {request.node.nodeid} called real '{command}' ({rule}) "
            "— stub it, or put a stub in tmp_path"
        )
        if current_mode == "report":
            request.config._k3dm_hermetic_offenders.append(
                (request.node.nodeid, command, rule)
            )
            return
        raise HermeticViolation(message)

    def guarded_init(self, args, *popen_args, **kwargs):
        words = _command_words(args)
        command = os.path.basename(words[0]) if words else ""
        env = kwargs.get("env")
        search_path = env["PATH"] if env is not None and "PATH" in env else os.environ.get("PATH")
        resolved = words[0] if words and os.path.isabs(words[0]) else shutil.which(command, path=search_path)
        cwd = kwargs.get("cwd") or os.getcwd()
        blocked = command in HERMETIC_BLOCKED and resolved and not _allowed_executable(
            resolved, tmp_path, basetemp
        )
        if blocked:
            violation(command, "executable")
        elif _git_remote_violation(words, cwd):
            violation("git", "git-remote")
        return _ORIGINAL_POPEN_INIT(self, args, *popen_args, **kwargs)

    def guarded_connect(self, address):
        if _network_violation(self, address):
            violation("socket.connect", "network")
        return original_connect(self, address)

    def guarded_connect_ex(self, address):
        if _network_violation(self, address):
            violation("socket.connect_ex", "network")
        return original_connect_ex(self, address)

    original_connect = socket.socket.connect
    original_connect_ex = socket.socket.connect_ex
    monkeypatch.setattr(subprocess.Popen, "__init__", guarded_init)
    monkeypatch.setattr(socket.socket, "connect", guarded_connect)
    monkeypatch.setattr(socket.socket, "connect_ex", guarded_connect_ex)
    yield
