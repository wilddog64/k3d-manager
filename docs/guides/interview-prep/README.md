# Interview Prep — Security & Vulnerability Management

These guides turn one line on the résumé —

> **Security & Vulnerability Mgmt:** Trivy scanning, prioritized CVE inventory,
> automated remediation (auto-patch promoter), LLM-assisted CVE triage, HashiCorp
> Vault (PKI), External Secrets Operator, image signing/attestation (cosign) +
> Kyverno admission — in progress

— into things you can talk about for ten minutes each, from real implementation
in this repo. Every guide is grounded in code you actually wrote, so you can answer
follow-ups instead of reciting a definition.

## The 30-second story (memorize this shape)

> "I built an automated vulnerability loop on a from-scratch Kubernetes platform.
> Trivy Operator scans running images and writes findings as Kubernetes objects.
> Those feed a prioritized CVE inventory in Prometheus/Grafana. When a Critical
> persists, Alertmanager calls a webhook that promotes a clean, immutable image by
> digest through ArgoCD — or, if none exists, dispatches a rebuild. An LLM triages
> failures into Slack. Secrets and TLS come from Vault: a PKI engine issues
> short-lived leaf certs, and External Secrets Operator syncs credentials into
> namespaces without them ever touching git. The piece I'm finishing closes the
> loop with cosign signing/attestation and Kyverno admission, so an image that
> wasn't the one we scanned can't run."

That paragraph *is* the architecture. Each guide below is one clause of it.

## Guides

| # | Guide | Résumé phrase | Status |
|---|-------|---------------|--------|
| 01 | [Trivy scanning & prioritized CVE inventory](01-trivy-and-cve-inventory.md) | Trivy scanning, prioritized CVE inventory | Shipping |
| 02 | [Automated remediation — the auto-patch promoter](02-automated-remediation-promoter.md) | automated remediation (auto-patch promoter) | Shipping |
| 03 | [LLM-assisted CVE triage](03-llm-assisted-cve-triage.md) | LLM-assisted CVE triage | Shipping |
| 04 | [HashiCorp Vault PKI](04-vault-pki.md) | HashiCorp Vault (PKI) | Shipping |
| 05 | [External Secrets Operator](05-external-secrets-operator.md) | External Secrets Operator | Shipping |
| 06 | [Image signing/attestation + Kyverno](06-image-signing-cosign-kyverno.md) | cosign + Kyverno admission | In progress (designed) |

## How to use these

- **Read the one-liner and "why it matters" first.** Those are what an interviewer
  actually probes. The mechanics are backup for follow-ups.
- **Know one war story per topic.** A real incident ("the promoter deadlocked
  because the surge pod couldn't schedule on a 95%-full node") beats any textbook
  answer — it proves you operated the thing, not just read about it.
- **Be honest about the in-progress piece.** "cosign + Kyverno is designed and
  scoped, not shipped yet" is a *strength* in an interview — it shows you scope
  and stage security work instead of flipping enforcement on a live fleet.

## Honesty guardrail

Guides 01–05 describe code that exists and runs. Guide 06 describes a **design that
is scoped but not yet implemented** (`docs/plans/v1.27.0-image-signing-cve-loop-closure.md`).
If asked "is it in production?", the honest answer for 06 is: *"It's designed and
staged — Audit before Enforce — but I haven't shipped it yet."* Never claim the
signing loop is live.
