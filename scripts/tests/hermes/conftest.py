import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
from hermes import e2e_bugs  # noqa: E402

_HERMES_GUARD_HITS = []


def _make_slack_transport_guard(hits, module, transport, aggregate=False):
    def blocked(*_args, **_kwargs):
        hit = f"{module}.{transport}"
        hits.append(hit)
        if aggregate:
            _HERMES_GUARD_HITS.append(hit)
        raise AssertionError("real transport reached in test")
    return blocked


def _assert_no_slack_transport_hits(hits):
    if hits:
        pytest.fail("real Slack transport reached in test: " + ", ".join(hits))


def _make_sensitive_command_guard(hits, module, method, original, aggregate=True):
    import os
    import shlex
    def guarded(args, *call_args, **call_kwargs):
        try:
            argv = shlex.split(args) if isinstance(args, str) else list(args)
            name = os.path.basename(str(argv[0])) if argv else ""
        except (TypeError, ValueError):
            argv, name = [], ""
        if name in ("ssh", "security", "curl"):
            hit = f"{module}.subprocess.{method}:{name}"
            hits.append(hit)
            if aggregate:
                _HERMES_GUARD_HITS.append(hit)
            raise AssertionError("sensitive subprocess reached in Hermes test")
        return original(args, *call_args, **call_kwargs)
    return guarded


def _make_sensitive_popen_guard(hits, module, original_class, aggregate=True):
    import os
    import shlex

    class GuardedPopen(original_class):
        def __init__(self, args, *call_args, **call_kwargs):
            try:
                argv = shlex.split(args) if isinstance(args, str) else list(args)
                name = os.path.basename(str(argv[0])) if argv else ""
            except (TypeError, ValueError):
                name = ""
            if name in ("ssh", "security", "curl"):
                hit = f"{module}.subprocess.Popen:{name}"
                hits.append(hit)
                if aggregate:
                    _HERMES_GUARD_HITS.append(hit)
                raise AssertionError("sensitive subprocess reached in Hermes test")
            super().__init__(args, *call_args, **call_kwargs)

    return GuardedPopen


def _assert_no_sensitive_subprocess_hits(hits):
    if hits:
        pytest.fail("sensitive subprocess reached in Hermes test: " + ", ".join(hits))


def _assert_no_sensitive_stub_hits(path):
    try:
        content = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return
    if content:
        pytest.fail("sensitive child tool reached in Hermes test: " + content.strip())


@pytest.hookimpl(trylast=True)
def pytest_sessionfinish(session, exitstatus):
    reporter = session.config.pluginmanager.get_plugin("terminalreporter")
    if reporter:
        reporter.write_line(f"Hermes hermetic guard hits: {len(_HERMES_GUARD_HITS)}")


@pytest.fixture(autouse=True)
def _no_live_retrieval(monkeypatch):
    """Every new Hermes bug doc is built through search(). Unstubbed, that reads the embeddings
    key and the Vault root token and calls the embeddings API. Tests that cover prior art
    override this with their own monkeypatch."""
    def unavailable(*_args, **_kwargs):
        raise e2e_bugs.RetrievalUnavailable("retrieval is stubbed out in tests")

    monkeypatch.setattr(e2e_bugs, "search", unavailable)


@pytest.fixture(autouse=True)
def _hermes_scratch_home(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_HEARTBEAT_MARKER", str(tmp_path / "heartbeat.timestamp"))


@pytest.fixture(autouse=True)
def _no_live_pushgateway(monkeypatch):
    """Unstubbed, a poll pushes the Hermes heartbeat and index metrics to the hub Pushgateway on
    localhost:19094, which makes a dead Hermes look alive to HermesNotRunning. Point every
    Pushgateway URL at a closed local port; tests that check the URL set their own."""
    for name in ("K3DM_VECTORDB_PUSHGATEWAY_URL", "K3DM_DISK_PUSHGATEWAY_URL",
                 "K3DM_PUSHGATEWAY_URL", "K3DM_KINE_PUSHGATEWAY_URL",
                 "K3DM_PR_CHECKS_PUSHGATEWAY_URL", "K3DM_CNI_IPAM_PUSHGATEWAY_URL",
                 "K3DM_ORBSTACK_PUSHGATEWAY_URL"):
        monkeypatch.setenv(name, "http://127.0.0.1:9")


@pytest.fixture(autouse=True)
def _no_live_slack_or_keychain(monkeypatch):
    """Guard every loaded Hermes entrypoint copy without replacing either sensor."""
    import sys
    import types
    from importlib.machinery import SourceFileLoader
    from pathlib import Path
    script = (Path(__file__).resolve().parents[3] / "bin" / "k3dm-hermes").resolve()
    hits = []
    from hermes.sensors import _SlackKeychainStore
    patched = set()
    def patch_module(module):
        if id(module) in patched:
            return
        patched.add(id(module))
        module._hermes_test_slack_api = module._slack_api
        module._hermes_test_slack_relay_probe = module._slack_relay_probe
        monkeypatch.setattr(module, "_slack_api",
                            _make_slack_transport_guard(hits, module.__name__, "_slack_api", aggregate=True))
        monkeypatch.setattr(module, "_slack_relay_probe",
                            _make_slack_transport_guard(hits, module.__name__, "_slack_relay_probe", aggregate=True))
        monkeypatch.setattr(module, "_slack_config_store",
                            lambda: _SlackKeychainStore(reader=lambda _service: "",
                                                        runner=_make_slack_transport_guard(
                                                            hits, module.__name__, "Keychain subprocess",
                                                            aggregate=True)))
    def matches(module):
        if not getattr(module, "__file__", None):
            return False
        try:
            return Path(module.__file__).resolve() == script
        except OSError:
            return False
    loaded = {}
    for parent in tuple(sys.modules.values()):
        candidates = (parent, *(vars(parent).values() if isinstance(parent, types.ModuleType) else ()))
        for module in candidates:
            if isinstance(module, types.ModuleType) and matches(module):
                loaded[id(module)] = module
    for module in loaded.values():
        patch_module(module)
    original_exec_module = SourceFileLoader.exec_module
    def exec_module(loader, module):
        original_exec_module(loader, module)
        if matches(module):
            patch_module(module)
    monkeypatch.setattr(SourceFileLoader, "exec_module", exec_module)
    yield hits
    _assert_no_slack_transport_hits(hits)


@pytest.fixture(autouse=True)
def _no_sensitive_hermes_subprocesses(monkeypatch, tmp_path):
    import subprocess
    import sys
    import types
    import os
    from importlib.machinery import SourceFileLoader
    from pathlib import Path
    entrypoint = (Path(__file__).resolve().parents[3] / "bin" / "k3dm-hermes").resolve()
    hits = []
    patched = set()
    stub_dir = tmp_path / "hermes-sensitive-bin"
    stub_dir.mkdir(exist_ok=True)
    stub_hits = tmp_path / "hermes-sensitive-tools.log"
    monkeypatch.setenv("HERMES_TEST_SENSITIVE_TOOL_HITS", str(stub_hits))
    for name in ("ssh", "security", "curl"):
        stub = stub_dir / name
        stub.write_text("#!/bin/sh\nprintf '%s\\n' \"${0##*/}\" >> \"$HERMES_TEST_SENSITIVE_TOOL_HITS\"\nexit 1\n",
                        encoding="utf-8")
        stub.chmod(0o700)
    monkeypatch.setenv("PATH", str(stub_dir) + os.pathsep + os.environ.get("PATH", ""))

    def matches(module):
        if not isinstance(module, types.ModuleType):
            return False
        if module.__name__.startswith("hermes."):
            return True
        if not getattr(module, "__file__", None):
            return False
        try:
            return Path(module.__file__).resolve() == entrypoint
        except (AttributeError, OSError):
            return False

    def patch_module(module):
        if id(module) in patched:
            return
        patched.add(id(module))
        command_module = getattr(module, "subprocess", None)
        if command_module is None:
            return
        for method in ("run", "Popen", "check_output"):
            original = getattr(command_module, method, None)
            if original is not None:
                guarded = (_make_sensitive_popen_guard(hits, module.__name__, original, aggregate=True)
                           if method == "Popen" else
                           _make_sensitive_command_guard(hits, module.__name__, method,
                                                         original, aggregate=True))
                monkeypatch.setattr(command_module, method, guarded)

    def patch_loaded():
        for module in tuple(sys.modules.values()):
            if matches(module):
                patch_module(module)

    patch_loaded()
    original_exec_module = SourceFileLoader.exec_module
    def exec_module(loader, module):
        original_exec_module(loader, module)
        if matches(module):
            patch_module(module)
    monkeypatch.setattr(SourceFileLoader, "exec_module", exec_module)
    yield hits
    _assert_no_sensitive_subprocess_hits(hits)
    _assert_no_sensitive_stub_hits(stub_hits)
