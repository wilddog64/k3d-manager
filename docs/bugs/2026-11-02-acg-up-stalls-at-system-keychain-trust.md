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

**Status:** IN PROGRESS — Gemini Argon read-only report attached (2026-11-03); Muse Wonder/Muse Code report and synthesis pending; not approved for code changes. This section records the operator's proposal to have Muse Wonder/Muse Code and Gemini Argon independently update **this existing bug** before choosing a revised fix plan. Do not describe either vendor as having inspected the incident until an actual dated, attributable report is attached. This is not approval to install tools, pay API charges, modify live hosts, or land changes.

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

### Gemini Argon independent report (2026-11-03)

- **Model / Tool / Host / Date:** Gemini 4 Argon (Medium) via Antigravity CLI (`agy`), executed on `m4-air.local` (`hostname && uname -n`), `2026-11-03`.
- **Input Evidence & Source SHAs Inspected (Read-Only):**
  - Release branch `k3d-manager-v1.43.14` HEAD: `094e90b7d15f781926fd3482b54b823de0472893` (incident post-pull ref: `8d9f5f0f`).
  - Task worktree `/Users/cliang/.local/share/k3d-manager/worktrees/v1.43.14/2026-11-02-acg-up-stalls-at-system-keychain-trust` (`task/v1.43.14/2026-11-02-acg-up-stalls-at-system-keychain-trust`): committed HEAD `f08a37751854707f72d4e5ca6ea8fe6b42dde138` (parent `6491d5d2`, spec base `204d8e81`: 28 files, +4,300 / -603 lines) plus uncommitted Phase C working-tree changes (10 tracked modified + 8 untracked files, +1,352 / -112 lines).
  - Incident & prior-art docs: `docs/issues/2026-11-02-acg-up-job-c38c3855.md`, `docs/issues/2026-11-02-find-similar-docs-prior-art.md`, `docs/issues/2026-11-03-ca-trust-phase-a-diagnosis.md`, `docs/issues/2026-11-03-ca-trust-phase-b-containment.md`, `docs/plans/v1.4.6-auto-trust-vault-ca.md`, `docs/bugs/v1.5.0-bugfix-acg-up-vault-ca-pty-sudo.md`, `docs/bugs/v1.5.3-bugfix-acg-up-vault-ca-trust-no-soft.md`.
  - macOS system policy & binaries inspected read-only on `m4-air.local`: `/System/Library/Security/authorization.plist`, `/usr/bin/security` entitlements (`codesign -d --entitlements :- /usr/bin/security`) and symbols (`nm -u /usr/bin/security`), `/etc/pam.d/sudo`, `/usr/share/man/man5/sudoers.5`.
- **Root-Cause Verdict for Job `c38c3855`:** **`INCONCLUSIVE` from preserved post-incident artifacts** (no live process tree or `authd` log was captured during the stall), with **two new verified forensic findings** that explain the M5 unified log timestamps, strongly support **H1** (`security add-trusted-cert -d` blocking in `AuthorizationCopyRights("com.apple.trust-settings.admin")` waiting for a GUI `SecurityAgent` prompt even when run as `root`), and show that a root helper cannot make headless System Keychain trust succeed unattended.

#### 1. Verified Facts vs. Inferences

**Verified Facts:**
1. **Exact Source of the Three `sudo true` Entries at `20:03:52.637–20:03:52.675 PST`:**
   - Immediately before Step 4c (`bin/cluster-up:763`), `bin/cluster-up:733-761` iterates over the **3-element** `_HOSTS_LIST` (`argocd.shopping-cart.local`, `keycloak.shopping-cart.local`, `frontend.shopping-cart.local`) and invokes `_run_command --prefer-sudo --soft -- sh -c ...`.
   - In `scripts/lib/foundation/scripts/lib/system.sh:108-109`, `--prefer-sudo` probes `sudo -n true >/dev/null 2>&1`. Because `/etc/sudoers.d/k3d-manager` (`bin/install-sudoers.sh:25-74`) does not grant `NOPASSWD: /usr/bin/true` and no sudo timestamp cache was active, those three loop iterations produced the exact three `a password is required ; ... COMMAND=/usr/bin/true` unified log entries on M5 within 38 ms (`20:03:52.637`, `20:03:52.658`, `20:03:52.675 PST`).
   - This pins the exact wall-clock entry into Step 4c to **`~20:03:53 PST`** (~6.5 minutes into the 3,300s job started around `19:57:22 PST` / Slack thread `p1793591842897049`), meaning the job stalled at Step 4c for **~48.5 minutes** until killed at `~20:52:22 PST`.
2. **Why Default `log show` Missed Allowed `sudo` Commands (`syslog_goodpri` vs `syslog_badpri`):**
   - Per `/usr/share/man/man5/sudoers.5` (`syslog_goodpri`, lines 5748–5760), `sudo` logs rejected/password-required commands at `syslog_badpri` (`alert` -> Unified Log `Default`/`Df`, shown by default in `log show`), whereas allowed commands (including `NOPASSWD` matches) log at `syslog_goodpri` (`notice` -> Unified Log `Info`/`I`, omitted by `log show` unless `--info` is passed). Thus, the absence of `add-trusted-cert` in a default `log show` query does not prove `sudo -n /usr/bin/security` was not executed.
3. **macOS `com.apple.trust-settings.admin` Authorization Policy Does Not Exempt `root`:**
   - Verified on `m4-air.local` via `plutil -extract 'rights.com\.apple\.trust-settings\.admin' xml1 -o - /System/Library/Security/authorization.plist` and `codesign -d --entitlements :- /usr/bin/security`:
     - Modifying Admin Trust Settings (`security add-trusted-cert -d`) calls `SecTrustSettingsSetTrustSettings` -> `AuthorizationCopyRights` for right `com.apple.trust-settings.admin`.
     - `com.apple.trust-settings.admin` evaluates `k-of-n: 1` of `[entitled, authenticate-admin]` and **does not set `allow-root: true`**.
     - `rules.entitled` requires `builtin:entitled,privileged` (`com.apple.private.AuthorizationServices`), which `/usr/bin/security` **does not possess** (its entitlements are only `com.apple.authorization.smartcard.override`, `com.apple.keystore.keybag.create`, `com.apple.private.CoreAuthentication.SPI`, and `com.apple.private.platformsso.security`).
     - Consequently, **even when `sudo -n /usr/bin/security add-trusted-cert -d ...` executes as `root` (`euid=0`)**, `authd` falls through to `rules.authenticate-admin` (`class: user`, `group: admin`, `shared: true`, `timeout: 0`), spawning a **GUI `SecurityAgent` / `CoreAuthUI` modal dialog** in the user's GUI session requiring interactive Touch ID or admin password entry on every call (`timeout: 0`).
4. **Webhook Subprocess Execution Model:**
   - `bin/k3dm-webhook:550-568` (`_posix_spawn_job`) launches `make up` via `os.posix_spawn(..., setsid=True)` with `fd 1` and `fd 2` redirected to the regular file `job_dir / "output"`, and `scripts/lib/webhook/lifecycle.py:380-386` polls `os.waitpid(pid, os.WNOHANG)` on the top-level job PID (not a pipe EOF).
   - `scripts/lib/foundation/scripts/lib/system.sh:60-76` (`_run_command_resolve_sudo`) checks `[[ ! -t 0 || ! -t 1 ]]`, sets `sudo_flags=(-n)`, and resolves `security` to `/usr/bin/security`.

**Inferences & Remaining Unknowns:**
- It is strongly inferred (but unconfirmed without M5 `authd`/`SecurityAgent` logs from `20:03:53–20:52:22 PST`) that `sudo -n` succeeded via `/etc/sudoers.d/k3d-manager` and `/usr/bin/security` blocked inside `AuthorizationCopyRights("com.apple.trust-settings.admin")` waiting for an unattended GUI `SecurityAgent` prompt on M5.
- Unknowns: exact M5 working-tree SHA prior to the 2026-11-02 pull; M5 screen-lock / GUI session state at `20:03:53 PST`; current AWS CloudFormation stack state (blocked by expired ACG credentials).

#### 2. Ranked Root-Cause Hypotheses & Counterevidence

1. **H1 (Most Strongly Supported): `sudo -n /usr/bin/security add-trusted-cert -d ...` succeeded via `NOPASSWD`, and `/usr/bin/security` (running as `root`) blocked in `AuthorizationCopyRights("com.apple.trust-settings.admin")` waiting on an unattended GUI `SecurityAgent` prompt.**
   - *Supporting evidence:* `/etc/sudoers.d/k3d-manager` predated the run (`2026-11-01 09:41:43 PST`); `sudo -n -l` for the exact command returned `0`; `com.apple.trust-settings.admin` requires `authenticate-admin` (`timeout: 0`) even for `root`; post-timeout `security verify-cert` returned `1` (CA untrusted).
   - *Missing confirmation:* Historical M5 `authd` / `SecurityAgent` unified log entries during `20:03:53–20:52:22 PST`.
2. **H2 (Weakly Supported / Unlikely): `sudo` itself blocked waiting for a password prompt.**
   - *Counterevidence:* `_posix_spawn_job` runs with `setsid=True` and file-redirected stdout/stderr (`! -t 1`), causing `_run_command_resolve_sudo` to pass `sudo -n`. `sudo -n` fails in ~20 ms when a password is required, as proved by the three `sudo -n true` calls at `20:03:52.637–.675 PST`. H2 would require M5 to have been running pre-v1.41.0 code without `-n` and with an accessible controlling TTY.
3. **H3 (Contradicted by Code & Logs): `sudo` and `security` exited, and an inherited stdout/stderr pipe held the job open.**
   - *Counterevidence:* `_posix_spawn_job` redirects stdout/stderr to a regular file (`job_dir / "output"`) and `_run_cluster` waits on `os.waitpid(pid, os.WNOHANG)`. In `bin/cluster-up:785-798`, `_run_command` runs synchronously; if `security` had exited `0` or non-zero, `bin/cluster-up` would have written the `_warn` line or the subsequent listener log lines to `output`.

#### 3. Review of Root-Helper Trust Boundaries, Certificate Provenance, Sudoers & Listener Migration

1. **Unattended Failure Semantics & Root-Helper Futility (`bin/k3dm-vault-ca-trust-supervisor` & `bin/k3dm-bounded-sudo`):**
   - Because `com.apple.trust-settings.admin` requires interactive `SecurityAgent` approval (`authenticate-admin`, `timeout: 0`) even when `/usr/bin/security` runs as `root`, executing `/usr/bin/security add-trusted-cert -d` inside `/Library/PrivilegedHelperTools/k3dm-vault-ca-trust-supervisor` **cannot make headless CA trust succeed unattended**. Instead, every headless run with a newly issued Vault CA will still pop up a GUI `SecurityAgent` modal on the Mac, hang for 30 seconds, get killed by `SIGKILL`, and potentially leave an orphaned `SecurityAgent` dialog in the GUI session before logging a warning.
2. **Certificate Identity & Provenance Gap (`bin/k3dm-vault-ca-trust-supervisor:55-86, 117`):**
   - Draft sudoers grants `%admin ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/k3dm-vault-ca-trust-supervisor *`.
   - `_open_certificate(path, owner)` in `bin/k3dm-vault-ca-trust-supervisor:55-86` only checks that `path` is an absolute non-symlink regular file owned by `SUDO_UID` with mode `0600`/`0644` and size `<= 1 MiB`. It neither restricts `path` to `${_ACG_STATE_DIR}/argocd-browser-https-tls/ca.crt` nor verifies X.509 CA attributes or Vault provenance—any process running as the user can pass an arbitrary self-generated CA file to `/Library/PrivilegedHelperTools/k3dm-vault-ca-trust-supervisor` (though on macOS `authd` will still prompt `SecurityAgent`).
3. **Listener Migration & Sudoers Over-Expansion (`bin/k3dm-browser-listener-supervisor`, `bin/k3dm-browser-listener-relay`, `bin/install-sudoers.sh`, `bin/cluster-down`):**
   - **Blast radius:** Phase B/C spans 38 files (+5,652 / -715 lines), replacing `socat` LaunchDaemons with a custom 164-line Python socket-activated TLS/TCP proxy (`bin/k3dm-browser-listener-relay` with `inetdCompatibility: {Wait: False}`), which spawns a new Python interpreter per TCP connection and discards all listener logs to `/dev/null`.
   - **Fragile `launchctl print` parsing:** `bin/install-sudoers.sh:20-22` and `bin/cluster-down:102-125` gate plist removal on `launchctl print` returning exit `113` and exact substring `"Could not find service \"${label}\" in domain for system"`. `launchctl(1)` explicitly warns `print` output is not a stable API.
   - **Destructive upgrade ordering:** `bin/install-sudoers.sh:211-220` deletes `/etc/sudoers.d/k3d-manager` before retiring legacy listeners and staging helpers; any mid-script failure leaves the host without sudoers policy.
   - **Unscoped Linux/k3s collateral changes:** Uncommitted Phase C modifies `scripts/lib/core.sh` and `scripts/lib/providers/k3s.sh` and exposes an unresolved `/bin/bash` 3.2 `set -u` (`probe_args[@]: unbound variable`) bug in `scripts/lib/foundation/scripts/lib/system.sh`.
4. **Recommended Narrow Alternative:**
   - In `bin/cluster-up:783-792`, if `security verify-cert -c "${_argocd_browser_tls_dir}/ca.crt"` fails and the run is headless (`! [[ -t 0 && -t 1 ]]`), **skip `security add-trusted-cert` immediately with `_warn`** (and print the exact one-line command for the operator to run interactively if browser trust is needed), while preserving automatic trust when `[[ -t 0 && -t 1 ]]` (optionally bounded by a caller timeout). Remove `NOPASSWD: /usr/bin/security add-trusted-cert ...` from `bin/install-sudoers.sh`, and decouple any broader sudoers/LaunchDaemon hardening into a dedicated security plan.

#### 4. Smallest Discriminating Experiment

Run one **read-only** unified log query on `m5-air.local` covering `2026-11-01 20:03:50` to `20:53:00 PST` with `--info` enabled (to capture `sudo`'s `LOG_NOTICE` entries) and including `authd`, `SecurityAgent`, `security`, and `trustd`:

```bash
/usr/bin/log show --info \
  --start '2026-11-01 20:03:50' \
  --end   '2026-11-01 20:53:00' \
  --predicate 'process IN {"sudo", "security", "authd", "SecurityAgent", "trustd"}' \
  --style compact
```

- **Predicted outcome under H1 (`security` blocked in `authd` / `SecurityAgent` for `com.apple.trust-settings.admin`):** Within ~1–3s after `20:03:52.675`, `sudo` logs an `I` (`Info`) entry for `COMMAND=/usr/bin/security add-trusted-cert ...`, immediately followed by `authd` / `SecurityAgent` evaluating `com.apple.trust-settings.admin`, which stays pending until `~20:52:22` when `SIGTERM` invalidates the client connection.
- **Predicted outcome under H2 (`sudo` blocked on password):** No `authd` evaluation for `com.apple.trust-settings.admin` appears at `20:03:53`; `sudo` blocks in PAM without spawning `security`.
- **Predicted outcome under H3 (post-`security` descriptor hang):** Both `sudo` and `authd` (`com.apple.trust-settings.admin`) complete within seconds of `20:03:53`.

#### 5. Test-Environment Limits & Cost
- **Test-environment limits:** All Phase B/C BATS suites (`vault_ca_trust_e2e.bats`, `vault_ca_trust_supervisor.bats`, `install_sudoers.bats`) use same-user stub processes and `fnmatch` models; offline tests cannot exercise macOS `authd` / `SecurityAgent` right evaluation or `sudo` policy evaluation.
- **Tokens / Cost:** Single bounded read-only pass on `m4-air.local`; no paid external API calls or subagents invoked.
