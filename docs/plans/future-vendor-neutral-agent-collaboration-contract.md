# Future enhancement — Vendor-neutral agent collaboration and dispatch contract

**Status:** PROPOSED — roadmap candidate only; not scheduled, implemented, or dispatched
**Filed:** 2026-10-20, at operator request
**Priority:** Enhancement; schedule after dispatcher P1 is resolved and verified
**Release:** Unassigned (candidate for the multi-agent product-team roadmap; no version commitment)
**Branch:** `k3d-manager-v1.43.5` (proposal filed here; eventual implementation uses its own approved release branch and PR)
**Approval:** Operator approved filing a proposal/roadmap item, NOT implementation, merge, or deployment
**Component (proposed):** `bin/k3dm-agent-dispatch`, dispatcher adapter/contract modules (paths TBD), dispatch ledger and metrics, `docs/howto/codex-dispatch.md` (migration), dispatcher tests, optional MCP/A2A adapter (deferred)
**Depends on:** `docs/bugs/2026-10-20-codex-dispatch-background-process-lost-no-terminal-status.md` (P1: detached worker lifecycle and real caller-environment verification)
**Related:** `docs/plans/v1.43.0-worktree-isolated-codex-dispatch.md`; `docs/plans/v1.43.5-dispatch-api-cost.md`; `docs/plans/v1.48.0-human-effort-per-release.md`

## Problem

Today `k3dm-codex-dispatch` is Codex-specific. Claude Code, Antigravity with Claude, Gemini CLI, Codex CLI, Hermes and the operator can coordinate tasks, but there is no k3d-manager-wide contract for agent identity, task ownership, durable state transitions, independent acceptance, cost, or safe handoff across model vendors and process environments. Different agent sessions may report completion without independently verifiable commits or execution evidence.

The recent P1 demonstrates why process lifecycle correctness precedes interoperability. Agent-initiated background workers may disappear when the launching command returns; no higher-level protocol can repair an unreliable local worker supervisor.

This proposal is **not** just renaming a script. It restructures the dispatch engine to separate **caller/coordinator** from **worker/backend** and to make evidence, policy and state first-class. Existing Git workflows remain authoritative.

## Objectives

1. Any **authorized** coordinator (Claude, Codex, Gemini, Hermes, human or future agents) can submit a bounded task to any **supported** worker backend, including Codex → Codex, without vendor-specific authority assumptions.
2. Preserve one trusted dispatch lifecycle, isolated worktree, scoped files, immutable task/run identifiers, start/exit acknowledgments, ledger and operator-controlled landing.
3. Agent-written statements are untrusted claims until checked against real Git objects, runner records, test outputs and the required acceptance gates.
4. Support independent reviewers and session handoff without sharing vendor chat history. The shared source of truth is the Git repository plus structured run artifacts and append-only ledger.
5. Account for attempted, rejected, reverted and accepted work, including coordinator overhead and quota consumption where observable, without conflating token estimates with subscription spend.

## Design proposal

### D1. Stable task envelope and identities

Use a versioned, machine-readable envelope (JSON schema or similarly deterministic format; final schema to be approved). Example **illustrative fields, not a committed interface**:

```json
{
  "schema_version": 1,
  "task_id": "opaque-id",
  "spec_path": "docs/bugs/example.md",
  "release_ref": "k3d-manager-vX.Y.Z",
  "base_sha": "verified-full-git-sha",
  "caller": {"kind": "agent", "backend": "claude", "session_id": "optional"},
  "worker": {"backend": "codex", "model": "optional"},
  "permissions": {"network": false, "execution_target": "local-isolated"},
  "limits": {"max_runtime_seconds": 1800, "max_handoffs": 1},
  "acceptance": {"required_tests": ["scoped-offline-tests"], "require_live": false}
}
```

No trust comes from self-declared identity alone. Authenticate authorization at the dispatch boundary using the actual caller's existing credentials/capabilities. Never let a task envelope authorize its own privileges. The envelope records requested scope, not a security grant.

### D2. Dispatch engine and backend adapters

Introduce `bin/k3dm-agent-dispatch` with a common `check/start/status/resume/land/abandon` contract; exact CLI syntax subject to spec review. Adapters for Codex first, then Gemini and Claude, translate provider CLI/auth/sandbox/logging and usage APIs while inheriting shared rules. No assumptions that the coordinator is Claude or that the worker is always Codex.

Caller and worker have separate identities. Codex → Codex is permitted when independently authorized, bounded and non-recursive by default (configurable explicit depth limit); a worker may not silently grant itself dispatch, merge, secret access, or live infrastructure permissions.

A local trusted supervisor owns detached workers, lifecycle durability, timeout/cancel, process identity (PID + start identity), and diagnostic output independent of the agent command runner. **Reuse the fixed P1 launcher**; do not redesign its process isolation before that fix is accepted.

Preserve backward-compatible `k3dm-codex-dispatch` aliases and existing run directories/ledger/metrics until migration is explicitly verified. Never silently reinterpret old ledger records or invent attribution.

### D3. State machine and handoffs

Distinguish `submitted`, `accepted`, `starting`, `running`, `exited`, `evidence_collected`, `awaiting_review`, `verified`, `landed`, `failed`, `cancelled`, and `terminated_unexpectedly` where needed; exact names and allowed transitions must be tested.

`exited(0)` does **not** imply tested, verified, landed, deployed, or live-verified. Persist worker exit and timestamps before nonessential ledger/Git/metrics bookkeeping. Reconcile missing/late markers idempotently. Every transition has actor, timestamp, task/run ID, and evidence reference; use append-only events plus projections for status.

Different sessions/vendors resume from the same task envelope, acceptance contract, Git SHA, decision log and artifact references—not a summarized assistant claim.

### D4. Evidence and safety

- Require a pinned base SHA, spec hash, expected file scope and actual commit/tree SHA; validate Git objects exist in the target repository.
- Store test command, exit code, environment, runner version, execution timestamp, output location, and SHA under test. A green unrelated test is not acceptance of the task.
- Distinguish offline checks, disposable vCluster/M2 checks, ephemeral ACG AWS sandbox and live/protected hub or Hostinger verification. Cloud sandbox credentials remain independently constrained despite sandbox disposability.
- Risk-gate changes to dispatch, auth, secret handling, Git landing, DR and production/hub/Hostinger infrastructure; keep operator approval for destructive changes and merge/release policies.
- A reviewer must not rely solely on the implementer's self-report. Separate review assertions (`must`, `must_not`, `evidence`) from worker output.
- Budget time, recursion depth, network and resource usage; default deny on unspecified capabilities. No open-ended autonomous subagent recursion.

### D5. Multi-vendor interoperability

Adopt open standards where they *fit*; do not require an A2A or MCP runtime for the initial local architecture.

- MCP can expose controlled dispatch tools to supported clients.
- A2A may eventually bridge agent discovery / task exchange across services.
- Neither substitutes for Git validation, access policy, local process supervision, test provenance, or operator acceptance.
- Keep transport optional and adapter-based; store the canonical task contract in k3d-manager, not a vendor's proprietary chat state.

### D6. FinOps and quality

Record caller/worker/backend/model where known, session/run IDs, token breakdown and cache usage when exposed, API-equivalent estimates separately from real subscription spending, quota utilization only when reliably observable, retries, rejected landings, operator corrections, reverted attempts, and final verified outcomes. Never infer missing data as zero.

Dashboards compare **verified outcomes per cost/quota** and **human interventions per verified task/release**, segmented by task complexity and role. Reverts and speculative retries are distinct from ordinary code review. Maintain clear instrumentation-coverage denominators to avoid a misleading productivity comparison.

## Phased implementation (no committed release numbers)

1. **Prerequisite:** Close dispatcher P1 with a real Codex CLI → Codex CLI completion test after launcher exit; preserve independent regression evidence.
2. **Contract:** Document task envelope, permissions, states, acceptance schema and migration compatibility; approve interface before coding.
3. **Codex adapter:** Refactor the fixed dispatcher behind the common engine; preserve old CLI behavior and all existing artifacts.
4. **Additional adapters:** Add Gemini and Claude using fake-CLI contract tests before real supervised smoke tests.
5. **Shared evidence and policy:** Enforce SHA-scoped acceptance and privilege separation; plug into existing plan/bug lifecycle and dashboard.
6. **Optional interoperability:** Consider MCP tool exposure, A2A bridge and cross-host use only after local deterministic behavior is proven.

## Tests and acceptance

**Must**
- Fake-backend contract suite validates each adapter and caller/worker separation, including Codex → Codex.
- Caller invocation can exit, disconnect, or have its process group terminated without losing an authorized worker or falsifying terminal status.
- Success, nonzero exit, failed auth, missing binary, worker SIGKILL, stale PID, cancellation, resume, duplicate event, network denial, budget breach and bookkeeping failure all yield accurate recoverable outcomes.
- Git SHA, allowed paths and test evidence are independently verified, including a malicious or incorrect agent completion claim.
- Old Codex dispatch commands, historical ledger records, metrics and in-flight run artifacts remain readable.
- Recorded acceptance clearly distinguishes implemented, landed and live verified; review rejects evidence tied to a different SHA.
- Verify with offline fake CLIs first, disposable environments as appropriate, and live operator approval where necessary.

**Must not**
- Bypass the active dispatcher P1, automatically merge or deploy, authorize privileged operations based on model identity, grant blanket network/secrets permissions, or fabricate cost/verification coverage.
- Treat agent-written summaries, exit 0, a healthy pod, or a passing unrelated test as sufficient evidence of accepted engineering work.
- Introduce A2A/MCP as mandatory dependencies merely for local multi-agent dispatch.

**Evidence**
- Schema fixtures, state-transition tests, process-survival logs, actual Git object checks, isolated integration tests, independent reviewer results, measured human-intervention counts, and a migration/rollback rehearsal.

## Files (proposed; refine before dispatch)

| Path | Intended change |
|---|---|
| `bin/k3dm-agent-dispatch` | Shared versioned dispatch CLI; new |
| `bin/k3dm-codex-dispatch` | Compatibility shim, after P1 accepted |
| `scripts/lib/agent-dispatch/` | Policy, ledger, supervisor and provider adapters; new proposed directory |
| `scripts/tests/bin/` | Fake-backend contract and lifecycle regression tests |
| `docs/howto/codex-dispatch.md` | Compatibility and migration guide |
| `docs/plans/future-vendor-neutral-agent-collaboration-contract.md` | This proposal |
| `docs/roadmap.md` | Forward-theme link after approval |
| Agent-dispatch Grafana/exporter files | Metrics extension only after schema approval |

## What NOT to Do

- Do not start implementation or rename `k3dm-codex-dispatch` while P1 remains open.
- Do not assign a version or replace an existing release plan without operator agreement.
- Do not change hub/Hostinger or invoke real LLM workers merely to file or validate this proposal.
- Do not treat this draft as a command for Hermes to dispatch work: **Status is PROPOSED**.
