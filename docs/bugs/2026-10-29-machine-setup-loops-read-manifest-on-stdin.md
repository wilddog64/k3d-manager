# Bug: machine setup installs almost nothing on a real terminal

**Status:** FIXED (offline) — 2026-10-29: E1/E2 green (machine_setup.bats 40/40, the 3 new behaviour tests red on the pre-fix script; machine_setup_acceptance.bats 45/45). E3 pending: operator reruns setup on the M5.
**Priority:** P1
**Approval:** Claude-owned small defect fix (operator trial week of 10-26: Claude fixes small review defects itself)
**Filed:** 2026-10-29
**Detected by:** operator (first live run, M5 `make machine-setup ROLE=hub` from a tmux pane)
**Affected:** `bin/k3dm-machine-setup` setup mode (v1.43.12 plan 1, landed `b0283432`)
**Branch:** `k3d-manager-v1.43.12`

## Observed failure

On a fresh M5, run from a terminal, setup finished with `make: *** [machine-setup] Error 1`:

- about 60 brew formulas and every cask, OrbStack included, were still `missing`;
- all 14 Keychain secrets were `missing`, and the operator was never prompted for them;
- the three hub setup scripts reported `missing (TTY required)`, although a terminal was attached;
- the 11 `make install-*` LaunchAgents were `missing`, with no reason shown.

## Root cause

Four phases read their manifest on stdin, with `while read ...; done < "<list>"`: brew, repos, secrets and agents. Inside those loops:

1. `[[ -t 0 ]]` tests the manifest file, not the terminal. It is therefore always false, so the secret prompts and the `bin/k3dm-*-setup` scripts are skipped as "TTY required".
2. Child commands inherit the manifest as stdin. Any child that reads stdin swallows the rest of the list, or gets list text instead of the keyboard: `brew install`, the `sudo` password prompt a cask install raises, and `make install-*`.
3. `brew install`, `git clone` and `make install-*` output goes to `/dev/null`. A failure shows only as `missing`, with nothing to read.

The 81 offline BATS tests never ran setup with a terminal on stdin, and no stub read stdin, so the defect was invisible offline. The independent verifier had listed "secrets phase when a TTY is present" as untested.

## Fix

- The four loops read their manifest on fd 3 (`read ... <&3`, `done 3< "<list>"`). This leaves stdin attached to the caller's terminal, so `-t 0` and child prompts see it.
- Install output goes to a setup log at `${XDG_STATE_HOME:-~/.local/state}/k3d-manager/machine-setup.log`, created mode 600. Install commands are `brew install`, `git clone` and `make` install targets. A failed install reports `missing (see machine-setup.log)`, with no path, which keeps the no-home-path rule.
- `docs/howto/machine-setup.md` adds the OrbStack first launch: open the app once and approve its helper. Setup installs the cask but cannot do this step.

## Acceptance

```yaml
must:
  M1: In setup mode, every manifest line is processed even when a brew, make or setup-script child reads all of its stdin.
  M2: When setup's stdin is a terminal, the secrets and agents phases see it (prompts are offered, bin/k3dm-*-setup scripts run) instead of reporting "TTY required".
  M3: A failed brew install, git clone or make install target appends its output to the setup log, and the report line says "missing (see machine-setup.log)".
  M4: docs/howto/machine-setup.md tells the operator to open OrbStack once after setup.
must_not:
  N1: No manifest loop reads its list on stdin (fd 0).
  N2: The report never prints a home path, and the log holds no Keychain secret value.
  N3: --check and --dry-run still create no log and make no mutating call.
evidence:
  E1: {proves: [M1, N1], kind: offline, what: "BATS with stdin-draining brew and make stubs and a three-item list: all three are installed; shown red on the pre-fix script"}
  E2: {proves: [M3, N2, N3], kind: offline, what: "BATS: a failing brew stub writes to the log, the report names the log without a path, --check leaves no log"}
  E3: {proves: [M2], kind: live, what: "operator reruns make machine-setup ROLE=hub on the M5 from a terminal; secret prompts appear and the hub setup scripts run"}
interface:
  - bin/k3dm-machine-setup --role hub|worker|console [--check|--dry-run]
  - make machine-setup ROLE=<role>
```
