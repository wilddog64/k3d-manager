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
