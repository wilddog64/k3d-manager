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

## v1.1.0 Track (branch: `k3d-manager-v1.1.0`)

- **Baseline** — branched off `main` (`279db18c`); AWS path verified 2026-04-19.
- [x] **Shared playwright vars** — COMPLETE (`3de58f4d`)
- [x] **Robot engine unification** — COMPLETE (`a986d5bb`)
- [x] **GCP identity bridge** — COMPLETE (`9686e5c3`). Credential extraction, identity bridge, OAuth automation verified.
- [x] **Documentation alignment** — COMPLETE (`7f3bd0a6`)
- [x] **lib-foundation v0.3.17** — COMPLETE (PR #23 merged). `_agent_lint` glob expanded to `*.sh *.js *.md`.
- [x] **GCP cluster provisioning** — COMPLETE (`c65f0c90`). Logic implemented (`916d71fc`); node-readiness timeout extended to 300s (`c65f0c90`).

---

## Agent Rigor CLI Improvements

- [ ] **Whitespace Enforcement** — OPEN. Add trailing-whitespace detection to `_agent_lint` for `.js`/`.sh` files.

---

## Known Bugs / Gaps
- [ ] **Google Identity Drift** — OPEN. Issue `docs/bugs/2026-04-20-google-account-mismatch-blocker.md`; robot clicks accounts but gcloud stays unauthenticated.

**Infra / tooling (tracked here):**

| Item | Status | Notes |
|---|---|---|
| GCP node readiness timeout | OPEN | 150s too short for fresh GCE bootstrap; bump to 300s. Spec: `docs/bugs/2026-04-20-gcp-node-readiness-timeout.md`. |
| GCP latch-on selector gap | OPEN | `gcp_login.js` missing "Agree and continue" + "Confirm" selectors. Spec: `docs/bugs/2026-04-20-gcp-latch-on-selector-gap.md`. |
| SSH Tunnel timeouts | OPEN | Connection resets during heavy ArgoCD sync |
| GCP Latch-on selectors | COMPLETE | `gcp_login.js` hardened with "Agree and continue" + "Confirm" buttons (`e45d9a04`). |

**App-layer bugs** live in their repos as GitHub Issues:

- `wilddog64/shopping-cart-order#26` — RabbitMQHealthIndicator NPE on stale `:latest` image; fix in `rabbitmq-client 1.0.1`, remediation is rebuild + rollout.

---

## Roadmap

- **v1.1.0** — Unified ACG automation AWS + GCP (IN PROGRESS on `k3d-manager-v1.1.0`)
- **v1.2.0** — k3dm-mcp (gate: v1.1.0 AWS+GCP fully provisioning; two cloud backends)
- **v1.3.0** — Home lab on Mac Mini M5 (`CLUSTER_PROVIDER=k3s-local-arm64`); home automation plugins
- **No EKS/GKE/AKS** — k3d-manager is kops-for-k3s; cloud-managed k8s is out of scope
