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
- `env -i PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" HOME="$HOME" TMPDIR="$TMPDIR" bash --norc --noprofile -c 'cd /Users/cliang/src/gitrepo/personal/k3d-manager && bats scripts/tests/plugins/vcluster.bats'`

## Next Steps
- Update `shopping-cart-e2e-tests` to consume the new composite actions
- Close PR #33 after new PR merges (Claude handles PR workflow)

## Third P1 — Composite Action Path Resolution (PR #34)

Copilot flagged a new P1 after the composite actions landed: `./scripts/k3d-manager`
resolved relative to `$GITHUB_WORKSPACE`. If the caller checks out k3d-manager into
a subdirectory, the path doesn't exist. Both setup and teardown actions now invoke
`k3d-manager` via `${{ github.action_path }}/../../../scripts/k3d-manager`, which is
stable regardless of caller checkout layout.
