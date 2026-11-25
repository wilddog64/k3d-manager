# Verified Stage Bootstrap and Execution Guide

This guide documents the setup, execution, security model, and maintenance of the verified-stage bootstrap (`/usr/local/libexec/k3dm/k3dm-verified-stage`), introduced to secure privileged installer scripts against same-UID tampering in the operator checkout.

## Overview

Three installers in k3d-manager run privileged steps using `sudo`:
- `bin/k3dm-web-console-sshd`
- `bin/k3dm-web-console-totp`
- `bin/k3dm-promote-authority`

Historically, these installers sourced libraries (such as `scripts/lib/system.sh` and `web_console_common.sh`) directly from the working tree. Under that model, any process running under the operator's UID—such as a compromised dependency, editor extension, agent, or ambient shell environment—could modify scripts, plant malicious Git objects, alter configuration files, or export environment variables (`CDPATH`, `SCRIPT_DIR`, `DEVELOPER_DIR`, `K3DM_WC_ROOT`, `PATH`, `BASH_ENV`) that would execute with root privileges the next time an installer was invoked with `sudo`.

The verified-stage bootstrap solves this by ensuring that installer code executes only from a root-owned, immutable staging directory:
1. Git objects are fetched directly from the upstream repository into a dedicated root-owned bare repository (`/private/var/db/k3dm-verified/repo.git`) with `transfer.fsckObjects=true` and `fetch.fsckObjects=true`.
2. The target commit is verified to be an ancestor of an approved remote anchor reference (`main` by default, or `--ref <branch>`).
3. The commit tree is extracted into `/private/var/db/k3dm-verified/stage/<commit>`, owned strictly by `root:wheel` (mode `0755` directories and executables, `0644` files, no group or other write permissions, no ACL entries, and no symlinks outside `.git`).
4. Installers run as the operator via `run` mode under `/usr/bin/env -i` with a strict environment allowlist (`PATH`, passwd-derived `HOME`, `LC_ALL=C`, `TERM`, `safe.directory`), working directory set to `/`, `SIGTSTP` and `SIGQUIT` ignored so the run cannot be suspended or killed from the keyboard, and automatic `sudo -k` ticket invalidation before and after execution.

## Initial Bootstrap Installation (One-Time Setup)

The bootstrap executable must be installed once at the physical console of the hub machine (e.g. `m5-air`). Because the machine does not yet have a trusted local bootstrap, the initial download must be verified against an independent second channel.

Follow these steps exactly at the hub console:

1. **Check the blob hash on a second device (the iPad):**
   Open the GitHub API endpoint for the bootstrap script on the iPad:
   `https://api.github.com/repos/wilddog64/k3d-manager/contents/bin/k3dm-verified-stage?ref=<c>`
   Note the `sha` field (the Git blob object ID).

2. **Download the bootstrap script as root without ambient environment:**
   Use `/usr/bin/env -i` as root so that per-user configurations (such as `~/.curlrc`) cannot alter the download:
   ```bash
   sudo /usr/bin/env -i /usr/bin/curl -q -fsS -o /var/root/k3dm-verified-stage.new https://raw.githubusercontent.com/wilddog64/k3d-manager/<c>/bin/k3dm-verified-stage
   ```

3. **Hash the downloaded file in a clean Git environment:**
   Compute the Git object hash outside any repository:
   ```bash
   sudo /usr/bin/env -i GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME=/var/empty /Library/Developer/CommandLineTools/usr/bin/git hash-object --no-filters /var/root/k3dm-verified-stage.new
   ```
   Verify that the output matches the `sha` blob ID displayed on the iPad.

4. **Install the bootstrap binary and clean up:**
   ```bash
   sudo /usr/bin/install -d -o root -g wheel -m 0755 /usr/local/libexec /usr/local/libexec/k3dm
   sudo /usr/bin/install -o root -g wheel -m 0755 /var/root/k3dm-verified-stage.new /usr/local/libexec/k3dm/k3dm-verified-stage
   sudo /bin/rm -f /var/root/k3dm-verified-stage.new
   ```

5. **Invalidate the sudo ticket:**
   ```bash
   sudo -k
   ```

## Routine Workflow: Stage and Run

For every subsequent installation, upgrade, or verification of an installer, follow the two-step workflow: stage the verified commit, then run the tool.

### Step 1: Stage the Commit

Read the target commit hash on GitHub on the iPad.

Run the stage wrapper as the operator (**do not type sudo**; the wrapper manages sudo internally):
```bash
/usr/local/libexec/k3dm/k3dm-verified-stage stage <c> [--ref <branch>]
```
- `<c>` must be the **full 40-character commit hash**; a short hash is refused with `invalid commit`.
- If `--ref` is omitted, it defaults to `main`.
- A commit not yet merged to `main` (a release before its PR merges) is refused with `commit not reachable from main`; stage it with `--ref deploy/hub` once it has been promoted.
- If `--ref` is set to any branch other than `main` (for example, `--ref deploy/hub` or a release branch), the bootstrap prints an `UNPROTECTED REF <name>` notice to remind the operator that the branch lacks ruleset protection.
- The wrapper invalidates any existing sudo ticket (`sudo -k`), invokes the root staging step via `sudo`, and immediately invalidates the ticket again (`sudo -k`) upon completion or interruption.
- The bootstrap fetches into `/private/var/db/k3dm-verified/repo.git`, recreates `/private/var/db/k3dm-verified/stage/<c>`, writes the verified marker `.git/k3dm-verified`, strips ACLs (`chmod -RN`), removes write bits (`chmod -R go-w`), and prints:
  - The staged commit hash
  - The current remote tips of `origin/main`, `origin/deploy/hub`, and `--ref`
  - The blob ids of the staged installer and library files
  - The exact `run` commands to execute

Compare the printed commit hash and branch tips with GitHub on the iPad.

### Step 2: Run the Staged Installer

Execute the desired installer using `run` mode as the operator (**do not run as root or with sudo**):
```bash
/usr/local/libexec/k3dm/k3dm-verified-stage run <c> <tool> [args...]
```
where `<tool>` is one of:
- `k3dm-web-console-sshd`
- `k3dm-web-console-totp`
- `k3dm-promote-authority`

Common command examples:
```bash
# Web console SSH daemon:
/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-web-console-sshd install --ca-file /absolute/path
/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-web-console-sshd check

# Web console TOTP:
/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-web-console-totp enroll
/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-web-console-totp status
/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-web-console-totp rotate

# Promote authority:
/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-promote-authority print-plan
/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-promote-authority install OPERATOR_IDS=U0123ABCD,cli
/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-promote-authority probe-deploy-key
/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-promote-authority ruleset-verified PROBE_FILE=/absolute/path
```

During `run` mode:
1. The bootstrap verifies the stage (`_vs_stage_ok`): validates root ownership, permissions, absence of ACLs, absence of foreign symlinks, clean git status, and matching marker and HEAD.
2. Any argument passed to `--ca-file`, `--cloudflared-config`, `--tmux`, or `PROBE_FILE=` must be an absolute path (starting with `/`). `WEB_CONSOLE_SSH_PORT` must be 1 to 5 digits.
3. The sudo ticket is cleared (`sudo -k`) before launching the child. If that `sudo -k` fails, `run` refuses (exit 3) and the installer does not start.
4. `SIGTSTP` and `SIGQUIT` are ignored (`trap '' TSTP QUIT`) so `Ctrl-Z` or `Ctrl-\` cannot return the terminal to a prompt with a live ticket. The stage wrapper ignores them too.
5. The working directory changes to `/`.
6. The child starts under `/usr/bin/env -i` with an allowlisted environment:
   - `PATH=/usr/bin:/bin:/usr/sbin:/sbin`
   - `HOME` read from the passwd database for the operator UID via `/usr/bin/id -P`
   - `LC_ALL=C`
   - `TERM` (validated to match `^[A-Za-z0-9._+-]{1,64}$`, defaulting to `dumb`)
   - `TMUX=1`, `TMUX_PANE=1`, `STY=1`, `SSH_CONNECTION=1`, `SSH_TTY=1` (passed as `1` only if present in caller)
   - `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_COUNT=1`, `GIT_CONFIG_KEY_0=safe.directory`, `GIT_CONFIG_VALUE_0=/private/var/db/k3dm-verified/stage/<commit>`
7. The child runs as `/bin/bash -p <stage>/bin/<tool> "$@"`.
8. When the installer exits or if the process receives `HUP`, `INT`, or `TERM`, the sudo ticket is invalidated again (`sudo -k`).

## Bootstrap Self-Updates

Updates to the bootstrap binary itself are performed using `--install-self`:
```bash
/usr/local/libexec/k3dm/k3dm-verified-stage stage --install-self <c>
```
- The operator runs this wrapper without typing `sudo`.
- Updates are restricted to commits on `main` only (`--ref` is refused).
- The wrapper re-enters the bootstrap with `sudo`, stages the commit, verifies the staged bootstrap (`<stage>/bin/k3dm-verified-stage`), installs it to `/usr/local/libexec/k3dm/k3dm-verified-stage` via a root-owned temporary file, and prints the previous and new Git blob object IDs.
- Never use the manual `curl` installation procedure for subsequent updates.

## Command Forms and Exit Codes

| Mode | Command Form | Caller | Exit Codes | Description |
| --- | --- | --- | --- | --- |
| Stage wrapper | `/usr/local/libexec/k3dm/k3dm-verified-stage stage <40-hex commit> [--ref <branch>]` | Operator (no sudo typed) | `2`: Usage error (malformed commit or ref)<br>`3`: Invocation error (must not be run as root, or the first `sudo -k` failed)<br>Otherwise: Inner status of stage command | Validates arguments, clears sudo ticket (`sudo -k`), calls root stage form via sudo, and clears ticket on exit |
| Self-install wrapper | `/usr/local/libexec/k3dm/k3dm-verified-stage stage --install-self <40-hex commit>` | Operator (no sudo typed) | `2`: Usage error (malformed commit)<br>`3`: Invocation error (must not be run as root)<br>Otherwise: Inner status of `--install-self` | Wraps self-install re-entry via sudo with `sudo -k` |
| Root stage | `sudo /usr/local/libexec/k3dm/k3dm-verified-stage <40-hex commit> [--ref <branch>]` | Root (EUID 0) | `0`: Success<br>`2`: Usage error<br>`3`: Caller not root, bootstrap not root-owned, or executed path is not `/usr/local/libexec/k3dm/k3dm-verified-stage`<br>`4`: Git fetch failed<br>`5`: Commit not reachable from anchor ref<br>`6`: Stage directory creation or verification failed | Root stage engine: fetches into bare repo, checks reachability, clones fresh stage, verifies permissions, prints tips and run commands |
| Root self-install | `sudo /usr/local/libexec/k3dm/k3dm-verified-stage --install-self <40-hex commit>` | Root (EUID 0) | `0`: Success<br>`2`: Usage error (commit format or `--ref` supplied)<br>`3`: Not root, bootstrap not root-owned, or wrong path<br>`4`: Git fetch failed<br>`5`: Commit not reachable from `main`<br>`6`: Stage failure or self-install atomic replacement failed | Stages commit from `main`, installs staged bootstrap binary to `/usr/local/libexec/k3dm/k3dm-verified-stage`, prints old and new blob hashes |
| Run | `/usr/local/libexec/k3dm/k3dm-verified-stage run <40-hex commit> <tool> [args...]` | Operator (no sudo typed) | `2`: Usage error (unknown tool, non-absolute path in `--ca-file`/`--cloudflared-config`/`--tmux`/`PROBE_FILE=`, invalid port, or invalid passwd home)<br>`3`: Invocation error (EUID 0 / run as root, bootstrap not root-owned, or the pre-run `sudo -k` failed)<br>`7`: Stage verification failed (`_vs_stage_ok`)<br>`128+n`: Terminated by signal `n` (e.g. `129` HUP, `130` INT, `143` TERM)<br>Otherwise: Exit status of the invoked installer tool | Verifies stage integrity, invalidates sudo ticket (`sudo -k`), sets `trap '' TSTP QUIT`, changes directory to `/`, launches `/bin/bash -p <stage>/bin/<tool>` under `env -i`, and clears ticket on exit |

## Stage Pruning

Stages are recreated on each staging run for a given commit. Older commit stages in `/private/var/db/k3dm-verified/stage/` are not pruned automatically, and an old or rejected stage stays runnable through `run` (there is no anti-rollback check). Remove a stage you rejected after comparing it on the iPad.

To inspect or remove older stages:
```bash
sudo rm -rf /private/var/db/k3dm-verified/stage/<old-commit>
```

## Threat Model and Residuals

The verified-stage bootstrap defends against attackers running with the operator's UID who attempt to escalate to root by tampering with working tree files, Git objects or configuration, or environment variables.

The following six limitations (residuals) are not fully defended by the bootstrap alone:

1. **Control of the operator's interactive shell:**
   An attacker who can write to shell configuration files (`~/.zshrc`, `~/.zshenv`) or set `ZDOTDIR` can define shell aliases or wrapper functions for `/usr/bin/sudo` or the bootstrap path. The attacker could fake prompts, Touch ID requests, or command outputs. The only complete mitigation is to run installs from a dedicated macOS admin account whose home directory is not writable by the operator UID.

2. **The operator's GitHub credentials:**
   A same-UID process may access GitHub tokens (e.g. from `gh`). While `main` has branch protection rules requiring pull request reviews, branches like `deploy/hub` or release branches may not have branch rulesets. In those cases, reachability from the ref proves only that the commit is public on GitHub. The true security anchor is the operator reading the commit hash and branch tips on an independent second device (the iPad) before typing the hash and executing commands.

3. **System Integrity Protection (SIP) state on development machines:**
   On `m4-air`, System Integrity Protection (SIP) is disabled, allowing `DYLD_INSERT_LIBRARIES` to inject code into the operator shell session and into `/bin/bash` prior to any scrub. The production hub (`m5-air`) operates with SIP enabled, preventing dynamic library injection into system binaries.

4. **Operator-supplied data inputs:**
   Data arguments (`CA_FILE`, `--cloudflared-config`, `--tmux`, `PROBE_FILE=`, `~/.cloudflared/config.yml`, and `OPERATOR_IDS`) are validated as data, not executed as code. For example, `k3dm-web-console-sshd check` runs `/opt/homebrew/bin/yq` without `sudo` to inspect routes; a malicious `yq` could alter diagnostic output, but cannot obtain root.

5. **The sudo ticket while live (best-effort defence):**
   The web-console installers require the sudo ticket to remain valid across multiple internal sudo invocations. On `m4-air` and the hub (`m5-air`), `sudo -V` probes confirm that the timestamp record type is `tty` with a `60.0 minutes` timeout (`/var/db/sudo/ts`).
   The bootstrap provides best-effort containment:
   - `stage` and `run` clear the ticket before and after execution (`sudo -k`).
   - `run` and the stage wrapper ignore `SIGTSTP` and `SIGQUIT` so `Ctrl-Z` or `Ctrl-\` cannot return the terminal to a prompt with an active ticket.
   - A `tty` ticket is shared by every process in the same terminal session, including background jobs and agents started from that shell. Run `stage` and `run` from a terminal that no agent shares.
   - The ticket clear on `HUP`, `INT` or `TERM` waits until the installer exits, because bash runs those traps only after its foreground child ends.
   However, if a same-UID process sends `SIGSTOP` (which cannot be caught or ignored) or `SIGKILL` to the process, or if keystrokes are injected into the active terminal while an installer prompts for input, the live ticket could be accessed before invalidation. The only complete mitigation is the separate admin account.

6. **Direct runs bypass the environment scrub:**
   Executing `<stage>/bin/<tool>`, a checkout's `bin/<tool>`, or `make` targets directly bypasses the `run` mode allowlist and scrub. While web-console installers invoke Command Line Tools Git (`/Library/Developer/CommandLineTools/usr/bin/git`) which ignores `DEVELOPER_DIR`, other variables (`CDPATH`, `SCRIPT_DIR`, `PATH`, `BASH_ENV`, `GIT_*`, `~/.gitconfig`, `K3DM_WC_ROOT`) could reach a direct run. Always use `/usr/local/libexec/k3dm/k3dm-verified-stage run <c> <tool>` for every operation that uses sudo.

## Optional Hardening: Dedicated Admin Account

To eliminate Residual 1 (shell compromise) and Residual 5 (sudo ticket misuse), operators may optionally configure a dedicated macOS administrator user account solely for managing system installations and upgrades:
- The standard operator account is used for everyday development.
- The dedicated admin account owns its own clean home directory, which the operator UID cannot write.
- When performing installs, log in as the dedicated admin user directly at the physical console (or switch to the admin user in a clean session) and execute the bootstrap commands.
