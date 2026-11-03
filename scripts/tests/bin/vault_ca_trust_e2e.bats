#!/usr/bin/env bats

@test "headless caller bounds controlled trust and continues after timeout or denial" {
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  mkdir -p "${BATS_TEST_TMPDIR}/home" "${BATS_TEST_TMPDIR}/repo/bin" "${BATS_TEST_TMPDIR}/repo/scripts/lib"
  sed -n '/^function _acg_ca_trust_helper_path()/,/^}/p; /^function _acg_run_ca_trust()/,/^}/p; /^function _acg_trust_vault_ca_if_needed()/,/^}/p' \
    "${repo_root}/bin/cluster-up" > "${BATS_TEST_TMPDIR}/caller.sh"
  [ -s "${BATS_TEST_TMPDIR}/caller.sh" ]
  run env HOME="${BATS_TEST_TMPDIR}/home" CA_E2E_ROOT="${BATS_TEST_TMPDIR}" CA_E2E_REPO="${repo_root}" python3 - <<'PY'
import os, pathlib, signal, subprocess, sys, textwrap, time
root = pathlib.Path(os.environ['CA_E2E_ROOT']).resolve()
repo = pathlib.Path(os.environ['CA_E2E_REPO']).resolve()
home = pathlib.Path(os.environ['HOME']).resolve()
assert home == root / 'home' and home.is_dir()
assert (repo / 'bin/cluster-up').is_file() and (root / 'caller.sh').is_file()
fixture_repo = root / 'repo'
assert fixture_repo.is_dir() and fixture_repo != repo
cert = root / 'ca.crt'
cert.write_text('scratch certificate')
cert.chmod(0o600)
helper = root / 'controlled-supervisor'
client = fixture_repo / 'bin/k3dm-bounded-sudo'
lib = fixture_repo / 'scripts/lib/system.sh'
security = root / 'controlled-security'
security.write_text(textwrap.dedent('''\
    #!/usr/bin/python3
    import os, pathlib, signal, sys, time
    root = pathlib.Path(os.environ['CA_E2E_ROOT']).resolve()
    assert sys.argv[1:7] == ['add-trusted-cert', '-d', '-r', 'trustRoot', '-k', '/Library/Keychains/System.keychain']
    assert pathlib.Path(sys.argv[7]).resolve().is_relative_to(root)
    (root / 'security-started').write_text(str(os.getpid()))
    if os.environ['CA_E2E_MODE'] == 'success':
        sys.exit(0)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    child = os.fork()
    if child == 0:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        (root / 'child-pid').write_text(str(os.getpid()))
        os.write(1, b'child-stdout-inherited\\n')
        os.write(2, b'child-stderr-inherited\\n')
        time.sleep(2)
        (root / 'late-effect').write_text('unexpected')
        os._exit(0)
    (root / 'security-pid').write_text(str(os.getpid()))
    while True:
        time.sleep(1)
'''))
security.chmod(0o755)
helper.write_text(textwrap.dedent('''\
    #!/bin/bash
    exec /usr/bin/python3 -I "$CA_E2E_ROOT/supervisor-fixture.py" "$@"
'''))
helper.chmod(0o755)
(root / 'supervisor-fixture.py').write_text(textwrap.dedent('''\
    import importlib.machinery, importlib.util, os, pathlib, sys, tempfile
    root = pathlib.Path(os.environ['CA_E2E_ROOT']).resolve()
    source = pathlib.Path(os.environ['CA_E2E_REPO']) / 'bin/k3dm-vault-ca-trust-supervisor'
    assert root.is_dir() and source.is_file() and pathlib.Path(sys.argv[1]).resolve() == root / 'ca.crt'
    loader = importlib.machinery.SourceFileLoader('production_supervisor', str(source))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    module._validate_installation = lambda: None
    module.os.geteuid = lambda: 0
    os.environ['SUDO_UID'] = str(os.getuid())
    original_tempdir = tempfile.TemporaryDirectory
    def scratch_tempdir(*args, **kwargs):
        assert kwargs['dir'] == '/private/tmp'
        kwargs['dir'] = str(root)
        return original_tempdir(*args, **kwargs)
    module.tempfile.TemporaryDirectory = scratch_tempdir
    original_run = module._run_security
    def controlled_run(path, **kwargs):
        return original_run(path, command=str(root / 'controlled-security'), grace=.15,
                            environment=os.environ.copy(), **kwargs)
    module._run_security = controlled_run
    (root / 'supervisor-pid').write_text(str(os.getpid()))
    sys.exit(module.main(sys.argv))
'''))
client.write_text(textwrap.dedent('''\
    import importlib.machinery, importlib.util, os, pathlib, sys
    root = pathlib.Path(os.environ['CA_E2E_ROOT']).resolve()
    source = pathlib.Path(os.environ['CA_E2E_REPO']) / 'bin/k3dm-bounded-sudo'
    assert source.is_file() and pathlib.Path(sys.argv[2]).resolve() == root / 'controlled-supervisor'
    loader = importlib.machinery.SourceFileLoader('production_bounded', str(source))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    module.ROOT_HELPER = str(root / 'controlled-supervisor')
    module.LIMIT = 1.0
    module.GRACE = .4
    original_popen = module.subprocess.Popen
    def record_wrapper(*args, **kwargs):
        process = original_popen(*args, **kwargs)
        (root / 'wrapper-pid').write_text(str(process.pid))
        return process
    module.subprocess.Popen = record_wrapper
    (root / 'client-pid').write_text(str(os.getpid()))
    sys.exit(module.main(sys.argv[1:]))
'''))
lib.write_text(textwrap.dedent('''\
    _run_command() {
      [[ "$1 $2 $3 $4" == "--interactive-sudo --quiet --soft --" ]] || return 92
      [[ "$5" == "$CA_E2E_ROOT/controlled-supervisor" && "$6" == "$CA_E2E_ROOT/ca.crt" ]] || return 93
      if [[ "$CA_E2E_MODE" == denied ]]; then printf 'controlled permission denied\\n' >&2; return 77; fi
      "$5" "$6" "$7"
    }
'''))
driver = root / 'driver.sh'
driver.write_text(textwrap.dedent('''\
    set -euo pipefail
    [[ "$HOME" == "$CA_E2E_ROOT/home" && "$REPO_ROOT" == "$CA_E2E_ROOT/repo" ]]
    security() { [[ "$*" == "verify-cert -c $CA_E2E_ROOT/ca.crt" ]] || return 91; return 1; }
    _info() { printf 'INFO:%s\\n' "$*"; }
    _warn() { printf 'WARN:%s\\n' "$*"; }
    _run_command() {
      [[ "$1 $2 $3 $4" == '--soft -- /usr/bin/python3 -I' ]] || return 94
      shift 2
      local rc=0
      "$@" || rc=$?
      printf 'bounded-result=%s\\n' "$rc"
      return "$rc"
    }
    source "$CA_E2E_ROOT/caller.sh"
    _acg_ca_trust_helper_path() { printf '%s\\n' "$CA_E2E_ROOT/controlled-supervisor"; }
    _acg_trust_vault_ca_if_needed "$CA_E2E_ROOT/ca.crt"
    printf 'NEXT-SENTINEL\\n'
'''))
for mode in ('success', 'denied', 'hung'):
    for name in ('client-pid', 'wrapper-pid', 'supervisor-pid', 'security-pid', 'child-pid', 'security-started', 'late-effect'):
        (root / name).unlink(missing_ok=True)
    env = dict(os.environ, HOME=str(home), REPO_ROOT=str(fixture_repo),
               CA_E2E_ROOT=str(root), CA_E2E_MODE=mode)
    started = time.monotonic()
    complete = False
    try:
        proc = subprocess.Popen(['/bin/bash', str(driver)], env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        try:
            output, _ = proc.communicate(timeout=4)
        except subprocess.TimeoutExpired as exc:
            proc.kill()
            proc.wait(timeout=1)
            raise AssertionError('caller or inherited output pipe did not close') from exc
        elapsed = time.monotonic() - started
        print(f'{mode}: exit={proc.returncode} elapsed={elapsed:.3f}s')
        print(output, end='')
        assert proc.returncode == 0 and 'NEXT-SENTINEL' in output
        assert ('Could not add Vault CA' in output) == (mode != 'success')
        if mode == 'success':
            assert 'bounded-result=0' in output and (root / 'security-started').is_file()
        elif mode == 'denied':
            assert 'bounded-result=77' in output and not (root / 'security-started').exists()
        else:
            # One second deadline, 0.4 seconds termination grace, plus 0.5
            # seconds for interpreter startup and scheduling in the fixture.
            assert 'bounded-result=124' in output and 0.8 <= elapsed < 1.9
            assert 'child-stdout-inherited' in output and 'child-stderr-inherited' in output
            assert (root / 'security-pid').is_file() and (root / 'child-pid').is_file()
            for name in ('client-pid', 'wrapper-pid', 'supervisor-pid', 'security-pid', 'child-pid'):
                pid = int((root / name).read_text())
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    continue
                raise AssertionError(f'{name} {pid} survived the caller')
            time.sleep(1.2)
            assert not (root / 'late-effect').exists()
        complete = True
    finally:
        if not complete:
            for name in ('client-pid', 'wrapper-pid', 'supervisor-pid', 'security-pid', 'child-pid'):
                path = root / name
                if path.exists():
                    try:
                        os.kill(int(path.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass
PY
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}
