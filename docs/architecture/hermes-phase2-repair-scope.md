# Architecture: Hermes Phase 2 — Allowlisted, Approval-Gated Repairs (scope)

Scope document for **Phase 2** of the **Hermes** event-driven operations automation
theme. The roadmap requires a scope document before Hermes may be assigned to a
release, and the Phase 1 scope (`hermes-phase1-monitoring-scope.md`) explicitly
deferred Phase 2 "with its own scope document as the gate." **This is that document.**

Phase 1 is read-only: it observes, correlates, and posts a Slack summary; it never
mutates anything. Phase 2 crosses the read-only → write boundary for the **first
time** — but only through a fixed, code-defined **allowlist** of narrow, reversible
repairs, and only after **explicit human approval**. Phase 3 (cooldowns, daily action
budgets, durable audit records, and automatic post-repair verification) remains out of
scope here and requires its own scope document.

> **This document must be reviewed and signed off before any Phase 2 code is written.**
> It defines the allowlist, the approval mechanism, the safety envelope, and the
> access posture. Those are product/safety decisions, not implementation details.

---

## 1 — Why Phase 2 exists

Phase 1 turned the slow, silent hub degradation (2026-09-02/03) into an early Slack
summary. But once Hermes has correlated a recurring, well-understood failure, a human
still has to notice the Slack post and hand-run the exact same recovery lever every
time. For a small, well-characterized set of failures the recovery is **deterministic,
local, and reversible** — the human is a copy-paste relay, not a decision-maker.

Phase 2 shortens mean-time-to-recovery for exactly those failures by letting Hermes
**propose** the specific allowlisted repair and, on explicit approval, **run** it. It
does **not** expand what Hermes may touch beyond a fixed list, and it does **not** let
Hermes decide on its own to act.

## 2 — The single governing principle (inherited from Phase 1 §7)

**Health-degraded ≠ safe-to-repair.** The Phase 1 scope records the cautionary tale:
the "obvious" auto-fix for the identity-stack incident — resume ArgoCD auto-sync — would
have force-replaced the Keycloak StatefulSet/PVC because the live app carried a blanket
`Replace=true` syncOption (`bin/cluster-up`, `0bca3e21`). An agent acting on a single
degraded signal would have caused real, irreversible damage.

Phase 2 therefore encodes three hard rules for **every** allowlisted repair:

1. **Multi-signal precondition.** A repair is proposable only when its specific
   precondition (a named signal pattern, not "something is degraded") holds. A single
   degraded sensor never triggers a repair proposal.
2. **Known, bounded blast radius.** Each allowlist entry declares exactly what it
   touches and why that is reversible. Anything whose worst case is data loss or an
   irreversible cluster mutation is **not eligible** for the allowlist (see §5).
3. **Human approval before action.** Hermes proposes; a human approves; only then does
   Hermes execute. No auto-execution in Phase 2. (Auto-execution of a subset, under
   budgets + cooldowns, is a Phase 3 question — explicitly out of scope here.)

## 3 — The repair allowlist (the whole of what Phase 2 may do)

The allowlist is **closed** and **defined in code** (a table, not a plugin surface).
Adding an entry is a code change that must cite this document. The initial set maps to
the roadmap's named Phase 2 repairs and to recovery levers that already exist in the
repo and in the operator's runbook memory.

| # | Repair | Precondition (multi-signal) | Exact lever (existing) | Blast radius | Reversible? |
|---|--------|-----------------------------|------------------------|--------------|-------------|
| R1 | **Restart the webhook** | webhook status source unavailable **and** local `k3dm-webhook` LaunchAgent present, **for ≥ N cycles** | `make restart-webhook` (documented target) | one local launchd service on the laptop; no cluster/edge state | yes — idempotent restart |
| R2 | **Kick a zombie port-forward** | exactly **one** public host non-2xx over M/K samples while siblings pass (single-service 502 signature), reachability sensor + webhook agree | `launchctl kickstart -k <PF plist>` for the affected service (per `reference_single_service_502_zombie_port_forward`) | one port-forward launchd job; no workload mutation | yes — re-establishes the PF |
| R3 | **Refresh the hostinger edge access layer** | **all** public hosts non-2xx (edge-down signature, not single-service), sustained | `_hostinger_refresh_access_layer` (the correct lever — **NOT** `make refresh`, per `reference_hostinger_edge_recovery_lever`) | edge/tunnel access layer only; no workload or cluster mutation | yes — re-establishes access |
| R4 | **Re-run a transient-failed required CI check** | a required check failed with a transient/infra signature (not a test/compile failure) on a run Hermes can read | `gh run rerun <run-id> --failed` (read-scoped today; needs `actions:write` — see §6) | one GitHub Actions run re-execution | yes — re-run only |

**Cloudflared split-brain (two connectors) is deliberately NOT R3.** Its fix is
`bootout` of a *stray* launchd agent (`reference_cloudflared_split_brain`) — an action
whose correctness depends on identifying *which* connector is the stray. That
discrimination is not yet mechanical enough to allowlist; it stays human-run and may be
proposed as advisory text only. Revisit for a later allowlist addition once the
detection is deterministic.

Each entry also declares: a **stable action-id**, a human-readable **proposal string**
(what Hermes will run, verbatim), and a **dry-run/preview** form where the lever supports
one, so the approver sees the exact command before approving.

## 4 — The approval mechanism (OPEN DECISION — needs sign-off)

Three candidate mechanisms, from least to most build cost. **This is the primary
decision the sign-off must settle**, because it determines the whole UX and what Codex
builds:

- **A. Propose-only (advisory++).** Hermes posts the incident *and* the exact
  allowlisted command(s) to run, but never executes. This is barely more than Phase 1
  and keeps Hermes 100% read-only in code. Lowest risk, lowest MTTR benefit.
- **B. CLI approval (recommended).** Hermes records a pending proposal (action-id +
  verbatim command) to its state and posts it to Slack. A human runs
  `bin/k3dm-hermes approve <action-id>` on the laptop, which re-validates the
  precondition still holds, executes the single allowlisted lever, and reports the
  result. The approval channel is the operator's own shell (already trusted, already
  where the levers live) — no new inbound surface, no Slack write-back credential.
- **C. Slack-interactive approval.** An approve/deny button in the Slack post drives a
  callback into the slack relay → Hermes. Best UX, but adds an inbound control path and
  a Slack interactivity credential/verification burden — a meaningful new attack
  surface for a component whose entire value is that it is bounded.

**Recommendation: B (CLI approval).** It delivers the MTTR win, keeps the trust boundary
at the operator's shell, adds no inbound control surface, and re-validates preconditions
at execution time (so a stale proposal cannot fire). C can be a Phase 3 enhancement once
budgets/cooldowns/audit exist to bound an inbound path.

## 5 — Non-goals (hard boundaries for Phase 2)

- **No ArgoCD sync / app-write, ever** — the `Replace=true` trap (§2) makes app-sync
  categorically ineligible for the allowlist in Phase 2.
- **No `kubectl apply/patch/delete`**, no pod/StatefulSet/PVC mutation, no scaling.
- **No Git writes**, no branch-protection changes, no PR/merge (Hermes holds no
  `contents:write` and no admin scope — unchanged from Phase 1).
- **No cloud resource create/destroy** (no EC2/ASG/CloudFormation writes).
- **No auto-execution** of any repair — every action is human-approved (§2 rule 3).
- **No open-ended action surface** — the allowlist is closed; a repair not in the §3
  table cannot be run even with approval.
- **No new health model** — preconditions are computed from the existing Phase 1
  records + webhook-authoritative status (Phase 1 §4), not a second prober.

## 6 — Access model (delta from Phase 1 §6)

The design goal is to add repair capability with the **smallest possible privilege
delta**. Because the levers are off-hub/local, most of Phase 2 needs **no new cluster or
cloud credentials**:

- **R1, R2, R3** run entirely on the laptop (make target, `launchctl`, a local
  lib-foundation function). They require **no new Kubernetes, ArgoCD, or cloud write
  credential** — Hermes already runs off-hub with local shell access. This is the whole
  reason off-hub placement (Phase 1 §9) matters.
- **R4** is the only entry that needs a new *remote* scope: the GitHub PAT gains
  `actions:write` (re-run runs) **in addition to** its existing read scope. It still
  holds **no** `contents:write`, no branch-protection, no PR/merge. If granting
  `actions:write` is unwanted, R4 drops to propose-only (mechanism A for that entry)
  and the PAT stays read-only.
- **Kubernetes / ArgoCD / cloud:** unchanged from Phase 1 — read-only, no write verbs.
- **Secret handling:** unchanged — secrets via Keychain at runtime, never in argv,
  never logged, never committed (Phase 1 posture and the repo secret-hygiene rules).

## 7 — Audit & post-repair verification (Phase 2 minimum; full form is Phase 3)

Phase 3 owns durable audit records, cooldowns, and daily action budgets. Phase 2 still
must not act blind, so it carries the **minimum**:

- **Proposal + approval + outcome** for every executed repair are appended to Hermes
  state (action-id, verbatim command, approver-invoked timestamp, exit status) and
  echoed to Slack. This is the seed of the Phase 3 audit trail.
- **Immediate post-repair re-sample.** After executing a repair, Hermes re-runs the
  relevant sensor(s) once and reports whether the precondition cleared. A repair that
  did not clear its precondition is reported as **failed**, and the same repair is not
  re-proposed within the same incident without fresh human involvement (a naive
  one-incident guard; true cooldowns are Phase 3).

## 8 — Phase 2 Definition of Done

- [ ] Closed, code-defined repair allowlist (§3) with per-entry action-id, multi-signal
      precondition, verbatim command, blast-radius note, and reversibility assertion.
- [ ] Approval mechanism (§4, per sign-off) implemented; **no auto-execution path exists
      in the code** (grep-assertable, mirroring Phase 1's "no mutation path" DoD).
- [ ] Precondition **re-validation at execution time** — an approved proposal that no
      longer holds does not fire.
- [ ] Access delta held to §6 — verified that R1–R3 add no cluster/cloud write, and R4's
      `actions:write` (if approved) grants no `contents`/branch-protection scope.
- [ ] Proposal/approval/outcome recorded to state + Slack, and post-repair re-sample
      reports whether the precondition cleared (§7).
- [ ] pytest suite (stubbed inputs, no live cluster/network — same posture as Phase 1)
      covering: each precondition fires only on its multi-signal pattern; a single
      degraded sensor proposes nothing; approval re-validates; a not-in-allowlist action
      is refused.
- [ ] `docs/guides/hermes.md` updated with the Phase 2 repair model, the allowlist, and
      the approval workflow (per the per-major-tech guide convention).
- [ ] Explicit statement in code and docs that Phase 3 (cooldowns, budgets, durable
      audit, auto-verification) is not implemented and requires its own scope document.

## 9 — Exit criteria before assigning a release

- This scope document reviewed and **the approval mechanism (§4) chosen**; the allowlist
  (§3) confirmed to contain only reversible, bounded-blast-radius repairs.
- Access delta (§6) confirmed least-privilege; if R4 is included, the `actions:write`
  grant is explicitly approved, else R4 ships as propose-only.
- Off-hub placement still holds (Phase 1 §9) — Hermes must not run inside the failure
  domain it now also repairs.
- Phase 3 explicitly deferred with its own scope document as the gate.
