# Copilot PR #107 review findings — v1.17.0 real login verification

**PR:** [#107](https://github.com/wilddog64/k3d-manager/pull/107) — `feat: v1.17.0 real login verification in health smoke`
**Branch:** `k3d-manager-v1.17.0`
**Date:** 2026-07-24

---

## Finding 1 — `base64 -d` decode flag portability

**Flagged:** `scripts/plugins/keycloak.sh:377` (also cited line 504)

**Copilot said:**

> The new smoke-seed helpers decode Kubernetes Secret fields using `base64 -d`, which is GNU-only.
> For macOS/BSD portability (already handled elsewhere via a dual-flag fallback), switch these
> decodes to `base64 --decode || base64 -D` so `keycloak_seed_smoke_user` works on non-GNU systems too.

### Verification before fixing

The finding was directionally right (decode-flag portability is a real concern) but the stated
premise and the suggested remedy were both wrong. Measured on this machine:

| Implementation | `-d` | `-D` | `--decode` |
|---|---|---|---|
| stock macOS `/usr/bin/base64` | ✅ rc=0 | ✅ rc=0 | ✅ rc=0 |
| GNU coreutils 9.11 | ✅ rc=0 | ❌ `invalid option -- 'D'` | ✅ rc=0 |

Two corrections:

1. **`-d` is not GNU-only.** Current macOS `/usr/bin/base64` accepts `-d`. (It was BSD-only-`-D` on
   much older macOS, which is where the belief comes from.)
2. **The suggested `--decode || -D` fallback is worse than the status quo on Linux.** `-D` is an
   invalid option under GNU coreutils, so the fallback arm can only ever fail there. It is also
   unsound inside a pipeline: `cmd | base64 --decode || base64 -D` re-runs the fallback with no
   stdin of its own, so it decodes nothing (or partial input if the first arm consumed some).

`--decode` is accepted by **both** implementations, so a single portable form is correct and no
fallback is needed.

### Scope note

`base64 -d` was **not** introduced by this PR alone — 4 of the 7 sites in `keycloak.sh` predate the
branch on `main` (lines 118, 254, 255, 333); the PR added 3 more (376, 377, 505) consistent with the
file's existing convention. Owner elected to normalize all 7 rather than leave the file with a mixed
convention.

### Fix applied — `3be18f1d`

```bash
# before (×7)
| base64 -d
| base64 -d 2>/dev/null || true

# after (×7)
| base64 --decode
| base64 --decode 2>/dev/null || true
```

Gates: `shellcheck -S warning` rc=0 · `bash -n` rc=0 · `_agent_audit` rc=0 · disappearance gate
`base64 -d` → 0, appearance `base64 --decode` → 7. Live re-verified the decode still works against
the real Secret (`kubectl -n identity get secret k3dm-smoke-user -o jsonpath='{.data.username}' |
base64 --decode` → `k3dm-smoke`).

### Root cause

The new smoke helpers copied the decode idiom from the surrounding functions in the same file, which
already used `base64 -d`. The idiom was never portability-reviewed when originally introduced.

### Process note

`scripts/lib/identity_tools.sh:36` already has the portable decode (`base64 --decode` first, `-D`
only as a secondary arm — and it re-pipes from a variable, so its fallback is actually sound).
Plugins that decode Secret fields inline should prefer a shared helper over hand-rolling the
pipeline. Worth a follow-up to route the remaining inline decoders through one function.

---

## Non-Copilot: GitGuardian check failure (merge-blocking)

The `GitGuardian Security Checks` check reported **3 secrets uncovered** and blocked merge, while a
local `ggshield secret scan commit-range origin/main..HEAD` reported **0 secrets detected**
(5 ignored). The divergence is that `.gitguardian.yaml` `ignored_matches` suppress findings for the
*local* CLI only — the server-side incidents stay OPEN until resolved on the dashboard.

All were previously vetted false positives already documented in the committed `.gitguardian.yaml`:

| Incident | File | What the detector matched |
|---|---|---|
| 35143325 | `bin/k3dm-webhook` | `K3DM_SMOKE_*` env-var **name** in an `os.environ.get` read |
| 35142552 | `bin/k3dm-webhook` | smoke-test env-var **name**, not a value |
| 35142551 | `bin/k3dm-webhook` | Grafana k8s Secret **name** in a jsonpath |
| 35144224 | `scripts/plugins/keycloak.sh` | `mktemp` temp-file **path** (`$wd/pword`), resolved earlier |

Resolved via `POST /v1/incidents/secrets/<id>/ignore` with `{"ignore_reason":"false_positive"}`
(HTTP 200 each); all four verified `status=IGNORED`.

### Process note

Adding a SHA to `.gitguardian.yaml` silences the pre-commit hook but does **not** clear the PR check.
Both steps are required: commit the ignore entry *and* resolve the incident via the API/dashboard.
