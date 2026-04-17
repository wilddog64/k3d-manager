# GitGuardian: Internal IP Addresses Committed to Docs

**Date:** 2026-02-28
**Reported:** 4:27 PM PST
**Status:** OPEN — investigation complete, no credentials exposed, action needed in dashboard
**Severity:** LOW
**Type:** Internal Secret Incident (GitGuardian Internal Monitoring)

---

## What GitGuardian Reported

GitGuardian detected "1 internal secret incident" in the `wilddog64/k3d-manager`
repository. The PR #8 check still shows **pass** — meaning GitGuardian's high-confidence
secret blocker did not fail the PR. The incident is logged in the dashboard as a
lower-confidence or "internal infrastructure" type finding.

**Note:** The exact incident ID and flagged line require GitGuardian dashboard access
to confirm. This analysis identifies all candidates introduced in the feature branch
and recent commits.

---

## Candidates Identified

### Candidate 1 — Private Network IPs in Planning Docs (Most Likely)

**Files:**
- `docs/plans/two-cluster-infra.md` (introduced in commit `a658d677`, pushed 2026-02-28)
- `memory-bank/activeContext.md` (commit `4e7fd3bd`, 2026-02-28 15:08)

**Content flagged:**
```
10.211.55.14:6443    — Ubuntu k3s API server (Parallels VM, host-only network)
10.211.55.3:8200     — Vault endpoint on Mac/OrbStack host (Parallels network)
```

These IPs appear in multiple contexts:
```markdown
# two-cluster-infra.md
| App | k3s (Ubuntu, 10.211.55.14) | SSH: `ssh ubuntu` | ...
kubernetes_host="https://10.211.55.14:6443"
REMOTE_VAULT_ADDR=https://10.211.55.3:8200

# activeContext.md
SSH: `ssh ubuntu`, host: 10.211.55.14
REMOTE_VAULT_ADDR=https://10.211.55.3:8200
```

**Risk:** `10.211.55.x` is the Parallels host-only network range — not routable from
the internet. These IPs only work inside the local Mac. However the repo is **public**,
so the IPs are indexed.

### Candidate 2 — Example AWS Public IP in Cloud Architecture Doc

**File:** `docs/plans/cloud-architecture.md` (commit `41c3b2e5`, 2026-02-28 13:56)

**Content:**
```
# Node 2 public IP: 54.210.1.50
basket.54-210-1-50.nip.io   → 54.210.1.50
jenkins.54-210-1-50.nip.io  → 54.210.1.50
```

`54.210.1.50` is in the AWS public IP range (54.x.x.x = Amazon-owned). It was
written as an illustrative nip.io DNS example (not a real deployed EC2 instance),
but GitGuardian cannot distinguish examples from real IPs. This is the most likely
trigger since the previous incident (`LDAP_PASSWORD_ROTATOR_IMAGE`) also came from
a plausible-but-false pattern.

**Risk:** If `54.210.1.50` is an active EC2 instance, its IP is publicly committed.
Based on context (written as a planning doc example before any AWS deployment), it is
most likely a made-up example IP.

---

## Root Cause Analysis

The repository is **public** (`private: false`). All docs committed to it — including
planning documents and memory-bank files containing operational IPs — are publicly
visible and indexed.

GitGuardian's Internal Monitoring component (connected via GitHub App) scanned the
`feature/two-cluster-infra` branch push and flagged one of the above as an internal
infrastructure detail being committed. The PR check still **passed** because GitGuardian's
PR blocker only blocks high-confidence secrets (API keys, tokens, private keys). IP
addresses in documentation are logged as incidents but don't fail the blocker.

No actual credentials were committed:
- No Vault tokens or root tokens
- No SSH private keys
- No Kubernetes service account tokens
- No passwords or API keys

---

## Comparison with Previous Incident

| | 2026-02-23 Incident | 2026-02-28 Incident |
|---|---|---|
| Trigger | `LDAP_PASSWORD_ROTATOR_IMAGE=docker.io/bitnami/kubectl:latest` | Private/internal IP in docs |
| Type | Generic password false positive (variable name heuristic) | Internal infrastructure IP |
| Risk | None — Docker image, not a credential | Low — IPs not internet-routable |
| Fix | Rename variable | Use placeholder text in future docs |
| Status | FIXED (2026-02-27) | Mark false positive in dashboard |

---

## Timeline

| Time | Event |
|---|---|
| 13:56 | Commit `41c3b2e5` — `cloud-architecture.md` with `54.210.1.50` pushed |
| 15:08 | Commit `4e7fd3bd` — `activeContext.md` + `two-cluster-infra.md` with `10.211.55.x` IPs pushed |
| 16:27 | GitGuardian reports 1 internal secret incident |

---

## Risk Assessment

| Factor | Assessment |
|---|---|
| Credentials exposed | None |
| Tokens / keys | None |
| IPs exposed | Yes — `10.211.55.14`, `10.211.55.3` (Parallels-only, not internet-routable); `54.210.1.50` (example only) |
| Repo visibility | Public |
| Exploitability | Essentially zero — Parallels IPs only work inside local machine |
| Severity | LOW |

---

## Recommended Actions

### Immediate (no code change required)
1. Open GitGuardian dashboard → find the incident → **mark as false positive** or
   **accepted risk** with note: "Parallels VM host-only network IPs, not internet-routable"
2. If `54.210.1.50` is the flagged item: same — mark as false positive with note:
   "Example IP in planning doc, not a real deployed resource"

### Going Forward (doc hygiene, apply on next edit)
Use placeholder variables in docs instead of real IPs:
```
Use:       <MAC-IP>, <UBUNTU-IP>, <NODE-IP>
Instead of: 10.211.55.3, 10.211.55.14, 54.210.1.50
```

This prevents future GitGuardian incidents from planning docs while keeping them
readable.

### Prevention (already noted in previous incident)
Install `ggshield` pre-commit hook to catch IPs + secrets before push:
```bash
pip install ggshield
ggshield secret hook install
```

---

## Verification — No Real Secrets in Diff

Full audit of `feature/two-cluster-infra` vs `main` confirmed:

| Category | Files Audited | Actual Secrets Found |
|---|---|---|
| vars.sh files | vault, jenkins, ldap, argocd | None — only namespace defaults |
| YAML templates | values-*.yaml.tmpl | None — only LDAP URL namespace changes |
| Plugin scripts | vault.sh, eso.sh, jenkins.sh, ldap.sh | None |
| Docs/plans | two-cluster-infra.md, cloud-architecture.md | IPs only (see above) |
| Memory-bank | activeContext.md, progress.md | IPs only |
| Test files | test_auth_cleanup.bats | None |

No tokens, passwords, private keys, or API keys were introduced in this branch.
