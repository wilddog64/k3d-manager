# Bug: the webhook smoke gate calls the unbounded full sweep behind a 90s cap, and masks the real error as HTTP `000000`

**Filed:** 2026-09-25
**Target branch:** `k3d-manager-v1.38.0` (held — v1.37.0 is awaiting merge)
**Files:** `bin/smoke-test-webhook`, `scripts/lib/webhook/smoke.py`, `scripts/tests/bin/` (new BATS), `CHANGELOG.md`
**Pre-existing:** `bin/smoke-test-webhook` is untouched since v1.16.0 (`4c5d3556`). Not a v1.37.0 regression — the identical call exists on `origin/main`.

---

## Problem

`make smoke` fails at the webhook gate. Three separate defects compound.

### D1 — the gate asks for the full sweep but only waits 90s

`bin/smoke-test-webhook:80-87`:

```bash
health_path="/api/v1/health"
http_code="$(curl -s -o "${HEALTH_JSON}" -w '%{http_code}' \
  -H "Authorization: Bearer ${TOKEN}" \
  --max-time 90 "${URL}${health_path}" 2>/dev/null || echo "000")"
```

The script's own header says its purpose is to prove the module split works **without needing a
cluster**. But bare `/api/v1/health` runs `_smoke_test_services()` with no bounds. Its cost model in
`scripts/lib/webhook/smoke.py`:

| constant | value |
|---|---|
| `_SMOKE_RETRIES` | 3 |
| `_SMOKE_RETRY_SLEEP` | 10 |
| per-request timeout | 8s |

Endpoints run in a `ThreadPoolExecutor`, but products, Vault, ESO, Kubernetes and the browser logins
run **serially** afterwards. `smoke.py`'s own comment concedes the point:

> The full sweep below also checks Vault, ESO, Kubernetes, and browser logins and can legitimately
> take longer than a CLI status probe should wait.

Three retries × 10s sleep × several serial stages exceeds 90s whenever any stage is unreachable.
Reproduced: `curl: (28) Operation timed out after 30008 milliseconds with 0 bytes received`, with an
**empty server log** — the handler was blocking, not crashing.

The bounded variant proves the split itself is sound:

```
GET /api/v1/health?quick=1   ->  HTTP 200 in 0.43s
```

All 10 `scripts/lib/webhook/*.py` modules import cleanly and the entrypoint compiles. So D1 is purely
the gate asking the wrong question.

### D2 — `000000` masks the real failure

`-w '%{http_code}'` already prints `000` when curl fails, and `|| echo "000"` appends another. The
gate reports `HTTP 000000`, which matches no real status and hides the curl exit code (28 = timeout)
that would have named the cause immediately.

### D3 — two probe targets are unreachable on this host by construction

Verified live on 2026-09-25:

| target | source | result |
|---|---|---|
| `http://localhost:19190/-/ready` | `smoke.py:525` app-cluster Prometheus | **unreachable** |
| `http://localhost:19200/-/ready` | hostinger offset | **unreachable** |
| `http://localhost:19090/-/ready` | hub | `401` (basic-auth) |
| `http://localhost:19091/-/ready` | hub | `200` |
| `http://keycloak.shopping-cart.local/realms/master` | `smoke.py:350` non-hostinger branch | **`000`** |
| `https://keycloak.3ai-talk.org/realms/master` | `smoke.py:350` hostinger branch | `200` |

- **Prometheus 19190/19200:** correct per the deliberate two-port scheme
  (`docs/bugs/2026-09-14-prometheus-port-19090-hub-acg-collision.md`) — hub keeps `19090`/`19091`,
  app clusters use `19190` + provider offset. But **no agent forwards the app-cluster port.** That
  doc's "Operator follow-up" item (`confirm lsof -iTCP:19190`) has never been satisfied, so this
  probe has failed since `31e69c56`. The port number is right; the forward is missing.
- **Keycloak non-hostinger:** `keycloak.shopping-cart.local` resolves to `127.0.0.1` via `/etc/hosts`,
  and **nothing listens on :80**. The hub has **no Ingress resources at all**; Keycloak is reachable
  only via `identity/keycloak` ClusterIP or `identity/keycloak-nodeport` (:30080, also not forwarded
  to the host). So the non-hostinger branch cannot pass from this host.

D3 is why the sweep blocks long enough to trip D1: each unreachable target burns
`3 × (8s timeout + 10s sleep)`.

## Fix

### S1 — the gate uses the bounded variant

`bin/smoke-test-webhook:80`. Old:

```bash
health_path="/api/v1/health"
```

New:

```bash
health_path="/api/v1/health?quick=1"
```

Line 82's provider branch must keep the parameter and append with `&`:

```bash
  health_path="/api/v1/health?quick=1&provider=${CLUSTER_PROVIDER}"
```

This matches the script's stated purpose. `--max-time 90` then has generous headroom over the
measured 0.43s. Do NOT raise `--max-time`.

### S2 — stop masking the curl failure

Replace the single command substitution with a form that keeps the exit code:

```bash
curl_rc=0
http_code="$(curl -s -o "${HEALTH_JSON}" -w '%{http_code}' \
  -H "Authorization: Bearer ${TOKEN}" \
  --max-time 90 "${URL}${health_path}" 2>/dev/null)" || curl_rc=$?
if [[ "${curl_rc}" -ne 0 ]]; then
  echo "[FAIL] GET ${health_path} — curl exit ${curl_rc} (28 = timeout)" >&2
  exit 1
fi
```

Keep the existing `!= "200"` check after it. The `|| echo "000"` must be gone.

### S3 — make the unreachable probes say what is missing

In `smoke.py`, when the app-cluster Prometheus or the non-hostinger Keycloak probe fails to connect
(as opposed to returning a non-2xx), the detail string must name the missing forward rather than just
the URL — e.g. `no listener on localhost:19190 (app-cluster Prometheus port-forward not running)`.
Do not change the port numbers, the hostinger branch, or the retry constants.

## Definition of Done

- [ ] S1–S3 applied; only the listed files change
- [ ] `grep -c 'echo "000"' bin/smoke-test-webhook` outputs `0`
- [ ] `grep -c 'quick=1' bin/smoke-test-webhook` outputs `2`
- [ ] `shellcheck -x bin/smoke-test-webhook`: rc 0
- [ ] `python3 -m py_compile scripts/lib/webhook/smoke.py bin/k3dm-webhook`: rc 0
- [ ] A new BATS case asserts the gate sends `quick=1` (stub `curl` on `PATH`, assert the call log)
      and that a curl exit 28 produces a message containing `curl exit 28`, not `000000`
- [ ] `bats scripts/tests/bin/` and `bats scripts/tests/lib/webhook.bats` green — paste the summaries
- [ ] CHANGELOG `[Unreleased]` → `### Fixed`: "the webhook smoke gate requests the bounded `?quick=1` health variant instead of the unbounded full sweep it could never complete inside its own 90s cap, and reports curl's exit code instead of a doubled `000000`"
- [ ] Commit message verbatim: `fix(smoke): webhook gate uses the bounded health variant and reports curl failures`

## What NOT to Do

- Do NOT raise `--max-time`, and do NOT lower `_SMOKE_RETRIES` or `_SMOKE_RETRY_SLEEP` — the sweep is
  legitimately slow; the gate was asking the wrong question
- Do NOT change the Prometheus port numbers; the two-port scheme is deliberate
- Do NOT add an Ingress or a port-forward as part of this fix (see the separate follow-up below)
- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/`
- Do NOT run anything against a live cluster

## Operator follow-up (NOT for an agent)

- Start the app-cluster Prometheus port-forward (`19190` for `k3s-aws`, `19200` for hostinger) and
  confirm with `lsof -iTCP:19190`. This closes the still-open item from
  `docs/bugs/2026-09-14-prometheus-port-19090-hub-acg-collision.md`.
- Decide whether the non-hostinger Keycloak smoke branch should target
  `identity/keycloak-nodeport` (:30080) via a host forward, or be skipped when no listener exists.
  Needs the owner's call — it changes what the gate certifies.
- `make restart-webhook` — the running webhook still executes pre-decomposition code (PID started
  08:52:55; every decomposed module was written 09:57-19:20), so none of this is exercised at runtime
  until it restarts.
