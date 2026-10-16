# P2 — e2e-sandbox fails when Argo CD CRDs already exist on a provisioned AWS sandbox

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.3` (moved from v1.43.4 on 2026-10-16 at operator request)
**Priority:** P2 — E2E verification blocked
**Status:** OPEN — fix spec below, dispatched to Codex 2026-10-16
**Approval:** explicit 2026-10-16 "can you move e2e-sandbox bug to v1.43.3 and send to codex" (operator)

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

## Fix (spec for Codex, 2026-10-16)

Read-only state of a fresh sandbox, checked by Claude on 2026-10-16 at about 16:40Z, after the
recurrence:

- `cicd` has Deployment `argocd-ubuntu-k3s-server` (label
  `app.kubernetes.io/name=argocd-server`) and StatefulSet `argocd-ubuntu-k3s-application-controller`
  (label `app.kubernetes.io/name=argocd-application-controller`), both Ready.
- `cicd` has no cluster Secret, no ApplicationSet and no Application. Namespace `argocd` does not
  exist.

So E2E keeps doing its own registration and appset apply, aimed at the `cicd` install, and installs
nothing.

### 1. `scripts/plugins/e2e.sh`: reuse the existing Argo CD

**a.** Add this after `_e2e_sandbox_preflight_cluster` (before
`_e2e_sandbox_argocd_cluster_manifest`):

```bash
function _e2e_sandbox_argocd_ready() {
  local ns="${E2E_SANDBOX_ARGOCD_NAMESPACE:-cicd}" server controller
  server="$(_run_command --soft --quiet -- kubectl --context ubuntu-k3s -n "$ns" get deployment \
    -l app.kubernetes.io/name=argocd-server -o 'jsonpath={.items[*].metadata.name}' 2>/dev/null || true)"
  controller="$(_run_command --soft --quiet -- kubectl --context ubuntu-k3s -n "$ns" get statefulset \
    -l app.kubernetes.io/name=argocd-application-controller -o 'jsonpath={.items[*].metadata.name}' 2>/dev/null || true)"
  if [[ -z "$server" || -z "$controller" || "$server" == *" "* || "$controller" == *" "* ]]; then
    _err "[e2e] sandbox Argo CD: expected exactly one argocd-server Deployment and one argocd-application-controller StatefulSet in namespace ${ns} on ubuntu-k3s (found server='${server}' controller='${controller}'); cluster-up installs Argo CD there and e2e-sandbox never installs it — run make up with the k3s-aws provider, then rerun Tier 2"
    return 1
  fi
  _info "[e2e] sandbox Argo CD: reusing ${ns}/${server}"
  _e2e_sandbox_kc -n "$ns" wait --for=condition=available "deployment/${server}" --timeout=600s
  _e2e_sandbox_kc -n "$ns" rollout status "statefulset/${controller}" --timeout=600s
}
```

**b.** In `_e2e_sandbox_argocd_cluster_manifest`, the Secret namespace follows the same variable.
Change the heredoc from quoted (`<<'YAML'`) to unquoted (`<<YAML`) and replace
`  namespace: argocd` with `  namespace: ${E2E_SANDBOX_ARGOCD_NAMESPACE:-cicd}`. No other line of
that manifest contains `$`; confirm it before unquoting.

**c.** In `e2e_verify_sandbox`, replace:

```bash
  _E2E_ACTIVE_PHASE="installing-argocd"
  _run_command -- helm upgrade --install argocd argo/argo-cd --kube-context ubuntu-k3s \
    -n argocd --create-namespace --set server.insecure=true --set server.service.type=ClusterIP
  _e2e_sandbox_kc -n argocd apply -f - <<< "$(_e2e_sandbox_argocd_cluster_manifest)"
  _e2e_sandbox_kc -n argocd wait --for=condition=available deployment/argocd-server --timeout=600s
```

with:

```bash
  _E2E_ACTIVE_PHASE="checking-argocd"
  _e2e_sandbox_argocd_ready
  _e2e_sandbox_kc -n "${E2E_SANDBOX_ARGOCD_NAMESPACE:-cicd}" apply -f - <<< "$(_e2e_sandbox_argocd_cluster_manifest)"
```

**d.** In the appset loop, `ARGOCD_NAMESPACE=argocd` becomes
`ARGOCD_NAMESPACE="${E2E_SANDBOX_ARGOCD_NAMESPACE:-cicd}"`.

No other `helm`, CRD, label or annotation change. Do not touch `bin/cluster-up` or
`scripts/plugins/argocd.sh`.

### 2. Docs

- `docs/guides/` or `docs/howto/`: wherever Tier 2 / `e2e-sandbox` is described (find it with
  `grep -rln 'e2e-sandbox' docs/guides docs/howto`), say that it reuses the Argo CD that
  `cluster-up` installs in `cicd` (`E2E_SANDBOX_ARGOCD_NAMESPACE` overrides it), installs none, and
  fails at phase `checking-argocd` with a "run make up" message when that install is missing.
- `CHANGELOG.md` `[Unreleased]`: one `Fixed:` entry.

## Files

| File | Change |
|---|---|
| `scripts/plugins/e2e.sh` | item 1 |
| `scripts/tests/plugins/e2e.bats`, `scripts/tests/plugins/e2e_sandbox_preflight.bats` | tests |
| the Tier 2 guide/howto found in item 2, `CHANGELOG.md` | item 2 |

### Tests (BATS, stubbed kubectl via a fake on `PATH` or function stubs; no real cluster, no real helm)

Show each new test failing against the pre-change `e2e.sh` (temp copy).

1. **Reuse:** a fake `kubectl` that answers the two `get` calls with one name each and records all
   argv. `e2e_verify_sandbox` (other phases stubbed, as in the existing "never invokes
   register_app_cluster" test) exits 0, and no `helm` is ever called. Put a fake `helm` on `PATH`
   that writes a marker, and assert the marker is absent. The recorded argv shows the `wait` on
   `deployment/<server name>` and `rollout status statefulset/<controller name>` in `cicd`.
2. **Registration target:** `_e2e_sandbox_argocd_cluster_manifest` renders `namespace: cicd` by
   default and `namespace: other` with `E2E_SANDBOX_ARGOCD_NAMESPACE=other`. The `kubectl apply` of
   it is in that namespace, and the appset loop's `envsubst` sees `ARGOCD_NAMESPACE=cicd`. Assert on
   the env the stub sees, not whole lines.
3. **Absent:** `get` returns nothing. `_e2e_sandbox_argocd_ready` returns non-zero with a message
   containing `cicd` and `make up`, and no `wait`, `apply` or `helm` call follows.
4. **Ambiguous:** two server names returned. Same non-zero result and no `wait`.
5. **Phase:** on the absent case, `e2e_verify_sandbox` fails with `_E2E_ACTIVE_PHASE` =
   `checking-argocd`. Assert through the summary stub's argument.
6. The existing "never invokes register_app_cluster" test stays green. Update its stubs only as
   needed for the two new `get` calls.

### Mutations (Claude, at verification)

- restore the `helm upgrade --install` line (test 1 red);
- default namespace back to `argocd` (tests 1 and 2 red);
- drop the exactly-one check (test 4 red);
- `return 0` instead of `return 1` on absent (tests 3 and 5 red).

### Definition of Done

- [ ] Items 1–2 exactly as written; `shellcheck scripts/plugins/e2e.sh` adds no warning.
- [ ] `bats scripts/tests/plugins/e2e.bats scripts/tests/plugins/e2e_sandbox_preflight.bats </dev/null`
  green; paste the tail.
- [ ] Leave the changes **uncommitted**. Claude verifies, commits and lands them with:
  `fix(e2e): reuse the sandbox's cicd Argo CD instead of installing a second one with Helm`
- [ ] Live proof (operator / Claude after landing): `make e2e-sandbox` on a running sandbox passes
  `checking-argocd`, and `helm list -A --kube-context ubuntu-k3s` still shows only `cilium` and
  `external-secrets`.

### What NOT to Do

- Do NOT run anything against a real cluster, real helm, the ACG sandbox or the Pushgateway.
- Do NOT delete or patch CRDs, Helm ownership labels or annotations, or uninstall anything.
- Do NOT modify files outside the Files table, `memory-bank/`, or `scripts/lib/foundation/`.
- Do NOT create a PR, commit, switch branches, or use `--no-verify`.

