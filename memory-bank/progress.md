# Progress — k3d-manager

## Shipped — pointer, not record

The authoritative release record lives in `docs/releases.md`, `CHANGE.md`, and `git tag -l`. Retros for each release are under `docs/retro/`. This file tracks **in-flight** work only.

**Most recent shipped:**

- v1.0.6 — AWS SSM support for `k3s-aws` (PR #64, `a54e152f`, 2026-04-11)
- v1.0.5 — antigravity decoupling + LDAP Vault KV seeding + Copilot fix-up (PR #62/#63, `71c88b05`, 2026-04-11)
- v1.0.4 — acg-up random passwords, acg_extend hardening (PR #61, `bc9028fb`, 2026-04-10)
- v1.0.3 — `bin/` SCRIPT_DIR, Vault KV seeding, ArgoCD registration fixes (PR #60, `91552139`, 2026-04-05)

Pre-v1.0.3 detail removed from this file (2026-04-19 cleanup); see `git log --tags` and `docs/retro/`.

---

## v1.1.0 Recovery Track (branch: `recovery-v1.1.0-aws-first`)

- **Baseline** — branched off `main`; AWS path functionally verified 2026-04-19 (3-node k3s Ready, `aws sts get-caller-identity` OK, shopping-cart pods mostly Healthy).
- **Seed commit** `11da18d8` (Gemini, 2026-04-19) — added `scripts/etc/playwright/vars.sh` + thin plan skeleton `docs/plans/v1.1.0-recovery-unified-automation.md`.
- [x] **Phase A — Shared playwright vars** — **COMPLETE** (`3de58f4d`, memory-bank `349bddbf`). Reconciled `vars.sh` with existing `playwright-auth`; sourced `vars.sh` from `acg.sh`. E2E A1/A2/A4 ✓; A3 has 5 pre-existing SC2034 warnings (not new).
- [x] **Phase B — Robot engine unification** — **COMPLETE** (`a986d5bb`). Issue `docs/bugs/v1.1.0-recovery-phase-b-robot-engine.md`. `acg_credentials.js`: `.close()`→`.disconnect()` for CDP; `--provider aws|gcp` flag; 127.0.0.1 CDP host; timer cleanup + explicit `process.exit(0)`.
- [ ] **Phase C — GCP identity (`gcp.sh`)** — SPEC `docs/bugs/v1.1.0-recovery-phase-c-gcp-identity.md`. Create `scripts/plugins/gcp.sh` with surgical latch-on (`gcloud auth login` for `cloud_user`), ADC via `GOOGLE_APPLICATION_CREDENTIALS` env (no `activate-service-account`), surgical revoke (SA email only).
- [ ] **E2E verify** — `CLUSTER_PROVIDER=k3s-aws make up` AND `CLUSTER_PROVIDER=k3s-gcp make up`; browser stays open; session cookies persist; active gcloud CLI account is user's, not the SA.

---

## Known Bugs / Gaps

**Infra / tooling (tracked here):**

| Item | Status | Notes |
|---|---|---|
| SSH Tunnel timeouts | OPEN | Connection resets during heavy ArgoCD sync |

**App-layer bugs** live in their repos as GitHub Issues (per "Bug Tracking Ownership" rule):

- `wilddog64/shopping-cart-order#26` — RabbitMQHealthIndicator NPE on stale `:latest` image; fix already in `rabbitmq-client 1.0.1`, remediation is rebuild + rollout.

---

## Roadmap

Authoritative roadmap lives in `~/.claude/projects/.../memory/MEMORY.md`. Summary for this file:

- **v1.1.0** — Unified ACG automation (AWS + GCP), surgical identity/Chrome handling (IN PROGRESS on `recovery-v1.1.0-aws-first`)
- **v1.2.0** — k3dm-mcp (gate: v1.1.0 AWS+GCP proven; two cloud backends = two clouds worth of plugin surface)
- **v1.3.0** — Home lab on Mac Mini M5 (`CLUSTER_PROVIDER=k3s-local-arm64`); home automation plugins
- **No EKS/GKE/AKS** — k3d-manager is kops-for-k3s; cloud-managed k8s is out of scope
