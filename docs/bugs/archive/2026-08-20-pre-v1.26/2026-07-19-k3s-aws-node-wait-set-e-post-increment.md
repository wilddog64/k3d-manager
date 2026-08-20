# Bugfix: v1.16.0 — `set -e` kills k3s-aws node-ready wait on first iteration (`(( var++ ))` post-increment from 0)

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/lib/providers/k3s-aws.sh`
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this fixes the OPEN
  blocker where `make up CLUSTER_PROVIDER=k3s-aws` aborts at "Waiting for all 3 nodes to be Ready".
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/lib/providers/k3s-aws.sh` — the two `until` wait loops:
    - `_provider_k3s_aws_wait_ssm_registered` (SSM registration wait, line ~86)
    - `_provider_k3s_aws_deploy_cluster` (node-ready wait, line ~198)
- Implement exactly what is written — no interpretation, no scope expansion. **Minimal patch only.**

---

## Problem

A fresh `make up CLUSTER_PROVIDER=k3s-aws` provisions the 3-node k3s cluster and Cilium
successfully, then aborts at Step 2 immediately after logging:

```
INFO: [k3s-aws] Waiting for all 3 nodes to be Ready...
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

**Root cause:** `bin/cluster-up` runs under `set -euo pipefail` (line 18), and it calls
`deploy_cluster` (→ `_provider_k3s_aws_deploy_cluster`) as a sourced function in the same shell,
so `set -e` is in effect inside the provider. The node-ready wait loop is:

```bash
  local node_attempts=0
  until [[ "$(... | grep -c " Ready")" -ge "${total_nodes}" ]]; do
    (( node_attempts++ ))          # ← BUG
    ...
```

`(( node_attempts++ ))` uses **post-increment**: on the first loop iteration `node_attempts`
is `0`, so the arithmetic expression *evaluates to 0*, and `(( expr ))` returns **exit status 1**
whenever the expression evaluates to 0. Under `set -e` that non-zero status terminates the script
on the very first iteration — but only if the loop body is entered, i.e. only if the first
node-ready check sees fewer than 3 Ready nodes.

**Why it surfaced now (Cilium path):** with default flannel, freshly-joined agents became Ready
almost immediately, so the first check usually already saw 3/3 Ready → the `until` condition was
true on entry → the loop body never ran → the bug stayed dormant. With Cilium (installed on the
ambient path via `K3S_AMBIENT_MESH=true`), freshly-joined agents take longer to become Ready
(Cilium DaemonSet must initialize on each new agent), so the first check sees <3 Ready → the loop
body runs → `(( node_attempts++ ))` at `node_attempts=0` → `set -e` death.

The identical defect exists in `_provider_k3s_aws_wait_ssm_registered` (line ~86,
`(( attempts++ ))` with `attempts=0`), which will bite the SSM path the same way.

**Reproduction of the gotcha (verified):**
```
$ bash -c 'set -euo pipefail; n=0; (( n++ )); echo after' ; echo "exit=$?"
exit=1          # never prints "after"
$ bash -c 'set -euo pipefail; n=0; n=$(( n + 1 )); echo after' ; echo "exit=$?"
after
exit=0
```

---

## Fix

Replace the two unguarded post-increment `(( var++ ))` statements with an assignment form,
`var=$(( var + 1 ))`, which always exits 0 and is semantically identical (the loop's subsequent
`>=` threshold check sees the incremented value in both forms).

### Change 1 — `_provider_k3s_aws_wait_ssm_registered` (line ~86)

**Exact old block:**

```bash
    (( attempts++ ))
```

**Exact new block:**

```bash
    attempts=$(( attempts + 1 ))
```

### Change 2 — `_provider_k3s_aws_deploy_cluster` node-ready wait (line ~198)

**Exact old block:**

```bash
    (( node_attempts++ ))
```

**Exact new block:**

```bash
    node_attempts=$(( node_attempts + 1 ))
```

Do NOT touch any other line, any other function, `bin/cluster-up`, `shopping_cart.sh`,
`k3s-oci.sh`, any appset YAML, or `vars.sh`. (Other `(( x++ ))` sites in `k3s-oci.sh` and
`shopping_cart.sh` are out of scope for this fix — they are a separate provider / a path this
rebuild proved works; do not touch them here.)

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-aws.sh` | Replace two `set -e`-unsafe `(( var++ ))` post-increments (SSM-register wait + node-ready wait) with `var=$(( var + 1 ))` so the wait loops survive `set -e` on the first iteration |

---

## Rules

- **Disappearance gate:** `grep -cE '\(\( (node_)?attempts\+\+ \)\)' scripts/lib/providers/k3s-aws.sh` → **`0`** (was `2`)
- **Appearance gates:**
  - `grep -c 'attempts=$(( attempts + 1 ))' scripts/lib/providers/k3s-aws.sh` → **`1`**
  - `grep -c 'node_attempts=$(( node_attempts + 1 ))' scripts/lib/providers/k3s-aws.sh` → **`1`**
- `shellcheck -S warning scripts/lib/providers/k3s-aws.sh` — **0 warnings** (baseline on
  `origin/k3d-manager-v1.16.0` is 0; must stay 0 — record baseline + after).
- `bats scripts/tests/lib/k3s_aws_provider.bats` — all tests pass (capture the `N tests, 0 failures`
  line). Do NOT add or modify tests.
- `./scripts/k3d-manager _agent_audit` — exit 0
- `git show --stat` shows exactly ONE file changed
- No other files touched

---

## Definition of Done

- [ ] Both `(( attempts++ ))` (line ~86) and `(( node_attempts++ ))` (line ~198) replaced with the
      `var=$(( var + 1 ))` assignment form
- [ ] `grep -cE '\(\( (node_)?attempts\+\+ \)\)' scripts/lib/providers/k3s-aws.sh` → `0` (record output)
- [ ] `grep -c 'attempts=$(( attempts + 1 ))'` → `1` and `grep -c 'node_attempts=$(( node_attempts + 1 ))'` → `1` (record output)
- [ ] `shellcheck -S warning scripts/lib/providers/k3s-aws.sh` — 0 warnings (record baseline + after)
- [ ] `bats scripts/tests/lib/k3s_aws_provider.bats` — 0 failures (record the summary line)
- [ ] `_agent_audit` exit 0
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status (separate commit)

**Commit message (exact):**
```
fix(k3s-aws): make node-ready + SSM-register wait loops set -e safe (assignment not (( var++ )))
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Claude has already re-run `make up` against the currently-Ready cluster to complete the ambient
e2e verify (the bug is dormant when nodes are already Ready). The purpose of this fix is the NEXT
cold rebuild: a fresh `make down` / `make up CLUSTER_PROVIDER=k3s-aws` on the Cilium path must pass
the "Waiting for all 3 nodes to be Ready" gate without aborting, even while agents are still
finishing Cilium rollout.

---

## What NOT to Do

- Do NOT change `bin/cluster-up`, `shopping_cart.sh`, `k3s-oci.sh`, any appset YAML, or `vars.sh`.
- Do NOT touch other `(( x++ ))` sites outside `k3s-aws.sh` — they are out of scope.
- Do NOT change loop timeouts, thresholds, or `sleep` values — only the increment statement.
- Do NOT add or edit BATS tests.
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the one listed target.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
