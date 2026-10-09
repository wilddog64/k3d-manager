# Slack successful-command fallthrough — 2026-10-08

**Result:** reproduced offline; deployed SHA and host logs unverified.
**Source:** `fefb741070ff87418b181508a8589969f38dcec3`
**Bug:** [reopened thread routing report](../bugs/2026-10-07-slack-thread-command-routing-gaps.md)

## Evidence

Operator screenshot: bare `cluster-diagnose hub pods monitoring`; queued job `a41b5ddc`;
Unknown command response; Diagnostics — pods in monitoring on k3d-k3d-cluster, provider hub.

Extracted current `_handle_thread_command` and `_parse_thread_diagnose` via AST and executed
with temporary job directories, stubbed role/parser helpers and a fake Thread recording starts.
Workers never run, role stubs do not establish production authorization, and the repro isolates
control flow rather than kubectl, Make, upgrade, Slack transport or duplicate event handling.

Actual final output:

```text
cluster-diagnose hub pods monitoring: workers=1, replies=['queued', 'unknown-command']
k3dm test-python-unit: workers=1, replies=['queued', 'unknown-command']
argocd-upgrade 7.9.1 acg: workers=1, replies=['queued', 'unknown-command']
3/3 commands reproduce successful handling followed by false Unknown command
k3dm help: replies=1, workers=0, no fallthrough (explicit return)
Workers stubbed; no Slack delivery, upgrade, or cluster operation executed
```

The first probe confirmed diagnostics, then an initial harness expectation incorrectly assumed
`k3dm help` would fall through. Its explicit return prevents that. Corrected the probe to use a
valid Make target with stubbed parser/lock and retained help as a negative control; final checks
above passed. No runtime source edits.

## Root cause and recommendation

The diagnostics/k3dm/argocd-upgrade if/elif chain is followed by an independent kill/diagnosis/
status/logs/... chain. Successful new branches do not return, so the second chain's final else
claims Unknown command. Join the chains with elif or return explicitly after success.
Cover absence of the error for all three handlers and preserve existing commands/authorization.
The earlier duplicate-old-webhook suggestion was unverified and is unnecessary for this repro.

Documentation-only triage. Full BATS/ShellCheck are not applicable to the changed Markdown;
document links and the repository pre-commit audit validate the filing. No live request or restart.
