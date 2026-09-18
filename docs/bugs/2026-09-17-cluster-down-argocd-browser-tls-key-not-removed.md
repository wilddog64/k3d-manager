# Bug — `cluster-down` never removes the ArgoCD browser TLS private key (path divergence)

**Date:** 2026-09-17
**Branch:** `k3d-manager-v1.35.0`
**Severity:** High (TLS private key survives teardown; `bin/cluster-down` deletes a path nothing writes)
**Found by:** `make test-bin` — `cluster_down.bats` test 15, dark until
`docs/bugs/2026-09-17-orphaned-test-suites-no-makefile-entrypoint.md` gave it an entrypoint.

---

## Problem

`bin/cluster-down` removes the ArgoCD browser HTTPS TLS material from a **provider-scoped**
directory. `bin/cluster-up` writes it to a **flat** directory. They have never agreed, so
`cluster-down` deletes nothing and the private key is left on disk after teardown.

The divergence comes from *who sources `scripts/plugins/argocd.sh`*:

| Script | sources `plugins/argocd.sh`? | `ARGOCD_BROWSER_TLS_DIR` resolves to |
|---|---|---|
| `bin/cluster-up:52` | ✅ yes | **flat** — `${HOME}/.local/share/k3d-manager/argocd-browser-https-tls` |
| `bin/cluster-refresh:31` | ✅ yes | **flat** — same |
| `bin/cluster-down` | ❌ **no** | **scoped** — `${_ACG_STATE_DIR}/argocd-browser-https-tls` |

`scripts/plugins/argocd.sh:61` sets the flat default:

```bash
: "${ARGOCD_BROWSER_TLS_DIR:=${HOME}/.local/share/k3d-manager/argocd-browser-https-tls}"
```

Because `cluster-up` sources that plugin at line 52 — *before* it computes the dir at
line 571 — the variable is already set, so `cluster-up`'s own scoped fallback never fires:

```bash
_argocd_browser_tls_dir="${ARGOCD_BROWSER_TLS_DIR:-${_ACG_STATE_DIR}/argocd-browser-https-tls}"
```

`cluster-down` sources only `system.sh`, `core.sh` and `provider.sh`, so for it the same
line *does* fire, and `_ACG_STATE_DIR` is provider-scoped
(`scripts/lib/provider.sh:177-183` → `${HOME}/.local/share/k3d-manager/<provider>`).

Net effect of `bin/cluster-down:231`:

```bash
_run_command --prefer-sudo --soft -- rm -f "${_argocd_browser_tls_cert}" … || true
```

It targets `…/k3d-manager/k3s-aws/argocd-browser-https-tls/` — a directory no writer has
ever populated. The `--soft`/`|| true` guards mean the no-op is completely silent.

### Impact

`fullchain.crt`, `tls.key`, `ca.crt` and `tls.crt` persist after `bin/cluster-down --confirm`.
`tls.key` is a **Vault-PKI-issued private key**. Teardown is the point at which it is supposed
to stop existing. Confirmed on the operator's own machine: real material is still present at
the flat path, mtime 2026-09-04, across every teardown since.

### The test was right

`scripts/tests/bin/cluster_down.bats:256-272` asserts removal of the **flat** path — which is
the path `cluster-up` actually writes. **The test is correct and `bin/cluster-down` is the
defect.** An earlier read of this session called the test stale because it predated
per-provider state scoping; that was wrong. The test asserts the writer's real path, it was
simply dark (no Makefile entrypoint, not in CI), so nobody saw `cluster-down` regress when
scoping was introduced.

Do **not** "fix" the test.

---

## Fix — remove the legacy flat path too

Minimal and strictly additive: `cluster-down` keeps removing the scoped path (correct once
writers migrate) **and also** removes the flat path (correct today, and cleans up the material
already leaked on operator machines).

In `bin/cluster-down`, immediately after the existing TLS removal at line 231, add:

```bash
  _argocd_browser_tls_dir_legacy="${HOME}/.local/share/k3d-manager/argocd-browser-https-tls"
  if [[ "${_argocd_browser_tls_dir_legacy}" != "${_argocd_browser_tls_dir}" ]]; then
    _run_command --prefer-sudo --soft -- rm -f \
      "${_argocd_browser_tls_dir_legacy}/fullchain.crt" \
      "${_argocd_browser_tls_dir_legacy}/tls.key" \
      "${_argocd_browser_tls_dir_legacy}/ca.crt" \
      "${_argocd_browser_tls_dir_legacy}/tls.crt" >/dev/null 2>&1 || true
  fi
```

### Requirements

- **Named files only — no wildcard, no `rm -rf` on the directory.** Mirror the existing line's
  four explicit filenames. The state dir is shared with other subsystems.
- The `!=` guard keeps this a genuine no-op when the two paths coincide (e.g. a caller that
  exported the flat path as `ARGOCD_BROWSER_TLS_DIR`), so nothing is removed twice.
- Do not change `_argocd_browser_tls_dir` itself, and do not make `cluster-down` source
  `plugins/argocd.sh`. Sourcing a lazy-loaded plugin into a teardown script to import one
  default pulls in its whole side-effect surface.
- Do not touch `scripts/plugins/argocd.sh:61`. Repointing the **writer** to the scoped path is
  the real long-term unification, but it orphans the certs already on operator machines and
  forces a re-issue — that is a separate, live-affecting change. See Follow-up.

---

## Verification

```bash
make test-bin
```

Test 15 (`acg-down removes the ArgoCD browser HTTPS listener`) must pass, and the suite must
report **108 of 108** (`1..108`). Paste the full verbatim output.

`cluster_down.bats` sets `export HOME="${BATS_TEST_TMPDIR}/home"` at line 58, so the suite is
hermetic — it cannot touch the operator's real state dir. Verified.

---

## Follow-up (NOT this commit)

Unify on one canonical location: repoint `scripts/plugins/argocd.sh:61` (and
`scripts/lib/providers/k3s-hostinger.sh:378-379`, which also hardcodes the flat path) at the
provider-scoped dir, with a one-time migration for existing material. Needs its own spec
because it changes where a live listener reads its cert from.

---

## Definition of Done

- [ ] `bin/cluster-down` patched exactly as specified.
- [ ] `make test-bin` → 109/109, output pasted verbatim.
- [ ] `shellcheck -S error bin/cluster-down` clean.
- [ ] CHANGELOG `[Unreleased]` → `### Fixed` entry naming the leaked private key and the
      path divergence as the cause.
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated.

## What NOT to Do

- Do NOT edit, skip or delete `cluster_down.bats` test 15. It is the correct assertion.
- Do NOT create a PR, merge, commit to `main`, or force-push.
- Do NOT use `--no-verify`.
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/`.
- Do NOT use a wildcard or `rm -rf` for the removal.
- Do NOT modify `scripts/plugins/argocd.sh` or `scripts/lib/providers/k3s-hostinger.sh`.
