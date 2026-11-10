# v0.5.5 — `_install_promtool`: pinned, checksum-verified promtool for every host

**Status:** OPEN — spec written 2026-11-09
**Approval:** operator, 2026-11-09 (k3d-manager session: "C2 is approved"). This is Part A of k3d-manager
`docs/bugs/2026-11-09-promtool-tests-need-pinned-install-on-every-host.md` (child C2 of the v1.43.16 parent).
Dispatch: Claude; not a hub or Hostinger change.
**Intent approved:** operator, 2026-11-09
**Branch:** `feat/install-promtool`
**Requested by:** k3d-manager C2. Its Part B (machine setup, CI, test resolvers) follows after the subtree pull.

## Problem

promtool is installed only by k3d-manager's CI. No Mac or control node has it, so promtool tests in k3d-manager fail or
skip locally. The operator's rule (2026-11-09) is that tool installs come from lib-foundation `_install_*`, so the
Linux control node gets the same thing. brew's `prometheus` formula floats; the tests pin 3.1.0.

## Fix spec

Add `_install_promtool` to `scripts/lib/system.sh`, after `_install_vagrant`. It follows the release-tarball pattern of
`_install_node_from_release`, and adds a checksum check.

- **Version:** `${PROMTOOL_VERSION:-3.1.0}`.
- **Platform:** `uname -s` gives `Darwin`→`darwin` or `Linux`→`linux`. `uname -m` gives `arm64`/`aarch64`→`arm64` or
  `x86_64`/`amd64`→`amd64`. Anything else returns 1 with a warning and downloads nothing.
- **Pinned checksums** live in a helper `_promtool_pinned_sha256 <version> <os> <arch>`, which prints the checksum or
  returns 1. No checksum means `_install_promtool` returns 1 and downloads nothing. There is no environment variable that
  replaces a checksum. Captured 2026-11-10T03:13:06Z from
  `https://github.com/prometheus/prometheus/releases/download/v3.1.0/sha256sums.txt`:
  - `3.1.0-darwin-amd64` `de958826f9ca20003b30c48fa3f2fcfa67b2a3aebcabd6230e90bb94f92d86e8`
  - `3.1.0-darwin-arm64` `8ebe1d60d8864ae3e10a359c3b543563e972505e5ef6fe1d00586d86a7e813fc`
  - `3.1.0-linux-amd64` `9a9d1e115d1745826b13aec3f1409780b9fcf1d4206746cb4faee46ca5add70c`
  - `3.1.0-linux-arm64` `c12b9e368006873df0c8865771af0434a3edfc8c8eaeea62b73d3974bff7f2a1`
- **Target:** `${PROMTOOL_INSTALL_DIR:-$HOME/.local/bin}/promtool`. Create the directory with `mkdir -p` if missing.
- **Already installed:** if the target exists, is executable, and its `--version` first line starts with
  `promtool, version <version> `, return 0 without downloading. Real output captured on `m4-air.local`, macOS 26.5.2,
  2026-11-10T03:17:59Z, from the 3.1.0 darwin-arm64 binary:
  `promtool, version 3.1.0 (branch: HEAD, revision: 7086161a93b262aa0949dbf2aba15a5a7b13e0a3)`.
  A target with a different version is replaced.
- **Download:** `_run_command -- curl -fsSL -o "$work/<tarball>" "$url"`, where `$work` is from `mktemp -d` and
  `$url` is `https://github.com/prometheus/prometheus/releases/download/v<version>/prometheus-<version>.<os>-<arch>.tar.gz`.
  Base URL overridable by `PROMTOOL_BASE_URL` for tests only.
- **Verify:** sha256 with `shasum -a 256`, else `sha256sum`. If neither exists, return 1. On mismatch, warn with
  expected and actual and return 1. The target is untouched.
- **Install:** extract only `prometheus-<version>.<os>-<arch>/promtool`. Copy it to `<target>.tmp.$$`, `chmod 0755`,
  then `mv -f` onto the target, so a failure never leaves a half-written promtool.
- `$work` is removed on every path, success or failure (a `trap … RETURN` or explicit cleanup before each return).
- Never sudo: no `--prefer-sudo` or `--require-sudo`, and no write outside the target dir and `$work`.
- Return non-zero on failure without exiting the caller's shell.

## Files

| File | Change |
|---|---|
| `scripts/lib/system.sh` | `_install_promtool` |
| `scripts/tests/lib/system.bats` | tests below |
| `docs/api/functions.md` | one entry beside `_install_vagrant` |
| `CHANGE.md` | entry under Unreleased |

## Rules

- Tests stub `curl` (and `uname` where a platform is chosen) on a scratch `PATH` and log argv. The stub `curl` copies a
  fixture tarball built in `BATS_TEST_TMPDIR`: a directory `prometheus-3.1.0.<os>-<arch>/promtool` holding a shell
  script that prints the captured version line. The fixture computes that tarball's sha256, and the test redefines
  `_promtool_pinned_sha256` after sourcing to return it (or a wrong value, for the mismatch case). Verification still
  runs on the downloaded bytes. M4 calls the real helper, not the redefined one. Each fixture first asserts that the `curl` on `PATH` is the stub and that
  `PROMTOOL_INSTALL_DIR` is under `BATS_TEST_TMPDIR`.
- No real network download in tests. No real `$HOME` writes: every test sets `HOME` and `PROMTOOL_INSTALL_DIR` under
  `BATS_TEST_TMPDIR`.
- Run `make bats` and `make shellcheck-lib`. Leave the changes uncommitted; Claude reviews and commits.
- Do not change any other installer.

## Acceptance

```yaml
must:
  - id: M1
    text: "With no promtool at the target, _install_promtool downloads the tarball for the detected os/arch, verifies its sha256, installs an executable promtool at PROMTOOL_INSTALL_DIR/promtool, and returns 0."
  - id: M2
    text: "os/arch mapping: Darwin/arm64, Darwin/x86_64, Linux/x86_64 and Linux/aarch64 each request the matching darwin-arm64, darwin-amd64, linux-amd64 or linux-arm64 tarball URL."
  - id: M3
    text: "A target reporting a different version is replaced by the pinned version (paired positive control for N1)."
  - id: M4
    text: "_promtool_pinned_sha256 prints exactly the four checksums in this spec for 3.1.0 and returns 1 for any other version or platform."
must_not:
  - id: N1
    text: "With promtool <version> already at the target, curl is called zero times and the target's bytes are unchanged."
  - id: N2
    text: "On a checksum mismatch, the function returns non-zero, the target is absent (or unchanged if one existed), and no promtool is left anywhere under PROMTOOL_INSTALL_DIR."
  - id: N3
    text: "For an unpinned version or an unsupported os/arch, the function returns non-zero and calls curl zero times."
  - id: N4
    text: "The function never calls sudo, and after any outcome nothing new exists outside PROMTOOL_INSTALL_DIR: its temp directory is removed."
  - id: N5
    text: "A failed call returns non-zero to a caller running under set -e inside a subshell, and does not exit the caller's shell."
evidence:
  - {id: E1, proves: [M1, M2, M3, M4, N1, N2, N3, N4, N5], kind: offline, intent: "Fed a fake download, the installer installs promtool when the checksum matches, refuses and leaves nothing when it does not, refuses unknown versions and platforms, skips the download when 3.1.0 is already there, and touches only its target and temp folders. Each must_not is shown red by a mutant."}
  - {id: E2, proves: [M1], kind: live, intent: "Claude runs the real installer on the M4 into a scratch folder: it downloads from GitHub, verifies, and the installed promtool prints version 3.1.0."}
interface:
  - "_install_promtool, _promtool_pinned_sha256 (source scripts/lib/system.sh; tests may redefine the helper)"
  - "env: PROMTOOL_VERSION, PROMTOOL_INSTALL_DIR, PROMTOOL_BASE_URL (test), HOME, PATH (curl, uname, sudo stubs)"
```

## Worker definition of done

- `make bats` and `make shellcheck-lib` pass; paste each command, rc and the proving lines.
- For each must_not, name the mutant and paste its red run.
- `git diff --stat` touches only the four files above.
- No real download and no `sudo` in the run log.
