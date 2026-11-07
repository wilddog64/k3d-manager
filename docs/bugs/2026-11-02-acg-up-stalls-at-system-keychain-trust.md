# Bug: headless ACG cluster-up stalls at Vault CA trust until timeout

**Status:** VERIFIED 2026-11-07 — `8d57ff9e` plus follow-up `0b11c1f9`; offline-verified by Argon (`verify-evidence.1.log`), then independent verifier PASS 2026-11-07 (14/14 on `0b11c1f9` and on head `5b7ecd15`; N3, N4 red on `8d57ff9e`); live M5 verification pending
**Waiting on:** live check — since 2026-11-07
**Priority:** P2
**Severity:** medium — Slack-driven ACG bring-up failed; an interactive CA trust path may be a workaround but has not been verified for this incident
**Filed:** 2026-11-02
**Detected by:** operator screenshot and read-only investigation of job `c38c3855`
**Branch:** `k3d-manager-v1.43.14`
**Approval:** Operator requested dispatch to Luna on 2026-11-02; on 2026-11-03, after reviewing the Gemini Argon independent root-cause report (`com.apple.trust-settings.admin` requires interactive `SecurityAgent` approval even for `root`), operator approved proceeding with Option A (`narrow_patch`) first before deciding on any broader sudoers/listener rework. Offline verification is sufficient for landing; live verification is deferred.
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
- `scripts/tests/bin/install_sudoers.bats`
- `CHANGELOG.md`

## Fix scope

Implement **Option A (`narrow_patch`) + M5 Live Verification Follow-Up (2026-11-03)**:

1. **`bin/cluster-up` (Step 4c System Keychain CA trust — `_acg_trust_vault_ca`):**
   - Extract a helper function `function _acg_trust_vault_ca()` and call `_acg_trust_vault_ca "${_argocd_browser_tls_dir}/ca.crt"` at Step 4c in place of the inline `if [[ "$(uname)" == "Darwin" ]]; then ... fi` block.
   - Inside `function _acg_trust_vault_ca()`:
     - Take `local _ca_cert="$1"`.
     - If `[[ "$(uname)" != "Darwin" ]]`, return `0` without calling `security`.
     - If `security verify-cert -c "${_ca_cert}" >/dev/null 2>&1` succeeds, log `_info "[acg-up] Vault CA cert already trusted in System Keychain — skipping"` and return `0`.
     - If `security verify-cert -c "${_ca_cert}" >/dev/null 2>&1` fails and either stdin/stdout is not a TTY (`! [[ -t 0 && -t 1 ]]`) **or** the shell is an SSH session (`[[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]`, which lacks macOS Aqua GUI `SecurityAgent` access and fails with `SecTrustSettingsSetTrustSettings: The authorization was denied since no user interaction was possible`), **do not** invoke `security add-trusted-cert`. Instead, emit:
       `_warn "[acg-up] Skipping System Keychain Vault CA trust in headless session (macOS SecurityAgent requires interactive approval) — to trust manually, run: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${_ca_cert}"`
       and return `0`.
     - If `security verify-cert -c "${_ca_cert}" >/dev/null 2>&1` fails, both stdin and stdout are TTYs (`[[ -t 0 && -t 1 ]]`), and `[[ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]`, preserve the interactive path:
       - Log `_info "[acg-up] Trusting Vault CA cert in macOS System Keychain (may prompt for sudo password)..."`
       - Run:
         ```bash
         _run_command --interactive-sudo --soft -- \
           security add-trusted-cert -d -r trustRoot \
             -k /Library/Keychains/System.keychain \
             "${_ca_cert}" || \
           _warn "[acg-up] Could not add Vault CA to System Keychain — browser may show TLS warning for ArgoCD HTTPS"
         ```
       - Return `0`.
2. **`bin/cluster-up` (Step 4b/4c `/etc/hosts` helper wiring — `_acg_update_hosts_entry`):**
   - On M5 live verification (2026-11-03), the `/etc/hosts` loop immediately before Step 4c failed with `sh: line 4: /etc/hosts: Permission denied` because `bin/cluster-up` called `_run_command --prefer-sudo --soft -- sh -c "... > /etc/hosts"` instead of the scoped sudoers helper `/usr/local/bin/k3d-manager-update-hosts` installed by `bin/install-sudoers.sh`.
   - Extract `function _acg_update_hosts_entry()` in `bin/cluster-up` and call `_acg_update_hosts_entry "${_h}" "${_desired_ip}"` inside the `_HOSTS_LIST` loop in place of the inline `grep`/`_run_command --prefer-sudo --soft -- sh -c ...` block:
     - Take `local _h="$1" _desired_ip="$2"`.
     - Use `local _hosts_file="${K3DM_HOSTS_FILE:-/etc/hosts}"` and `local _update_hosts_bin="${K3DM_UPDATE_HOSTS_BIN:-/usr/local/bin/k3d-manager-update-hosts}"`.
     - Set `local _desired_host_entry="${_desired_ip} ${_h}"` and `local _current_host_entry`.
     - Read `_current_host_entry=$(grep -E "^[0-9.]+[[:space:]]+${_h//./\\.}$" "${_hosts_file}" 2>/dev/null | tail -n 1 || true)`.
     - If `[[ "${_current_host_entry}" == "${_desired_host_entry}" ]]`, return `0` without calling `_run_command`.
     - Log `_info "[acg-up] Updating /etc/hosts for ${_h} → ${_desired_ip} (requires sudo)..."`.
     - Decide the helper executable: if `[[ -x "${_update_hosts_bin}" ]]`, use `"${_update_hosts_bin}"`; otherwise use `"${REPO_ROOT}/bin/update-hosts-entry.sh"`.
     - Invoke `if _run_command --interactive-sudo --soft -- "${_helper}" "${_h}" "${_desired_ip}"; then _info "[acg-up] /etc/hosts: ${_h} → ${_desired_ip}"; else _warn "could not update /etc/hosts for ${_h} — please add manually: ${_desired_host_entry}"; fi` and return `0`.
     - Never invoke `sh -c` or `--prefer-sudo` for `/etc/hosts` updates.
3. **`bin/install-sudoers.sh`:**
   - Keep the ineffective `%admin ALL=(root) NOPASSWD: /usr/bin/security add-trusted-cert ...` rule removed and `/usr/local/bin/k3d-manager-update-hosts *` preserved.
4. **`scripts/tests/bin/cluster_up.bats` & `scripts/tests/bin/install_sudoers.bats`:**
   - Add isolated offline BATS tests covering `M1`–`M5` and `N1`–`N4` below. In `_run_vault_ca_trust_test`, explicitly clear `SSH_CONNECTION` and `SSH_TTY` by default unless the test passes an SSH simulation variable so tests running inside an SSH tmux session are hermetic.
5. **`CHANGELOG.md`:**
   - Update the `## [1.43.14] - Unreleased` bullet to mention skipping System Keychain Vault CA trust in headless/SSH sessions and updating `/etc/hosts` through `/usr/local/bin/k3d-manager-update-hosts`.

## Acceptance

```yaml
must:
  - id: M1
    req: when uname is Darwin, security verify-cert returns non-zero, stdin and stdout are TTYs, and SSH_CONNECTION/SSH_TTY are unset, _acg_trust_vault_ca invokes _run_command --interactive-sudo --soft -- security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <ca_cert> once (paired positive control for N1/N3), and logs the TLS warning while returning 0 if that command exits non-zero
  - id: M2
    req: when uname is Darwin and security verify-cert returns 0, _acg_trust_vault_ca logs that the Vault CA cert is already trusted and never invokes security add-trusted-cert (even in a headless or SSH session)
  - id: M3
    req: when uname is not Darwin (e.g. Linux), _acg_trust_vault_ca returns 0 without invoking security
  - id: M4
    req: when the desired host entry is missing or stale in K3DM_HOSTS_FILE and K3DM_UPDATE_HOSTS_BIN is executable, _acg_update_hosts_entry invokes _run_command --interactive-sudo --soft -- "$K3DM_UPDATE_HOSTS_BIN" <host> <ip> and logs "[acg-up] /etc/hosts: <host> → <ip>" on success or warns with the manual entry on failure
  - id: M5
    req: when the desired host entry is already present in K3DM_HOSTS_FILE, _acg_update_hosts_entry returns 0 without invoking _run_command
must_not:
  - id: N1
    req: when uname is Darwin, security verify-cert returns non-zero, and stdin or stdout is not a TTY (headless), _acg_trust_vault_ca never invokes security add-trusted-cert or _run_command, returns 0, and emits a warning naming SecurityAgent and the manual "sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain" command
  - id: N2
    req: bin/install-sudoers.sh (and bin/install-sudoers.sh --dry-run output) never grants NOPASSWD for /usr/bin/security or security add-trusted-cert
  - id: N3
    req: when uname is Darwin, security verify-cert returns non-zero, stdin and stdout are TTYs, and SSH_CONNECTION or SSH_TTY is non-empty, _acg_trust_vault_ca never invokes security add-trusted-cert or _run_command and emits the headless/SecurityAgent remediation warning
  - id: N4
    req: bin/cluster-up never uses "--prefer-sudo" or "sh -c" to write /etc/hosts directly
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, N1, N2, N3, N4]
    kind: offline
    intent: >-
      Isolated BATS tests in scripts/tests/bin/cluster_up.bats and scripts/tests/bin/install_sudoers.bats prove N3 and N4 fail (red) on pre-followup code (8d57ff9e) and M1-M5 + N1-N4 pass (green) on fixed code without touching real /etc/hosts or System Keychain.
    what: env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/bin/cluster_up.bats scripts/tests/bin/install_sudoers.bats
```

## Rules

- Touch only the 5 files listed under `## Files`. Do not create or modify any other files, and do not touch `memory-bank/`.
- Do not run `git add`, `git commit`, or `git push`. Leave changes in the working tree.
- Do not unset or override task-provided `K3DM_*` and `TMPDIR` environment variables.
- Run and paste the output of:
  - `bats scripts/tests/bin/cluster_up.bats scripts/tests/bin/install_sudoers.bats`
  - `shellcheck -x -S warning bin/cluster-up bin/install-sudoers.sh`
  - `git --no-pager diff --check`

## Independent cross-vendor diagnosis before replanning (2026-11-03)

**Status:** APPROVED FOR OPTION A (`narrow_patch`, 2026-11-03) — Gemini Argon read-only report attached below; operator reviewed findings on 2026-11-03 and authorized proceeding with Option A (`narrow_patch`) first before deciding whether to pursue broader sudoers/listener rework.

### Shared read-only investigation contract

Give each investigator the same frozen evidence bundle and file SHAs: incident job `c38c3855` and its 3,300-second hang; original observed log and process-state limitations; related v1.4.6 CA trust plan and v1.5.0/v1.5.3 bugs; Phase A diagnosis and artifacts; Terra Phase B/C changes and their **actual** branch/commit/diff; focused BATS/ShellCheck results; sudoers/supervisor design; M5 vs M4 behavior and absence of live reproduction. Include dispatch runs and measured rework only as **process evidence**, not proof of technical root cause. Retrieve current exact refs before preparing the bundle; do not assume all reported local commits are pushed.

1. **Muse Wonder / Muse Code (OPTIONAL, NOT FUNDED):** If separately approved and connected, independently trace the headless `acg-up` CA trust call path, privilege boundary, timeout supervisor, descendant cleanup, Keychain authorization behavior and whether broad changes are necessary. The operator reports a minimum $5/month Muse Code commitment; do not activate a paid subscription or make Muse review a dependency of the already-authorized Option A narrow patch.
2. **Gemini Argon:** independently challenge the leading stall hypotheses, identify missing falsification evidence and review root-helper trust boundaries, certificate identity/provenance, sudoers restrictions, listener migration and unattended failure semantics.
3. For any separately commissioned independent investigation, investigators must not receive one another's conclusions before finishing their first report. No production commands, real Keychain operations, AWS access, repository modification beyond an explicitly authorized evidence-only bug update, PR/merge, new spec, or unbounded implementation/rework loop. Prefer separate report artifacts linked here; if both edit this bug, apply their additions serially to avoid overwriting either analysis. An operator or coordinator must authenticate report attribution and ensure the report reflects actual execution.
4. Each report must state model/tool/version and execution date where known; actual input evidence + source SHAs; facts versus inference; ranked hypotheses and counterevidence; concrete file/line references; privilege/security concerns; **one smallest discriminating experiment** with predicted outcomes for competing hypotheses; test-environment limits; remaining unknowns; and tokens/cost where available. Return `INCONCLUSIVE` if the evidence does not support a root cause. The report is evidence to review, not a self-approved fix.
5. Use a bounded review budget and stop for operator approval before a second large context sweep, additional model spending, broad file expansion, or implementation. No arbitrary numeric token cap is assumed until the operator sets one.

### Synthesis and new plan decision gate

- **Current Option A path:** Argon's existing report and the operator's explicit narrow-patch approval are sufficient to proceed with the isolated Luna dispatch and offline evidence collection; the optional paid Muse report is **not a prerequisite**. After Luna exits, Argon reviews its actual diff, scope, evidence and failure modes; a separate independent reviewer (Claude when available, or another authorized reviewer) assesses the patch before landing as required by existing verification rules. A future Muse report, if separately commissioned, may augment but not retroactively block the approved narrow patch. Do not assume Argon/Claude succeeds automatically or that model majority establishes truth.
- Update this bug with a dated **evidence comparison and implementation outcome**: Argon's diagnosed facts/inferences, Luna's scoped patch and offline tests, outstanding contradictions and M5 live-verification limits, token/cost coverage where measured, and the existing operator decision `narrow_patch`. If a second independently funded diagnostic report later arrives, append its contrasting findings rather than overwriting this record.
- Do **not** replace Terra's Phase A/B/C record or silently mark acceptance/live verification complete. A new implementation plan is warranted only when the evidence changes the approach or acceptance contract; first amend the existing plan/bug if the correction is narrow, preserving release-slot rules.
- Treat the 2026-11-03 multi-run rework and repeated corrections as a P0 dispatch-stall historical regression case (see `docs/plans/v1.43.14-dispatch-stall-detection-and-escalation-gates.md`), while keeping causal diagnosis separate from model/token efficiency. Do not promote `resume.clarification` to independently verified progress.
- **2026-11-03 Operator Decision (`narrow_patch`):** Operator authorized dispatching Option A (`narrow_patch`) to Luna (`gpt-6-luna`) with a 3-run cap to land the narrow fix first before evaluating any broader sudoers/listener work.

### Subscription / investigation funding decision (2026-11-03)

- **Operator decision:** Muse Code reportedly requires a minimum **$5/month subscription**. This is an operator-observed price, not a verified entitlement or a budget authorization. **Do not subscribe, start pay-as-you-go usage, install Muse, or consume paid model capacity** for this incident without a new explicit approval. Record Muse status as `OPTIONAL_NOT_COMMISSIONED`, not `FAILED` or `MISSING_REQUIRED_EVIDENCE`.
- **Existing authorized path:** Gemini Argon coordinates the approved Option A narrow fix through the existing `k3dm-codex-dispatch` workflow using **GPT-6 Luna**, task slug `2026-11-02-acg-up-stalls-at-system-keychain-trust-fix`; screenshot reports Run 1 launched, maximum three runs, with the original Terra task/worktree retained untouched. Treat those as operator-observed dispatch status until verified in the ledger. Preserve separate worktrees, canonical bug identity, SHA-pinned evidence and scope.
- **Verification:** Do not let Argon self-review replace independent verification or promote an offline pass to live verified. Review exact Luna diff, tests, source SHA, headless skip semantics, and sudoers restriction. Landing under existing offline-approval rules is distinct from the separately authorized real M5 headless `cluster-up` validation.
- **Future escalation:** Consider an explicitly funded one-month Muse comparison only if Argon/Luna and the independent reviewer identify material unresolved security or architectural disagreements; first examine no-additional-cost options and measured potential value. No automatic expense or provider switch. Preserve the report contract above for any investigator later commissioned.

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

### Evidence comparison and Option A implementation outcome (2026-11-03)

- **Decision & Muse Status:**
  - **Chosen path:** `narrow_patch` (Option A), authorized by the operator on `2026-11-03`.
  - **Muse Wonder / Muse Code status:** `OPTIONAL_NOT_COMMISSIONED` (no subscription or paid usage activated).
  - **Original Phase B/C worktree:** `/Users/cliang/.local/share/k3d-manager/worktrees/v1.43.14/2026-11-02-acg-up-stalls-at-system-keychain-trust` (`f08a3775`, 24 runs) retained untouched in place.
- **Dispatched Implementation (`2026-11-02-acg-up-stalls-at-system-keychain-trust-fix`):**
  - **Worker / Coordinator:** OpenAI `gpt-6-luna` via `bin/k3dm-codex-dispatch` (session `01a1a424-3817-7220-a589-c31971e525cd`), coordinated by `google/gemini-4-argon-medium`.
  - **Run count:** **1 run** (`start` only, 0 resumes; well within the 3-run cap), `state: exited successfully (rc=0)`, `scope: in-scope`.
  - **Landed commit:** `8d57ff9e9451d2154bc36f9a1edf53ed817bd27c` (`8d57ff9e`), rebased onto `12b617026b5edbabf376f373acf1ac80beca410a` (`12b61702`).
  - **Scoped changes (5 files, +115 / -17 lines; `code: 44, tests: 87, docs: 1`):**
    1. `bin/cluster-up` (lines 150–174, 808): Extracted `_acg_trust_vault_ca()`. Non-Darwin returns `0`; already-trusted CA (`security verify-cert -c`) logs and returns `0`; headless Darwin (`! [[ -t 0 && -t 1 ]]`) skips `security add-trusted-cert` and emits `_warn` naming `SecurityAgent` and the manual `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <ca_cert>` command; interactive TTY Darwin (`[[ -t 0 && -t 1 ]]`) preserves `_run_command --interactive-sudo --soft -- security add-trusted-cert ...` with warning fallback.
    2. `bin/install-sudoers.sh` (lines 30–35, 130): Removed the ineffective `%admin ALL=(root) NOPASSWD: /usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain *` rule and updated the `sudo -l` verification hint.
    3. `scripts/tests/bin/cluster_up.bats` (lines 3–73): Added isolated stub tests for `M1` (interactive TTY positive control + warning on add failure), `M2` (already-trusted CA skipped in headless mode), `M3` (non-Darwin no-op), and `N1` (headless Darwin skip + remediation warning, no `security add-trusted-cert` or `_run_command` call).
    4. `scripts/tests/bin/install_sudoers.bats` (lines 5, 34–45): Added `N2` test verifying `bin/install-sudoers.sh` and `--dry-run` output never grant `NOPASSWD` to `/usr/bin/security` or `security add-trusted-cert`.
    5. `CHANGELOG.md` (line 7): Added `1.43.14` entry.
- **Offline Verification & Evidence (`verify-evidence.1.log`):**
  - **Pre-fix red (`12b61702`):** `N1` and `N2` failed (`pre_fix_rc: 1`) against pre-fix `bin/cluster-up` and `bin/install-sudoers.sh` while `M1`–`M3` passed.
  - **Post-fix green (`8d57ff9e`):** `env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/bin/cluster_up.bats scripts/tests/bin/install_sudoers.bats` passed all **81/81** tests (`rc: 0`); `shellcheck -x -S warning bin/cluster-up bin/install-sudoers.sh` exited `0`; `scripts/ci/fast_gate.sh` passed all 24 suites in 24s; `_agent_audit` exited `0`.
  - **Ledger verification artifact:** `v1.43.14/2026-11-02-acg-up-stalls-at-system-keychain-trust-fix.run/verify-evidence.1.log` (SHA-256 `381631e7d81c972abc861d55a1ac380041bd161a103ec10048438fd444d24a8f`, verifier `gemini-4-argon-medium`).
- **Token / Cost Coverage (from `ledger.jsonl`):**
  - `2026-11-02-acg-up-stalls-at-system-keychain-trust-fix` (run 1, `gpt-6-luna`, session `01a1a424-3817-7220-a589-c31971e525cd`): `input: 2,463,898` (`cached_input: 2,376,832`, uncached input: `87,066`), `output: 14,007` (`codex_exit` billed tokens: `101,073`).
  - `2026-11-02-acg-up-stalls-at-system-keychain-trust-m5-followup` (run 1, `gpt-6-luna`, session `01a1a450-60b4-7763-b362-42b95e7fefed`): `input: 2,213,209` (`cached_input: 2,120,960`, uncached input: `92,249`), `output: 12,920` (`codex_exit` billed tokens: `105,169`).
- **Live M5 Verification & Follow-Up Implementation (`2026-11-02-acg-up-stalls-at-system-keychain-trust-m5-followup`, `0b11c1f9`):**
  - **Live M5 confirmation of H1 (`SecTrustSettingsSetTrustSettings`):** On `m5-air` (`2026-11-03`), running `sudo /usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain .../ca.crt` in an SSH session returned:
    `SecTrustSettingsSetTrustSettings: The authorization was denied since no user interaction was possible.`
    This directly confirms H1: `SecTrustSettingsSetTrustSettings` requires interactive GUI `SecurityAgent` approval even when `security` runs as `root` via `sudo`. Over SSH (non-Aqua session), `authd` denies immediately with `errSecInteractionNotAllowed`; inside `k3dm-webhook` (`gui/$(id -u)` Aqua LaunchAgent), `authd` spawns a GUI `SecurityAgent` dialog and blocks until timeout.
  - **Follow-up fixes (`0b11c1f98099973e91b831a379130f164af47454`, 3 files, +104 / -22 lines; `code: 45, tests: 79, docs: 2`):**
    1. `bin/cluster-up` (`_acg_trust_vault_ca`): Extended the skip guard to `! [[ -t 0 && -t 1 ]] || [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]` so interactive SSH sessions also skip `security add-trusted-cert` with the headless remediation warning (`N3`, `M2`).
    2. `bin/cluster-up` (`_acg_update_hosts_entry`): Replaced the inline `_run_command --prefer-sudo --soft -- sh -c "... > /etc/hosts"` loop (`sh: line 4: /etc/hosts: Permission denied` on `m5-air`) with `_acg_update_hosts_entry`, which invokes `/usr/local/bin/k3d-manager-update-hosts <host> <ip>` (matching `NOPASSWD: /usr/local/bin/k3d-manager-update-hosts *` in `bin/install-sudoers.sh`) via `_run_command --interactive-sudo --soft --` (`M4`, `M5`, `N4`).
    3. `scripts/tests/bin/cluster_up.bats`: Added `N3`, `M4`, `M5`, and `N4` tests and extended `M2` for SSH sessions (`pre_fix_rc: 1` on `36e6a2d1`, `post_fix_rc: 0` with **85/85** passing in `cluster_up.bats` + `install_sudoers.bats`).
    4. **Ledger verification artifact:** `v1.43.14/2026-11-02-acg-up-stalls-at-system-keychain-trust-m5-followup.run/verify-evidence.1.log` (SHA-256 `958ab554bdf71fe28f2d04afdd8a90412367607085ebac35fbc73081fbcb7893`, verifier `gemini-4-argon-medium`).
  - **Live M5 end-to-end headless & Slack verification (`2026-11-03`, commit `73c14ac6`):**
    - Headless CLI run (`make up CLUSTER_PROVIDER=k3s-aws < /dev/null`) on `m5-air` skipped System Keychain CA trust cleanly at Step 4c and completed all steps.
    - Unattended Slack webhook run (`/k3dm acg-up`, job `4a9b212c` on `m5-air.local`, `~/.local/share/k3d-manager/webhook-jobs/4a9b212c/output`) completed all 14 steps + `deploy_observability --confirm` + `argocd_deploy_platform_ops` with `status: success` (`up complete`).
