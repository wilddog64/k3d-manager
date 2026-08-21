# Fleet Phase B — live verification findings (v1.26.0)

**Date:** 2026-08-21
**Branch:** `k3d-manager-v1.26.0`
**Verified commit:** `b0fe320a` (Phase B impl) + `70940a01` (memory-bank)
**Run context:** live ACG sandbox `851725327555`, `ACG_AGENT_COUNT=4` (1 server + 4 agents = 5 nodes = ACG cap)

**STATUS 2026-08-21: BOTH FINDINGS FIXED + RE-VERIFIED LIVE.** Finding 1 fixed in
`scripts/plugins/shopping_cart.sh`; Finding 2 fixed in `Makefile`. A fresh live
Rung-3 `fleet-up` at `ACG_AGENT_COUNT=4` (same ACG sandbox `851725327555`)
now exits **`FLEET_UP_EXIT=0`** with `All agent nodes joined and Ready` — the
150s false-negative is gone. See the per-finding resolution blocks below.

Live Rungs 1–3 were run against a fresh ACG sandbox. **The count-agnostic
provisioning and parallel join work correctly** — the CFN stack deployed as
"1 server + 4 agents", all 4 agents joined via the parallel path, and
`kubectl get nodes` showed **all 5 nodes `Ready`**. Two defects surfaced that
Rung-0 offline gates (mocked BATS) could not catch.

---

## Finding 1 — `_k3s_agent_is_ready` false-negative readiness gate (BLOCKING)

**File:** `scripts/plugins/shopping_cart.sh` (`_k3s_agent_is_ready` ~L1034; helper
`_k3s_agent_address` ~L1023)

**Symptom:** `make fleet-up ACG_AGENT_COUNT=4` exits non-zero with:

```
ERROR: [shopping_cart] Agent ubuntu-1 did not become Ready after 150s
ERROR: [shopping_cart] Agent ubuntu-2 did not become Ready after 150s
ERROR: [shopping_cart] Agent ubuntu-3 did not become Ready after 150s
ERROR: [shopping_cart] Agent ubuntu-4 did not become Ready after 150s
make: *** [fleet-up] Error 1
```

…even though every node had already joined and gone `Ready`:

```
ip-10-0-1-168   Ready   control-plane,master  (server)
ip-10-0-1-104   Ready   <none>
ip-10-0-1-138   Ready   <none>
ip-10-0-1-17    Ready   <none>
ip-10-0-1-219   Ready   <none>
```

**Root cause:** the readiness matcher compares each `kubectl get nodes` line
against the SSH alias `agent_host` (`ubuntu-1`..`ubuntu-4`) or against
`agent_ip` from `_k3s_agent_address`, which reads the **HostName** from
`~/.ssh/config`:

```
ubuntu-1 -> 44.246.134.16   (PUBLIC IP)
ubuntu-2 -> 18.246.241.154
ubuntu-3 -> 35.88.145.95
ubuntu-4 -> 34.216.70.51
```

But k3s names each node by its **private-IP-derived hostname** (`ip-10-0-1-104`)
with InternalIP `10.0.1.104`. Neither the SSH alias nor the public IP ever
appears in the node line, so `[[ "${_node}" == *"${agent_host}"* || "${_node}"
== *"${agent_ip}"* ]]` (L1040) is **always false** → the 30×5s poll always
times out.

**Impact:**
- `fleet-up` / `deploy_cluster` false-fail on a fully successful join.
- The idempotent-skip in `_k3sup_join_agent_worker` (L1063) uses the same check,
  so "already Ready — skipping join" never fires; a re-run re-joins every agent.

**Fix direction:** match on the node's **private IP / InternalIP**, not the SSH
alias or public HostName. The private IP is what k3s registers as node name
(`ip-<priv-with-dashes>`) and InternalIP. Options: derive the private IP from
the k3sup join (it already targets the node), or query the node by InternalIP.
The substring match should also be tightened to avoid `ip-10-0-1-1` matching
`ip-10-0-1-17` / `-168` (N≥10 substring aliasing — pre-existing nit).

**RESOLVED (2026-08-21).** New `_k3s_agent_private_ip` resolves each agent's
primary private IPv4 over SSH (`ip -4 route get 1.1.1.1` → `src`), and
`_k3s_agent_is_ready` now does an **exact field match** on the InternalIP column
(field 6 of `kubectl get nodes -o wide`) plus `STATUS == Ready` — no substring
compare, so both the public-IP/alias false-negative and the N≥10 aliasing nit
are eliminated. `_k3sup_join_agent_worker` resolves the private IP before the
join for the idempotent pre-check and re-resolves after join if the pre-join SSH
was unreachable. Unit coverage: 2 new BATS tests
(`_k3s_agent_is_ready matches node InternalIP…`, `…false when the matched node
is NotReady`) plus a `_k3s_agent_private_ip` stub in the 3 worker-orchestration
tests — suite 17/17 green. **Live re-verify:** `fleet-up` count=4 →
`Agent ubuntu-{1..4} is Ready` / `All agent nodes joined and Ready` /
`FLEET_UP_EXIT=0`.

---

## Finding 2 — `fleet-plan` change-set invocation is invalid (Rung 2 unusable)

**File:** `Makefile` `fleet-plan:` target (~L83)

**Symptom:** `make fleet-plan ACG_AGENT_COUNT=4`:

```
aws: [ERROR]: Unknown options: --no-execute
make: *** [fleet-plan] Error 252
```

**Root cause (two issues):**
1. `aws cloudformation create-change-set` has **no `--no-execute` flag** —
   change-sets are never executed until a separate `execute-change-set`, so the
   flag is bogus and the command fails outright.
2. Even with the flag removed, `create-change-set` fails with
   `Parameters: [KeyName, AllowedCidr, AmiId] must have values` — these template
   parameters have no defaults and must be supplied via `--parameters`
   (the deploy path passes them; `fleet-plan` does not).

**Fix direction:** drop `--no-execute`; supply the same required
`--parameters` the deploy path uses (KeyName / AllowedCidr / AmiId, plus
`--capabilities CAPABILITY_NAMED_IAM`). Consider `--region "${ACG_REGION}"`
explicitly (works today only because default region == `us-west-2`).

**RESOLVED (2026-08-21).** `fleet-plan` rewritten to
`create-change-set --change-set-type CREATE` against a **throwaway** stack
`k3d-manager-cluster-plan` (never collides with the live `k3d-manager-cluster`),
supplying all four required params (KeyName / AllowedCidr / InstanceType / AmiId,
AMI resolved via `describe-images`) + `--capabilities CAPABILITY_NAMED_IAM` +
explicit `--region`. An `EXIT` trap deletes the plan stack and the rendered
temp file, so Rung 2 provisions **zero real resources** and leaves nothing
behind. A target-specific `fleet-plan: SHELL := /bin/bash` was added so sourcing
`acg.sh` (which transitively loads `agent_rigor.sh`'s process substitution) does
not break under Make's default `/bin/sh`. **Live re-verify:** `fleet-plan`
count=4 planned exactly 4 Agent instances + 1 Server + VPC/SG/routing, then the
trap deleted the plan stack (confirmed absent afterward).

---

## Non-blocking note — static template `Description`

`aws cloudformation validate-template` (Rung 1) **passed** for the count=4
render, but the template's `Description` field still literally reads
`"k3d-manager 3-node k3s cluster (1 server + 2 agents)"`. The awk verbatim-clone
emitter does not rewrite this cosmetic header. Harmless; worth a one-line fix so
the rendered description matches the agent count.

**CARRY-FORWARD (upstream-first).** The `_acg_render_template` awk emitter lives
in the **lib-foundation subtree** (`scripts/lib/foundation/scripts/lib/acg/acg.sh`)
— it must NOT be patched directly in k3d-manager. The one-line `Description`
rewrite belongs in the lib-foundation clone (edit → PR → tag → subtree-pull).
Tracked as upstream cosmetic debt; not fixed in this branch.

---

## What verification confirmed WORKS

- Rung 1 `fleet-validate ACG_AGENT_COUNT=4` — AWS accepted the count=4 render
  (IAM capability recognized, all params parsed).
- CFN deploy templated to "1 server + 4 agents" from `ACG_AGENT_COUNT` alone.
- Parallel agent join (B3) — all 4 agents joined concurrently and reached
  `Ready`; 5-node cluster healthy.
- Teardown: `make down CLUSTER_PROVIDER=k3s-aws CLEANUP_STALE=1` deleted the CFN
  stack (all 5 EC2 instances gone, stack absent) and left ArgoCD **identical to
  baseline** — zero new/Unknown Applications, no leftover cluster registration.
