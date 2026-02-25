# m2-air Stage 2 Validation Plan

**Last Updated:** 2026-02-25
**Owner:** Codex agents (handoff-friendly)

## Goal
Ensure the `m2-air` self-hosted runner can execute the OrbStack-based Stage 2
integration flow (Vault/ESO/Istio health + Jenkins smoke) so PRs gain a repeatable
macOS validation gate after Stage 1 linting succeeds.

## Environment Overview
- **Runner:** `m2-air` (macOS ARM64) registered as `self-hosted, macOS, ARM64`
- **Container runtime:** OrbStack pre-installed manually; GUI onboarding complete
- **Cluster provider:** `CLUSTER_PROVIDER=orbstack`
- **Persistent cluster model:** Single long-lived k3d cluster kept warm between runs

## Prerequisites
1. OrbStack app running and healthy (`orb status` returns `OK`).
2. Runner online in GitHub (`Settings → Actions → Runners`).
3. Toolchain installed (via `.github/actions/setup`): bash 5, bats, shellcheck,
   yamllint, kubectl, helm.
4. Vault unsealed if cluster already exists (`./scripts/k3d-manager reunseal_vault`).

## Validation Sequence
Perform these steps sequentially on `m2-air` whenever Stage 2 needs to be (re)qualified.

1. **Baseline sanity**
   ```bash
   PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test lib
   orb status
   kubectl config current-context
   ```
   - Confirms unit tests and OrbStack health before touching the cluster.

2. **Cluster bring-up (only if starting fresh)**
   ```bash
   CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager create_cluster
   CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_istio
   CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_vault ha
   CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_eso
   CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager reunseal_vault
   ```
   - Record kubeconfig path and keep cluster running between CI jobs.

3. **Stage 2.0 health probe**
   - Script to write (`scripts/ci/check_cluster_health.sh` — TBD) should verify:
     - Istio ingress Deployment and Service Ready
     - Vault StatefulSet pods Ready, `vault status` == `Initialized true, Sealed false`
     - ESO pods Ready
   - Until the script exists, run manual commands:
     ```bash
     kubectl get pods -A
     kubectl -n vault exec -i vault-0 -- vault status
     ```

4. **Stage 2.1 integration tests**
   ```bash
   CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_vault
   CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_eso
   CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_istio
   ```
   - Capture logs; ensure each test’s cleanup trap fires (no leaked namespaces).

5. **Jenkins smoke rehearsal (mac tunnel path)**
   ```bash
   CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault
   ./scripts/k3d-manager test_jenkins_smoke
   ```
   - Confirms `_jenkins_run_smoke_test` port-forward path works end-to-end on m2.

## Automation Roadmap
1. Write `scripts/ci/check_cluster_health.sh` (bash) and add it as the first step in
   the Stage 2 job.
2. Extend `.github/workflows/ci.yml` with a `stage2` job that:
   - Uses `runs-on: [self-hosted, macOS, ARM64]`
   - Runs health check + the three integration tests
   - (Optional) Adds Jenkins smoke as a follow-up step once stable
3. Update branch protection to require the Stage 2 job after it has run cleanly.

## Risks & Mitigations
- **Runner drift (OrbStack stopped, cluster stale):** Health script should fail fast.
- **Namespace collisions in tests:** Namespace isolation work in `scripts/lib/test.sh`
  remains prerequisite; do not enable Stage 2 until that refactor lands.
- **Manual unseal required after host reboot:** Document runbook in `docs/issues/`
  and reference from the CI failure messages.

## Exit Criteria
- Documented manual run on m2 shows all commands succeed.
- Stage 2 job defined in workflow and runs green for PR #2.
- Memory bank reflects Stage 2 readiness and links to this plan.

## Workflow Hardening Checklist
To keep both Stage 1 and the upcoming Stage 2 jobs safe:
1. **Minimum token scope** — workflows set `permissions: contents: read` so GITHUB_TOKEN
   cannot push or manage secrets.
2. **Concurrency guard** — `concurrency: ci-${{ github.workflow }}-${{ github.ref }}` with
   `cancel-in-progress: true` ensures duplicate pushes cancel older runs, freeing the
   m2 runner.
3. **Pinned actions** — continue pinning marketplace actions to tags (`actions/checkout@v4`)
   or SHAs when available; avoid floating `@main`.
4. **Secrets isolation** — Stage 2 job will only read required secrets via
   `env:` entries scoped to the job; never echo Vault tokens in logs.
5. **Runner safeguards** — Stage 2 job must check OrbStack/kube health up front so
   it fails fast without mutating state.

Revisit this list whenever we add new workflows or jobs.
