# Hub Vault Relocation with Laptop Fallback (Tier 3 — durable Vault-bridge stability)

**Status:** decisions LOCKED 2026-06-27 (see "Locked decisions" below). Target release **v1.10.0**.
**Depends on:** v1.10.0 provider-agnostic Vault auth (`configure_vault_app_auth_for_context`).
**Motivation:** two live Hostinger outages on 2026-06-26, both rooted in the hub Vault
living on the Mac and being reached through a fragile reverse-SSH/socat bridge.

---

## Locked decisions (2026-06-27)

1. **Primary = Hostinger VPS (co-located, in-cluster Vault).** OCI Always Free is **dropped
   entirely** — it could never be provisioned, so it is not a candidate.
2. **Fallback = laptop** (today's reverse-tunnel + socat bridge, kept intact). Because the
   primary is co-located with the app cluster, the laptop fallback is **load-bearing**: it is
   the only hub Vault left if the Hostinger Vault dies. Therefore **seed continuity is
   mandatory, not optional.**
3. **Assisted failover up front** — a health probe detects the primary Vault unreachable and
   automatically flips `HUB_VAULT_PROFILE` + reconciles. (No manual-only first cut.)
4. **Re-seed on failover** — seeding scripts are made idempotent + canonical-source-driven
   (source of truth lives outside Vault: seed scripts / Keychain). On failover, seed the
   fallback Vault, then repoint the CSS. No periodic kv mirror.

---

## Problem

The hub Vault (`vault-0`) runs on the Mac k3d cluster (`k3d-k3d-cluster`, `secrets` ns). The
Hostinger app cluster reaches it through (verified in code):

```
app ClusterSecretStore  server: http://vault-bridge.secrets.svc.cluster.local:8201
  → vault-bridge Svc/Endpoints (manual Endpoints → <node IP>:8201)   shopping_cart_create_vault_bridge
  → Hostinger host socat  TCP-LISTEN:8201 → localhost:8200            _setup_vault_bridge
  → autossh reverse tunnel (-R 8200:127.0.0.1:18200)                 tunnel_start
  → Mac LaunchAgent kubectl port-forward vault-0 18200:8200          com.k3d-manager.vault-port-forward
  → vault-0:8200 on k3d-k3d-cluster
```

The orchestrator is `_hostinger_reconcile_vault_cluster_store()`
(`scripts/lib/providers/k3s-hostinger.sh:671`); the CSS itself is written by
`shopping_cart_apply_vault_token_and_cluster_secret_store()`
(`scripts/plugins/shopping_cart.sh:447`, server hardcoded at line 482, token read from the
**laptop** `vault-root` at line 451).

The Mac is therefore a **single point of failure** for the entire app cluster's secrets:
the Mac sleeps / roams / reboots → the tunnel drops → ESO store goes `Ready=False`. The chain
has four independent hops; any one flapping breaks secret delivery. Tier 1
(`docs/bugs/2026-06-26-eso-refresh-interval-self-heal.md`) makes ESO *recover* faster but does
not remove the laptop dependency.

## Goal

Run the hub Vault **in the Hostinger app cluster** as the primary (no bridge, no tunnel,
in-cluster `http://vault.secrets.svc:8200`), and **keep the laptop + reverse-tunnel path as a
selectable fallback** so that losing the in-cluster Vault does not strand the platform. The
laptop code path is retained verbatim.

---

## Design

### The Vault endpoint becomes a selectable seam: `HUB_VAULT_PROFILE`

v1.10.0 already made Vault *auth* provider-agnostic (kube-context-keyed). This plan closes the
remaining open seam: the Vault **endpoint** is currently hardcoded to the laptop bridge.
Introduce a profile selected by env/config:

```
HUB_VAULT_PROFILE = hostinger | laptop      # default: laptop (today's behavior) until P2 lands
```

Each profile resolves two things:
- `HUB_VAULT_CSS_SERVER` — the `server:` URL written into the app-cluster ClusterSecretStore.
- `HUB_VAULT_USE_BRIDGE` — whether the reconcile path stands up the tunnel + socat + vault-bridge Svc.

| Profile | CSS server | Bridge/tunnel | Token source |
|---------|-----------|---------------|--------------|
| `laptop` (fallback, = today byte-for-byte) | `http://vault-bridge.secrets.svc.cluster.local:8201` | yes | laptop `vault-root` |
| `hostinger` (primary) | `http://vault.secrets.svc:8200` (in-cluster) | no | in-cluster Vault (P2) |

**Phase 1 ships the seam with `default=laptop`, so it is behavior-preserving** — the
`hostinger` branch is wired but inert (and not fully functional) until Phase 2 provisions the
in-cluster Vault. **The default does NOT flip in Phase 2** (revised 2026-06-27): the
in-cluster Vault is empty until P3 seeds it, so flipping the default before seeding would point
the CSS at an empty Vault. The flip is a dedicated **cutover** step, gated on P3 seeding.

### Secret continuity (re-seed on failover)

The fallback (laptop) Vault must serve the same secrets as the primary. Source of truth lives
**outside** Vault (seed scripts / Keychain), so either Vault can be (re)populated identically.
On failover: seed the target Vault (idempotent), then repoint the CSS via the profile.
Pair with `docs/plans/vault-resilience.md` (auto-unseal) so a relocated/fallback Vault comes
back unsealed without manual shard entry.

### Assisted failover

A health probe (extend the Tier 2 watchdog idea) periodically checks the active hub Vault. On
sustained unreachability it flips `HUB_VAULT_PROFILE` to the fallback, re-seeds if needed, and
re-runs the Hostinger reconcile so the CSS repoints and ESO re-syncs.

---

## Phasing (each phase = one Codex spec)

1. **P1 — endpoint seam (`HUB_VAULT_PROFILE`)** — `docs/plans/v1.10.0-hub-vault-profile-seam.md`
   (WRITTEN, Codex-ready). Pure code; `default=laptop` ⇒ no functional change. Unblocks all
   later phases.
2. **P2 — in-cluster Hostinger Vault + auto-unseal.** Split into two specs (decided
   2026-06-27 after grounding `deploy_vault` + the k8s-auth path):
   - **P2a — auto-unseal watchdog** — `docs/plans/v1.10.0-hub-vault-incluster-unseal.md`
     (WRITTEN, Codex-ready). Shamir `shard-1` (init is `-key-shares=1 -key-threshold=1`) stored
     in the in-cluster `vault-unseal` Secret (already created by `_vault_process_init_artifacts`)
     replayed by an in-cluster CronJob (`vault status` exit-code driven; pinned image;
     namespace-scoped; no RBAC — optional secret volume). Self-contained, safe-anywhere,
     behavior-preserving (nothing auto-calls it). No KMS, no Keychain, no laptop dependency.
   - **P2b — provision + CSS k8s-auth cutover** — `docs/plans/v1.10.0-hub-vault-incluster-provision.md`
     (WRITTEN, Codex-ready; live grounding pass done 2026-06-27). Both blockers resolved:
     (1) provisioning runs via a new `vault_deploy_hub_into_context` wrapper that
     saves/restores the current-context (k3s-hostinger.sh idiom) and runs `deploy_vault` with
     a `HUB_VAULT_INCLUSTER=1` guard bypassing the `CLUSTER_ROLE=app` early-return — chosen
     over threading `--context` because `_kubectl`/`_helm` are lib-foundation subtree.
     (2) the app's real `remoteRef` keys are `secret/data/{postgres,payment,redis,rabbitmq,keycloak,ldap,minio}/*`
     (none under `eso/*`), so the k8s-auth CSS binds a new least-privilege `app-cluster-reader`
     policy (those 7 prefixes), not `eso-reader`. CSS auth mode is derived per profile
     (`HUB_VAULT_CSS_AUTH`: laptop→token, hostinger→kubernetes); default `laptop` stays
     behavior-preserving. The default flip is the P3-gated cutover (runbook in the P2b spec).
3. **P3 — idempotent canonical-source seeding** — `docs/plans/v1.11.0-hub-vault-canonical-seeding.md`
   (WRITTEN 2026-06-27, Codex-ready). Makes the seed scripts re-runnable and canonical-source-driven
   so either Vault can be populated identically. Locked model (user 2026-06-27): **Vault = source of
   truth, Keychain = backup, also mirrored to a native k8s `vault-seed-backup` Secret**; per-key
   resolution source-Vault → keyring → generate. Fixes the `redis/*`+`rabbitmq/default` clobber
   (now reuse-if-exists) and adds operator `vault_seed_hub_into_context <ctx>` (laptop→in-cluster
   mirror, no auto-caller). The **default-profile flip to `hostinger` (cutover) is gated on this.**
   Target **v1.11.0**.
4. **P4 — assisted-failover watchdog** — health-probe-driven profile flip + reconcile. (Spec
   last; depends on P1–P3.)

> **Release-scope note (CLAUDE.md max-5-plan-docs):** v1.10.0 already holds the design doc + P1
> + P2a. Adding P2b + P3 + P4 to the same release would exceed 5. Plan: **v1.10.0 = seam (P1) +
> auto-unseal (P2a) + provision/cutover (P2b)**; **v1.11.0 = canonical seeding (P3) +
> assisted-failover (P4)**. Confirm the split before writing P3.

## Out of scope

- Vault Enterprise replication (OSS only) and periodic kv mirroring.
- Removing the laptop code path — explicitly retained as the fallback.
- OCI as a Vault host — dropped (cannot provision).

---

## Relationship to other work

- **Tier 1** (`docs/bugs/2026-06-26-eso-refresh-interval-self-heal.md`) — SHIPPED (PR #86,
  merge `4afa9dce`); makes ESO self-heal regardless of where Vault lives.
- **v1.10.0** — the kube-context-keyed auth helper this builds on.
- **`vault-resilience.md`** — auto-unseal, required for an always-on in-cluster Vault (P2).
