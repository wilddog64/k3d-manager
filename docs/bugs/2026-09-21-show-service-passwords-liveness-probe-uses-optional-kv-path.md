# Bug: `make show-service-passwords` hard-fails because its Vault liveness probe reads an optional KV path

**Filed:** 2026-09-21
**Branch:** `k3d-manager-v1.36.0`
**Status:** OPEN
**Target:** `Makefile` (`show-service-passwords`, line 496)

---

## Problem

```
make show-service-passwords
[show-service-passwords] Vault credential lookup unavailable; restarting its port-forward
[show-service-passwords] ERROR: Vault credential lookup still unavailable (check Vault token and port-forward)
make: *** [show-service-passwords] Error 1
```

**Every layer the error names is healthy.** Verified on hub `k3d-k3d-cluster` 2026-09-21:

| Check | Result |
|---|---|
| `:18200` listening | yes — `kubectl port-forward vault-0 18200:8200 -n secrets --context k3d-k3d-cluster` |
| `GET /v1/sys/health` | HTTP 200, `sealed: false`, raft, v1.20.1 |
| `vault-0` pod | `Running`, **0 restarts**, 24h uptime |
| `secrets/vault-root` | present and readable |
| ArgoCD pods | 7/7 `Running` |
| `cicd/argocd-initial-admin-secret` | present |

Direct probe of `127.0.0.1:18200`, 2026-09-21 (status codes only; no token printed):

| Endpoint | with `secrets/vault-root` token | anonymous |
|---|---|---|
| `sys/health` | 200 | — |
| `auth/token/lookup-self` | **200** | **403** |
| `secret/data/argocd/admin` | **404** ← what the gate probes | — |
| `secret/data/observability/grafana` | **200** | — |

Vault is reachable, the token is valid, and Grafana's credential is present and readable. The
only 404 is the one path the gate happens to probe.

The gate at `Makefile:500` decides whether **Vault itself** is reachable by probing one
specific KV entry:

```make
if ! curl -sf -H "@$$_vault_hdr" "http://127.0.0.1:18200/v1/secret/data/argocd/admin" -o /dev/null 2>/dev/null; then
```

`secret/argocd/admin` is a **best-effort display mirror**, not a Vault health signal. Its only
producer is `_hub_recovery_mirror_argocd_admin` (`scripts/plugins/hub_recovery.sh:118-140`),
added by `docs/bugs/2026-09-13-hub-restore-argocd-admin-vault-mirror-missing.md`. That function
`return 0`s (success) on **every** failure branch:

- `argocd-initial-admin-secret` unavailable → `_warn` + `return 0` (line 126-129)
- ArgoCD rejects the password (HTTP ≠ 200) → `_warn` + `return 0`

So a reconcile can complete successfully with the path absent — by design. When it is absent,
`curl -sf` returns non-zero (HTTP 404), and the Makefile concludes Vault is down, restarts a
healthy port-forward, retries the same doomed 404 ten times, and exits 1.

**Consequence:** a cosmetic gap in one optional display value blocks *all four* credentials —
ArgoCD, Grafana, Prometheus and Alertmanager — even though each of those blocks already
degrades to `N/A` independently and would print fine.

### Contributing: bootstrap race in the mirror

On the 2026-09-21 hub bring-up, `vault-0` started at 23:46:10Z and
`cicd/argocd-initial-admin-secret` was created at 23:51:56Z — a ~6 minute window in which
`_hub_recovery_mirror_argocd_admin` takes the `return 0` branch at line 126-129 and never
retries. A reconcile landing in that window leaves the path permanently absent until the next
manual run.

---

## Fix

Three parts, in priority order. **M1 alone resolves the reported failure.**

### M1 — probe Vault, not a KV entry (`Makefile`, the `show-service-passwords` gate)

Replace **both** occurrences of the probe URL inside the gate block (the initial `if !` at
line 500 and the retry inside the `for` loop at line 505) with a token-scoped Vault endpoint
that has no dependency on any KV path:

Old (both places):
```
"http://127.0.0.1:18200/v1/secret/data/argocd/admin"
```

New (both places):
```
"http://127.0.0.1:18200/v1/auth/token/lookup-self"
```

`auth/token/lookup-self` is the correct probe for this gate's actual question: it returns 200
only when the port-forward is up **and** the root token is valid, which is exactly the pair the
error message already blames. It returns 403 on a bad token and connection-refused when the
port-forward is down — both real failures worth restarting for.

Do **not** substitute `/v1/sys/health` here: it is unauthenticated, so it would pass with an
invalid token and the credential blocks below would then all silently print `N/A` with no
diagnostic.

Then split the error message so the two causes are distinguishable:

Old:
```
[ "$$__vault_ready" -eq 1 ] || { echo "[show-service-passwords] ERROR: Vault credential lookup still unavailable (check Vault token and port-forward)" >&2; exit 1; }; \
```

New:
```
[ "$$__vault_ready" -eq 1 ] || { echo "[show-service-passwords] ERROR: Vault unreachable at 127.0.0.1:18200 with the secrets/vault-root token (port-forward restarted, still failing)" >&2; exit 1; }; \
```

Leave the four credential blocks (ArgoCD, Grafana, Prometheus, Alertmanager) **unchanged** —
they already degrade to `N/A` per-service via `|| true` and the `$${_x:-N/A}` default. M1 is the
change that lets them do so.

### M2 — close the mirror bootstrap race (`scripts/plugins/hub_recovery.sh`)

In `_hub_recovery_mirror_argocd_admin`, the `argocd-initial-admin-secret` read at line 126 is a
single attempt against a secret ArgoCD may not have created yet. Wrap it in a bounded retry
(10 attempts, 6s apart = 60s) before falling through to the existing `_warn` + `return 0`:

```bash
  local __attempt
  for __attempt in $(seq 1 10); do
    password=$(_kubectl -- --context "$hub_context" -n cicd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || true)
    [[ -n "$password" ]] && break
    sleep 6
  done
```

Keep the existing `return 0` on exhaustion — a missing mirror must stay non-fatal to reconcile.
Gate the sleep behind `${HUB_RECOVERY_MIRROR_RETRY_DELAY:-6}` so BATS can set it to `0`.

### M3 — note the path is optional (`docs/guides/`)

Add one line to the `show-service-passwords` triage entry stating that `secret/argocd/admin` is
an optional display mirror and its absence is **not** a Vault fault. Update the memory-bank
reference behaviour accordingly.

---

## Tests

### `scripts/tests/bin/makefile_show_service_passwords.bats` (new)

Follow the static-source idiom in `scripts/tests/bin/makefile_platform_ops.bats`
(`awk '/^show-service-passwords:/,/^$$/' "${MAKEFILE}"`). Assert on meaningful tokens, never a
whole source line.

1. **Disappearance gate** — the gate block contains **zero** occurrences of
   `secret/data/argocd/admin`. Extract only the gate (first recipe line through the closing
   `fi`), not the whole target: the ArgoCD credential block below legitimately still reads that
   path, and a target-wide assertion would be unfalsifiable.
2. The gate references `auth/token/lookup-self`, and it appears **twice** (initial probe +
   retry loop).
3. The failure message names `127.0.0.1:18200` and no longer says `check Vault token and
   port-forward`.
4. The four credential blocks still each contain `:-N/A}` — proving per-service degradation was
   not removed.

**Mutation check (mandatory, per `reference_new_test_passing_does_not_mean_it_can_fail`):** run
tests 1–3 against the **pre-fix** `Makefile` (`git stash` is forbidden while Codex runs — use
`git show HEAD:Makefile > /tmp/pre.mk` and point `MAKEFILE` at it) and paste the output showing
they **fail**. A test that cannot fail is not coverage.

### `scripts/tests/plugins/hub_recovery.bats` (M2 only)

Add to the existing `_hub_recovery_mirror_argocd_admin` tests, with
`HUB_RECOVERY_MIRROR_RETRY_DELAY=0`:

5. Secret empty on attempts 1–2, present on attempt 3, `curl` prints `200` → `kv put` called,
   rc 0, and the `_kubectl` call log shows 3 `get secret argocd-initial-admin-secret` calls.
6. Secret empty for all 10 attempts → no `curl`, no `kv put`, rc **0** (still non-fatal),
   `_warn` emitted once.

Assert the recorded call log never contains the stub password value.

---

## Definition of Done

- [ ] M1 implemented; only `Makefile` changed for it
- [ ] M2 implemented; only `scripts/plugins/hub_recovery.sh` changed for it
- [ ] M3 doc line added
- [ ] `shellcheck -x scripts/plugins/hub_recovery.sh` — rc 0
- [ ] `bats scripts/tests/bin/makefile_show_service_passwords.bats scripts/tests/plugins/hub_recovery.bats` green — paste the summary
- [ ] Mutation check output pasted, showing tests 1–3 red against the pre-fix `Makefile`
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "`make show-service-passwords` probes Vault via `auth/token/lookup-self` instead of the optional `secret/argocd/admin` display mirror, so a missing mirror no longer blocks all four credentials"
- [ ] Commit message verbatim: `fix(makefile): probe Vault liveness with lookup-self, not the optional argocd mirror`
- [ ] Pushed to `origin/k3d-manager-v1.36.0`; report the SHA and confirm with `git rev-parse origin/k3d-manager-v1.36.0`

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`
- Do NOT run anything against a live cluster, Vault, ArgoCD or the port-forward — this is a
  source-only change with static-source tests
- Do NOT read, print or echo the Vault root token, or place it in argv (the existing
  `-H "@$$_vault_hdr"` header-file idiom is correct — keep it)
- Do NOT make a missing `secret/argocd/admin` fatal anywhere, and do NOT call
  `_argocd_seed_vault_admin_secret` or generate a new password
- Do NOT restructure, reformat or "clean up" the four credential blocks — M1 touches the gate
  only
- Do NOT modify `scripts/lib/foundation/`, `scripts/lib/acg/`, or any file outside the targets
- Do NOT `git add -A` and do NOT `git stash`
