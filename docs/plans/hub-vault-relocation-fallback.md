# Hub Vault Relocation with Laptop Fallback (Tier 3 — durable Vault-bridge stability)

**Status:** design / roadmap (post-v1.10.0). Assign a version when scheduled.
**Depends on:** v1.10.0 provider-agnostic Vault auth (`configure_vault_app_auth_for_context`).
**Motivation:** two live Hostinger outages on 2026-06-26, both rooted in the hub Vault
living on the Mac and being reached through a fragile reverse-SSH/socat bridge.

---

## Problem

The hub Vault (`vault-0`) runs on the Mac k3d cluster (`k3d-k3d-cluster`, `secrets` ns). The
Hostinger app cluster reaches it through:

```
app CSS → vault-bridge:8201 (Svc) → Hostinger host socat → host:8200
        → autossh reverse tunnel (-R) → Mac 127.0.0.1:18200 → vault-0:8200
```

The Mac is therefore a **single point of failure** for the entire app cluster's secrets:
- The Mac sleeps / roams / reboots → the tunnel drops → ESO store goes `Ready=False`.
- The chain has four independent hops (socat, autossh, kubectl pf, Vault pod); any one
  flapping breaks secret delivery.
- Tier 1 (`docs/bugs/2026-06-26-eso-refresh-interval-self-heal.md`) makes ESO *recover*
  faster, but does not remove the laptop dependency.

## Goal

Run the hub Vault on an **always-on node** as the primary, and **keep the laptop +
reverse-tunnel path as a selectable fallback** so that losing the primary (or losing
Hostinger) does not strand the platform. This is additive — the laptop code path stays.

---

## Design

### Make the Vault endpoint a selectable seam (not a relocation-in-place)

v1.10.0 already made Vault *auth* provider-agnostic (kube-context-keyed). This plan closes
the remaining open seam: the Vault **endpoint** is currently hardcoded
(`vault.3ai-talk.org` in the static CSS / `VAULT_ENDPOINT` default in `eso.sh`). Introduce a
hub-Vault **profile** selected by env/config:

```
HUB_VAULT_PROFILE = oci | hostinger | laptop      # default: oci (or per-CLUSTER_PROVIDER)
```

Each profile resolves: Vault server address, the network path (direct vs. bridge), and the
reconcile steps. The CSS/`VAULT_ENDPOINT` is rendered from the active profile instead of a
constant. The laptop profile = today's reverse-tunnel bridge, kept intact.

### Where the always-on Vault should live (decision needed)

| Candidate | Pro | Con |
|-----------|-----|-----|
| **OCI Always Free** (roadmap v1.0.8, ARM64) | Truly independent of Hostinger; survives losing Hostinger; zero cost | New node to provision + maintain; cross-cloud network path |
| **Hostinger VPS itself** | Co-located with the app cluster → near-zero-latency, no bridge | If you lose Hostinger you lose Vault too — fallback to laptop becomes mandatory, not optional |
| **Laptop (today)** | Already works; dev-friendly | The SPOF we are fixing — demote to fallback only |

**Recommendation:** primary = **OCI Always Free** (independent failure domain), fallback =
**laptop**. If primary = Hostinger is chosen for latency, the laptop fallback is load-bearing
(it is the only Vault left when Hostinger dies), so seed-continuity (below) becomes mandatory.

### Secret continuity across primary ↔ fallback

The fallback Vault must serve the same secrets as the primary. Options (OSS Vault — no
performance replication):
1. **Re-seed on failover (recommended):** keep the existing seeding scripts idempotent and
   canonical-source-driven; on failover, seed the fallback Vault then repoint the CSS. The
   secrets' source of truth lives outside Vault (seed scripts / Keychain), so both Vaults can
   be (re)populated identically.
2. **Periodic export/import sync:** a scheduled `vault kv get`→`vault kv put` mirror from
   primary to fallback. More moving parts; defer unless RTO requires it.

Pair with `docs/plans/vault-resilience.md` (auto-unseal) so a relocated/fallback Vault comes
back unsealed without manual shard entry.

### Failover mechanism

- **Phase 1 (manual):** operator sets `HUB_VAULT_PROFILE=laptop` and runs the Hostinger
  reconcile/refresh → CSS repoints to the laptop bridge, ESO re-syncs. Document as a runbook.
- **Phase 2 (assisted):** a health probe (extend the Tier 2 watchdog idea) detects the
  primary Vault unreachable and flips the profile + reconciles automatically.

---

## Scope / Phasing

1. **Endpoint seam** — render CSS/`VAULT_ENDPOINT` from `HUB_VAULT_PROFILE`; laptop profile
   reproduces today's behavior byte-for-byte (no functional change when profile=laptop).
2. **Provision always-on Vault** — stand up Vault on the chosen node (OCI Always Free first),
   reachable by the app cluster over a stable path; wire auto-unseal (`vault-resilience.md`).
3. **Seed continuity** — make seeding idempotent + canonical-source-driven; runbook to seed
   either Vault from the same source.
4. **Failover runbook (manual)** — switch profile → reconcile → verify CSS Valid + ES synced.
5. **(Later) Assisted failover** — health-probe-driven profile flip.

## Out of scope

- Vault Enterprise replication (OSS only).
- Removing the laptop code path — explicitly retained as the fallback.

## Open decisions (for the user)

1. Primary location: **OCI Always Free** (independent) vs **Hostinger VPS** (co-located, but
   makes the laptop fallback load-bearing)?
2. Failover: manual runbook first (Phase 1) or build assisted failover up front?
3. Seed continuity: re-seed-on-failover (simpler) vs periodic mirror (lower RTO)?

---

## Relationship to other work

- **Tier 1** (`docs/bugs/2026-06-26-eso-refresh-interval-self-heal.md`) — ships now; makes
  ESO self-heal regardless of where Vault lives.
- **Tier 2** (tunnel chain watchdog) — optional belt-and-suspenders while the laptop bridge
  exists; folds naturally into Phase 5 assisted failover.
- **v1.10.0** — the kube-context-keyed auth helper this builds on.
- **`vault-resilience.md`** — auto-unseal, required for an always-on Vault.
