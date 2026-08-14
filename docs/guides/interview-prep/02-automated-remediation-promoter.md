# 02 — Automated Remediation: The Auto-Patch Promoter

**Résumé phrase:** *automated remediation (auto-patch promoter)*
**Status:** Shipping. Source: `bin/k3dm-webhook`,
`scripts/etc/argocd/platform-ops/app-cve-scan.sh`,
`docs/architecture/cve-remediation-pipeline.md`.

---

## The one-liner

> "When a Critical CVE persists, the platform doesn't just page me — it tries to fix
> it. A webhook kicks off a scan job that finds a clean, immutable image, pins it by
> digest, and lets ArgoCD deploy it. If no clean image exists, it dispatches a
> rebuild instead. Every step is guarded so it can't loop, thrash, or false-green."

## What "remediation" means here

There are **two remediation paths**, and naming both shows you understand the limits:

1. **Image remediation (the promoter).** Promote a *clean, already-built* immutable
   image to replace the vulnerable one — or trigger a rebuild if there's no clean
   candidate. This is what "auto-patch promoter" refers to.
2. **Dependency remediation (Dependabot).** Some CVEs need a *source* change (bump a
   library). No image on the shelf is clean; you have to rebuild from patched
   dependencies. Dependabot opens those PRs; eligible green ones auto-merge.

The honest framing: **the image path is an automated *attempt*, not a guarantee.**
Some CVEs simply can't be patched without a source change, and the design admits
that instead of pretending.

## How the loop works (the flow you can draw)

```
Trivy finding persists 15 min
   → TrivyCriticalVulnerabilityDetected (Prometheus)
   → AlertmanagerConfig routes to webhook
   → POST /api/v1/cve-remediate  (bin/k3dm-webhook)
   → [guards] 24h cooldown? active scan job? → skip & log
   → create cve-auto-<timestamp> Job from the app-cve-scan CronJob
   → read the app cluster's VulnerabilityReports
   → deployed image still has High/Critical?
        no  → no action
        yes → find immutable sha-<tag> candidate matching GHCR latest digest
            → Trivy-scan that candidate
                clean     → patch ArgoCD Application to <repo>:<sha>@<digest>
                          → ArgoCD syncs the workload   ✅ remediated
                not clean → dispatch the app's GitHub Actions rebuild on main
                          → new image published → loop re-evaluates
```

## The safeguards (this is what an interviewer digs into)

An auto-remediation system that can deploy is dangerous if it's naïve. The guards
are the interesting engineering:

- **15-minute persistence** before it's even requested — no reaction to transient
  findings.
- **24-hour cooldown**, keyed by `namespace` + `image_repository` — one repo can't
  trigger remediation over and over.
- **Single-flight** — only one `app-cve-scan` / `cve-auto-*` Job at a time. No
  concurrent promoters racing on the same workload.
- **Promotion requires proof of cleanliness** — the candidate must (a) be an
  immutable `sha-*` tag that resolves to the registry's *current* `latest` digest,
  and (b) pass a *fresh* Trivy High/Critical scan. It's not "deploy something newer,"
  it's "deploy something proven clean."
- **Pin by digest, not tag** — the promoted image is `<repo>:<sha-tag>@<digest>`.
  A tag can be repointed; a digest is the immutable bytes. This is also why it's
  called *git-persisted*: the digest is written to the app's frozen target branch,
  so ArgoCD deploys exactly those bytes and the choice survives a resync.
- **Fail loud, not green** — missing `VulnerabilityReport`s cause a *non-zero* scan
  result, never a fake success. A remediation loop that false-greens is worse than
  no loop.

## Why it matters (design judgment)

- **Event-driven, not polling.** The alert *is* the trigger — the system reacts to
  state changes rather than sweeping on a timer. Cheaper and faster.
- **GitOps is the actuator.** The promoter never `kubectl apply`s a running workload
  directly. It edits the ArgoCD Application (the desired state), and ArgoCD
  reconciles. Every remediation is therefore a reviewable, revertible change, not an
  imperative mutation. This is the same discipline you'd bring to a locked-down
  enterprise cluster where engineers have no direct `kubectl`.
- **It degrades honestly.** No clean candidate → rebuild → wait. No infinite retry,
  no pretending.

## Likely interview questions

**Q: Isn't auto-deploying a security risk in itself?**
> Only if it's naïve. It can *only* promote an immutable digest that resolves to the
> registry's current latest AND passes a fresh scan — so the worst case is deploying
> a newer, independently-verified-clean build of the same service. And it goes
> through ArgoCD, so it's a reviewable git-persisted change I can revert, not a
> silent mutation.

**Q: What stops it from thrashing?**
> A 24h cooldown per namespace+repo, single-flight job execution, and the 15-minute
> alert debounce upstream. Three independent brakes.

**Q: What if the CVE needs a code change, not a new image?**
> The promoter can't fix that — no clean image exists. It dispatches a rebuild and
> waits; Dependabot handles the actual dependency bump via PR. I'm explicit that the
> image path is a best-effort attempt, not a guarantee every CVE auto-resolves.

**Q: Why pin by digest instead of tag?**
> Tags are mutable — `sha-abc` could be repointed to different bytes tomorrow. Pinning
> `@sha256:...` deploys exactly what I scanned. It's the difference between "which
> tag" and "which bytes."

## War story (credibility)

> "A remediation looked stuck — 'failed CVE remediation' on the Hostinger node — and
> I almost blamed the verifier. Real cause: the rollout used `maxSurge=1`, which needs
> a second pod, and the node was 95% full on CPU. The surge pod sat in
> `FailedScheduling` while the old ReplicaSet still reported `1/1`, masking it. So
> *capacity* was silently blocking CVE convergence. Stopgap was patching
> `maxSurge=0/maxUnavailable=1`; durable fix is committing that to git or bumping the
> node. Lesson: 'remediation failed' can be an infra-capacity problem wearing a
> security-tool costume."

(Reference: `reference_hostinger_maxsurge_rollout_deadlock`.)

## Live checks you can name

```bash
kubectl -n platform-ops get jobs                    # scan/remediation jobs
kubectl -n platform-ops logs job/<cve-auto-job>     # promotion decision logs
tail -f ~/.k3dm/logs/k3dm-webhook.log               # cooldown & dispatch decisions
```
