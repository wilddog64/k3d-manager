# P2 — e2e-sandbox fails when Argo CD CRDs already exist on a provisioned AWS sandbox

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.4` (triage 2026-10-15, operator-approved placement)
**Priority:** P2 — E2E verification blocked
**Status:** OPEN — observed reproduction and unconditional install confirmed; implementation not started
**Approval:** operator explicitly requested P2 bug filing; no implementation authorized

## Observed failure

Shortly after provisioning the AWS ACG sandbox, the operator launched Slack `k3dm e2e-sandbox`, job `3b0687a9`. The job reported `make e2e-sandbox failed (rc 2)`. Full output was recorded locally at `/Users/cliang/.k3dm/e2e/make-e2e-sandbox-20261015T185052Z.log`.

The job passed its preflight checks: ACG context `ubuntu-k3s` was ready; the sandbox TTL was extended/checked with approximately 217 minutes remaining; three nodes reported Ready; GHCR pull secret and namespace were configured. It then attempted to install Argo CD with Helm.

Key error excerpt:

```
Release "argocd" does not exist. Installing it now.
Error: unable to continue with install: CustomResourceDefinition "applications.argoproj.io" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata; label validation error: missing key "app.kubernetes.io/managed-by": must be set to "Helm"; annotation validation error: missing key "meta.helm.sh/release-name": must be set to "argocd"; annotation validation error: missing key "meta.helm.sh/release-namespace": must be set to "argocd"
```

The Helm command returned 1 and the Make target returned a nonzero exit. The screenshot proves the Helm ownership conflict, **not** that the existing Argo CD installation was unhealthy or that the AWS sandbox itself failed.

## Confirmed implementation path

In `scripts/plugins/e2e.sh`, `_e2e_sandbox_preflight_cluster` checks the existing sandbox. Later, `e2e-sandbox` unconditionally executes:

```bash
_run_command -- helm upgrade --install argocd argo/argo-cd --kube-context ubuntu-k3s \
  -n argocd --create-namespace --set server.insecure=true --set server.service.type=ClusterIP
```

It then applies Argo CD cluster registration and waits for `deployment/argocd-server`. There is no existing-Argo-CD ownership/health gate before this Helm install. The current cluster-up workflow can already leave Argo CD resources in place, including CRDs not owned by the Helm release named `argocd`.

## Expected behavior

`e2e-sandbox` should be safe and repeatable against an already-provisioned, healthy AWS ACG cluster. It must reuse a compatible existing Argo CD installation rather than try to claim preexisting CRDs into a new Helm release. If Argo CD is absent, install it only through an explicitly supported and verified ownership model; if partly installed or incompatible, fail with a clear non-destructive diagnostic.

## Investigation and requirements

1. Inspect the live (or saved) `ubuntu-k3s` state read-only: Argo CD deployments, namespaces, Helm releases and release names, `applications.argoproj.io` CRD ownership metadata, and the exact setup path used by `cluster-up`. Do not infer that all CRDs were Helm-managed.
2. Trace the existing cluster-up Argo CD installation/registration contract and compare it with the duplicate Helm installation in `scripts/plugins/e2e.sh`. Determine whether E2E needs any Argo CD installation step at all when platform provisioning is already complete.
3. Add an idempotent preflight: healthy compatible Argo CD → reuse; genuinely absent Argo CD → follow the supported provisioning mechanism; partial/incompatible state → explicit actionable failure without changing resource ownership.
4. Do **not** delete CRDs, uninstall Argo CD, patch Helm ownership labels/annotations, or recreate the AWS cluster as a quick fix; CRDs may contain live Argo CD custom resources shared with the provisioned platform.
5. Verify correct Kubernetes context, release naming, namespace, and controller/API readiness; do not treat merely finding a CRD as proof of full Argo CD health.
6. Keep `e2e-sandbox` independently usable after a normal `cluster-up`, and preserve the earlier requirement that an absent ACG sandbox be provisioned via the approved lifecycle path (a separate issue).
7. Provide a clear failure summary in Slack and retained job output with the exact preflight/installation phase, avoiding secrets or excessive logs.

## Acceptance / regression tests

- Given an existing healthy Argo CD installation and preexisting non-Helm-owned Argo CD CRDs, `e2e-sandbox` skips the conflicting Helm install and continues to E2E setup.
- Given a compatible Helm-owned installation, it does not take destructive ownership actions or gratuitously reinstall controllers.
- Given absent or inconsistent Argo CD, behavior follows a documented provisioning path or returns a clear non-destructive diagnostic.
- Repeat E2E twice on the same running sandbox and confirm no Argo CD release or CRD ownership drift.
- Include mocked command-level tests that reproduce the reported `invalid ownership metadata` failure before correction and pass after the fix.
- No real cloud infrastructure or destructive Kubernetes operations in automated regression tests.

## Related

- `docs/plans/v1.41.0-cloud-bridge-sandbox-lifecycle.md` — sandbox lifecycle design.
- `docs/bugs/2026-10-15-acg-up-prometheus-forward-missing-after-success.md` — separate post-provision readiness verification issue.

**Implementation:** not started. Filing this report did not run E2E, modify Helm releases or change the sandbox.

## Recurrence — 2026-10-16

The operator ran `make e2e-sandbox` against a freshly provisioned sandbox (built about 12:59Z). It
failed with the same Helm ownership error. Run `1792155966-29279`, summary
`~/.k3dm/e2e/1792155966-29279.json`, and the failing result was published to the hub.

Read-only state of `ubuntu-k3s`, answering investigation item 1:

- `cluster-up` already installs Argo CD into the **`cicd`** namespace. The deployments are named
  `argocd-ubuntu-k3s-*` (server, repo-server, applicationset, dex, notifications, redis), and all are
  Ready.
- That install is not a Helm release. `helm list -A` shows only `cilium` and `external-secrets`. The
  `applications.argoproj.io` CRD carries `kubectl.kubernetes.io/last-applied-configuration` and
  `helm.sh/resource-policy: keep`, but no `meta.helm.sh/*` ownership.
- `e2e-sandbox` (`scripts/plugins/e2e.sh:395`) then tries to install a **second** Argo CD, as Helm
  release `argocd` in namespace `argocd`. It fails on every freshly built sandbox, not only on a
  reused one.

So the answer to investigation item 2 is that E2E needs no Argo CD install after `cluster-up`. The
fix is to reuse the `cicd` install, which means retargeting the step's later registration and its
`deployment/argocd-server` wait at that install, rather than deleting the install line alone.
