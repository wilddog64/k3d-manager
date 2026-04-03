# Issue: Reusable Workflow Broke Due to Runner Isolation

## Summary
PR #33 uncovered two P1 findings: (1) reusable workflow jobs run on different
runners so kubeconfig/cluster is unreachable; (2) k3d installer pulled from `main`
branch. Fix implemented:
- Deleted `.github/workflows/vcluster-e2e-setup.yml`
- Added composite actions `.github/actions/vcluster-e2e-setup` and `...-teardown`
  so callers run setup/teardown on the same runner
- Installer now uses tag-specific URL `https://raw.githubusercontent.com/k3d-io/k3d/${{ inputs.k3d-version }}/install.sh`

## Tests
- `yamllint .github/actions/vcluster-e2e-setup/action.yml`
- `yamllint .github/actions/vcluster-e2e-teardown/action.yml`
- `shellcheck scripts/plugins/vcluster.sh`
- `env -i PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" HOME="$HOME" TMPDIR="$TMPDIR" bash --norc --noprofile -c 'cd "$(git rev-parse --show-toplevel)" && bats scripts/tests/plugins/vcluster.bats'`

## Next Steps
- Update `shopping-cart-e2e-tests` to consume the new composite actions
- Close PR #33 after new PR merges (Claude handles PR workflow)

## Third P1 — Composite Action Path Resolution (PR #34)

Copilot flagged a new P1 after the composite actions landed: `./scripts/k3d-manager`
resolved relative to `$GITHUB_WORKSPACE`. If the caller checks out k3d-manager into
a subdirectory, the path doesn't exist. Both setup and teardown actions now invoke
`k3d-manager` via `${{ github.action_path }}/../../../scripts/k3d-manager`, which is
stable regardless of caller checkout layout.

## Fourth and Fifth Findings — curl Safety + Input Validation (PR #34)

Two more Copilot findings landed after the action path fix:

1. **curl -s piped to sudo bash** — this hid HTTP errors and executed remote
   content as root without inspection. Fixed by switching to `curl -fsSL`,
   downloading to a unique temp file (`mktemp /tmp/k3d-install.XXXXXX`), and
   executing that same file with `sudo bash`.
2. **k3d-version input unvalidated** — callers could supply `main` or other
   non-tag values, reintroducing the supply-chain risk from PR #33. Fixed by
   requiring the input to match `^v[0-9]+\.[0-9]+\.[0-9]+$` before constructing
   the download URL.

## Sixth and Seventh Findings — mktemp + Teardown Dependency Check (PR #34)

1. **Predictable /tmp path** — `/tmp/k3d-install.sh` lived in a world-writable
   directory and could be swapped via TOCTOU or symlink attacks. Fixed by using
   `mktemp /tmp/k3d-install.XXXXXX`, restricting with `chmod 600`, and removing
   it via a `trap` on EXIT after the installer runs.
2. **Teardown assumes dependencies** — running teardown standalone emitted
   `command not found` errors if `kubectl` or `k3d` were absent. Fixed by adding
   a dependency check step that fails fast with guidance to run in the same job
   as setup.

## Eighth, Ninth, and Tenth Findings — TAG env, sudo -n, teardown manager check (PR #34)

1. **k3d-version not forwarded to installer** — installer pins via `TAG=`.
   Fixed: `sudo -n env TAG="$k3d_version" bash "$tmp_script"`.
2. **sudo without -n** — could hang on password prompts. Fixed by using
   `sudo -n` to fail fast.
3. **Teardown dependency message ambiguous + missing manager check** — error now
   explicitly references running in the same job as setup and verifies the
   `${{ github.action_path }}/../../../scripts/k3d-manager` path is executable
   before teardown runs.
