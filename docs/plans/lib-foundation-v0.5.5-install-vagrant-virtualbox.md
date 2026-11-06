# v0.5.5 — `_install_virtualbox` and `_install_vagrant`: standard installers for the local VM tools

**Status:** OPEN — dispatched to Luna 2026-11-06
**Approval:** operator, 2026-11-06 (k3d-manager session: "we need _install_vagrant and _install_virtualbox to handle two packages installation"). Dispatch: Claude; not a hub or Hostinger change.
**Branch:** `feat/install-vagrant-virtualbox`
**Requested by:** k3d-manager `docs/plans/dirused-windows-disk-usage-tool.md` and `docs/plans/v1.43.15-control-node-linux.md`, both of which test in Vagrant VMs on VirtualBox.

## Problem

The two tools are installed by hand on each Mac. Consumers should install them through one library function each, like
`_install_helm` and `_install_macmon`.

Captured from the operator's M5 terminal (`m5-air.local`), 2026-11-06, running `brew install --cask virtualbox vagrant`:
`Cask vagrant (2.4.9)`, `Cask virtualbox (7.2.22,175245)`, and sudo prompts raised by Homebrew's installer. Afterwards
`command -v` gives `/usr/local/bin/VBoxManage` and `/usr/local/bin/vagrant`.

## Fix spec

Add to `scripts/lib/system.sh`, next to `_install_macmon`:

```bash
function _install_virtualbox() {
  _install_mac_cask VirtualBox VBoxManage virtualbox
}

function _install_vagrant() {
  _install_mac_cask Vagrant vagrant vagrant
}
```

`_install_mac_cask <label> <binary> <cask>` is a private helper. Behaviour, in order:

1. Not macOS (`_is_mac` false): `_warn` that `<label>` installation is supported only on macOS, return 1. No other call.
   This differs from `_install_macmon` deliberately: a caller about to run a VM must not be told the install succeeded.
2. `_command_exist <binary>`: return 0 quietly (idempotent). No brew call.
3. `brew` missing: `_warn` "Homebrew is required to install `<label>`", return 1.
4. Otherwise `( _run_command -- brew install --cask <cask> ) || return $?`. The subshell keeps a failed install from
   exiting the caller. On success, `_info` "`<label>` installed".

It never calls sudo itself: Homebrew's installer asks for the password. It creates no VM, downloads no box, starts
nothing, and does not check versions. Linux hosts are out of scope.

## Files

| File | Change |
|---|---|
| `scripts/lib/system.sh` | `_install_mac_cask`, `_install_virtualbox`, `_install_vagrant` |
| `scripts/tests/lib/system.bats` | tests below |
| `docs/api/functions.md` | one entry each, beside `_install_macmon` |
| `CHANGE.md` | entry under Unreleased |

## Rules

- Tests stub `brew`, `VBoxManage` and `vagrant` on a scratch `PATH` and record argv to a log. The fixture first asserts the
  stub `brew` is the one on `PATH`, not `/opt/homebrew/bin/brew`. No real `brew install` in tests.
- Run `make test` and `make lint`. Leave the changes uncommitted; Claude reviews and commits.
- Do not change `_install_macmon` or any other installer.

## Acceptance

```yaml
must:
  - id: M1
    text: "On macOS with VBoxManage absent and brew present, _install_virtualbox runs exactly `brew install --cask virtualbox` and returns 0."
  - id: M2
    text: "On macOS with vagrant absent and brew present, _install_vagrant runs exactly `brew install --cask vagrant` and returns 0."
  - id: M3
    text: "When the brew install fails, either function returns non-zero, and the calling shell keeps running."
  - id: M4
    text: "The two are independent: each installs its own cask when only its own binary is absent, even if the other tool is present (paired positive control for N1)."
must_not:
  - id: N1
    text: "With the tool's binary already on PATH, the function returns 0 and calls brew zero times."
  - id: N2
    text: "On Linux, the function returns non-zero and never calls brew."
  - id: N3
    text: "With brew missing, the function returns non-zero and never calls sudo."
  - id: N4
    text: "A package is never installed as a formula: brew is never called without --cask."
evidence:
  - {id: E1, proves: [M1, M2, M3, M4, N1, N2, N3, N4], kind: offline, text: "BATS with stubs on a scratch PATH, asserted first; argv logged. Each must_not shown red by a mutant."}
  - {id: E2, proves: [N1], kind: live, text: "Claude on the M4, where both tools are installed: both functions return 0 with Homebrew's cask list unchanged."}
interface:
  - "_install_virtualbox, _install_vagrant (source scripts/lib/system.sh)"
  - "env: PATH (brew, VBoxManage, vagrant, sudo stubs); _is_mac may be overridden in a test to choose the platform"
```
