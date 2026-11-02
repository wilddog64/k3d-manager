# Agent audit counts an embedded AWK function as Bash

While staging the ACG imported-key fingerprint fix, the repository's staged `_agent_audit` returned:

```text
WARN: Agent audit: scripts/lib/acg/acg.sh exceeds if-count threshold in: emit_output:10
```

`emit_output` is an unchanged AWK function inside `_acg_render_template`, already present in merged `bb7f1f28`; it has no `if` statements. The audit parser treats it as a shell function and continues counting later shell `if` statements because it does not recognize Bash `name()` function declarations. The exact legacy pair is allowlisted in `scripts/etc/agent/if-count-allowlist`; the threshold remains 8.

Follow-up: teach the audit to distinguish embedded AWK from Bash and recognize Bash function boundaries, then remove this allowlist entry. Do not use this exception for new functions.
