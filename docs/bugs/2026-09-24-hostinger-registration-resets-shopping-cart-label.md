# Bug: hostinger registration resets `k3d-manager/shopping-cart` to `false`, un-generating every shopping-cart Application and silently killing CVE auto-patch

**Filed:** 2026-09-24
**Branch:** `k3d-manager-v1.37.0` — work on this branch, never `main`
**Type:** bug (same defect shape as
`2026-09-23-hostinger-registration-never-sets-provider-label.md`, same function, one line away)

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- `git pull origin k3d-manager-v1.37.0`.
- Read IN FULL before editing:
  - `scripts/lib/providers/k3s-hostinger.sh` — the `_hostinger_register_cluster` env block (~lines 162–172)
  - `scripts/plugins/argocd.sh` — `register_app_cluster`, lines 1481–1520
  - `scripts/etc/argocd/platform-ops/app-cve-scan.sh` — the `_promote` path, lines 516–540
- Implement exactly what is written. No interpretation, no unsolicited refactors.

---

## Problem — measured live on 2026-09-24, not inferred

The `app-cve-scan` CronJob in `platform-ops` has **never succeeded**:
`kubectl get cronjob app-cve-scan -o jsonpath='{.status.lastSuccessfulTime}'` returns **empty**.
A manual run (`kubectl create job --from=cronjob/app-cve-scan`) reproduced it in 6m32s,
exit code 1, with exactly one error:

```
Error from server (NotFound): applications.argoproj.io "ubuntu-hostinger-shopping-cart-frontend" not found
```

There are **0** ConfigMaps matching `k3dm.k3d.io/cve-remediation-event=true`, which is why the
"CVE auto Patch" Grafana dashboard's remediation panels are empty. (Its *inventory* panels are
fine — `trivy_vulnerability_inventory` has 7447 series.)

### The chain

1. `register_app_cluster` (`scripts/plugins/argocd.sh:1481`) derives the label from
   `ARGOCD_APP_CLUSTER_SHOPPING_CART`, defaulting to **`false`**:
   ```bash
   local _shopping_cart="${ARGOCD_APP_CLUSTER_SHOPPING_CART:-false}"
   ```
   and writes it at line 1519 as `k3d-manager/shopping-cart: "${_shopping_cart}"`.

2. `_hostinger_register_cluster` **never sets that variable** — `grep -c
   'ARGOCD_APP_CLUSTER_SHOPPING_CART' scripts/lib/providers/k3s-hostinger.sh` returns **0**. So
   every `make refresh-registration CLUSTER_PROVIDER=k3s-hostinger` stamps the label to `false`.

3. The live `services-git` ApplicationSet selects clusters on **both** labels:
   ```yaml
   matchLabels:
     k3d-manager/role: app-cluster        # hostinger HAS this
     k3d-manager/shopping-cart: "true"    # hostinger has "false"
   ```
   Its cluster generator therefore matches **zero** clusters. The AppSet still reports
   `All applications have been generated successfully` — generating nothing is "success".

4. Its template is `{{.name}}-{{.path.basename}}`, i.e. exactly
   `ubuntu-hostinger-shopping-cart-frontend`. Confirmed: hub `cicd` has
   `ubuntu-hostinger-eso`, `ubuntu-hostinger-platform`, `ubuntu-hostinger-grafana-dashboards`,
   `shopping-cart-identity` — and **no** `ubuntu-hostinger-shopping-cart-*` at all.

5. `app-cve-scan.sh:526` patches that Application **unguarded** under `set -eu`:
   ```bash
   _hub_kubectl -n "${HUB_ARGOCD_NAMESPACE}" patch application "${_app}" --type merge -p "${_patch}" >/dev/null
   ```
   `_emit_remediation_event` is on line **529**. The patch 404s, `set -e` aborts the script, and
   the event is never emitted — for this service *or any remaining one*.

**This regressed.** `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`
records a run that promoted four services including `frontend`, so these Applications existed and
a registration refresh has since flipped the label.

### Why this matters beyond the dashboard

The scan reaching `_promote` means it **found a real HIGH/CRITICAL CVE worth promoting** on
`shopping-cart-frontend`. The auto-patch loop has been silently not remediating. The empty
dashboard was the only symptom, and it read as a cosmetic gap.

---

## S1 — set the label at registration (the actual fix)

In `scripts/lib/providers/k3s-hostinger.sh`, in the `_hostinger_register_cluster` env block,
immediately after the `ARGOCD_APP_CLUSTER_PROVIDER` line added by `834149ea`, add exactly:

```bash
    ARGOCD_APP_CLUSTER_SHOPPING_CART="${ARGOCD_APP_CLUSTER_SHOPPING_CART:-true}" \
```

Keep the `:-` default so an explicit override still wins — Test 2 exists to prove that.

`true` is correct for this cluster: namespace `shopping-cart-apps` is deployed and enrolled in
ambient on `ubuntu-hostinger`, and `services-git` is the AppSet that manages it.

## S2 — a missing Application must not abort the whole scan

In `scripts/etc/argocd/platform-ops/app-cve-scan.sh`, replace the unguarded patch at line 526:

```bash
  _hub_kubectl -n "${HUB_ARGOCD_NAMESPACE}" patch application "${_app}" --type merge -p "${_patch}" >/dev/null
```

with:

```bash
  if ! _hub_kubectl -n "${HUB_ARGOCD_NAMESPACE}" patch application "${_app}" --type merge -p "${_patch}" >/dev/null 2>&1; then
    _log "PROMOTION ${_svc}: FAILED — ArgoCD Application '${_app}' not patchable (missing or forbidden); skipping this service"
    _rc=1
    return 0
  fi
```

Rules for S2, each deliberate:

- It must `return 0`, not a non-zero code, so `set -e` does not abort the loop. The run's overall
  failure is carried by `_rc`, which is the mechanism
  `2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md` already established.
- Do **not** emit a remediation event on this path. An event means "a promotion happened". Emitting
  one for a promotion that did not happen would put a false success on the dashboard, which is
  strictly worse than the empty panel we started with.
- Do **not** reorder `_emit_remediation_event` to run before the patch, for the same reason.
- `_rc` must be visible here. If it is not in scope as written, set it via the same mechanism the
  surrounding code already uses — do not invent a new global.

## S3 — do not change any of these

- Do NOT edit the `services-git` ApplicationSet. Its selector is correct; the cluster label was wrong.
- Do NOT hand-patch the live `cluster-ubuntu-hostinger` Secret. S1 is the fix; the operator re-runs
  registration.
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/` — subtrees, fixed upstream.
- Do NOT weaken `02e3fa76`, `03b875c5`, `114e5c82` or `834149ea`.
- Do NOT change the `false` default in `register_app_cluster:1481`. Other app clusters legitimately
  are not shopping-cart clusters; the default is right and the caller was wrong.

---

## Tests

Add to `scripts/tests/plugins/argocd_app_cluster_provider_label.bats` (it already covers the
sibling label from `834149ea`, so this is the correct home — do not create a second file):

1. `_hostinger_register_cluster` exports `ARGOCD_APP_CLUSTER_SHOPPING_CART=true` when unset.
   Assert on the **rendered label value** `k3d-manager/shopping-cart: "true"`, via grep — not on the
   function's exit status.
2. An explicit `ARGOCD_APP_CLUSTER_SHOPPING_CART=false` still wins (proves the `:-` default).
3. `register_app_cluster` still writes `"false"` when the variable is unset by any other caller.

New file `scripts/tests/plugins/app_cve_scan_promote_guard.bats`:

4. A failing `patch application` logs `PROMOTION <svc>: FAILED` and the function returns 0.
5. A failing `patch application` emits **no** remediation event.
6. A succeeding `patch application` still emits exactly one remediation event (no regression).

No bare `!` and no whole-line `grep -F` in any BATS assertion.

## Mutations — a passing test is not evidence it can fail

Prove each, one at a time, restoring and confirming `git diff --quiet` between them. Paste the red.

- **M1** — remove the S1 line. Test 1 must go red **on the asserted label value being `false`**, not
  on a stub error. If it reds for any other reason, the test is wrong; fix the test.
- **M2** — change S1's default to `false`. Test 1 must go red; Test 2 must stay green.
- **M3** — restore the unguarded patch from S2. Test 4 must go red.
- **M4** — make the S2 failure path emit an event anyway. Test 5 must go red.

## Gates — paste actual output for each

1. `bats` on both test files — green, paste counts. `bats` is bare on PATH at `/opt/homebrew/bin/bats`.
2. `shellcheck -x` on `scripts/lib/providers/k3s-hostinger.sh` and
   `scripts/etc/argocd/platform-ops/app-cve-scan.sh` — zero new warnings vs `HEAD~`. Paste **both**
   counts. Count with `grep -cE '\^-*\^ SC'`, **not** `grep -c 'SC[0-9]'` — the latter double-counts
   because the "For more information" wiki URL line also contains the code.
3. All four mutations, as above.
4. `make test` — green. It takes ~15 minutes; that is **not** a hang. Paste the final summary line.
   Then bare `pytest` (pyenv shim — `pytest` is NOT on `/opt/homebrew/bin/python3`).
5. `make check-doc-links` — the pre-commit hook runs it on staged `.md`.

---

## Docs — required in this release

- `docs/guides/cve-auto-patch.md` (or the existing equivalent — find it, do not create a duplicate):
  document that the `services-git` AppSet requires **both** `k3d-manager/role=app-cluster` and
  `k3d-manager/shopping-cart=true`, that registration sets the latter, and that a registration
  refresh which omits it silently un-generates every shopping-cart Application.
- `CHANGELOG.md` under `[Unreleased]` → `### Fixed`.
- `memory-bank/activeContext.md` and `memory-bank/progress.md` with the commit SHA and status.

CHANGELOG and memory-bank do **not** count as the feature's documentation.

## Definition of Done

- [ ] S1, S2 and S3 implemented exactly as written.
- [ ] Tests 1–6 green; M1–M4 each proved red then restored.
- [ ] shellcheck zero new warnings, both counts pasted.
- [ ] `make test` and bare `pytest` green, summary lines pasted.
- [ ] Guide updated; CHANGELOG updated; memory-bank updated.
- [ ] Committed and pushed to `origin/k3d-manager-v1.37.0`; `git rev-parse HEAD` and
      `git rev-parse origin/k3d-manager-v1.37.0` print the same SHA.

Commit message — pass with `git commit -F <file>` or a real heredoc, never an escaped one-line
string (a previous run's trailers arrived as literal `\n` and were not parsed as trailers):

```
fix(argocd): set the shopping-cart label when registering ubuntu-hostinger

Registration defaulted k3d-manager/shopping-cart to "false", so the
services-git ApplicationSet matched zero clusters and generated none of
the ubuntu-hostinger-shopping-cart-* Applications. app-cve-scan then died
under set -e patching a missing Application, before emitting any
remediation event — leaving the CVE auto-patch dashboard permanently empty
while real HIGH/CRITICAL findings went unremediated.

Also guards the promotion patch so one missing Application no longer
aborts the scan for every remaining service.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

## What NOT to do

- Do NOT create a pull request. Do NOT merge. Do NOT commit to `main`. Do NOT force-push.
- Do NOT use `--no-verify` or otherwise skip the pre-commit hooks.
- Do NOT modify files outside: `scripts/lib/providers/k3s-hostinger.sh`,
  `scripts/etc/argocd/platform-ops/app-cve-scan.sh`,
  `scripts/tests/plugins/argocd_app_cluster_provider_label.bats`,
  `scripts/tests/plugins/app_cve_scan_promote_guard.bats`, the guide, `CHANGELOG.md`, memory-bank.
- Do NOT DELETE, MOVE or RENAME any file outside that list, for any reason, including a hygiene or
  scope check. A previous run deleted an untracked spec file it judged test-generated; it was not,
  and the work had to be reconstructed from a log. If a check flags an unrelated or untracked file,
  LEAVE IT ALONE and report it in your final message.
- Do NOT touch the live cluster: no `kubectl`, `helm`, `docker`, `make up`, `make refresh`,
  `make refresh-registration`, and no reapply of any ApplicationSet. The operator owns that step.
- Do NOT run `agy` or `gemini` against the real APIs.

## Operator runbook — NOT the agent's work

After this lands, the operator (not the agent) runs
`make refresh-registration CLUSTER_PROVIDER=k3s-hostinger`, confirms the label flips to `"true"`,
confirms `services-git` generates the five `ubuntu-hostinger-shopping-cart-*` Applications, then
triggers `app-cve-scan` and confirms a `k3dm.k3d.io/cve-remediation-event=true` ConfigMap appears.
