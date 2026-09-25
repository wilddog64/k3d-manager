# `_argocd_appset_live_overrides` makes a wrong live value permanent — the istio-cni dir fix has now regressed three times

**Filed:** 2026-09-23
**Branch:** `k3d-manager-v1.37.0`
**Status:** OPEN
**Severity:** high — the same defect has been "fixed" three times and re-broken three times, because the fix cannot reach the cluster

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- `git pull origin k3d-manager-v1.37.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/plugins/argocd.sh` — `_argocd_appset_live_overrides` at `:1250-1288` and its only
    consumer, the `env ... envsubst` apply at `:1344-1356`.
  - `scripts/plugins/istio_ambient.sh` — `_istio_ambient_cni_dirs` at `:54` and
    `_istio_ambient_target_provider` at `:62`.
  - `scripts/lib/providers/k3s-hostinger.sh` — `_hostinger_reapply_gitops_applicationsets` at
    `:818-840`, especially the two exports at `:830-831` and the comment above them.
  - `scripts/etc/argocd/vars.sh:80-81` — the generic defaults.
- Read the three prior specs for this same symptom. **All three fixes are correct. Do NOT revert
  any of them** — this spec explains why correct fixes never took effect:
  - `docs/bugs/2026-07-17-ambient-istio-cni-conf-bin-dir-mismatch.md` (fix `ce4d83f0`)
  - `docs/bugs/2026-07-21-istio-ambient-cni-dirs-not-substrate-aware.md` (fix `9c0e336a`)
  - `docs/bugs/2026-07-21-ambient-cni-vars-missing-from-argocd-vars.md`
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

`istio-cni-node-vgr6m` on `ubuntu-hostinger`: `0/1 Running`, 0 restarts, 17 days.

```
Readiness probe failed: HTTP probe failed with statuscode: 503
```

The pod's own first log line, written once at start and never repeated, is the whole diagnosis:

```
2026-09-06T16:36:54.921898Z warn cni-agent Istio CNI is configured as chained plugin,
but cannot find existing CNI network config: no networks found in /host/etc/cni/net.d
```

k3s keeps its CNI config in `/var/lib/rancher/k3s/agent/etc/cni/net.d` and its binaries in
`/var/lib/rancher/k3s/data/cni`. The DaemonSet mounts `/etc/cni/net.d` and `/opt/cni/bin` — the
generic defaults from `scripts/etc/argocd/vars.sh:80-81`. With no base config to chain onto,
install-cni never writes its conflist, so `/readyz` on `:8000` returns 503 forever. This is a
correct, permanent "I did not install", not a probe-tuning problem.

The live ApplicationSet holds the wrong values:

```
$ kubectl --context k3d-k3d-cluster -n cicd get applicationset istio-ambient -o json \
  | jq -r '[.spec.generators[].list.elements[] | select(.name=="istio-cni") | .values][0]'
cniConfDir: /etc/cni/net.d
cniBinDir: /opt/cni/bin
```

The repo already knows the right answer. `_hostinger_reapply_gitops_applicationsets` exports it:

```bash
      # Hostinger runs k3s/flannel. The Istio CNI DaemonSet must mount the k3s CNI
      # directories rather than the generic Cilium defaults.
      export AMBIENT_CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
      export AMBIENT_CNI_BIN_DIR="/var/lib/rancher/k3s/data/cni"
```

## Root cause — the live value wins over both the export and the provider

`_argocd_appset_live_overrides` reads the **live** ApplicationSet and emits its current values as
overrides:

```bash
   if grep -q '\${AMBIENT_CNI_CONF_DIR}' "$file"; then
      if [[ -n "${live}" ]]; then
         value="$(printf '%s' "${live}" | jq -r '[.spec.generators[]?.list.elements[]? | select(.name == "istio-cni") | .values][0] // ""')"
         conf="$(printf '%s\n' "${value}" | sed -n 's/^[[:space:]]*cniConfDir:[[:space:]]*//p' | head -1)"
         bin="$(printf '%s\n' "${value}" | sed -n 's/^[[:space:]]*cniBinDir:[[:space:]]*//p' | head -1)"
      fi
      if [[ -z "${conf:-}" || -z "${bin:-}" ]]; then
```

The provider-derived branch runs **only when the live read came back empty**. The result is
consumed at `:1355`:

```bash
      _apply_err="$(env ${_overrides[@]+"${_overrides[@]}"} envsubst "${_vars}" < "$file" \
         | _kubectl apply -f - 2>&1 >/dev/null)" || _apply_rc=$?
```

`env VAR=value` overrides the inherited environment. So the precedence is:

```
live ApplicationSet  >  provider-derived dirs  >  caller's export
                                                   ^ never consulted at all
```

The caller's exported `AMBIENT_CNI_CONF_DIR` is not merely outranked — it is never read by this
function. Once the live AppSet holds the generic defaults, every reapply reads them back and
writes them again. The value is self-perpetuating, and the log line says exactly this, every
time, as if it were good news:

```
[argocd] istio-ambient.yaml: keeping live AMBIENT_CNI_CONF_DIR=/etc/cni/net.d ...
```

That is why the fix has landed three times in git and never reached hostinger. `ce4d83f0`
hardcoded the Cilium paths; `9c0e336a` made them substrate-aware; the vars.sh spec wired the
defaults. Each was correct and each was immediately overwritten by the live value on the next
reapply. The `2026-07-17` spec's own status line records the workaround that was needed:
*"live hub FIXED 2026-09-13 (operator reapply); code default still needs a spec"* — that reapply
worked only because the operator happened to clear the live value first.

### Why the live-read exists, and must stay

Preferring the live value is correct for `APP_CLUSTER_NAME`, the other override this function
emits: the active app cluster is chosen at runtime and the file has no way to know it. It is
wrong for the CNI dirs, which are a **deterministic function of the target cluster's CNI
substrate** — something the code can compute and the live AppSet can only remember, correctly or
otherwise.

---

## S1 — invert the precedence for the CNI dirs only

In `_argocd_appset_live_overrides`, compute the provider-derived dirs **first** and consult the
live AppSet only as a fallback. Replace the whole `if grep -q '\${AMBIENT_CNI_CONF_DIR}' "$file";
then ... fi` block with:

```bash
   if grep -q '\${AMBIENT_CNI_CONF_DIR}' "$file"; then
      if ! declare -f _istio_ambient_cni_dirs >/dev/null 2>&1 && [[ -r "${PLUGINS_DIR}/istio_ambient.sh" ]]; then
         # shellcheck disable=SC1090,SC1091
         source "${PLUGINS_DIR}/istio_ambient.sh"
      fi
      if declare -f _istio_ambient_target_provider >/dev/null 2>&1; then
         provider="${AMBIENT_CNI_PROVIDER:-$(_istio_ambient_target_provider "${ARGOCD_CONTEXT:-k3d-k3d-cluster}" "${ARGOCD_NAMESPACE:-cicd}" "${APP_CLUSTER_NAME:-ubuntu-k3s}")}"
         if [[ -n "${provider}" ]]; then
            dirs="$(_istio_ambient_cni_dirs "${provider}")"
            conf="${dirs%% *}"
            bin="${dirs##* }"
         fi
      fi
      if [[ -z "${conf:-}" || -z "${bin:-}" ]] && [[ -n "${live}" ]]; then
         value="$(printf '%s' "${live}" | jq -r '[.spec.generators[]?.list.elements[]? | select(.name == "istio-cni") | .values][0] // ""')"
         conf="$(printf '%s\n' "${value}" | sed -n 's/^[[:space:]]*cniConfDir:[[:space:]]*//p' | head -1)"
         bin="$(printf '%s\n' "${value}" | sed -n 's/^[[:space:]]*cniBinDir:[[:space:]]*//p' | head -1)"
      fi
      if [[ -n "${conf:-}" && -n "${bin:-}" ]]; then
         printf 'AMBIENT_CNI_CONF_DIR=%s\nAMBIENT_CNI_BIN_DIR=%s\n' "${conf}" "${bin}"
      fi
   fi
```

This is the same two blocks in the opposite order, with the guard inverted. Nothing else changes:
the `APP_CLUSTER_NAME` block above is untouched, the function still returns 0, and it still emits
nothing when neither source resolves — in which case the caller's own exported value survives
into `envsubst`, which is the correct last resort.

## S2 — say which source won

The current log line claims the live value is being *kept* even when it is being overwritten. In
`_argocd_deploy_applicationsets`, replace:

```bash
      if (( ${#_overrides[@]} > 0 )); then
         _info "[argocd] ${filename}: keeping live ${_overrides[*]}"
      fi
```

with:

```bash
      if (( ${#_overrides[@]} > 0 )); then
         _info "[argocd] ${filename}: resolved overrides ${_overrides[*]}"
      fi
```

Wording only — the message must not assert a provenance it does not know.

## S3 — refuse to write generic CNI dirs to a k3s target

A guard so this class cannot come back silently. Add to `_argocd_appset_live_overrides`, at the
point where `conf` and `bin` are both known and before the `printf`:

```bash
      if [[ -n "${conf:-}" && "${conf}" == "/etc/cni/net.d" && "${provider:-}" == k3s* ]]; then
         _warn "[argocd] ${name}: refusing generic CNI dirs for provider ${provider}"
         conf=""
         bin=""
      fi
```

Emitting nothing makes `envsubst` fall through to the caller's export — which for hostinger is
the correct k3s path, already exported at `k3s-hostinger.sh:830-831`. A wrong value that the code
can recognise must never be written.

---

## Tests

New file `scripts/tests/plugins/argocd_appset_cni_dir_precedence.bats`. Stub `_kubectl` to return
a canned ApplicationSet JSON and stub `_istio_ambient_target_provider` /
`_istio_ambient_cni_dirs`. 7 cases:

1. live holds `/etc/cni/net.d` and the provider resolves to `k3s` → output is the **k3s** dirs,
   not the live ones. This is the regression test; it must fail against the pre-fix source.
2. live holds `/etc/cni/net.d` and the provider resolves to `orbstack` → output is the
   orbstack-derived dirs
3. the provider cannot be resolved and live holds usable dirs → output is the **live** dirs
   (fallback still works)
4. neither source resolves → the function emits no `AMBIENT_CNI_*` line and returns 0
5. S3: provider is `k3s-hostinger` and the only available value is `/etc/cni/net.d` → no
   `AMBIENT_CNI_*` line is emitted, and the warning names the provider
6. the `APP_CLUSTER_NAME` override is still emitted from the live AppSet, unchanged
7. the function returns 0 when the live read returns non-JSON

Extend `scripts/tests/plugins/` wherever `_argocd_deploy_applicationsets` logging is already
covered with 1 case asserting the log says `resolved overrides` and no longer says
`keeping live`. Assert tokens, not whole lines.

---

## Mutations — prove each guard can fail

One at a time; restore and `git diff --quiet` between each.

- **M1** — move the live-read block back above the provider block (i.e. restore the original
  precedence). Expect: case 1 red, asserting the k3s dirs and getting `/etc/cni/net.d`.
- **M2** — delete the S3 refusal block. Expect: case 5 red because an `AMBIENT_CNI_CONF_DIR=`
  line is emitted.
- **M3** — delete the `[[ -n "${live}" ]]` guard on the fallback block. Expect: case 7 red, or a
  failure under `set -u`; if neither, the test is wrong — fix it.

---

## Docs

- `docs/guides/istio-ambient.md` (or the nearest existing ambient guide — do not create a second
  one) — a short section: the CNI dirs are derived from the target cluster's substrate, the live
  AppSet is only a fallback, and `ARGOCD_APPSET_IGNORE_LIVE=1` bypasses the live read entirely.
- `CHANGELOG.md` — `[Unreleased]` → `### Fixed`.
- `memory-bank/activeContext.md` and `memory-bank/progress.md` — status and the commit SHA.

---

## Operator runbook (NOT Codex)

Codex must not run any of this: it is a live mutation on the hub and the VPS.

1. Reapply with the live read bypassed, so the wrong value cannot be read back:
   ```
   ARGOCD_APPSET_IGNORE_LIVE=1 ./scripts/k3d-manager _hostinger_reapply_gitops_applicationsets
   ```
   (or `make refresh-edge` — **not** `make refresh CLUSTER_PROVIDER=k3s-hostinger`, which is
   forbidden.)
2. Confirm the live AppSet now holds the k3s dirs, reading the value back — an ArgoCD selfHeal
   can revert an out-of-band write, so do not trust the apply's exit code.
3. Let the `istio-ambient` Application sync and the DaemonSet roll. **Do not delete the pod as
   the fix** — a new pod with the same hostPaths comes back 503 identically, which is what
   happened on 2026-09-06.
4. Confirm `istio-cni-node` reaches `1/1` and that the conflist now exists in
   `/var/lib/rancher/k3s/agent/etc/cni/net.d`.

### Read-only precondition — run BEFORE step 3

The frozen agent log is not evidence of a dataplane outage and must not be treated as one. The
485-line log shows istio-cni programming iptables and sending pod-add events to ztunnel for 11
days *while unready*, ending 2026-09-17 after enrolling `product-catalog-seed-nkdlx`. Ambient
enrollment goes through the informer→ztunnel socket, independent of the chained-plugin install,
so a log that stops on 2026-09-17 most likely means "no new ambient pods since then".

Before rolling anything, confirm that read-only:

- ztunnel is `1/1` and istiod is `1/1` (both were, at 34d and 30d).
- For a pod in `shopping-cart-apps` created after 2026-09-17, confirm it is enrolled in the mesh
  (ztunnel's workload list, or `istioctl ztunnel-config workload`).

If post-2026-09-17 pods are **not** enrolled, this is an active outage and the rollout is urgent.
If they are, the cost is narrower: a startup race window before enrollment, and a readiness
signal that can never go green — so a genuine future CNI failure is indistinguishable from
today's steady state.

---

## Definition of Done

- [ ] S1 precedence inverted; `APP_CLUSTER_NAME` handling untouched; function still returns 0
- [ ] S2 log wording no longer claims a provenance it does not know
- [ ] S3 refusal guard in place
- [ ] 7 + 1 BATS cases green
- [ ] M1, M2, M3 each proven red, then restored
- [ ] `shellcheck -x scripts/plugins/argocd.sh` — zero new warnings vs `HEAD~`; paste both counts
- [ ] `make test` green; bare `pytest` green
- [ ] `make check-doc-links` green
- [ ] Docs written; memory-bank updated with the commit SHA

Commit message (verbatim):

```
fix(argocd): derive istio-cni dirs from the target substrate, not the live AppSet

_argocd_appset_live_overrides read the live ApplicationSet's cniConfDir and
cniBinDir and only fell back to the provider-derived dirs when that read came
back empty, and the values are applied via env, which outranks the caller's
export. Once the AppSet held the generic /etc/cni/net.d defaults every reapply
read them back and wrote them again, so three correct fixes never reached
ubuntu-hostinger and istio-cni-node stayed 0/1 for 17 days. Prefers the
substrate-derived dirs, keeps the live value as a fallback, and refuses to write
generic CNI dirs to a k3s target.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

---

## What NOT to Do

- Do NOT create a pull request, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT touch the live cluster: no `kubectl`, no `helm`, no `docker`, no `make up`, no `make
  refresh`, no `make refresh-edge`, no reapply. Code, tests and docs only.
- Do NOT revert `ce4d83f0`, `9c0e336a`, or the vars.sh defaults. All three are correct.
- Do NOT change the `APP_CLUSTER_NAME` override's live-first behaviour — it is correct there.
- Do NOT remove the live read, and do NOT change the `ARGOCD_APPSET_IGNORE_LIVE` gate.
- Do NOT edit `scripts/etc/argocd/applicationsets/istio-ambient.yaml` or
  `scripts/etc/argocd/vars.sh` — the template and the generic defaults both stay as they are.
- Do NOT modify `_hostinger_reapply_gitops_applicationsets`. Its exports become reachable once
  precedence is fixed; it does not need editing.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` — subtrees, fixed upstream.
- Do NOT delete any file outside the target list. If a scope check flags an unrelated file,
  report it and leave it alone.

---

## Cross-references

- `docs/bugs/2026-07-17-ambient-istio-cni-conf-bin-dir-mismatch.md`
- `docs/bugs/2026-07-21-istio-ambient-cni-dirs-not-substrate-aware.md`
- `docs/bugs/2026-07-21-ambient-cni-vars-missing-from-argocd-vars.md`
- `docs/bugs/2026-07-18-appset-envsubst-empty-var-substitution.md`
- `docs/bugs/2026-09-23-hostinger-alertmanager-discards-every-alert.md` — why 17 days passed with
  nobody told
- `memory/reference_argocd_selfheal_reverts_out_of_band_patch.md`
