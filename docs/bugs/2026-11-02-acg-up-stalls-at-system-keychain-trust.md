# Bug: headless ACG cluster-up stalls at Vault CA trust until timeout

**Status:** OPEN — investigating; exact blocking process and cause unconfirmed
**Priority:** P2
**Severity:** medium — Slack-driven ACG bring-up failed; an interactive CA trust path may be a workaround but has not been verified for this incident
**Filed:** 2026-11-02
**Detected by:** operator screenshot and read-only investigation of job `c38c3855`
**Branch:** `k3d-manager-v1.43.14`
**Approval:** Operator requested dispatch to Luna on 2026-11-02 and subsequently authorized a narrowly scoped privileged supervisor and new sudoers permission to preserve automatic headless trust. Operator explicitly expanded scope to harden existing sudoers rules and dependent listener flows. Offline verification is sufficient for landing; live verification is deferred.
**Related:** `docs/bugs/v1.5.0-bugfix-acg-up-vault-ca-pty-sudo.md`, `docs/bugs/v1.5.3-bugfix-acg-up-vault-ca-trust-no-soft.md`

## Evidence

On 2026-11-01, Slack job `c38c3855` created or updated the CloudFormation stack and proceeded into k3s installation. At step 4c its last meaningful log line was:

```text
INFO: [acg-up] Trusting Vault CA cert in macOS System Keychain (may prompt for sudo password)...
```

The job stayed there until the 3,300-second deadline and was killed. Slack failure analysis hypothesized an interactive sudo prompt; it did not observe the blocking process. The cleanup message says stale connections were removed, and `_run_cleanup` only invokes `pkill` for autossh and deletes a kubeconfig context; it does not delete the AWS stack. Current stack state is unknown: the read-only M5 `DescribeStacks` query returned `InvalidClientTokenId` on 2026-11-02.

The M5 had `/etc/sudoers.d/k3d-manager`, last modified 2026-11-01 09:41 PST, before this run. A current noninteractive sudo policy query for the exact CA trust command returned exit 0. The existing CA's `security verify-cert` returned 1. These observations do not prove the old job's process state or establish why the command blocked. The job's code path calls `_run_command --interactive-sudo --soft`; the checked-in runner selects `sudo -n` if stdin or stdout is not a TTY. The M5 unified log recorded three `sudo true` checks requiring a password at 20:03:52 PST, but a query for `add-trusted-cert` returned no matching entries; this does not identify the blocked process. Other possibilities include `security` or macOS authorization, a TTY/environment difference, or a different running code revision.

The operator states the failed run was before today's pull. Read-only checks on 2026-11-02 show the M5 now matches the release-branch remote head `8d9f5f0f`. Its default `~/.config/k3d-manager/machine-role` is missing; current `bin/cluster-up` requires the `hub` role or an explicit override, so a subsequent run may refuse at that earlier guard. No retry or host configuration change was performed during this investigation.

## Next investigation

Capture the real process tree and TTY/authorization state if this recurs; distinguish `sudo` waiting from `security` waiting, and confirm the deployed webhook and job environment. Establish a bounded, safe failure mode for headless CA trust, preserving certificate verification and not assuming that a pull alone fixes the stall. Verify stack state after sandbox credentials are restored before deciding whether to reuse or clean up infrastructure. See `docs/issues/2026-11-02-acg-up-job-c38c3855.md` for exact diagnostic output.

## Prior-art search

`make find-similar-docs` on M5 surfaced `docs/plans/v1.4.6-auto-trust-vault-ca.md` (score 0.806) and the two related CA-trust bugs above among the top results for the incident query. A timeout/cleanup query found `docs/bugs/2026-08-15-cluster-up-failure-orphans-cloudformation-stack.md` (0.793). M4 retrieval was unavailable; see `docs/issues/2026-11-02-find-similar-docs-prior-art.md`. These examples are useful retrieval evidence, not a comparative evaluation.

## Files

- `bin/cluster-up`
- `scripts/tests/bin/cluster_up.bats`
- `bin/install-sudoers.sh`
- `bin/k3dm-vault-ca-trust-supervisor` (new, if needed)
- `scripts/tests/bin/install_sudoers.bats`
- `scripts/tests/bin/vault_ca_trust_supervisor.bats` (new, if needed)
- `scripts/plugins/argocd.sh`
- `bin/cluster-refresh`
- `scripts/lib/providers/k3s-hostinger.sh`
- `scripts/lib/core.sh` and directly corresponding tests, for preserving k3s installation after hardening generic installation rules.
- `bin/cluster-down` and directly corresponding tests, for preserving safe listener cleanup after hardening plist removal.
- Corresponding listener templates and BATS suites, limited to files directly needed for securing and preserving those flows; identify precise paths in the implementation report.
- `CHANGELOG.md`

## Fix scope

Bound the headless System Keychain CA-trust operation so a hung authorization or `security` process cannot consume the cluster-up job deadline. Implement a narrowly scoped privileged supervisor and sudoers rule as needed, with a short deadline (at most 30 seconds plus a short termination grace), without relying on GNU `timeout` being installed on macOS. The existing privileged sudo monitor may serve as supervisor if a command-specific timeout can be enforced and missing policy fails closed. Terminate and reap controlled processes on timeout. Warn and continue along the existing failure path; do not claim trust succeeded. Do not assume a particular cause of the observed stall. Investigate whether macOS service work may complete after client cancellation and document what offline tests can and cannot prove; do not make unsupported guarantees about macOS service internals.

Preserve the documented automatic trust behavior: already-trusted certificates skip the add operation, interactive use retains its existing prompt and warning behavior, and failed trust remains a warning. Match the existing runner's headless definition (stdin or stdout is not a TTY). Preserve certificate verification and non-Darwin behavior. The supervisor must be installed securely as a root-owned, non-user-writable executable and allow only the intended Keychain trust operation; reject arbitrary commands, unsafe paths, options, symlinks and mutable executable substitution. Add only a narrowly scoped rule for that fixed helper, with no shell or arbitrary command permission. Existing permissive installation rules may be tightened where necessary to secure the helper, with compatibility tests for legitimate installation flows. Existing hosts must receive clear instructions to install the new helper and sudoers rule; if unavailable, warn and continue without falling back to an unbounded privileged command. Do not weaken trust, modify AWS cleanup, automatically destroy infrastructure, or access real Keychains, AWS, Kubernetes or remote hosts in tests. No live installation or live cluster-up is authorized by this dispatch. The live environment and stack state require separate operator investigation.

The operator explicitly authorized expanding scope to close existing passwordless sudoers self-update, binary path traversal, and caller-controlled root LaunchDaemon routes that would defeat the supervisor's security boundary. Preserve legitimate listener configuration and lifecycle using validated, root-controlled executables and narrowly scoped policy. Investigate and test all applicable sudoers paths to helper or policy replacement. Avoid unrelated redesign. Provide clear upgrade instructions and do not modify live host configuration.

## Acceptance

- A headless trust operation that hangs is terminated within the deadline, including controlled descendants, and produces a warning before execution continues. Test with real controlled subprocesses including a TERM-resistant child; provide a short test-only deadline without adding a public option. Investigate and accurately document macOS service cancellation limits; offline tests alone cannot prove cancellation of requests already handed to system services.
- A quick successful headless trust attempt executes once, an already-trusted CA skips it, and an immediate trust failure warns and continues. Preserve interactive and non-Darwin behavior. Tests must isolate command stubs and assert they cannot touch real system state.
- Test the supervisor's argument/path validation, trusted installation and exact sudoers rule, missing helper/permission behavior, and all above paths with isolated stubs. Run the focused BATS suites, ShellCheck on touched shell scripts, `git diff --check`, and a meaningful staged `_agent_audit`; report actual results. Do not run a live cluster-up or install the helper on the host.


## Independent cross-vendor diagnosis before replanning (2026-11-03)

**Status:** REVIEW REQUESTED — not assigned, dispatched, performed, independently verified, or approved for code changes. This section records the operator's proposal to have Muse Wonder/Muse Code and Gemini Argon independently update **this existing bug** before choosing a revised fix plan. Do not describe either vendor as having inspected the incident until an actual dated, attributable report is attached. This is not approval to install tools, pay API charges, modify live hosts, or land changes.

### Shared read-only investigation contract

Give each investigator the same frozen evidence bundle and file SHAs: incident job `c38c3855` and its 3,300-second hang; original observed log and process-state limitations; related v1.4.6 CA trust plan and v1.5.0/v1.5.3 bugs; Phase A diagnosis and artifacts; Terra Phase B/C changes and their **actual** branch/commit/diff; focused BATS/ShellCheck results; sudoers/supervisor design; M5 vs M4 behavior and absence of live reproduction. Include dispatch runs and measured rework only as **process evidence**, not proof of technical root cause. Retrieve current exact refs before preparing the bundle; do not assume all reported local commits are pushed.

1. **Muse Wonder / Muse Code:** independently trace the headless `acg-up` CA trust call path, privilege boundary, timeout supervisor, descendant cleanup, Keychain authorization behavior and whether broad changes are necessary.
2. **Gemini Argon:** independently challenge the leading stall hypotheses, identify missing falsification evidence and review root-helper trust boundaries, certificate identity/provenance, sudoers restrictions, listener migration and unattended failure semantics.
3. Neither agent receives the other's conclusions before finishing its first report. No production commands, real Keychain operations, AWS access, repository modification beyond an explicitly authorized evidence-only bug update, PR/merge, new spec, or unbounded implementation/rework loop. Prefer separate report artifacts linked here; if both edit this bug, apply their additions serially to avoid overwriting either analysis. An operator or coordinator must authenticate report attribution and ensure the report reflects actual execution.
4. Each report must state model/tool/version and execution date where known; actual input evidence + source SHAs; facts versus inference; ranked hypotheses and counterevidence; concrete file/line references; privilege/security concerns; **one smallest discriminating experiment** with predicted outcomes for competing hypotheses; test-environment limits; remaining unknowns; and tokens/cost where available. Return `INCONCLUSIVE` if the evidence does not support a root cause. The report is evidence to review, not a self-approved fix.
5. Use a bounded review budget and stop for operator approval before a second large context sweep, additional model spending, broad file expansion, or implementation. No arbitrary numeric token cap is assumed until the operator sets one.

### Synthesis and new plan decision gate

- After **both** independent reports are available, Claude or another separately authorized reviewer compares agreement, contradictions, missing telemetry, security implications and the minimum experiment needed; do not assume Claude succeeds automatically or that model majority establishes truth.
- Update this bug with a dated **cross-vendor evidence comparison**: verified facts, conflicting conclusions, cost/effort coverage, chosen experiment, rejection reasons, and a clear decision: `diagnose_first`, `narrow_patch`, `revise_existing_plan`, or `operator_decision_required`.
- Do **not** replace Terra's Phase A/B/C record or silently mark acceptance/live verification complete. A new implementation plan is warranted only when the evidence changes the approach or acceptance contract; first amend the existing plan/bug if the correction is narrow, preserving release-slot rules.
- Treat the 2026-11-03 multi-run rework and repeated corrections as a P0 dispatch-stall historical regression case (see `docs/plans/v1.43.14-dispatch-stall-detection-and-escalation-gates.md`), while keeping causal diagnosis separate from model/token efficiency. Do not promote `resume.clarification` to independently verified progress.
- Until synthesis and separate authorization, **implementation remains on hold for this proposed cross-vendor review**, without reversing any previously completed commits or claiming the active worker has been automatically paused.
