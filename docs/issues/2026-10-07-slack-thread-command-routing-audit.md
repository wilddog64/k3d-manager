# Slack thread routing audit — 2026-10-07

**Result:** FAIL for missing bare-command routing; source-only for other commands.
**Source revision:** `a7bff6228d65e5a9ee8ea851de2f8aad4d6e282d`
**Bug:** [thread command routing gaps](../bugs/2026-10-07-slack-thread-command-routing-gaps.md)

## Method and actual output

Read current relay registration, webhook gates/dispatcher, role policy, help and related bugs.
Parsed the webhook AST, compared all 16 relay commands against both gates and handlers.
Executed only the extracted dispatcher for eight missing bare commands with a notification stub
and permissive role stub; every call returned before a worker or role check. This does not test
production authorization or successful commands. No network/cluster mutations in the probes.

```text
COMMAND | THREAD GATE | STANDALONE GATE | HANDLER
cluster-up | True | True | True
cluster-down | True | True | True
cluster-status | True | True | True
cluster-diagnose | False | False | False
cluster-refresh | True | True | True
cluster-resume | True | True | True
hostinger-status | True | True | True
cleanup-stale-sandbox | True | True | True
ask | True | True | True
ask-docs | True | True | True
claude | True | True | True
gemini | True | True | True
codex | True | True | True
argocd-upgrade | False | False | False
hermes-auth | False | False | False
k3dm | False | False | False
HANDLER ALIASES BLOCKED AS BARE REPLIES: down, refresh, resume, up
BARE REPLY SILENT: cluster-diagnose hub monitoring pod grafana
BARE REPLY SILENT: k3dm help
BARE REPLY SILENT: argocd-upgrade 7.9.1 infra
BARE REPLY SILENT: hermes-auth
BARE REPLY SILENT: refresh
BARE REPLY SILENT: up
BARE REPLY SILENT: down
BARE REPLY SILENT: resume
8/8 isolated missing-command probes confirmed silent; no workers executed
```

Operator screenshot text:

```text
cluster-diagnose hub monitoring kube-prometheus-stack-grafana-7b66b4567f-sm4c4
cluster-diagnose hub monitoring pod kube-prometheus-stack-grafana-7b66b4567f-sm4c4
```

Screenshot shows no response beneath these messages; event receipt, deployment SHA and eventual
reply remain unverified. The second syntax matches current documentation. Existing thread output
delivery and ask-docs follow-up reports are marked FIXED; this is a distinct registry/input gap.

## Follow-up

Implement the bug's supported/slash-only command contract and test routing with stubbed workers.
Other twelve slash commands are structurally routed; no live success claim. Full BATS/ShellCheck
runtime testing is not applicable to this documentation-only filing. Documentation links and
pre-commit audit are the checks for changed files.
