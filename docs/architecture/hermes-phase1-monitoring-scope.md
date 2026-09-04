# Architecture: Hermes Phase 1 — Read-Only Operations Monitoring (scope)

Scope document for the first phase of the **Hermes** event-driven operations
automation theme (roadmap: *Hermes event-driven operations automation, candidate
v1.28.x or later*). The roadmap requires a scope document before Hermes may be
assigned to a release; this is that document for **Phase 1 only**.

Phase 1 is **read-only**. It observes, correlates, and reports. It never mutates
cluster, cloud, Git, or edge state. Phases 2 (allowlisted approval-gated repairs)
and 3 (cooldowns, budgets, audit, post-repair verification) are out of scope here
and each require their own scope document before assignment.

---

## 1 — Why Phase 1 exists

The 2026-09-02/03 hub incident is the motivating case. A single-node control-plane
CPU saturation starved External Secrets Operator, which stalled the identity stack,
which drove an ArgoCD reconcile storm, which flapped the port-forwards behind
Cloudflare and surfaced as public 502s. The failure was **slow** (24h; 232 ExternalSecret
retries) and **repeatable**, yet:

- `make status` reported green because it probes health URLs once, and a stale
  Keycloak session returns 200 (see `docs/issues/2026-09-01-status-blind-spot-*`).
- The first human signal was a user noticing Cloudflare could not reach services.

Every diagnostic step that actually found the root cause — read ExternalSecret sync
status, correlate node CPU, check ArgoCD app health, probe the public endpoint
repeatedly — is mechanical and could have fired hours earlier. Phase 1 is exactly
that: a bounded, read-only sensor and correlator that turns a slow silent
degradation into an early Slack summary.

## 2 — Non-goals (hard boundaries for Phase 1)

- **No mutation of any kind.** No `kubectl apply/patch/delete`, no ArgoCD sync,
  no pod restarts, no edge refresh, no Git writes, no branch-protection changes.
- **No autonomous decision authority.** Phase 1 output is advisory. A human (or a
  later, separately-scoped phase) decides what to do.
- **No new source of truth.** Hermes does **not** run its own cluster health model.
  It consumes the k3d-manager webhook's status as authoritative (§4). This avoids the
  two-health-models drift the roadmap already warns against.
- **No new standing credentials.** Read-only, least-privilege access only (§6). No
  cluster-admin, no cloud write, no Git token, no branch-protection scope.

## 3 — Sensors (Phase 1 signal set)

Each sensor is a bounded, read-only poll. Intervals are illustrative and become
config in the implementation phase.

| Sensor | Source (read-only) | Fires on |
|--------|--------------------|----------|
| ExternalSecret sync | `kubectl get externalsecret -A` conditions | any `SecretSyncedError` sustained > 2 poll cycles |
| ArgoCD app health | ArgoCD API app list (health + sync status) | `Degraded`/`OutOfSync` sustained > N cycles |
| Sustained public reachability | HTTP(S) probe of public hostnames | ≥ M of K samples non-2xx/3xx (multi-sample, not single) |
| Node/control-plane pressure | webhook status payload (§4) node evidence | control-plane CPU over threshold, sustained |
| CI health | GitHub Actions API (read) | required check failing / stuck run |

The **sustained public reachability** sensor is Phase 1's first concrete deliverable
and is described in §5 — it is a k3d-manager improvement worth shipping on its own.

## 4 — The webhook is authoritative

Hermes Phase 1 **reads the k3d-manager webhook's status output** for cluster and node
health rather than re-implementing its own cluster probes. Consequences:

- One health model, not two. If the webhook and Hermes ever disagree, that is a bug
  in one place, not a race between two independent probers.
- The webhook already surfaces node evidence (e.g. exited hub agents, per
  `bin/cluster-status-summary`); Hermes correlates that with the other sensors instead
  of duplicating it.
- Hermes degrades safely: if the webhook is unreachable, Hermes reports "status
  source unavailable" rather than inventing a health verdict.

## 5 — First deliverable: sustained public-endpoint probe in `make status`

Before any Hermes process exists, add a **multi-sample** public-endpoint probe to
`make status` (or a dedicated subcommand it calls). Rationale: the current single-shot
health-URL check false-greened the 502 incident. Requirements:

- Sample each public hostname K times over a short window; report a host healthy only
  if ≥ M of K samples return 2xx/3xx.
- Distinguish edge/tunnel failure (all hosts fail) from single-service failure (one
  host fails while siblings pass) — the two have different root causes and different
  fixes (see `reference_cloudflared_split_brain`, `reference_single_service_502_zombie_port_forward`).
- Emit machine-readable output (per-host sample counts) so Hermes can consume it later
  without scraping human text.

This lands in k3d-manager independently of Hermes and becomes Hermes's first sensor
for free. It is the recommended low-cost starting point.

## 6 — Access model (least privilege)

- **Kubernetes:** a read-only ServiceAccount scoped to the resources the sensors read
  (ExternalSecrets, pods/nodes via webhook, ArgoCD app status). Namespace-scoped Roles
  where possible; no `cluster-admin`, no write verbs.
- **ArgoCD:** read-only API account (app get/list only), no sync/app-write permission.
- **GitHub:** read-only Actions/status access. No `contents:write`, no branch-protection
  scope, no PR/merge capability.
- **Cloud/edge:** none in Phase 1.
- **Secrets:** Hermes reads ExternalSecret *conditions/metadata*, never secret *values*.

## 7 — The cautionary principle Phase 1 encodes

**Health-degraded ≠ safe-to-repair.** In the motivating incident the "obvious" auto-fix
— resume the identity app's ArgoCD auto-sync — was the *wrong* action: the live app
carried a blanket `Replace=true` syncOption (`bin/cluster-up`, commit `0bca3e21`), so a
resync would have force-replaced the Keycloak StatefulSet/PVC. An agent acting on
app-health alone would have caused real damage. Phase 1 therefore **reports and stops**;
it establishes the discipline that any future repair phase must gate a fix on more than
a single degraded signal, and must know the blast radius of the action it proposes.

## 8 — Phase 1 Definition of Done

- [ ] Sustained multi-sample public-endpoint probe shipped in `make status` with
      machine-readable output and edge-vs-single-service discrimination (§5).
- [ ] Read-only sensor set (§3) implemented against the authoritative webhook status (§4).
- [ ] Least-privilege access model (§6) provisioned and verified to hold no write verbs.
- [ ] Correlator emits a Slack summary on sustained multi-signal degradation, with
      bounded polling (no tight loops) and no mutation path in the codebase.
- [ ] A guide under `docs/guides/` or `docs/howto/` documents Hermes Phase 1 grounded in
      the real code (per the per-major-tech guide convention).
- [ ] Explicit statement in code and docs that Phases 2/3 are not implemented and require
      their own scope documents.

## 9 — Exit criteria before assigning a release

- Hub is structurally stable (single-node control-plane over-capacity addressed — the
  roadmap home-lab / Mac Mini M5 tier, or workload offload), **or** Hermes runs off-hub
  (on the laptop, like `bin/k3dm-webhook`) so it does not compete for the substrate it
  observes. The §9 intent — "don't monitor from inside the failure domain" — is satisfied
  by off-hub placement without waiting for the M5 tier.
- This scope document reviewed and the access model (§6) confirmed least-privilege.
- Phase 2 explicitly deferred with its own scope document as the gate.

## 10 — Installation (`_install_hermes_agent`, lib-foundation)

Decision (2026-09-04): installation is handled by a new **`_install_hermes_agent`** helper
in **lib-foundation**, subtree-pulled into k3d-manager (edit lib-foundation upstream first,
then pull — never edit `scripts/lib/` subtrees directly). Rationale and constraints:

- **Off-hub placement.** The helper installs and supervises the Hermes agent on the laptop
  (the same tier as `bin/k3dm-webhook`), not as an in-cluster workload — this is what
  satisfies §9 without the M5 tier.
- **No new privilege at install time.** The installer provisions only the read-only access
  of §6; it must not create write verbs, cluster-admin, cloud-write, or Git tokens.
- **Least-resort LLM routing baked in.** Per the token-economy invariant (below), the agent
  the installer stands up does deterministic sensing in code, calls an LLM only on sustained
  multi-signal degradation, and defaults that LLM to a **non-Claude** agent (Codex/Gemini),
  escalating to Claude only for verification — with a per-day call budget from day one.
- Deferred to the Hermes implementation phase; recorded here so the design carries it. No
  code lands until this Phase-1 scope is assigned to a release.
