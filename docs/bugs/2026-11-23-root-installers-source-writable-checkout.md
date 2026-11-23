# Bug: root installers source libraries from the operator-writable checkout

**Status:** OPEN — spec rev 2 (Fable + Argon review applied; pending operator intent approval)
**Priority:** P2 (operator, 2026-11-23: doc + bug, does not block v1.45.0)
**Introduced by:** v1.45.0 plans 2c, web-console A and C
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-23 (intent approval of rev 2)
**Triage:** patch → v1.45.1 (operator, 2026-11-23: "can you spec R2 and have Fable and Argon to review independently")
**Branch:** k3d-manager-v1.45.1
**Intent approved:** operator, 2026-11-23
**Approval:** operator, 2026-11-23 — intents of spec rev 2 approved ("approved"); dispatch after the Fable round-2 review findings are applied.
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** a same-uid process becomes root at the operator's next install; defeats the promote authority's goal of surviving a compromised operator uid.
**Findings:** Fable 3 (Medium). Claude: confirmed (`bin/k3dm-promote-authority:3-5` sources `scripts/lib/system.sh`, which provides `_run_command`, from the checkout).
**Reviews of rev 1 (11df6067):** Fable (B1-B7, S1-S10) and Argon (F-1 to F-15), independently, both NEEDS FIXES. Rev 2 adopts Fable's smaller design; every finding is mapped in [Rev 2 changes](#rev-2-changes).

## What is wrong

`bin/k3dm-promote-authority`, `bin/k3dm-web-console-sshd` and `bin/k3dm-web-console-totp` source `scripts/lib/system.sh` (and
`web_console_common.sh`) from the working tree, then run privileged steps through `_run_command` under the operator's sudo. Taking
payload blobs from `HEAD` (`k3dm-promote-authority:76-86`) protects the payload against uncommitted edits only: not the installer,
its sourced libraries, or a local commit.

The environment is a second path in. Each of these was reproduced on m4-air on 2026-11-23 (External behaviour):

- `CDPATH` hijacks the relative `cd -P "scripts/lib"` in `scripts/lib/system.sh:10`, so the web installers source an attacker's
  `foundation/scripts/lib/system.sh` (P7);
- an exported `SCRIPT_DIR` survives `scripts/lib/system.sh:12`, and the foundation library then sources
  `${SCRIPT_DIR}/lib/agent_rigor.sh` (P14);
- `DEVELOPER_DIR` makes `/usr/bin/git` run `$DEVELOPER_DIR/usr/bin/xcrun` (P8);
- promote-authority never sets `PATH`, so `id`, `mktemp`, `mkdir` and `_run_command`'s `sudo` lookup use the operator's PATH;
- `K3DM_WC_ROOT` plus a marker file puts the web installers in fixture mode, which replaces `_wc_priv` with shims;
- after an install the sudo ticket stays valid for 60 minutes (P9), for anything that can use the same terminal.

## Workaround (documented in docs/howto/promote-authority.md)

Run installs from a fresh clone of the protected remote ref, at a commit checked on a second channel. This defeats tampering done
before the clone only, not a watcher that edits the clone afterwards, and not the environment paths above.

## Threat model

**Attacker.** Any process running as the operator's uid: a compromised agent, tool, editor plugin or dependency. It can:

- edit any file in the checkout, including `.git/` (objects, refs, `config`, hooks);
- make local commits and move local refs;
- set environment variables for later processes (`launchctl setenv`, tmux global environment);
- put files earlier on PATH, for example in `~/.local/bin`, or in `/opt/homebrew`, which the operator's account owns;
- write `~/.gitconfig` and other per-user configuration;
- run continuously, so it can change a directory in the seconds between a clone and an install.

**Goal.** Become root the next time the operator runs one of the three installers with sudo, or use the sudo ticket the install
leaves behind.

**Defended by this fix** (when the operator uses `k3dm-verified-stage run`): everything the attacker can do by changing **files
and environment variables**: the working tree, local commits, `.git` objects and config, `~/.gitconfig`, PATH entries, `GIT_*`,
`BASH_ENV`, exported shell functions, `SHELLOPTS`, `CDPATH`, `SCRIPT_DIR`, `DEVELOPER_DIR`, `K3DM_WC_ROOT`; and a ticket left
valid after the run.

**Not defended (residuals, stated in the howto):**

1. **Control of the operator's interactive shell.** An attacker that can write `~/.zshrc`, `~/.zshenv` or set `ZDOTDIR` can
   alias or wrap even an absolute `/usr/bin/sudo` or the bootstrap path (P10). It can then fake the prompt, the bootstrap's output
   or the Touch ID request. No design run from that shell can defend against this. The only full mitigation is to run installs
   from a separate macOS admin account whose home directory the operator uid cannot write (Q2).
2. **The operator's GitHub credentials.** A same-uid process may read the operator's `gh` token.
   - For `main` it needs a token that can bypass the `main` ruleset (`bypass_actors: RepositoryRole`, P13).
   - For `--ref deploy/hub` or a release branch, which Q1 makes the routine cases, it needs **no** bypass: those branches have no
     ruleset, so any push token puts a commit there.
   - In both cases the only real anchor is the operator reading the commit on a second device (the iPad) before typing its hash.
     Reachability from the ref proves only that the commit is public.
3. **m4-air runs with SIP disabled** (P11). A `DYLD_INSERT_LIBRARIES` set for the operator's session loads into the operator's
   shell and into the first `/bin/bash` the bootstrap runs in, before any scrub. That is residual 1 again. The hub (m5-air) has
   SIP enabled.
4. **Operator-supplied data inputs** keep their current validation: `CA_FILE`, `--cloudflared-config`, `--tmux`,
   `~/.cloudflared/config.yml`, `OPERATOR_IDS`, and `HOME`, which `run` passes through. They are data, not code. `web-console-sshd
   check` runs `/opt/homebrew/bin/yq` as the operator to read cloudflared routes (`k3dm-web-console-sshd:275-277`). It never uses
   sudo, so a planted `yq` can only make `check` report a wrong result, which the same attacker could do by editing the config.
5. **The sudo ticket while the run lasts.** The web installers need the ticket to stay usable across their sudo calls
   (`web_console_common.sh:47-63`). While a run lasts, anything that shares its terminal can use the ticket: keystrokes sent into
   that pane with `tmux send-keys`, a background job started earlier in the same shell, or an operator-uid child an installer
   starts. `timestamp_timeout` is 60 minutes on m4-air (P9), and whether tickets are per-tty is unproven (P12; sudo 1.9 defaults
   to per-tty). `run` invalidates the ticket before and after the child, which bounds the window to the run itself.
6. **Direct runs get no scrub.** Running `<stage>/bin/<tool>`, or a checkout's `bin/<tool>` or `make` target, directly skips
   `run`'s environment allowlist. What still holds in a direct run:
   - every installer sets `PATH` itself;
   - promote-authority sets `SCRIPT_DIR` and unsets `CDPATH`;
   - CLT git ignores `DEVELOPER_DIR`;
   - `_wc_fixture_gate` refuses fixture mode under the stage base.

   What does not: `CDPATH` reaching the web installers' relative `source scripts/lib/system.sh`, `GIT_*` and `~/.gitconfig`
   reaching their git calls, and the checkout's own code. The `make` targets stay as they are (Q8). The howtos say to use `run`
   for every verb that uses sudo.

## Designs considered

| | Design | Defeats the file/env attacker? | Size | Verdict |
|---|---|---|---|---|
| a | Installer refuses unless run from a fresh clone at a verified commit | **No.** The check is code inside the clone, and git does not re-hash loose objects on read (P1) | small | rejected |
| b | Root-owned staging copy taken with `git show <commit>:path` **from the operator's `.git`**, run with `env -i` | **No.** P1, and root running git in the operator's repo runs its `.git/config` (`core.fsmonitor`, P5) | medium | rejected |
| b′ (rev 1) | Root-owned bootstrap fetches by fixed URL into a root-owned repo and stages the commit; installers carry a guard (`_k3dm_verified_stage_check` in `_wc_priv`/`priv`) and scrub `GIT_*` themselves | Partly. The guard and scrub are code in the stage, but the environment reaches the installer before the guard runs: `CDPATH`, `SCRIPT_DIR`, `DEVELOPER_DIR`, `K3DM_WC_ROOT` (B1-B5) | 1 new script, 5 changed scripts | **replaced by b‴** |
| b″ | b′, but the bootstrap runs the staged installer as root | Yes | large: both web-console installers refuse root by design (`k3dm-web-console-sshd:95`; `k3dm-web-console-totp:29-30`) | rejected |
| **b‴ (rev 2)** | b′'s root-owned bootstrap and stage, plus a `run <commit> <tool>` mode in the same root-owned file, run as the operator: it verifies the stage, then starts the staged installer from `/` under `/usr/bin/env -i` with an allowlist and drops the sudo ticket after it | **Yes**, for files and env: the scrub is root-owned code that runs before any installer line | 1 new script; small changes to 3 installers and 1 lib; no guard, no `system.sh` change | **recommended** |
| c | Signed tags verified against a key | No, unless the key is a hardware key that needs a touch | medium | out of scope (Q6) |
| d | Separate macOS admin account for installs | Yes, including residual 1 | operator setup, no code | optional hardening (Q2) |

**Why b‴ is the smallest design that works.** Trusted code has to start somewhere the attacker cannot write. That place is a
root-owned file installed once at the physical console, then updated only through itself. It now does two things: it stages a
commit (as root), and it starts a staged installer (as the operator) with an environment it builds itself. Root never runs git in
the operator's repository and never runs installer code. The installers keep running as the operator, as they do today, so their
own refusals stay as they are. Because the scrub lives in the bootstrap, the installers need no guard and no per-installer
`GIT_*` scrub. Their sudo wrapper `_wc_priv` and `_wc_main_env` stay byte-identical (B7, F-15).

## Fix (spec rev 2, Claude, 2026-11-23)

### F1. Bootstrap `bin/k3dm-verified-stage` (new)

The operator installs it once at `/usr/local/libexec/k3dm/k3dm-verified-stage`, `root:wheel 0755` (see Rollout). Three forms:

- `sudo /usr/local/libexec/k3dm/k3dm-verified-stage <commit> [--ref <branch>]` — stage mode (F1.4-F1.9);
- `sudo /usr/local/libexec/k3dm/k3dm-verified-stage --install-self <commit>` — self-update (F1.10);
- `/usr/local/libexec/k3dm/k3dm-verified-stage run <commit> <tool> [args…]` — run mode, **no sudo** (F1.11).

1. **Shell.** Shebang `#!/bin/bash -p`. In privileged mode bash 3.2.57 ignores `BASH_ENV`, `ENV`, exported functions and
   `SHELLOPTS` (P6). It does **not** ignore `CDPATH` (P7; rev 1's claim was wrong). Always `/bin/bash`, never Homebrew bash,
   because `/opt/homebrew` is writable by the operator (P11).
2. **Environment, first statements.** `unset CDPATH`, `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `LC_ALL=C`, `umask 022`. The
   bootstrap uses only absolute paths for programs and for `cd`. It does not re-exec itself: rev 1's "re-exec unless the
   environment is exactly the allowlist" could never be satisfied, because bash always exports `PWD` and `SHLVL` (P15, S5).
   Instead, every external program that reads configuration from the environment is started through `/usr/bin/env -i` with an
   explicit list:
   - git through `_vs_git` (F1.5);
   - the installer through `_vs_child_argv` (F1.11).

   Tests source the file and therefore run the same `env -i` paths (F-7). The `SUDO_*` variables are used by no step and are
   not read.
3. **Self-check (all modes).** `$0` resolves (`cd -P`) to a file, and the file and every ancestor directory pass `_vs_root_owned`:
   - owner uid 0 (`/usr/bin/stat -f '%u %Lp'`);
   - no group or other write bit;
   - no ACL entry (`/bin/ls -lde` shows no ` 0: ` line, P15).

   The same walk runs over `/Library/Developer/CommandLineTools/usr/bin/git` and its ancestors (F-4). Failure exits 3 with
   "bootstrap not root-owned".
4. **Arguments.** The commit must be exactly 40 lowercase hex characters. `--ref` defaults to `main` and must match
   `^[A-Za-z0-9._/-]+$` with no `..`. When it is not `main`, the output says `UNPROTECTED REF <name>` (P13). `--install-self`
   refuses `--ref` (S1). Stage mode and `--install-self` refuse unless `_vs_require_root` passes (EUID 0). Anything else exits 2.
5. **Git.** `_vs_git` runs `/usr/bin/env -i PATH=/usr/bin:/bin HOME=/var/empty GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 "$_VS_GIT" -c transfer.fsckObjects=true -c fetch.fsckObjects=true -c core.hooksPath=/dev/null -c credential.helper= "$@"`.
   `_VS_GIT` is `/Library/Developer/CommandLineTools/usr/bin/git`, which is root-owned and ignores `DEVELOPER_DIR` (P8, P11).
   Git runs only against `$_VS_BASE/repo.git` and the stage, never in the operator's checkout.
6. **Base and fetch.** `_VS_BASE` is the canonical `/private/var/db/k3dm-verified`, not `/var/db/…`, so `cd -P` results compare
   equal (F-3). On first use the bootstrap creates `$_VS_BASE` and `$_VS_BASE/stage` with
   `/usr/bin/install -d -o root -g wheel -m 0755`, and `repo.git` as a bare repo, `root:wheel 0700` (F-5). The URL is the
   constant `https://github.com/wilddog64/k3d-manager.git`, passed on the command line and never read from config. Fetch
   `+refs/heads/main`, `+refs/heads/deploy/hub` and the `--ref` branch into `refs/remotes/origin/*`. A failed fetch exits 4.
7. **Verify.** The commit must exist (`cat-file -e <c>^{commit}`) and satisfy
   `merge-base --is-ancestor <c> refs/remotes/origin/<ref>`. Otherwise exit 5 with the ref tips printed.
8. **Stage, always recreated** (S4, F-5). Path: `$_VS_BASE/stage/<c>`. The steps:
   - remove any `$_VS_BASE/stage/.tmp.*` left by an interrupted run;
   - `git clone --no-hardlinks --no-checkout $_VS_BASE/repo.git $_VS_BASE/stage/.tmp.<c>.$$`, then `checkout --detach <c>`;
   - write `.git/k3dm-verified` containing `<c>`;
   - `chown -R root:wheel`, `chmod -RN` (removes ACLs), `chmod -R go-w`;
   - remove the old `<stage>` if present, then `mv` the temp directory to `<stage>`.

   An existing stage is never reused. The stage stays readable by the operator, who can run it but not change it. A stage
   failure exits 6 and leaves no `<stage>`.
9. **Print, then stop.** Print these, in order, and exit 0:
   - the commit;
   - the tips of `origin/main`, `origin/deploy/hub` and `--ref`, and whether the commit equals each one;
   - `git ls-tree -r <c> --` for the installer set: the three installers, `scripts/lib/system.sh`,
     `scripts/lib/foundation/scripts/lib/system.sh`, `scripts/lib/web_console_common.sh`, `scripts/lib/agent_rigor.sh` and
     promote-authority's five `sources`;
   - the next commands in `run` form, without sudo, for example
     `/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-web-console-sshd install --ca-file /absolute/path`;
   - the line "run drops the sudo ticket when the installer exits (sudo -k)".

   Stage mode never runs an installer.
10. **`--install-self <c>`.** Run steps 4-8 for `<c>` against `main` only. Then copy `<stage>/bin/k3dm-verified-stage` to a temp
    file beside the target with `/usr/bin/install -o root -g wheel -m 0755`, and `mv` it into place. Print the old and new blob
    ids.
11. **`run <c> <tool> [args…]`** (operator, no sudo):
    1. Refuse when EUID is 0 (`_vs_euid`), exit 3: the installers must run as the operator.
    2. `<tool>` must be one of `k3dm-web-console-sshd`, `k3dm-web-console-totp`, `k3dm-promote-authority`. Otherwise exit 2.
    3. **Verify the stage** with `_vs_stage_ok "$_VS_BASE/stage/<c>"`; any failure exits 7 with "stage <c> not verified; run
       sudo k3dm-verified-stage <c>". It checks:
       - the path resolves (`cd -P`) to `$_VS_BASE/stage/<c>`;
       - every ancestor from the stage up to `$_VS_BASE` is owned by `$_VS_OWNER`, and every ancestor above `$_VS_BASE` by uid
         0, all with no group or other write bit and no ACL (S10);
       - every entry under the stage is owned by `$_VS_OWNER`, has no group or other write bit, and has no ACL entry
         (`/usr/bin/find <stage> ! -user …`, `-perm +022`, `/bin/ls -lReA`), and none is a symlink that points out of the
         stage;
       - `.git/k3dm-verified` holds `<c>`, and `rev-parse HEAD` equals `<c>`;
       - `status --porcelain --untracked-files=all --ignored` prints nothing.

       Git runs through `_vs_git`, with the stage passed as `safe.directory` (`-c safe.directory=<stage>` on the command line is
       not enough for a foreign-owned repo, so use `GIT_CONFIG_COUNT`, P3).
    4. **Arguments.** The value after `--ca-file`, `--cloudflared-config` or `--tmux` must start with `/`; otherwise exit 2 with
       "pass an absolute path". The working directory changes to `/` in the next step, so a relative path would point at the
       wrong file.
    5. `"$_VS_SUDO" -k` (default `/usr/bin/sudo`), so the installer's first sudo prompts afresh and no earlier ticket is used.
    6. `cd /`, then run the child given by `_vs_child_argv`:
       `/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=<HOME> LANG=<LANG or C> TERM=<validated or dumb> [TMUX=… TMUX_PANE=… STY=… SSH_CONNECTION=… SSH_TTY=… WEB_CONSOLE_SSH_PORT=…] GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=<stage> /bin/bash -p <stage>/bin/<tool> <args>`.
       - The bracketed names are copied only when set. `TMUX`, `TMUX_PANE`, `STY`, `SSH_CONNECTION` and `SSH_TTY` must pass
         through, because the installers' tmux and ssh refusals read them (`k3dm-web-console-totp:25`, the promote-authority enrol
         guard).
       - `HOME` must be absolute with no control character, and `TERM` must match `^[A-Za-z0-9._+-]{1,64}$`; a bad `HOME` exits
         2, a bad `TERM` becomes `dumb`.
       - Everything else is dropped: `CDPATH`, `SCRIPT_DIR`, `DEVELOPER_DIR`, `K3DM_WC_ROOT`, `BASH_ENV`, every `GIT_*`, every
         `DYLD_*` and `K3DM_*`.
       - The child starts as a child process, not via `exec`, so step 7 runs.
       - Bash adds `PWD`, `SHLVL`, `_` and `OLDPWD` itself; tests tolerate exactly those four.
    7. `"$_VS_SUDO" -k` again after the child exits, from a trap on `EXIT`, `INT` and `TERM` as well, then exit with the child's
       status.
12. **Structure and test seams** (S8). Logic lives in functions; `main` runs only when `"${BASH_SOURCE[0]}" = "$0"`.
    - The constants `_VS_BASE`, `_VS_URL`, `_VS_GIT`, `_VS_SELF_DIR`, `_VS_OWNER` (0) and `_VS_SUDO` are assigned
      unconditionally at the top, so nothing in the environment can set them. Tests source the file and then override them.
    - The functions tests may override: `_vs_require_root` (EUID check for stage mode), `_vs_euid` (prints EUID for run mode),
      `_vs_chown` (wraps `chown -R root:wheel`, which a normal user cannot run).
    - Printing helpers: `_vs_git_argv` and `_vs_child_argv` print the exact argv, one word per line, that `_vs_git` and the child
      launch use. Tests compare them with an expected list.
    - No `K3DM_VS_*` or other environment variable selects a test path.

### F2. Web-console installers (`bin/k3dm-web-console-sshd`, `bin/k3dm-web-console-totp`, `scripts/lib/web_console_common.sh`)

1. **Shebang** `#!/bin/bash -p` on both installers. `_wc_main_env` and `_wct_main_env` are unchanged.
2. **CLT git.** Every `/usr/bin/git` in both installers becomes `/Library/Developer/CommandLineTools/usr/bin/git`
   (`k3dm-web-console-sshd:7-23`, `:154-155`, `:679-682`; `k3dm-web-console-totp:83`, `:84`, `:88`, `:155`, `:370`). CLT git ignores
   `DEVELOPER_DIR` (P8). The fixture shim is keyed by basename (`web_console_common.sh:26`), so fixture tests are unaffected.
3. **Fixture gate refuses under the stage base** (B5). `web_console_common.sh` gains `_WC_VS_BASE=/private/var/db/k3dm-verified`,
   assigned unconditionally. `_wc_fixture_gate`, right after its `[[ ${K3DM_WC_ROOT+x} ]] || return 0` line, returns 2 when
   `$(pwd -P)/` starts with `$_WC_VS_BASE/`. Tests override `_WC_VS_BASE` after sourcing the lib.
4. **Drop the ticket on exit** (B6). `web_console_common.sh` gains `_wc_priv_close`:
   - in fixture mode, it appends `priv_close` to `$_WC_PREFIX/close.log`, a separate file so `calls.log` assertions do not change;
   - otherwise it runs `/usr/bin/sudo -k`.

   Each installer's `main` keeps its head (`function main() {` then `_wc_main_env`/`_wct_main_env`, asserted by
   `web_console_sshd.bats:932-948`) and changes its verb dispatch to `local rc=0`, `case … || rc=$?`, `_wc_priv_close`,
   `return "$rc"`. `_wc_priv_close` does not use `_run_command`, because `web_console_sshd.bats:941` asserts that
   `_run_command` appears exactly once in the lib plus the sshd installer. `sudo -k` invalidates a ticket and runs nothing as root.
5. **Unchanged:** `_wc_priv`, `_wc_priv_open`, `_wc_priv_ticket`, `_wc_main_env`, `_wct_main_env`, `scripts/lib/system.sh`,
   everything under `scripts/lib/foundation/`. There is no guard and no per-installer `GIT_*` scrub (`run` builds the environment).

### F3. promote-authority (`bin/k3dm-promote-authority`)

1. **Shebang** `#!/bin/bash -p`. This moves it from Homebrew bash 5.3 (via `env bash`) to `/bin/bash` 3.2; its tests run the file
   directly, so they cover that.
2. **First statements, before `repo=`** (B1, B2, B3/F-1). Each serves direct runs as well as `run`:
   - `PATH=/usr/bin:/bin:/usr/sbin:/sbin`;
   - `unset CDPATH`;
   - `unset -f sudo`;
   - `unset K3DM_AGENT_RIGOR_LIB_SOURCED`.

   After `repo=` and before the `source` line: `SCRIPT_DIR="$repo/scripts"`.
3. **Install ref** (M5). It no longer fetches.
   - An empty `INSTALL_REF` means `HEAD`.
   - A non-empty `INSTALL_REF` must resolve to the same commit as `HEAD^{commit}`; otherwise it dies with "INSTALL_REF must be
     the staged commit".
   - The `fetch origin refs/heads/deploy/hub` line (:72) is removed. The bootstrap fetches and shows whether the commit is the
     `deploy/hub` tip.
4. **values.json re-check** (S3, F-2, Q7). After the `hash-object` loop (:165-172) and before `render-check` (:173), outside plan
   mode: `actual=$(priv /bin/cat "$stage/values.json")` must equal the `printf` string written at :85, rebuilt from `id -u`,
   `id -g` and `$ids`. Otherwise it dies with "Staged values mismatch". `render-check` already re-renders from the staged
   `values.json` and the hash-checked daemon, so verifying `values.json` makes the rendered files covered too.
5. **Ticket drop** (B6). Every `trap … EXIT` the script sets (the `$tmp` trap at :77, the `cleanup` trap at :148-149) also runs
   `/usr/bin/sudo -k`, and the script sets `trap '/usr/bin/sudo -k' EXIT` right after the first statements. The absolute path
   keeps the source scan in `promote_authority.bats:144` green.
6. **No new variable names** (F-13). `test_promote_daemon.py:329-355` only allows the names already in `locals_used`. Item 3
   compares inline, item 4 reuses `actual`, and `PATH=`, `SCRIPT_DIR=` and `unset` are assignments, not `$` expansions.

## External behaviour

All probes: Claude, 2026-11-23, read-only or in the session scratchpad.

- m4-air: macOS 26.5.2, git 2.50.1 (Apple Git-155), `/bin/bash` 3.2.57, sudo 1.9.17p2, SIP disabled.
- m5-air (hub, over ssh, read-only): macOS 26.5.1, git 2.50.1 (Apple Git-155), `/bin/bash` 3.2.57, sudo 1.9.17p2.

P7, P8, P9, P14 and P15 are new in rev 2. Rev 1's P7-P10 are renumbered P10-P13.

| # | Probe (m4-air unless stated) | Result | Consequence |
|---|---|---|---|
| P1 | scratch repo: replace the loose object file for blob `12799cc…` (`good`) with a valid zlib object holding `evil`; run `cat-file blob <id>`, `cat-file -p HEAD:f` and `cat-file --batch` | all three print `evil` under the original id; only `git fsck` reports `hash-path mismatch` | a verified commit hash in a writable `.git` does not protect content |
| P2 | `git fetch file://<that repo> HEAD:refs/heads/x` into a fresh bare repo; once by default, once with `fetch.fsckObjects=true` | default: `missing blob object …`, rc 1, no ref. fsck: `index-pack failed`, rc 128 | the receiving side re-hashes every object, so a fetch into root-owned storage is the trust step |
| P3 | `GIT_TEST_ASSUME_DIFFERENT_OWNER=1` | `detected dubious ownership`. With `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=<dir>` git proceeds; `safe.directory` in the repo's own config does not help | `run` and `_vs_stage_ok` pass `safe.directory` through `GIT_CONFIG_COUNT` |
| P4 | read-only, foreign-owned clone; `ls-files --error-unmatch`, `diff --quiet HEAD --`, `rev-parse HEAD:<path>`, `cat-file blob HEAD:<path>` on the `_wc_sources` paths | rc 0, rc 0, a blob id, the content | the installers' existing git checks work in the stage |
| P5 | scratch repo with `core.fsmonitor` in `.git/config` | the command runs on `git status` and `git diff --quiet HEAD` | root never runs git in the operator's repo; `run` sets `GIT_CONFIG_GLOBAL=/dev/null` for the installers |
| P6 | `/bin/bash` 3.2.57 with `BASH_ENV=<marker script>`, `BASH_FUNC_id%%=…`, `SHELLOPTS=xtrace`; with and without `-p`, and under `env -i` | without `-p`: all three take effect. With `-p` or under `env -i`: none | `#!/bin/bash -p` everywhere |
| **P7** | `CDPATH=<evil> /usr/bin/env -i … /bin/bash -p` sourcing `scripts/lib/system.sh` by its relative path, as the web installers do, with `<evil>/scripts/lib/foundation/scripts/lib/system.sh` printing `CDPATH-PWNED` | `CDPATH-PWNED` printed; `_run_command` undefined | `-p` does not ignore `CDPATH`. `run` drops it, promote-authority unsets it, and residual 6 covers direct web-installer runs |
| **P8** | `DEVELOPER_DIR=<dir>` with `<dir>/usr/bin/xcrun` writing a marker; run `/usr/bin/git --version`, then `/Library/Developer/CommandLineTools/usr/bin/git --version` | `/usr/bin/git`: marker written. CLT git: no marker, normal output | the web installers move to CLT git (F2.2); `run` drops `DEVELOPER_DIR` |
| **P9** | `sudo -n -l` | `timestamp_timeout=60`; ticket type not shown | a ticket stays valid 60 minutes after an install; `run` and the installers run `sudo -k` |
| P10 | (earlier in this session) zsh 5.9.2 and bash 5.3.20: an alias and a function named `/usr/bin/sudo` | both replace the absolute path | residual 1 |
| P11 | `csrutil status`; ownership | m4-air: SIP **disabled**; m5-air: SIP enabled. `/usr/local` `root:wheel 0755` on both; `/usr/local/libexec` absent on both; `/`, `/private`, `/private/var`, `/private/var/db`, CLT `git` and each of its ancestors are uid 0 mode 755; `/opt/homebrew` belongs to the operator | residual 3; the walk in F1.3 passes on a stock system |
| P12 | `/etc/sudoers` | `root 0440`, unreadable: `env_reset`, `env_keep`, `secure_path` and `timestamp_type` are unproven | the bootstrap depends on none of them |
| P13 | `gh api repos/wilddog64/k3d-manager/rulesets` and `branches/main/protection` | one ruleset `main`: `deletion` and `non_fast_forward`, bypass `RepositoryRole`; 1 approving review, `enforce_admins: true`; public repo, 34 MB | `deploy/hub` and release branches are unprotected (Q1, residual 2) |
| **P14** | `SCRIPT_DIR=<evil> /bin/bash -p -c 'source <repo>/scripts/lib/system.sh'` with `<evil>/lib/agent_rigor.sh` printing `SCRIPT_DIR-PWNED` | `SCRIPT_DIR-PWNED` printed | promote-authority sets `SCRIPT_DIR` before its `source` (F3.2); the web installers already set `local SCRIPT_DIR=scripts` |
| **P15** | `/usr/bin/env -i /bin/bash -p -c 'compgen -e'`; a scratch file given `chmod +a "everyone allow write"`, then `/bin/ls -le`, `/bin/ls -lReA \| grep -cE '^ [0-9]+: '`, `chmod -RN`, count again | `PWD SHLVL`. ACL: mode shows `+`, one ` 0: group:everyone allow write` line; count 1, then 0 after `chmod -RN` | rev 1's self re-exec would loop (S5); the ACL check and `chmod -RN` work as specified |

## Contract readers

| Where | Reads / writes | Change |
|---|---|---|
| `bin/k3dm-promote-authority:1` | shebang `#!/usr/bin/env bash` | `#!/bin/bash -p` |
| `bin/k3dm-promote-authority:3-5` | `repo` via bare `dirname`, relative-capable `cd`; sources `scripts/lib/system.sh` | `PATH`, `unset CDPATH`, `unset -f sudo`, `unset K3DM_AGENT_RIGOR_LIB_SOURCED` first; `SCRIPT_DIR="$repo/scripts"` before the source |
| `bin/k3dm-promote-authority:58-75` | `INSTALL_REF`; `fetch origin refs/heads/deploy/hub` (:72) | no fetch; empty = `HEAD`; otherwise it must equal `HEAD` |
| `bin/k3dm-promote-authority:77`, `:148-149` | EXIT traps | each also runs `/usr/bin/sudo -k` |
| `bin/k3dm-promote-authority:85`, `:151-173` | writes `values.json` in the operator's temp dir; `ditto` to stage; hash-checks the 5 sources only | root re-reads the staged `values.json` and compares it with the expected string before `render-check` |
| `scripts/libexec/k3dm-promote-daemon.py:629-641` `render-check` | staged `values.json` and rendered files | unchanged; covered once `values.json` is checked |
| `scripts/tests/bin/test_promote_daemon.py:329-355` | allowlist of `$var` names in `bin/k3dm-promote-authority` | unchanged; child C adds no name (F3.6) |
| `scripts/tests/bin/promote_authority.bats:35-46` | `*/git` stub: `rev-parse --verify` prints `base` for any ref; anything else returns 99 | prints `base` for `HEAD^{commit}` and `base^{commit}`, another hash for any other ref (S9, F-12); a new `damage=values` mode tampers with the temp dir at the `ditto` call |
| `scripts/tests/bin/promote_authority.bats:120-136`, `:140-147` | `INSTALL_REF=HEAD` runs; source scan (no bare `sudo `, `_run_command --interactive-sudo` present) | stay valid (`/usr/bin/sudo -k` is not a bare `sudo`) |
| `scripts/tests/bin/promote_authority.bats:11-16` | Makefile target names, `not-installed.list:48-49` | unchanged |
| `Makefile:2509-2516` promote-authority targets; `Makefile:647-672` web-console targets; `Makefile:2421-2431` help | run `bin/…` from the checkout | unchanged (residual 6, Q8) |
| `scripts/etc/machine/not-installed.list:44-49` | web-console and promote-authority rows | unchanged |
| `bin/k3dm-web-console-sshd:1`, `bin/k3dm-web-console-totp:1` | `#!/bin/bash` | `#!/bin/bash -p` |
| `bin/k3dm-web-console-sshd:7-23`, `:154-155`, `:679-682`; `bin/k3dm-web-console-totp:83-88`, `:155`, `:370` | `/usr/bin/git` | CLT git |
| `bin/k3dm-web-console-sshd:743-772` `main`, `bin/k3dm-web-console-totp:519-546` `main` | verb dispatch; relative `source scripts/lib/system.sh`; `caller_dir` for `--ca-file`/`--cloudflared-config` | dispatch ends with `_wc_priv_close`; head unchanged. `run` passes absolute paths only, so `caller_dir="/"` changes nothing |
| `bin/k3dm-web-console-sshd:95-96`, `bin/k3dm-web-console-totp:25`, `:29-30` | refuse root; refuse inside tmux/screen | unchanged; `run` passes `TMUX`, `TMUX_PANE`, `STY` and refuses EUID 0 |
| `bin/k3dm-web-console-sshd:269-291` `_wc_route_file`/`_wc_check_routes` | `/opt/homebrew/bin/yq` as the operator in `check` | unchanged (residual 4, F-6) |
| `bin/k3dm-web-console-totp:356-360` | `$PWD` as the checkout for the tmux path check | `$PWD` is the stage |
| `scripts/lib/web_console_common.sh:15-17` `_wc_priv`, `:47-63` | `_run_command --interactive-sudo`; ticket reuse | **unchanged** (B7) |
| `scripts/lib/web_console_common.sh:32-45` `_wc_fixture_gate` | `K3DM_WC_ROOT` | refuses under `_WC_VS_BASE`; new `_WC_VS_BASE`, `_wc_priv_close` |
| `scripts/tests/bin/web_console_sshd.bats:932-948` | `_wc_priv` body, `_run_command` count == 1, `main` head, `_wc_main_env` body | stays green unchanged |
| `scripts/tests/bin/web_console_sshd.bats:133`, `:689`, `:1631`, `:1696`; `web_console_totp.bats:663` | call `_wc_priv`/`_wc_priv_open`/`_wc_revoke` outside fixture mode | unchanged: no guard was added (F-15) |
| `scripts/tests/bin/web_console_sshd.bats:815`, `:837`, `:886`, `:1015`, `:1139` | call `_wc_fixture_gate` from `$BATS_TEST_TMPDIR` | unchanged: not under the stage base |
| `scripts/tests/bin/web_console_sshd.bats:117-127`, `:1122-1135`; `web_console_totp.bats:40-64`, `:114-119` | exact sentences in the two web-console howtos; Makefile recipes | D keeps every grepped sentence (F-14) |
| `scripts/lib/system.sh`, `scripts/lib/foundation/scripts/lib/system.sh` `_run_command`, `_run_command_resolve_sudo` | sudo handling | **unchanged** |
| `docs/howto/promote-authority.md:3-18`, `:49`, `:78`, `:92-96` | install steps; fresh-clone workaround | `run` form; the workaround's gap |
| `docs/howto/web-console-sshd.md:8-22`, `docs/howto/web-console-totp.md:8-78` | `make …` commands | a "from a verified stage" section mapping each privileged target to its `run` form; existing sentences kept |
| **writer** (new) `bin/k3dm-verified-stage` | creates `/private/var/db/k3dm-verified/{repo.git,stage/<c>}` and `/usr/local/libexec/k3dm/` | new paths. promote-authority uses `/var/db/k3dm-promote` and `/usr/local/libexec/k3dm-promote` (`:9-11`), so nothing collides (grep: no `k3dm-verified` in `bin`, `scripts`, `Makefile`) |
| reader (new) `_wc_fixture_gate` | `/private/var/db/k3dm-verified` | new constant `_WC_VS_BASE` |
| R3 children `docs/plans/v1.45.1-totp-b-revoked-keys.md`, `v1.45.1-totp-c-guides.md` | also edit `bin/k3dm-web-console-sshd` and the web-console howtos | B and D dispatch after they land (one dispatch per file) |

## Acceptance

```yaml
must:
  M1: stage mode, run as root with a 40-hex commit reachable from the anchor ref, fetches by its constant URL into a root-owned bare repo with fsckObjects on, builds the stage in a temp directory and moves it to /private/var/db/k3dm-verified/stage/<c> (always recreated, owned by root, no group or other write bit, no ACL), writes .git/k3dm-verified = <c>, prints the commit, the main, deploy/hub and --ref tips, the installer-set blob ids and the next commands in run form, and exits 0 without running any installer
  M2: stage mode and --install-self exit non-zero before any fetch when not root, when the commit is not exactly 40 lowercase hex, or when --ref is malformed; stage mode prints UNPROTECTED REF for any --ref other than main
  M3: run mode, as the operator, with a verified stage and an allowlisted tool, runs sudo -k, changes to /, starts /bin/bash -p <stage>/bin/<tool> with exactly the allowlisted environment plus the fixed git variables, runs sudo -k again when the child exits for any reason, and exits with the child's status
  M4: every existing promote_authority, web_console_sshd and web_console_totp test and test_promote_daemon.py/test_web_console_totp.py pass; the only edits to existing test files are the promote stub's distinct rev-parse hashes, its damage=values mode, and new tests
  M5: promote-authority install treats an empty INSTALL_REF as HEAD and never runs git fetch
  M6: --install-self <c> replaces /usr/local/libexec/k3dm/k3dm-verified-stage with the stage's copy, root:wheel 0755, through a temp file and mv, prints old and new blob ids, and refuses --ref
  M7: scripts/lib/foundation/, scripts/lib/system.sh, and the bodies of _run_command, _run_command_resolve_sudo, _wc_priv, _wc_priv_open, _wc_priv_ticket, _wc_main_env and _wct_main_env are byte-identical to the base commit
  M8: both web installers call _wc_priv_close when any verb returns, success or failure; promote-authority's EXIT traps all run /usr/bin/sudo -k
  M9: promote-authority compares the root-owned staged values.json with the expected string before render-check and refuses activation on a mismatch
must_not:
  N1: stage mode creates a stage for a commit that is not an ancestor of the anchor ref on the fetched remote
  N2: stage mode stages content that differs from the commit's tree when the remote serves a corrupted object, reuses an existing stage directory, or runs git in any repository other than its own repo.git and the stage
  N3: a git call made by the bootstrap carries any environment variable outside its fixed list (GIT_DIR, GIT_CONFIG_PARAMETERS, BASH_ENV and an arbitrary variable set by the caller)
  N4: run mode starts an installer with any environment variable outside its allowlist, from a working directory other than /, as root, with a relative --ca-file/--cloudflared-config/--tmux value, or from a stage that fails any _vs_stage_ok condition (group-writable entry, ACL entry, entry owned by another uid, operator-owned ancestor above the base, wrong marker, HEAD different from the name, untracked or ignored file)
  N5: BASH_ENV, an exported function or SHELLOPTS in the environment takes effect inside the bootstrap or any installer
  N6: with CDPATH pointing at an attacker tree, a run-mode installer sources any file outside the stage
  N7: with SCRIPT_DIR pointing at an attacker tree, promote-authority sources any file outside its own repo, whether started through run or directly
  N8: with DEVELOPER_DIR pointing at an attacker tree, a web installer's git call executes a program from that tree
  N9: _wc_fixture_gate enables fixture mode when the working directory is under the stage base
  N10: run mode or a web installer returns without invalidating the sudo ticket (normal exit, failing verb, child killed by TERM)
  N11: promote-authority installs a payload from a commit other than its HEAD
  N12: promote-authority activates a payload whose staged values.json differs from the operator uid, gid and OPERATOR_IDS it was given
evidence:
  - {id: E1, proves: [M1, N1, N2], kind: offline, intent: "You will see tests source the bootstrap, point it at a scratch bare repo served over file:// and a scratch base, with the owner set to the test user and chown replaced, and find that a commit on main gets a stage with the right marker and tree; a commit only on a side branch is refused; a remote with one corrupted object fails with no stage left; a pre-existing stage holding an extra file is replaced; a leftover .tmp directory is removed; and the logged git argv carries both fsckObjects flags.", command: "bats scripts/tests/bin/verified_stage.bats", red: "today's tree: bin/k3dm-verified-stage does not exist, so every test fails"}
  - {id: E2, proves: [M2, M6, N3], kind: offline, intent: "You will see the bootstrap run as a normal user refuse at once; a short or uppercase commit, a bad --ref and --install-self with --ref refused; and the printed git argv, taken with GIT_DIR, GIT_CONFIG_PARAMETERS, BASH_ENV and an extra variable set in the caller, contain only the fixed names after env -i.", command: "bats scripts/tests/bin/verified_stage.bats", red: "missing file"}
  - {id: E3, proves: [M3, N4], kind: offline, intent: "You will see run mode tested against a scratch stage whose committed tool is a probe that writes its environment and working directory to a file: a good stage gives only the allowlisted names (plus PWD, SHLVL, _ and OLDPWD) and the directory /; then a group-writable file, an ACL entry, a file owned by another uid (faked by changing the owner setting), a wrong marker, a HEAD different from the name, an untracked file, an unknown tool name, a relative --ca-file and an EUID of 0 each stop before the probe runs, and no probe output appears.", command: "bats scripts/tests/bin/verified_stage.bats", red: "missing file"}
  - {id: E4, proves: [N6], kind: offline, intent: "You will see a scratch stage built from the working tree and an attacker tree whose foundation system.sh writes a marker. Run directly with CDPATH set, the sshd installer's check verb writes the marker, which shows the attack is live. Run through run mode with the same CDPATH, no marker appears.", command: "bats scripts/tests/bin/verified_stage.bats", red: "today's tree: run mode does not exist; the direct run (today's documented path) writes the marker (P7)"}
  - {id: E5, proves: [N5], kind: offline, intent: "You will see the bootstrap and the three installers started with BASH_ENV pointing at a script that writes a marker, an exported function named git, and SHELLOPTS=xtrace; no marker, no call to the function, no trace output.", command: "bats scripts/tests/bin/verified_stage.bats scripts/tests/bin/web_console_verified_stage.bats scripts/tests/bin/promote_authority.bats", red: "today's tree: promote-authority's env bash shebang lacks -p, so the BASH_ENV marker appears; the bootstrap is missing"}
  - {id: E6, proves: [N7], kind: offline, intent: "You will see promote-authority, in a scratch tree that has the real system.sh and foundation library, started directly with SCRIPT_DIR pointing at an attacker tree whose lib/agent_rigor.sh writes a marker; no marker. A control that sources system.sh with the same SCRIPT_DIR does write it.", command: "bats scripts/tests/bin/promote_authority.bats", red: "today's tree: promote-authority keeps the environment SCRIPT_DIR and the marker appears (P14)"}
  - {id: E7, proves: [N8], kind: offline, intent: "You will see the sshd and TOTP installers sourced outside fixture mode in a scratch stage, with DEVELOPER_DIR pointing at a tree whose usr/bin/xcrun writes a marker, and their source-check functions run against the real git: no marker. A control running /usr/bin/git --version with the same DEVELOPER_DIR writes it.", command: "bats scripts/tests/bin/web_console_verified_stage.bats", red: "today's tree: the installers call /usr/bin/git and the marker appears (P8)"}
  - {id: E8, proves: [N9], kind: offline, intent: "You will see _wc_fixture_gate called with a complete fixture root, once from a directory under an overridden stage base, where it refuses with 2, and once from a directory outside it, where it accepts.", command: "bats scripts/tests/bin/web_console_verified_stage.bats", red: "today's tree: the gate has no stage-base check and accepts under the base"}
  - {id: E9, proves: [M8, N10], kind: offline, intent: "You will see run mode with a logging sudo stand-in record sudo -k before and after the probe child, after a child that exits 3 (run then exits 3 as well) and after a child killed by TERM; and see fixture runs of a passing and a failing verb of each web installer leave priv_close in close.log; and see every EXIT trap line in promote-authority carry /usr/bin/sudo -k.", command: "bats scripts/tests/bin/verified_stage.bats scripts/tests/bin/web_console_verified_stage.bats scripts/tests/bin/promote_authority.bats", red: "today's tree: the bootstrap is missing, no installer writes close.log, and promote-authority's traps lack sudo -k"}
  - {id: E10, proves: [M5, N11], kind: offline, intent: "You will see promote-authority install, with a git stand-in that gives HEAD and another ref different hashes, run with INSTALL_REF empty, equal to HEAD, and naming the other commit; the first two install HEAD's blobs, the third is refused, and the call log has no fetch.", command: "bats scripts/tests/bin/promote_authority.bats", red: "today's tree: an empty INSTALL_REF logs git fetch origin refs/heads/deploy/hub, and the other commit is installed"}
  - {id: E11, proves: [M9, N12], kind: offline, intent: "You will see promote-authority install where the test changes operator_ids in the operator-owned temp values.json and re-renders it just before the copy into the stage; activation is refused with Staged values mismatch and nothing is bootstrapped.", command: "bats scripts/tests/bin/promote_authority.bats", red: "today's tree: render-check agrees with the tampered values and the payload activates with the attacker's operator_ids"}
  - {id: E12, proves: [M4], kind: offline, intent: "You will see the whole existing promote-authority, console sshd and console TOTP suites and both pytest files pass, and the git diff of the existing .bats files show only the stub change, the damage mode and new tests.", command: "bats scripts/tests/bin/promote_authority.bats scripts/tests/bin/web_console_sshd.bats scripts/tests/bin/web_console_totp.bats; python3 -m pytest scripts/tests/bin/test_promote_daemon.py scripts/tests/bin/test_web_console_totp.py", red: "regression guard: add a new $name to promote-authority and test_promote_daemon.py fails"}
  - {id: E13, proves: [M7], kind: offline, intent: "You will see a diff against the base commit that lists nothing under scripts/lib/foundation/ or scripts/lib/system.sh, and the seven named function bodies compared byte for byte.", command: "git diff --stat <base>..HEAD -- scripts/lib/foundation/ scripts/lib/system.sh; body comparison script", red: "regression guard: any edit to _wc_priv shows in the comparison and web_console_sshd.bats:939 fails"}
  - {id: E14, proves: [M6], kind: offline, intent: "You will see --install-self run against a scratch self-directory replace the bootstrap with the staged copy, leave no temp file behind and print both blob ids.", command: "bats scripts/tests/bin/verified_stage.bats", red: "missing file"}
  - {id: E15, proves: [M1, M3, N4, N10], kind: live, intent: "You will see the operator, at home on the hub's physical console, install the bootstrap, stage the release commit, compare the printed commit with GitHub on the iPad, run promote-authority print-plan and web-console-sshd check through run mode, and then see sudo -n true fail right after a run that used sudo. Claude reads the pasted output.", command: "operator, m5-air console: sudo /usr/local/libexec/k3dm/k3dm-verified-stage <c>; /usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-web-console-sshd check; ... run <c> k3dm-web-console-totp status; sudo -n true", red: "n/a (live)"}
interface:
  - "new: sudo /usr/local/libexec/k3dm/k3dm-verified-stage <40-hex commit> [--ref <branch>] | --install-self <40-hex commit>; exit 0 ok, 2 usage, 3 not root or bootstrap not root-owned, 4 fetch, 5 not reachable, 6 stage"
  - "new: /usr/local/libexec/k3dm/k3dm-verified-stage run <40-hex commit> k3dm-web-console-sshd|k3dm-web-console-totp|k3dm-promote-authority [args]; exit 2 usage or relative path argument, 3 run as root or bootstrap not root-owned, 7 stage not verified, otherwise the installer's status"
  - "new: _WC_VS_BASE and _wc_priv_close in scripts/lib/web_console_common.sh"
  - "changed: promote-authority INSTALL_REF must equal HEAD, empty means HEAD, no fetch; refuses a staged values.json mismatch"
  - "unchanged: _run_command, _wc_priv, scripts/lib/system.sh, Makefile targets, installer verbs and flags"
```

## Files

| # | File | New? | Child |
|---|---|---|---|
| 1 | `bin/k3dm-verified-stage` | new | A |
| 2 | `scripts/tests/bin/verified_stage.bats` | new | A |
| 3 | `scripts/lib/web_console_common.sh` | | B |
| 4 | `bin/k3dm-web-console-sshd` | | B |
| 5 | `bin/k3dm-web-console-totp` | | B |
| 6 | `scripts/tests/bin/web_console_verified_stage.bats` | new | B |
| 7 | `bin/k3dm-promote-authority` | | C |
| 8 | `scripts/tests/bin/promote_authority.bats` | | C |
| 9 | `docs/howto/verified-stage.md` | new | D |
| 10 | `docs/howto/promote-authority.md` | | D |
| 11 | `docs/howto/web-console-sshd.md` | | D |
| 12 | `docs/howto/web-console-totp.md` | | D |

12 files: 4 new, 8 changed (rev 1: 13). Dropped from rev 1: `scripts/lib/system.sh`, because the guard is gone. Source files per Luna
child: A 1, B 3, C 1. No Makefile change, nothing under `scripts/lib/foundation/`, no lib-foundation upstream change,
`test_promote_daemon.py` unchanged.

## Routing

Each child is its own `docs/plans/v1.45.1-r2-<letter>-*.md` with a slice of this Acceptance block. No two children share a file.

- **A — Luna** (`gpt-6-luna`): the bootstrap and its tests (E1, E2, E3, E4, E5 bootstrap part, E9 run part, E14). No
  dependencies. E4 builds its scratch stage from the working-tree installers and needs nothing from B or C.
- **B — Luna**: the web-console lib and installers (E5 web part, E7, E8, E9 web part, E12 web part, E13). It edits
  `bin/k3dm-web-console-sshd`, which R3's `totp-b` also edits, so B dispatches after `totp-b` lands.
- **C — Luna**: promote-authority (E5 promote part, E6, E9 promote part, E10, E11, E12 promote part). No dependencies.
- **D — Flash** (`gemini-3.8-flash-medium`): docs, after A-C and R3's `totp-c` land. Contents:
  - `verified-stage.md` covers the one-time bootstrap install at the physical console, stage then `run`, the second-channel check
    on the iPad, the six residuals, and the optional separate admin account;
  - each web-console howto gains a short section that maps every `make` target which uses sudo to its `run` form, and keeps
    every sentence that `web_console_sshd.bats:117-127` and `web_console_totp.bats:40-64` grep;
  - `promote-authority.md:92-96` says the fresh-clone workaround only defeats tampering done before the clone.

WIP: at most 3 open dispatches. A and C can go as soon as slots free. P2 does not exceed the limit.

## Worker definition of done (A-C)

- Change only your child's files. Work offline: no network (use a `file://` scratch remote), no sudo, no Keychain, nothing
  outside `$BATS_TEST_TMPDIR`. Assert the scratch base and HOME first.
- Never run the bootstrap's `main` as root or for real. Tests source it and override the F1.12 seams, or run the file as the
  normal user to check that it refuses. Do not invent environment-variable seams.
- Never run a real `sudo` other than `sudo -k`. Tests replace `_VS_SUDO` with a logging stand-in.
- Show each must_not test red on today's tree, then green. Mutations to show:
  - drop `-p` from one shebang;
  - pass `CDPATH` (A) or `DEVELOPER_DIR` (A) through the child allowlist;
  - restore `/usr/bin/git` in one web installer (B);
  - remove the stage-base check from `_wc_fixture_gate` (B);
  - remove `SCRIPT_DIR=` from promote-authority (C);
  - remove the `values.json` comparison (C);
  - make the bootstrap read the URL from `repo.git` config (A);
  - remove the `fsckObjects` flags (A): E1's argv assertion must go red.
- `shellcheck` on every changed script; `/bin/bash -n` on each; the full runs of the touched suites, with rc and counts.
- Leave changes uncommitted; no push; do not touch `docs/bugs/`. E15 belongs to the operator and Claude.

## Rollout (operator, at home, with sudo)

1. **Land A-D, then promote** (`make hub-deploy REF=<commit>`; the hub reads `deploy/hub`).
2. **First install of the bootstrap, at the hub's physical console.**
   - **On the iPad:** open
     `https://api.github.com/repos/wilddog64/k3d-manager/contents/bin/k3dm-verified-stage?ref=<c>` and note `sha` (the blob id).
   - **On the Mac:**
     - Download it as root, without your environment, so `~/.curlrc` cannot act:
       `sudo /usr/bin/env -i /usr/bin/curl -q -fsS -o /var/root/k3dm-verified-stage.new https://raw.githubusercontent.com/wilddog64/k3d-manager/<c>/bin/k3dm-verified-stage`
     - Hash it with a clean git environment, outside any repository (F-8):
       `sudo /usr/bin/env -i GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME=/var/empty /Library/Developer/CommandLineTools/usr/bin/git hash-object --no-filters /var/root/k3dm-verified-stage.new`
     - The hash must match the iPad. Then install it and remove the download:
       `sudo /usr/bin/install -d -o root -g wheel -m 0755 /usr/local/libexec /usr/local/libexec/k3dm`,
       `sudo /usr/bin/install -o root -g wheel -m 0755 /var/root/k3dm-verified-stage.new /usr/local/libexec/k3dm/k3dm-verified-stage`,
       `sudo /bin/rm -f /var/root/k3dm-verified-stage.new`
3. **Each later install, upgrade or uninstall:**
   - Read the commit on GitHub on the iPad.
   - Run `sudo /usr/local/libexec/k3dm/k3dm-verified-stage <c> [--ref <branch>]` and compare the printed commit and tips with
     the iPad.
   - Run the printed `/usr/local/libexec/k3dm/k3dm-verified-stage run <c> <tool> <verb> …` command, without sudo. It drops the
     ticket when the installer exits.
4. **Bootstrap updates** go through `--install-self <c>` (main only) and never through step 2 again.
5. **Re-run web-console on m4-air the same way.** Its SIP is disabled (residual 3, Q5).
6. **Claude reads the pasted output (E15).** Then the bug moves to `LIVE-VERIFIED`.

## Open questions

- **Q1 — anchor ref.** Only `main` is protected. promote-authority installs the `deploy/hub` commit, and release-time installs use
  the release branch; neither is protected.
  - Recommended: the default is `main`, and `--ref` is allowed with an `UNPROTECTED REF` banner. Residual 2 says the iPad check
    is the only anchor for those refs.
  - Alternative: refuse anything not on `main` until those branches get rulesets.
- **Q2 — separate admin account.** A dedicated macOS admin user for installs closes residual 1.
  - Recommended: document it as optional hardening, not required.
- **Q3 — stage pruning.** Stages are recreated per run but old commits' stages remain. Recommended: no automatic pruning in
  v1.45.1; the howto documents `sudo rm -rf /private/var/db/k3dm-verified/stage/<old>`.
- **Q4 — read-only verbs (decided in rev 2).** `web-console-sshd check` never calls sudo (`k3dm-web-console-sshd:336-365`), so
  it works from anywhere and needs no stage. `web-console-totp status`, `enroll` and `rotate` call sudo
  (`k3dm-web-console-totp:502-517`), and `promote-authority probe-deploy-key` and `ruleset-verified` call `priv`
  (`k3dm-promote-authority:43-48`). Those go through `run`.
- **Q5 — SIP on m4-air.** Disabled today, which widens residual 3. This is the operator's decision, outside this fix.
- **Q6 — hardware-backed signed tags** as a second anchor. Recommended: out of scope for v1.45.1; add a row to `docs/ideas.md`.
- **Q7 — answered (Fable S3, Argon F-2).** The post-copy re-check did **not** cover every rendered input.
  `values.json` (`k3dm-promote-authority:85`) was written in the operator-owned temp directory and copied unchecked, and
  `render-check` re-renders from it. A racing process could change `operator_ids`, which decides who approves promotes, and
  re-render to match. The fix is cheap (one root `cat` and a string compare, no new variable), so rev 2 fixes it in child C
  (F3.4, M9, N12, E11) instead of filing a P3.
- **Q8 — Makefile targets** (new). `make install-web-console-*` and `make promote-authority-install` still run checkout code
  under sudo (residual 6). Changing their recipes would break the recipe assertions in `web_console_sshd.bats:1122-1135` and
  `web_console_totp.bats:114-119`. Recommended: leave them in v1.45.1; the howtos point at `run`. Capture a P3 to make the
  privileged targets print the `run` command instead, if the operator wants it.

## Rev 2 changes

| Finding | Change in rev 2 |
|---|---|
| Fable B1 (CDPATH not ignored by `-p`) | F1.1 corrected; `run` drops `CDPATH`; bootstrap and promote-authority `unset CDPATH`; N6, E4; P7; residual 6 for direct web runs |
| Fable B2 (`SCRIPT_DIR` from env) | promote-authority sets `SCRIPT_DIR` before `source` (F3.2); `run` drops it; N7, E6; P14 |
| Fable B3 (PATH, bare sudo) | promote-authority sets `PATH` first and `unset -f sudo` (F3.2); `run` fixes PATH |
| Fable B4 (`DEVELOPER_DIR`) | web installers use CLT git (F2.2); `run` drops it; N8, E7; P8 |
| Fable B5 (`K3DM_WC_ROOT`) | `_wc_fixture_gate` refuses under the stage base (F2.3); `run` drops it; N9, E8 |
| Fable B6 (sudo ticket) | `run` runs `sudo -k` before and after the child, with traps; web installers `_wc_priv_close`; promote-authority traps; M8, N10, E9; P9; residual 5 |
| Fable B7 (`_wc_priv` body test) | moot: no guard, `_wc_priv` unchanged; M7 asserts it |
| Fable S1 (`--install-self` with `--ref`) | main only (F1.4, F1.10, M6) |
| Fable S2 (residual 2 understated) | residual 2 rewritten for `--ref` flows |
| Fable S3 (`values.json` not covered) | F3.4, M9, N12, E11; Q7 answered |
| Fable S4 (stage reuse) | stage always recreated via temp dir and `mv` (F1.8, N2) |
| Fable S5 (re-exec loops; `SUDO_*` unused) | no self re-exec; `env -i` per external program; `PWD`/`SHLVL`/`_`/`OLDPWD` tolerated; `TERM` validated; `SUDO_*` dropped; `cd /` (F1.2, F1.11); P15 |
| Fable S6 (E3 red false without a tty) | the guard and its tty-dependent test are gone; run mode is tested with a probe tool (E3); Q4 decided |
| Fable S7 (E4 red unproven in fixture mode) | git-related evidence runs outside fixture mode with real git (E4, E7) |
| Fable S8 (E2 not runnable; chown as normal user) | seams named in F1.12: `_VS_OWNER`, `_VS_SUDO`, `_vs_require_root`, `_vs_euid`, `_vs_chown`, `_vs_git_argv`, `_vs_child_argv` |
| Fable S9 (E6 vs M4; stub) | promote stub returns distinct hashes; M4 allows that edit (E10) |
| Fable S10 (walk fails in tests) | walk: owner up to the base, uid 0 above (F1.11.3) |
| Argon F-1 (PATH in promote-authority) | = B3 |
| Argon F-2 (`values.json` TOCTOU) | = S3 |
| Argon F-3 (`/var` symlink) | `_VS_BASE` and `_WC_VS_BASE` are `/private/var/db/k3dm-verified` (F1.6, F2.3) |
| Argon F-4 (ACLs; CLT git trust) | ACL check in every walk; CLT git ancestors walked (F1.3, F1.11.3); `chmod -RN` on the stage; P15 |
| Argon F-5 (partial stage) | `umask 022`, `install -d` for base dirs, temp dir and `mv`, leftover temp dirs removed (F1.6, F1.8) |
| Argon F-6 (`check` and yq) | partly **rejected**: `check` uses no sudo, so it needs no stage (Q4); the operator-uid `yq` stays and is named in residual 4, because it cannot reach root and replacing it is outside this bug |
| Argon F-7 (`env -i` bypassed when sourced; `compgen -e`) | accepted for git: every git call goes through `env -i` (F1.2, F1.5). `compgen` is moot: there is no per-installer scrub |
| Argon F-8 (rollout hash env, leftover file) | clean env on `hash-object`, `rm -f` after install (Rollout 2) |
| Argon F-9 (E3 red false; verbs missing) | = S6; `probe-deploy-key` and `ruleset-verified` named in Q4; E15 checks `totp status` live |
| Argon F-10 (fsck mutant not red) | E1 asserts the `fsckObjects` flags in the git argv; the mutation is listed in the DoD |
| Argon F-11 (E4 fixture shim) | = S7 |
| Argon F-12 (stub returns `base`) | = S9 |
| Argon F-13 (`test_promote_daemon.py` allowlist) | listed in Contract readers; F3.6 forbids new names; file not edited |
| Argon F-14 (doc greps; R3 ordering) | doc tests listed in Contract readers; D keeps the sentences; B after `totp-b`, D after `totp-c` |
| Argon F-15 (non-fixture `_wc_priv` tests) | moot: no guard, those tests stay unchanged |
| Directive (operator via Claude) | F1.11 runs the installer as a child, not via `exec`, so the bootstrap can run `sudo -k` after it |
