# Agent audit misclassifies the foundation subtree's AWK helper

The lib-foundation subtree sync to `339a713391998703875e7634c91edb1c70a843e4` failed the staged audit:

```text
WARN: Agent audit: scripts/lib/foundation/scripts/lib/acg/acg.sh exceeds if-count threshold in: emit_output:10
```

The upstream `emit_output` is an existing embedded AWK function with no `if` statements; the audit incorrectly counts subsequent Bash `if` blocks against it. Upstream documented the issue and exact legacy exception in `scripts/lib/foundation/docs/issues/2026-11-01-agent-audit-acg-awk-if-count.md`. The k3d-manager audit uses its own path-based allowlist, so the corresponding subtree path is listed in `scripts/etc/agent/if-count-allowlist`. The threshold remains 8. Follow-up: fix the upstream audit parser and remove both path-specific exceptions.
