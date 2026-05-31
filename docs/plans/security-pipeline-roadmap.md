# Security Pipeline Roadmap

Continuous security loop for the k3d-manager OCI stack:
scan → report → AI review → spec → patch → verify → deploy.

---

## Phases

### v1.6.1 — Full-stack vulnerability scan
**Spec:** `v1.6.1-stack-vuln-report.md`
**Status:** Spec written, not implemented

Bi-weekly in-cluster CronJob on OCI. Scans all Helm releases and running pod images
with `trivy k8s`. Generates JSON + Markdown report, uploads to OCI object storage,
notifies via notify.sh.

**Cadence:** 1st and 15th of each month
**Cluster:** OCI (passive — no active exploitation)
**Tools:** `trivy k8s --severity HIGH,CRITICAL --all-namespaces`
**Output:** `docs/security/vuln-YYYY-MM-DD.json` + `.md`

Patch promotion (human-triggered):
```
make stack-upgrade COMPONENT=vault VERSION=0.31.0 CLUSTER_PROVIDER=acg
make stack-upgrade COMPONENT=vault VERSION=0.31.0 CLUSTER_PROVIDER=k3s-remote
make stack-upgrade COMPONENT=vault VERSION=0.31.0 CLUSTER_PROVIDER=k3s-oci
```

**Prerequisites:** v1.5.1 (OCI storage), v1.6.0 webhook server, notify.sh

---

### v1.6.2 — Red team scan
**Spec:** `v1.6.2-red-team-scan.md` ← not yet written
**Status:** Design complete

Two scan tiers on separate schedules:

| Tier | Cluster | Cadence | Tools |
|------|---------|---------|-------|
| Passive audit | OCI | Every 12h | `kubescape` + `trivy k8s --scanners misconfig,rbac,secret` |
| Active red team | vCluster | Every 24h | `kube-hunter --active` + `kubescape` + `trivy` |

vCluster nightly job: provision → deploy full stack → attack → tear down → upload report.
Triggered via laptop webhook (OCI CronJob → POST webhook → laptop spins vCluster).
If laptop is offline, active scan is skipped; passive OCI scan always runs.

**Output format:** JSON per finding:
```json
{
  "date": "2026-05-30",
  "component": "vault",
  "namespace": "secrets",
  "severity": "HIGH",
  "cve": "CVE-2026-12345",
  "finding_type": "rbac",
  "resource": "ServiceAccount/vault-sa",
  "description": "SA has cluster-admin binding",
  "fix_category": "rbac_scope_reduction"
}
```

Report layout:
```
docs/security/
  red-team-YYYY-MM-DD.json    ← structured findings
  red-team-YYYY-MM-DD.md      ← generated summary for notifications
  red-team-latest.json        ← always current (what AI agents read)
  red-team-latest.md
```

`fix_category` values: `rbac_scope_reduction`, `network_policy`, `image_patch`,
`secret_hygiene`, `config_hardening`, `tls_enforcement`

**Prerequisites:** v1.6.1, vCluster deployed with full stack, laptop webhook server

---

### v1.6.3 — AI security review loop
**Spec:** `v1.6.3-security-review-loop.md` ← not yet written
**Status:** Design complete, blocked on k3dm-MCP (v1.2.0) for full automation

Multi-agent pipeline that consumes scan reports and drives fixes to completion.

**Cadence:**
- Claude triage + spec writing: every 3 days
- Full Codex → Copilot → Gemini cycle: weekly

**Agent roles:**

| Agent | Task | Input | Output |
|-------|------|-------|--------|
| Claude | Triage findings, write fix specs | `red-team-latest.json` + `vuln-latest.json` | `docs/bugs/YYYY-MM-DD-security-<finding>.md` per HIGH/CRITICAL |
| Codex | Implement fix specs | `docs/bugs/` spec | Code commits on feature branch |
| Copilot | Review code changes | PR diff | Inline review comments |
| Gemini | Verify fixes on live cluster | Fix spec + cluster access | Verification report (passive only) |

**Weekly sprint shape:**
```
Day 1-2:  Scans run, reports accumulate in docs/security/
Day 3:    Claude reads red-team-latest.json → writes docs/bugs/ specs per finding
Day 4-5:  Codex implements specs → Copilot reviews PRs
Day 6-7:  Gemini verifies on OCI → Claude creates PRs → merge
Day 1:    Next scan cycle begins
```

**Until k3dm-MCP is ready (v1.2.0):**
Scans run on schedule automatically. AI review is human-triggered:
paste `docs/security/red-team-latest.json` path to Claude → Claude triages and
writes specs in one pass. The JSON structure is designed for AI consumption from
day 1 so the transition to full automation requires no format changes.

**After k3dm-MCP (v1.2.0):**
CronJob posts report path to k3dm-MCP endpoint → Claude is invoked automatically
→ specs written without human intervention.

**Prerequisites:** v1.6.2 (reports), k3dm-MCP v1.2.0 (for full automation)

---

## Dependency chain

```
v1.5.1 (OCI storage)
  └─ v1.6.0 (webhook server + notify.sh)
       └─ v1.6.1 (stack vuln scan)        ← bi-weekly, passive
            └─ v1.6.2 (red team scan)     ← 12h passive + 24h active
                 └─ v1.6.3 (AI review)    ← 3-day/weekly, needs k3dm-MCP for full auto
```

---

## Interfaces

```bash
make vuln-scan CLUSTER_PROVIDER=k3s-oci          # trigger vuln scan now
make red-team CLUSTER_PROVIDER=k3s-oci           # trigger passive red team now
make red-team CLUSTER_PROVIDER=vcluster          # trigger active red team now
make stack-upgrade COMPONENT=<n> VERSION=<v>     # promote a patch through ACG→laptop→OCI
```

Claude review (manual until k3dm-MCP):
```
"Review docs/security/red-team-latest.json and write fix specs"
```

---

## Out of scope

- Active exploitation against any cluster not owned by this project
- Auto-patching stateful components (Vault, Keycloak) without human sign-off
- Red team against ACG sandbox (session-based, not schedulable)
