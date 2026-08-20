# 04 — HashiCorp Vault (PKI)

**Topic:** *HashiCorp Vault (PKI)*
**Status:** Shipping. Source: `scripts/plugins/vault.sh`
(`_vault_setup_pki`, `_vault_enable_pki`, `_vault_ensure_pki_root_ca`,
`_vault_upsert_pki_role`, `_vault_issue_pki_tls_secret`).

---

## The one-liner

> "I run Vault as an in-cluster certificate authority. Its PKI secrets engine holds a
> root CA, and I define a *role* that issues short-lived leaf TLS certificates on
> demand. Services get a real, CA-signed cert as a Kubernetes secret — no
> self-signed certs, no manually-managed key files, and the leaves expire fast enough
> that rotation is the normal case, not an emergency."

## What Vault PKI is (fundamentals)

Vault's **PKI secrets engine** turns Vault into a certificate authority:

- **Root CA** — the trust anchor. Generated once, long-lived. Everything chains to it.
- **Role** — a *policy template* for issuance: which common names/domains are allowed,
  max TTL, hostname enforcement. A role is how you say "this identity may only issue
  certs for `*.dev.k3d.internal`, valid at most 30 days."
- **Issue** — a service (or automation) calls `pki/issue/<role>` and Vault mints a
  fresh leaf cert + private key, signed by the root, on the spot.

The pitch vs. alternatives:
- vs. **self-signed** — real chain of trust, centrally revocable.
- vs. **cert-manager + Let's Encrypt** — works for *internal* names with no public
  DNS/ACME, and keeps the CA under your control. (This repo uses cert-manager too, for
  the public edge — Vault PKI is for internal service-to-service and dev TLS.)

## How it works in k3d-manager

`_vault_setup_pki` orchestrates the standard sequence:

1. **Enable the engine** (`_vault_enable_pki`) at mount path `pki`, tuned with a
   max lease TTL (`VAULT_PKI_MAX_TTL`, default `87600h` ≈ 10y for the *mount ceiling*,
   not the leaves).

2. **Configure URLs** (`_vault_pki_config_urls`) — set the issuing-cert and CRL
   distribution endpoints to Vault's in-cluster service address, so issued certs
   carry a resolvable AIA/CRL pointer.

3. **Generate the root CA** (`_vault_ensure_pki_root_ca`) — idempotent: if
   `pki/cert/ca` already exists it *skips*, so re-running deploy doesn't reissue the
   root and invalidate the chain. Common name defaults to `dev.k3d.internal`.

4. **Upsert a role** (`_vault_upsert_pki_role`) — defines the issuance policy:
   allowed domains (or `allow_any_name` in dev), `enforce_hostnames`, and crucially
   **`max_ttl` on the leaf** (`VAULT_PKI_ROLE_TTL`, default `720h` = 30 days).

5. **Issue into a Kubernetes secret** (`_vault_issue_pki_tls_secret` /
   `_vault_pki_issue_tls_secret`) — call `pki/issue/<role>`, take the returned cert +
   key, and write them as a `tls.crt`/`tls.key` Secret in the target namespace
   (e.g. `istio-system`) for a gateway or workload to mount. It also reads any
   existing secret and extracts the current serial, so it can revoke/rotate cleanly
   instead of orphaning old certs.

## Why it matters (and the security rules)

- **Short leaf TTLs are the security control.** The repo rule is **leaf TTL ≤ 720h**
  and you don't raise `VAULT_PKI_ROLE_TTL` without justification. Short-lived certs
  mean a leaked key is useful for weeks, not years, and rotation is exercised
  constantly so it never rots into a break-glass ritual.
- **Root TTL ≠ leaf TTL.** The mount ceiling is 10 years (you don't want to rebuild
  your CA constantly); the *leaves* are 30 days. Confusing these is a common
  trip-up — the distinction is worth stating explicitly.
- **Idempotent root generation.** Reissuing a root CA silently breaks every cert that
  chained to the old one. The "already exists → skip" guard is a correctness control,
  not just an optimization.
- **Certs delivered as Kubernetes Secrets** means Istio/gateways/workloads consume
  them with zero Vault-awareness — the same clean separation as ESO does for
  credentials (guide 05).

## Common questions

**Q: Why Vault PKI instead of cert-manager for everything?**
> cert-manager + ACME is great for public names with real DNS. For internal
> service-to-service names with no public DNS, and where I want the CA under my own
> control and backed up in Vault, a Vault PKI role issuing short leaves is the better
> fit. I use both — public edge via cert-manager, internal via Vault.

**Q: What's a "role" in Vault PKI?**
> An issuance policy template — allowed domains, hostname enforcement, and the max
> TTL of any cert it issues. It's how you scope *what* an identity is allowed to mint,
> so a compromised issuing path can't request a cert for an arbitrary name.

**Q: Why such short cert lifetimes?**
> Blast-radius and muscle-memory. A 30-day leaf means a leaked key expires soon, and
> because rotation happens routinely the automation is always proven working — you
> never discover your renewal path is broken during an outage.

**Q: How do you avoid breaking the trust chain on redeploy?**
> Root generation is idempotent — if the root CA already exists, deploy skips it.
> Reissuing a root would invalidate every leaf chained to it, so that guard is
> essential, not cosmetic.

**Q: How does a workload actually get its cert?**
> Vault issues into a Kubernetes `tls.crt`/`tls.key` Secret in the workload's
> namespace; the workload (or Istio gateway) mounts the Secret. The workload never
> talks to Vault directly.

## Security rules you're enforcing (repo policy)

- Leaf TTL **≤ 720h** — never raise without justification.
- Vault tokens **never** in shell history or CI logs — passed via env/stdin, and
  sensitive flags registered in `_args_have_sensitive_flag`.
- New Vault policies grant **least privilege** — `read` unless `write` is explicitly
  needed, scoped to the minimum path.
