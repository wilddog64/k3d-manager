# E2E failure-group publisher if-count follow-up

The E2E remote publisher embeds schema validation in `_e2e_publish_build`, a
legacy shell function containing an inline Python validator. `_agent_audit`
reports 11 conditional tokens for that function after the failure-group schema
was added. The function is allowlisted temporarily so the observability change
can land without raising the global threshold.

Follow-up: extract the inline publisher validator into a standalone helper and
remove `scripts/plugins/e2e_remote.sh:_e2e_publish_build` from
`scripts/etc/agent/if-count-allowlist`.
