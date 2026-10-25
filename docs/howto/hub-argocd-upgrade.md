# Hub Argo CD chart upgrade

Check the `argo/argo-cd` chart repository for a newer version and read that version's release notes for breaking changes. Patch bumps within `10.10.x` are routine. A minor or major chart bump needs its own plan.

On the release branch, update `ARGOCD_HELM_CHART_VERSION` in `scripts/etc/argocd/vars.sh` and review the change. Preview the exact operation and baseline snapshot:

```sh
make argocd-upgrade DRY_RUN=1
```

Run the upgrade in the operator's tmux session. It refuses unless the current kube context is the hub (`ARGOCD_HUB_CONTEXT`, default `k3d-k3d-cluster`):

```sh
make argocd-upgrade
# or select an explicit version:
make argocd-upgrade TO=10.10.6
```

The command records Application sync and health states plus the prior chart version and Helm revision under `${K3DM_STATE_DIR}/argocd-upgrade/<UTC timestamp>/`. Read `before.json`, `after.json`, and the command result. If the postcheck reports a regression, review the affected Applications and snapshot, then roll back manually using the printed `helm rollback` command. The command never rolls back automatically.

An equal target reports `already at <version>` without changing the release. A downgrade is refused unless explicitly invoked with `--allow-downgrade` through `argocd_upgrade`.
