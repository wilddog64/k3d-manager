# Bugfix: v1.16.0 — `make status` reports no service-mesh or CNI health

**Branch:** `k3d-manager-v1.16.0`
**Files:** `bin/cluster-status`

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — the Hostinger ambient
  section records the incident this spec prevents recurring.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `bin/cluster-status` — the whole file. Note the section convention
    (`echo ""` then `echo "=== <Name> (${APP_CONTEXT}) ==="`), how `APP_CONTEXT` / `INFRA_CONTEXT`
    are resolved, and how existing sections degrade when a resource is absent (they print a short
    note, they do not `exit`).
  - The `=== App Observability (${APP_CONTEXT}) ===` section (currently ~lines 134–165) — the new
    section goes immediately after it and must match its style.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

`bin/cluster-status` (435 lines) contains **no** check for istio, ztunnel, istio-cni, Cilium, or
ambient namespace enrollment — `grep -n 'istio\|cilium\|ztunnel\|ambient' bin/cluster-status`
returns nothing. `make status` therefore reports a cluster as healthy while its service mesh is
entirely broken.

This is not hypothetical. On `ubuntu-hostinger` the mesh was non-functional for **~3 days** and
`make status` never indicated a problem. Two distinct faults were invisible:

1. **`istio-cni-node` stuck `0/1`** — the ApplicationSet pinned Cilium's CNI paths on a
   bare-flannel k3s host, so istio-cni never chained.
   (See `docs/bugs/2026-07-21-istio-ambient-cni-dirs-not-substrate-aware.md`.)
2. **Namespace carried `istio-injection=enabled` while the milestone had moved to ambient** —
   the two enrollment modes are mutually exclusive, so sidecars kept being injected and the
   workloads never entered the ambient dataplane at all. Every pod ran `2/2` with an
   `istio-proxy` that was doing work ztunnel was already deployed to do.
   (See `docs/bugs/2026-07-21-shopping-cart-ns-sidecar-blocks-ambient.md`.)

   > The sibling spec originally also blamed sidecar injection for the node's CPU pressure.
   > That claim was **measured and retracted** on 2026-07-21: with every sidecar removed,
   > requests went 1910m (95%) → **1960m (98%)** of 2000m and two pods stayed `Pending`.
   > The 2-CPU node is genuinely oversubscribed by non-app workloads. Do not carry the CPU
   > story into this section — this section reports **mesh health**, not capacity.

**Root cause:** `cluster-status` grew sections for nodes, pods, API health, observability, ArgoCD,
and Trivy, but the mesh was never added when the ambient milestone landed.

---

## Reproduction

1. Point at a cluster whose ambient mesh is broken (e.g. `istio-cni-node` `0/1`).
2. `make status CLUSTER_PROVIDER=k3s-hostinger`.
3. Output contains no mesh information; nothing signals the mesh is down.

Expected: a `Service Mesh` section that names the CNI substrate, shows the three ambient component
ready-counts, lists ambient-enrolled namespaces, and loudly flags the injection/ambient conflict.

---

## Fix

### Change 1 — `bin/cluster-status`: add a Service Mesh section after App Observability

The App Observability section ends at the current **line 163** (`fi`). Line 164 is blank, line 165
is `echo ""`, line 166 is the `=== Hub ArgoCD Registration ... ===` header.

Insert the new block **after line 163** and **before the `echo ""` on line 165**. The block below
opens with its own `echo ""`, so after insertion the file reads: `fi` → blank → new block →
blank → `echo ""` → Hub ArgoCD header.

**Exact new block to insert:**

```bash
echo ""
echo "=== Service Mesh / CNI (${APP_CONTEXT}) ==="
if kubectl --context "${APP_CONTEXT}" get ns istio-system >/dev/null 2>&1; then
  if kubectl --context "${APP_CONTEXT}" -n kube-system get daemonset cilium >/dev/null 2>&1; then
    _mesh_cni_ready="$(kubectl --context "${APP_CONTEXT}" -n kube-system get daemonset cilium \
      -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}' 2>/dev/null || true)"
    echo "CNI substrate:    cilium (${_mesh_cni_ready:-unknown} ready)"
  else
    echo "CNI substrate:    flannel (no cilium daemonset)"
  fi

  for _mesh_ds in istio-cni-node ztunnel; do
    if kubectl --context "${APP_CONTEXT}" -n istio-system get daemonset "${_mesh_ds}" >/dev/null 2>&1; then
      _mesh_ready="$(kubectl --context "${APP_CONTEXT}" -n istio-system get daemonset "${_mesh_ds}" \
        -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}' 2>/dev/null || true)"
      printf '%-18s%s ready\n' "${_mesh_ds}:" "${_mesh_ready:-unknown}"
    else
      printf '%-18s%s\n' "${_mesh_ds}:" "ABSENT"
    fi
  done

  if kubectl --context "${APP_CONTEXT}" -n istio-system get deployment istiod >/dev/null 2>&1; then
    _mesh_istiod="$(kubectl --context "${APP_CONTEXT}" -n istio-system get deployment istiod \
      -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null || true)"
    printf '%-18s%s ready\n' "istiod:" "${_mesh_istiod:-unknown}"
  else
    printf '%-18s%s\n' "istiod:" "ABSENT"
  fi

  _mesh_ambient_ns="$(kubectl --context "${APP_CONTEXT}" get ns \
    -l istio.io/dataplane-mode=ambient \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' 2>/dev/null || true)"
  echo "ambient ns:       ${_mesh_ambient_ns:-<none>}"

  _mesh_conflict="$(kubectl --context "${APP_CONTEXT}" get ns \
    -l istio.io/dataplane-mode=ambient,istio-injection=enabled \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' 2>/dev/null || true)"
  if [[ -n "${_mesh_conflict}" ]]; then
    echo "CONFLICT:         ${_mesh_conflict}— has BOTH istio-injection=enabled and dataplane-mode=ambient"
    echo "                  sidecars are still being injected; ambient will not take effect"
  fi
else
  echo "istio-system namespace absent — service mesh not deployed"
fi
```

> Every lookup is guarded and degrades to `ABSENT` / a short note, matching how the existing
> sections behave on a partially-provisioned cluster. The section must never `exit` non-zero — a
> missing mesh is information, not a status-tool failure.

> **`|| true` on every command substitution is load-bearing, not style.** `bin/cluster-status`
> runs under `set -euo pipefail` at line 14, and these assignments are at top level, so a bare
> `_var="$(kubectl …)"` whose `kubectl` exits non-zero takes the **whole status tool** down —
> turning "the mesh is unreachable" into "the status tool is broken". The existing App
> Observability section (lines 136–154) already ends every substitution with `2>/dev/null || true`
> for exactly this reason. Copy the block verbatim; do not drop the `|| true`.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/cluster-status` | add `Service Mesh / CNI` section: CNI substrate, istio-cni/ztunnel/istiod ready counts, ambient-enrolled namespaces, injection-vs-ambient conflict warning |

---

## Rules

- `shellcheck -S warning bin/cluster-status` — zero new warnings. Quote every expansion; the new
  locals use the `_mesh_`/`_mesh_cni_` prefix to avoid colliding with existing names — verify with
  `grep -n '_mesh' bin/cluster-status` that no prior variable of that name exists.
- No other section touched; no reordering of existing output.
- Must not change `bin/cluster-status` exit status in any scenario.
- `bash -n bin/cluster-status` — the file must still parse.
- Do NOT run `bin/cluster-status` or `make status` against a live cluster. Codex has no
  live-cluster verification role here; static gates only. Claude runs the live check (below).

### Stub-kubectl harness — REQUIRED, and it is the only proof of the CONFLICT branch

The live cluster can no longer exercise the CONFLICT branch: commit `ebf27de3` removed
`istio-injection` from `shopping-cart-apps`, so `make status` against `ubuntu-hostinger` will
correctly print **no** CONFLICT line. That branch must therefore be proven against a synthetic
fixture, in-process, with no cluster.

Write this file to your scratchpad (NOT into the repo — it must never be committed), then append
the new Service Mesh block to it **verbatim** where the marker says:

```bash
cat > /tmp/mesh-harness.sh <<'HARNESS'
set -euo pipefail
APP_CONTEXT=fake

kubectl() {
  local args="$*"
  case "${args}" in
    *"get ns istio-system"*)
      if [[ "${MODE}" == "nomesh" ]]; then return 1; fi
      return 0 ;;
  esac
  if [[ "${MODE}" == "flaky" ]]; then return 1; fi
  case "${args}" in
    *"daemonset cilium"*)          return 1 ;;
    *"daemonset istio-cni-node"*)  echo "1/1"; return 0 ;;
    *"daemonset ztunnel"*)         echo "1/1"; return 0 ;;
    *"deployment istiod"*)         echo "1/1"; return 0 ;;
    *"istio-injection=enabled"*)
      if [[ "${MODE}" == "conflict" ]]; then echo "shopping-cart-apps "; fi
      return 0 ;;
    *"dataplane-mode=ambient"*)    echo "shopping-cart-apps "; return 0 ;;
  esac
  return 0
}

# >>> PASTE THE NEW SERVICE MESH BLOCK BELOW THIS LINE, VERBATIM <<<
HARNESS
```

Then run all four modes and paste the complete output:

```bash
for M in normal conflict nomesh flaky; do
  echo "########## MODE=${M}"
  MODE="${M}" bash /tmp/mesh-harness.sh
  echo "RC=$?"
done
```

**Required results — all four must hold:**

| MODE | Must print | RC |
|------|-----------|----|
| `normal` | `flannel` substrate, three `1/1 ready` lines, `ambient ns: shopping-cart-apps`, **no** CONFLICT | 0 |
| `conflict` | all of the above **plus** both CONFLICT lines | 0 |
| `nomesh` | only `istio-system namespace absent — service mesh not deployed` | 0 |
| `flaky` | `flannel`, three `ABSENT` lines, `ambient ns: <none>`, no CONFLICT | 0 |

`flaky` is the `set -e` safety proof and is the one that matters most. It has been confirmed to
fail correctly: with `|| true` dropped from the command substitutions, `flaky` exits **RC=1** and
the output truncates after the `istiod:` line — the `ambient ns:` line never prints. If you see
that, you dropped a `|| true`. Do not "fix" it by changing the harness.

Judge each mode by the `RC=` line, which is on its own line by design — never append `; echo` to
the harness invocation.

---

## Definition of Done

- [ ] `Service Mesh / CNI` section present, placed after App Observability.
- [ ] Reports cilium-vs-flannel substrate; ready counts for istio-cni-node, ztunnel, istiod.
- [ ] Lists ambient-enrolled namespaces; prints `<none>` when there are none.
- [ ] Prints the CONFLICT warning when a namespace has both labels — proven by harness
      `MODE=conflict`, since the live cluster can no longer produce this state.
- [ ] Degrades cleanly (`ABSENT` / note) when istio-system or a component is missing.
- [ ] Every command substitution in the new block ends `2>/dev/null || true` — proven by harness
      `MODE=flaky` returning **RC=0** with the `ambient ns:` line present.
- [ ] All four harness modes pass per the table in Rules; full output pasted in the report.
- [ ] Harness file lives in scratchpad only — `git status` shows no new untracked file in the repo.
- [ ] `shellcheck -S warning bin/cluster-status` clean; `bash -n bin/cluster-status` clean.
- [ ] Exit status unchanged; existing sections untouched.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`; push verified with
      `git log origin/k3d-manager-v1.16.0 --oneline -1` (paste the output).
- [ ] memory-bank updated with commit SHA and task status — as a **separate commit**, never
      bundled with `bin/cluster-status`.

**Commit message (exact):**
```
feat(status): report service mesh, CNI substrate, and ambient enrollment
```

### Live re-verify — Claude runs this after the push (NOT Codex)

`make status CLUSTER_PROVIDER=k3s-hostinger` must print the new section without error and report:

- `CNI substrate:    flannel (no cilium daemonset)`
- `istio-cni-node`, `ztunnel`, `istiod` all `1/1 ready`
- `ambient ns:       shopping-cart-apps`
- **no CONFLICT line**

The absent CONFLICT line is the expected result, not a gap in coverage. Both sibling specs have
landed and were live-verified on 2026-07-21: `ebf27de3` removed `istio-injection` from the
namespace, and `a08911b3` fixed the CNI paths so `istio-cni-node` reaches `1/1`. The CONFLICT
branch is covered by the harness `MODE=conflict` instead.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `bin/cluster-status`.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT make the mesh section fatal or add `set -e`-sensitive bare command substitutions that
  abort the script when a resource is missing. This is the single most likely way to get this
  change wrong — see the `flaky` harness mode.
- Do NOT add mesh checks to the Hub section — the hub does not run the ambient dataplane.
- Do NOT commit the harness file, and do NOT add it under `scripts/tests/`. It is a throwaway
  static fixture for this one change; the repo's BATS suites are pure-logic only and do not mock
  clusters. Scratchpad only.
- Do NOT convert the new block to `_kubectl` and do NOT "modernize" the existing calls.
  `bin/cluster-status` sources `scripts/lib/system.sh` but deliberately calls bare
  `kubectl --context` throughout (5 existing call sites, 0 uses of `_kubectl`); the new section
  matches the file's local convention. Changing that convention is a separate decision and would
  also break the stub-kubectl harness above.
- Do NOT rename or reuse any `_mesh*` variable name expecting a collision — `grep -c '_mesh'
  bin/cluster-status` currently returns **0**, so all six new locals are collision-free as written.
