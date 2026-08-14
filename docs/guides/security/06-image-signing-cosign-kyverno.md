# 06 — Image Signing / Attestation (cosign) + Kyverno Admission

**Topic:** *image signing/attestation (cosign) + Kyverno admission — in progress*
**Status:** ⚠️ **DESIGNED, NOT SHIPPED.** Full design locked in
`docs/plans/v1.27.0-image-signing-cve-loop-closure.md`. Talk about it as *scoped and
staged*, never as running in production.

---

## Honesty first

This is the one item marked **"in progress."** That's an asset, not a gap — *if* it's
framed right:

> "It's designed and scoped, staged Audit-before-Enforce, but I haven't shipped it
> yet. I don't flip cryptographic admission enforcement on a live fleet without a
> gap-closing Audit phase first."

That framing reflects *more* security maturity than claiming it's done — rushing
enforcement is exactly how you wedge a cluster.

## The one-liner

> "Pinning a digest proves *which bytes* deploy. It proves *nothing about
> provenance* — anyone who can push to the registry could land a different image. So
> I'm closing the loop with cosign: sign each image by digest at build, attest the
> Trivy scan result to it, and have Kyverno reject any first-party pod that isn't
> signed by my key and carrying a passing scan attestation. Signed-and-scanned
> becomes a hard precondition to run."

## The gap it closes (the "why")

Today's loop is **scan → remediate → pin digest → deploy**. Pinning `@sha256:...`
proves the exact bytes. But there's **no cryptographic link** between:

- "my CI built this,"
- "Trivy scanned this and it was clean," and
- "this is what the cluster is running."

Anyone who can push to GHCR can publish a *different* image. If it lands at a digest
the promoter selects, the cluster runs it with no objection. **This isn't
hypothetical** — the shared `PACKAGES_TOKEN` already expired and broke every PR once;
a *leaked* (rather than expired) push token is the same mechanism with a malicious
payload. The loop scans and pins but never **latches** — it can't reject an image
that isn't the one it scanned.

**Goal: add the missing latch.**

## The design — three latches

```
 BUILD (app CI)               PROMOTE (k3d-manager)          ADMIT (cluster)
 cosign sign   (by digest) ─sig──▶ promoter runs             Kyverno verifyImages
 cosign attest (Trivy vuln ─att──▶ cosign verify +           • signature by our key
   + SBOM predicate)              verify-attestation         • valid vuln attestation
                                  BEFORE it pins    ──ok──▶   → Audit, then Enforce
```

1. **Sign at build** — cosign signs each image **by digest** in the publish workflow.
2. **Attest the scan** — `cosign attest` binds the Trivy vuln result + SBOM to the
   digest, so "scanned & clean" travels *with* the artifact and is verifiable offline.
3. **Verify at admission** — Kyverno rejects any first-party pod whose image isn't
   signed by our key and lacks a passing vuln attestation. **Staged Audit → Enforce.**
4. **Verify at promotion** — the promoter runs `cosign verify` + `verify-attestation`
   on a candidate digest **before** pinning it. Unsigned/unattested → not a promotable
   candidate. *This is the latch that closes this project's specific loop* (admission
   is the cluster-wide backstop).

## Key decisions (and the "why not")

**D1 — Key-based, private key in Vault (not keyless).**
cosign keypair generated once; private key + password in Vault
`secret/cosign/signing`; public key distributed via ESO + published for CI.
- *Why not keyless (Fulcio/Rekor OIDC)?* Keyless depends on reachable **public**
  sigstore infra + a public transparency log — at odds with a self-managed,
  Vault-centric, **offline-capable** fleet (Hostinger VPS, OCI ARM64, ephemeral
  sandboxes, laptop hub). Key-based keeps trust material inside my own Vault, which I
  already operate and back up (mirrored to macOS Keychain so the identity survives a
  Vault/k3d rebuild).

**D2 — Staged Audit → Enforce (never flip straight to blocking).**
`validationFailureAction: Audit` first — dashboards show what *would* be blocked —
close the gaps (re-sign/rebuild legacy images), *then* flip to `Enforce` on **app
namespaces only**. A bad enforce rule on a solo-operated fleet with ephemeral bring-up
could wedge cluster startup, so enforcement is namespace-scoped, never hub/system.

**D3 — Kyverno as the admission engine (recommended).**
- *Why Kyverno?* One admission controller I can **reuse** to machine-enforce the
  OWASP-A05 conventions currently enforced only by review (namespace-per-service,
  pinned tags, no `:latest`). `verifyImages` handles key-based cosign signatures *and*
  attestation predicate checks, public key from a Secret/ConfigMap.
- *Alternative — sigstore `policy-controller`:* sigstore-native `ClusterImagePolicy`,
  cleaner if I *only* ever do signature/attestation policy. Loses the reuse upside.

## Critical safety details

- **Scope only to app namespaces**, and **exclude all third-party/upstream images**
  (postgres, rabbitmq, redis, argocd, `alpine/k8s`). I don't sign those — an unscoped
  policy would block the entire platform. Reuse the same `wilddog64/.*` vs.
  `tier: upstream` split the Trivy alerting already uses, so the boundary is
  consistent.
- **`failurePolicy: Ignore` (fail-open) during Audit.** A `Fail` (fail-closed) webhook
  that goes down can wedge app-namespace scheduling — dangerous on a solo fleet.
  Document the choice; revisit for Enforce with eyes open, never silently fail-closed.
- **Key never in argv/logs (OWASP A02).** cosign reads material via
  `--key env://COSIGN_KEY` + `COSIGN_PASSWORD`. Private key is password-encrypted at
  rest; the password is strong-generated, never a literal.
- **CI can't reach Vault.** GitHub runners have no path to the in-cluster Vault (same
  constraint as the queued Vault-remote-access work), so the key is delivered as GH
  Actions secrets seeded once from Vault and **re-seeded on rotation** — *not*
  `hashivault://` transit.
- **Sign by digest, never by tag.** Digests are immutable; tags can be repointed.

## Staged rollout (maps to D2)

| Stage | What | Gate to advance |
|---|---|---|
| 0 | Key seeded: Vault + Keychain backup + ESO pub secret; read-only verifier policy | `signing_status` shows key present + pub projected |
| 1 | All first-party CI signs + attests by digest | `cosign verify` passes on a fresh build of every image |
| 2 | Kyverno installed, `ClusterPolicy` in **Audit** | **Zero** would-be-blocks for current first-party images |
| 3 | Flip to **Enforce** on app namespaces; promoter gate live | Unsigned test image *rejected*; signed one admits |
| 4 | Rotation runbook exercised (`signing_rotate_key`) | Re-seed Vault + GH secrets + ESO pub; dual-key overlap documented |

## Common questions

**Q: Isn't pinning by digest already secure?**
> It proves *which bytes* run, not *where they came from*. Nothing cryptographically
> ties the running image to "my CI built it and Trivy passed it." A leaked push token
> could land a malicious image at a digest the promoter picks. Signing + attestation
> adds the provenance latch — the cluster can reject anything not signed by my key
> with a passing scan attestation.

**Q: Keyless cosign is the modern default — why key-based?**
> Keyless needs reachable public sigstore infra and a public transparency log. My
> fleet is self-managed and offline-capable — ephemeral sandboxes, a VPS, a laptop
> hub. Key-based keeps the trust material in my own Vault, which I already back up. I
> traded sigstore's zero-key-management for self-sufficiency, deliberately.

**Q: How do you roll this out without breaking the cluster?**
> Staged. Audit mode first so dashboards show what *would* be blocked, close every gap
> — re-sign or rebuild legacy images — then flip to Enforce on app namespaces only,
> never hub/system, with upstream images explicitly excluded because I don't sign
> those. And fail-open during Audit so a webhook outage can't wedge scheduling.

**Q: What's an attestation vs. a signature?**
> A signature proves *who* produced the image. An attestation is signed *metadata
> about* the image — here, the Trivy vuln result and an SBOM bound to the digest. So
> the cluster can verify not just "my key signed this" but "and it carried a passing
> scan," offline, without re-running Trivy.

**Q: Where does the verifier get the public key?**
> ESO projects `cosign.pub` from Vault into a Secret in the Kyverno namespace, so the
> verifier reads it from a Kubernetes Secret and never touches Vault directly — same
> distribution pattern I use for all Vault material.

## Summary

> "Signing is the last latch on a loop that already scans, prioritizes, and
> remediates. Detection tells me what's wrong; remediation fixes it; signing makes
> sure the thing that actually runs is the thing I scanned and built. That's the
> full detect → prioritize → remediate → *verify* loop."
