# Documentation architecture and Mermaid diagram review

**Date:** 2026-10-19  
**Status:** REVIEWED — current non-archive docs updated  
**Scope:** `docs/` architecture, guides, how-to pages, tests, bugs, and plans

## What was reviewed

The review compared current documentation claims with the source tree, especially:

- `workers/slack-relay/index.js` for Slack command coverage
- `bin/k3dm-webhook` and `scripts/lib/webhook/make_targets.py` for webhook routes and `/k3dm` targets
- `scripts/plugins/*.sh` and `scripts/etc/argocd/*.yaml*` for current Argo CD namespace and deployment shape
- Mermaid and non-Mermaid diagram blocks under non-archive `docs/`

## Findings and changes

1. `docs/architecture/cloudflare-slack-relay.md` was stale: it omitted `/ask-docs` and said there were 17 `/k3dm` targets. The current source contains `/api/v1/ask-docs` and 31 entries in `MAKE_TARGETS`. The route table, command list, and target count were corrected.
2. `docs/architecture/ingress-port-forwarding.md` describes an optional legacy k3s-host `socat`/Istio path, not the current default Cloudflare/port-forward path. It now says so prominently, and its Argo CD diagram uses the current `cicd` namespace.
3. Actual boxed or ASCII flow/architecture diagrams in current non-archive docs were converted to Mermaid, including the LDAP test flow, image-signing flows, E2E tiers, chisel tunnel, SMB CSI, Jenkins plans, Gemini flow, Argo CD setup, CVE scan stages, and the vCluster teardown flow.
4. Directory trees and command/output snippets remain fenced text or shell because they are listings/evidence, not diagrams. Archived historical documents were not rewritten.

## Verification output

```text
mermaid fences: 37
boxed non-mermaid diagrams: 0
remaining box lines: 0
check-doc-links: 2218 file(s) OK
```

`mmdc` was not installed, so Mermaid rendering was not available locally. The changed blocks use standard `flowchart`, `sequenceDiagram`, and `quadrantChart` Mermaid fences and passed the repository link check.

The targeted BATS check was also run. Its verbatim result was:

```text
1..1
not ok 1 no bare '! cmd' assertions in BATS suites (set -e ignores them)
# (in test file scripts/tests/lib/bats_negation_lint.bats, line 6)
#   `[ "$status" -ne 0 ]' failed
```

This failure is unrelated to the documentation-only diff: the test's own assertion is the line it reports. No test or shell file was changed.

## Follow-up

If archived historical documents are required to meet the same Mermaid-only policy, convert them in a separate cleanup task; changing them here would rewrite historical evidence rather than document the current system.
