# Bug: root installers source libraries from the operator-writable checkout

**Status:** OPEN — spec rev 3 (Fable round 2 applied; scope cut to 8 files; pending operator re-approval of changed intents and the P12 probe)
**Priority:** P2 (operator, 2026-11-23: doc + bug, does not block v1.45.0)
**Introduced by:** v1.45.0 plans 2c, web-console A and C
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-23 (P12 probe: `tty` on both hosts)
**Triage:** patch → v1.45.1 (operator, 2026-11-23: "can you spec R2 and have Fable and Argon to review independently")
**Branch:** k3d-manager-v1.45.1
**Intent approved:** operator, 2026-11-23
**Approval:** operator, 2026-11-23 — intents of spec rev 2 approved ("approved"); dispatch after the Fable round-2 review findings are applied. Operator, 2026-11-23, on Fable round 2: scope cut to about 8 files, direct-run hardening deferred to a P3 ("Cut to ~8 files"); `run` is allowed inside tmux, with Ctrl-Z blocked and the sudo ticket cleared afterwards ("Allow, block Ctrl-Z"). Rev 3 changed intents (E1-E5, E7, E9, E12, E15) re-approved by the operator, 2026-11-23 ("approved"); dispatch of child A also waits on the P12 probe.
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** a same-uid process becomes root at the operator's next install; defeats the promote authority's goal of surviving a compromised operator uid.
**Findings:** Fable 3 (Medium). Claude: confirmed (`bin/k3dm-promote-authority:3-5` sources `scripts/lib/system.sh`, which provides `_run_command`, from the checkout).
**Reviews:** rev 1 (11df6067): Fable (B1-B7, S1-S10) and Argon (F-1 to F-15), independently, both NEEDS FIXES; mapped in [Rev 2 changes](#rev-2-changes). Rev 2 (e350217d): Fable round 2 (B1-B2, S1-S8, nits), NEEDS FIXES; mapped in [Rev 3 changes](#rev-3-changes).
**Deferred:** direct-run hardening of the installers → [2026-11-23-installer-direct-run-hardening-deferred.md](2026-11-23-installer-direct-run-hardening-deferred.md) (P3).

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
- `POSIXLY_CORRECT` reaches a `/bin/bash -p` script and changes its parsing (P16);
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
- run continuously, so it can change a directory in the seconds between a clone and an install;
- type into the operator's terminal with `tmux send-keys` (Enter, `C-z`, a whole `sudo …` line) and signal the operator's
  processes (`kill -STOP`, `kill -KILL`), because tmux and those processes run as the same uid.

**Goal.** Become root the next time the operator runs one of the three installers with sudo, or use the sudo ticket the install
leaves behind.

**Defended by this fix** (when the operator uses `k3dm-verified-stage stage` and `run`): everything the attacker can do by
changing **files and environment variables**: the working tree, local commits, `.git` objects and config, `~/.gitconfig`, PATH
entries, `GIT_*`, `BASH_ENV`, exported shell functions, `SHELLOPTS`, `POSIXLY_CORRECT`, `CDPATH`, `SCRIPT_DIR`, `DEVELOPER_DIR`,
`K3DM_WC_ROOT`. The sudo ticket is cleared after `stage` and after `run` (best-effort, residual 5).

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
4. **Operator-supplied data inputs** keep their current validation: `CA_FILE`, `--cloudflared-config`, `--tmux`, `PROBE_FILE=`,
   `~/.cloudflared/config.yml` and `OPERATOR_IDS`. They are data, not code. `web-console-sshd check` runs `/opt/homebrew/bin/yq`
   as the operator to read cloudflared routes (`k3dm-web-console-sshd:275-277`). It never uses sudo, so a planted `yq` can only
   make `check` report a wrong result, which the same attacker could do by editing the config.
5. **The sudo ticket while it is live (best-effort only).** The web installers need the ticket to stay usable across their sudo
   calls (`web_console_common.sh:47-63`), and `timestamp_timeout` is 60 minutes on m4-air (P9). `stage` and `run` clear the
   ticket before and after their sudo use, and `run` ignores `SIGTSTP` so `C-z` typed into the pane cannot return it to a
   prompt mid-run. What still gets the ticket:
   - `kill -STOP` (cannot be ignored) or `kill -KILL` of `run` or its child from any same-uid process: the pane returns to a
     prompt with the ticket live and no trap runs;
   - keystrokes typed into the pane while a run is waiting at an installer prompt, which the installer reads as input;
   - any same-uid process using `sudo -n` while the ticket is live, if the ticket is not per-tty. Whether it is depends on
     `timestamp_type`, which is unproven (P12) and is a pre-dispatch gate for child A.

   The window is therefore bounded by the run only when the attacker does not stop or kill it. The only full mitigation is the
   separate admin account (Q2).
6. **Direct runs get no scrub.** Running `<stage>/bin/<tool>`, or a checkout's `bin/<tool>` or `make` target, directly skips
   `run`'s environment allowlist and gets none of this fix's environment defences. The web installers' CLT git (F2) still ignores
   `DEVELOPER_DIR`; nothing else holds: `CDPATH`, `SCRIPT_DIR`, `PATH`, `BASH_ENV`, `GIT_*`, `~/.gitconfig` and `K3DM_WC_ROOT` all
   reach the installer, and so does the checkout's own code. Hardening direct runs (shebangs, promote-authority's first
   statements, the fixture gate, ticket drops) is deferred to the P3 named under **Deferred**. The `make` targets stay as they
   are (Q8). The howtos say to use `run` for every verb that uses sudo.

## Designs considered

| | Design | Defeats the file/env attacker? | Size | Verdict |
|---|---|---|---|---|
| a | Installer refuses unless run from a fresh clone at a verified commit | **No.** The check is code inside the clone, and git does not re-hash loose objects on read (P1) | small | rejected |
| b | Root-owned staging copy taken with `git show <commit>:path` **from the operator's `.git`**, run with `env -i` | **No.** P1, and root running git in the operator's repo runs its `.git/config` (`core.fsmonitor`, P5) | medium | rejected |
| b′ (rev 1) | Root-owned bootstrap fetches by fixed URL into a root-owned repo and stages the commit; installers carry a guard (`_k3dm_verified_stage_check` in `_wc_priv`/`priv`) and scrub `GIT_*` themselves | Partly. The guard and scrub are code in the stage, but the environment reaches the installer before the guard runs: `CDPATH`, `SCRIPT_DIR`, `DEVELOPER_DIR`, `K3DM_WC_ROOT` (B1-B5) | 1 new script, 5 changed scripts | **replaced by b‴** |
| b″ | b′, but the bootstrap runs the staged installer as root | Yes | large: both web-console installers refuse root by design (`k3dm-web-console-sshd:95`; `k3dm-web-console-totp:29-30`) | rejected |
| **b‴ (rev 2, cut in rev 3)** | b′'s root-owned bootstrap and stage, plus a `run <commit> <tool>` mode in the same root-owned file, run as the operator: it verifies the stage, then starts the staged installer from `/` under `/usr/bin/env -i` with an allowlist and drops the sudo ticket after it | **Yes**, for files and env: the scrub is root-owned code that runs before any installer line | 1 new script; CLT git path substitution in 2 installers; 2 small promote-authority changes; no guard, no lib change | **recommended** |
| c | Signed tags verified against a key | No, unless the key is a hardware key that needs a touch | medium | out of scope (Q6) |
| d | Separate macOS admin account for installs | Yes, including residuals 1 and 5 | operator setup, no code | optional hardening (Q2) |

**Why b‴ is the smallest design that works.** Trusted code has to start somewhere the attacker cannot write. That place is a
root-owned file installed once at the physical console, then updated only through itself. It does two things: it stages a commit
(as root), and it starts a staged installer (as the operator) with an environment it builds itself. Root never runs git in the
operator's repository and never runs installer code. The installers keep running as the operator, as they do today, so their own
refusals stay as they are. Because the scrub lives in the bootstrap and the child starts as `/bin/bash -p` under `env -i`, the
installers need no guard, no shebang change and no per-installer scrub for the `run` path. Rev 3 keeps only the installer changes
that matter under `run`: CLT git (the `/usr/bin/git` shim resolves through `xcrun`, whose per-user cache is believed
operator-writable; unprobed, because probing writes the real cache) and promote-authority's install-ref and `values.json` checks,
which guard a root step against the operator-owned temp directory.

## Fix (spec rev 3, Claude, 2026-11-23)

### F1. Bootstrap `bin/k3dm-verified-stage` (new)

The operator installs it once at `/usr/local/libexec/k3dm/k3dm-verified-stage`, `root:wheel 0755` (see Rollout). Forms:

- `/usr/local/libexec/k3dm/k3dm-verified-stage stage <commit> [--ref <branch>]` — **operator-run wrapper, no sudo typed**
  (F1.13): clears the ticket, runs stage mode through sudo, clears the ticket again;
- `/usr/local/libexec/k3dm/k3dm-verified-stage stage --install-self <commit>` — the same wrapper around self-update;
- `/usr/local/libexec/k3dm/k3dm-verified-stage run <commit> <tool> [args…]` — run mode, **no sudo** (F1.11);
- `sudo /usr/local/libexec/k3dm/k3dm-verified-stage <commit> [--ref <branch>]` and `… --install-self <commit>` — the root forms
  the wrapper calls (F1.4-F1.10). The howto tells the operator to use the wrapper.

1. **Shell.** Shebang `#!/bin/bash -p`. In privileged mode bash 3.2.57 ignores `BASH_ENV`, `ENV`, exported functions and
   `SHELLOPTS` (P6). It does **not** ignore `CDPATH` (P7) or `POSIXLY_CORRECT` (P16). Always `/bin/bash`, never Homebrew bash,
   because `/opt/homebrew` is writable by the operator (P11).
2. **Environment and error mode, first statements.** `unset POSIXLY_CORRECT CDPATH`, `set +o posix`, `set -euo pipefail`,
   `export PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `export LC_ALL=C`, `umask 022`. Every step whose failure has its own exit code
   checks it explicitly (`|| _vs_die <code> …`), so `set -e` is a backstop, not the error path. The bootstrap uses only absolute
   paths for programs and for `cd`. It does not re-exec itself (P15). Every external program that reads configuration from the
   environment is started through `/usr/bin/env -i` with an explicit list:
   - git through `_vs_git` (F1.5);
   - the installer through `_vs_child_argv` (F1.11);
   - sudo is called by absolute path `"$_VS_SUDO"` and only as `-k`, `-n true` is never used, and the stage-mode re-entry is
     `"$_VS_SUDO" "$_VS_SELF" …` (F1.13).

   Tests source the file and therefore run the same `env -i` paths (F-7). The `SUDO_*` variables are used by no step.
3. **Self-check (all modes).** `$_VS_SELF` (a constant, default `/usr/local/libexec/k3dm/k3dm-verified-stage`) and every
   ancestor directory pass `_vs_root_owned`:
   - owner uid `$_VS_OWNER` (`/usr/bin/stat -f '%u %Lp'`);
   - no group or other write bit;
   - no ACL entry (`/bin/ls -lde` shows no ` 0: ` line, P15).

   When executed (not sourced), `$0` must resolve (`cd -P`) to `$_VS_SELF`; otherwise exit 3 "run the installed bootstrap
   `/usr/local/libexec/k3dm/k3dm-verified-stage`". The same walk runs over `$_VS_GIT`, `$_VS_GIT_CORE`
   (`/Library/Developer/CommandLineTools/usr/libexec/git-core`, which holds `git-remote-https`) and their ancestors (F-4). The walk
   stops after `$_VS_TRUST_TOP` (constant, default `/`). Failure exits 3 with "bootstrap not root-owned".
4. **Arguments.** The commit must be exactly 40 lowercase hex characters. `--ref` defaults to `main` and must match
   `^[A-Za-z0-9._/-]+$` with no `..`. When it is not `main`, the output says `UNPROTECTED REF <name>` (P13). `--install-self`
   refuses `--ref` (S1). Stage mode and `--install-self` refuse unless `_vs_require_root` passes (EUID 0). Anything else exits 2.
5. **Git.** `_vs_git` runs `/usr/bin/env -i PATH=/usr/bin:/bin HOME=/var/empty GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 "$_VS_GIT" -c transfer.fsckObjects=true -c fetch.fsckObjects=true -c core.hooksPath=/dev/null -c credential.helper= "$@"`.
   `_VS_GIT` is `/Library/Developer/CommandLineTools/usr/bin/git`, which is root-owned and ignores `DEVELOPER_DIR` (P8, P11).
   Git runs only against `$_VS_BASE/repo.git` and the stage, never in the operator's checkout.
6. **Base and fetch.** `_VS_BASE` is the canonical `/private/var/db/k3dm-verified`, not `/var/db/…`, so `cd -P` results compare
   equal (F-3). On first use the bootstrap creates `$_VS_BASE` and `$_VS_BASE/stage` with
   `/usr/bin/install -d -o "$_VS_OWNER" -g "$_VS_GROUP" -m 0755`, and `repo.git` as a bare repo, mode 0700 (F-5). Tests set
   `_VS_OWNER` and `_VS_GROUP` to the test user's uid and gid, because `install -o root` as a normal user exits 71 (P17). The URL
   is the constant `https://github.com/wilddog64/k3d-manager.git`, passed on the command line and never read from config. Fetch
   `+refs/heads/main`, `+refs/heads/deploy/hub` and the `--ref` branch into `refs/remotes/origin/*`. A failed fetch exits 4.
7. **Verify.** The commit must exist (`cat-file -e <c>^{commit}`) and satisfy
   `merge-base --is-ancestor <c> refs/remotes/origin/<ref>`. Otherwise exit 5 with the ref tips printed.
8. **Stage, always recreated** (S4, F-5). Path: `$_VS_BASE/stage/<c>`. The steps:
   - remove any `$_VS_BASE/stage/.tmp.*` left by an interrupted run;
   - `git clone --no-hardlinks --no-checkout $_VS_BASE/repo.git $_VS_BASE/stage/.tmp.<c>.$$`, then `checkout --detach <c>`;
   - write `.git/k3dm-verified` containing `<c>`;
   - `/usr/sbin/chown -R "$_VS_OWNER:$_VS_GROUP"`, `/bin/chmod -RN` (removes ACLs), `/bin/chmod -R go-w`;
   - remove the old `<stage>` if present, then `mv` the temp directory to `<stage>`.

   An existing stage is never reused. The stage stays readable by the operator, who can run it but not change it. A stage
   failure exits 6 and leaves no `<stage>`.
9. **Print, then stop.** Print these, in order, and exit 0:
   - the commit;
   - the tips of `origin/main`, `origin/deploy/hub` and `--ref`, and whether the commit equals each one;
   - `git ls-tree -r <c> --` for the installer set: the three installers, `scripts/lib/system.sh`,
     `scripts/lib/foundation/scripts/lib/system.sh`, `scripts/lib/web_console_common.sh`, `scripts/lib/agent_rigor.sh` and
     promote-authority's five `sources`;
   - the next commands in `run` form, by absolute path and without sudo, for example
     `/usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-web-console-sshd install --ca-file /absolute/path`.

   Stage mode never runs an installer.
10. **`--install-self <c>`.** Run steps 4-8 for `<c>` against `main` only. Then copy `<stage>/bin/k3dm-verified-stage` to a temp
    file beside `$_VS_SELF` with `/usr/bin/install -o "$_VS_OWNER" -g "$_VS_GROUP" -m 0755`, and `mv` it into place. Print the
    old and new blob ids.
11. **`run <c> <tool> [args…]`** (operator, no sudo):
    1. Refuse when EUID is 0 (`_vs_euid`), exit 3: the installers must run as the operator. `run` is allowed inside tmux and
       screen (operator, 2026-11-23); the TOTP and promote-authority enrol refusals still apply, because `run` tells the child
       that it is inside one (step 6).
    2. `<tool>` must be one of `k3dm-web-console-sshd`, `k3dm-web-console-totp`, `k3dm-promote-authority`. Otherwise exit 2.
    3. **Verify the stage** with `_vs_stage_ok "$_VS_BASE/stage/<c>"`; any failure exits 7 with "stage <c> not verified; run
       /usr/local/libexec/k3dm/k3dm-verified-stage stage <c>" (absolute path, S1). It checks:
       - the path resolves (`cd -P`) to `$_VS_BASE/stage/<c>`;
       - every ancestor from the stage up to `$_VS_BASE` is owned by `$_VS_OWNER`, and every ancestor above `$_VS_BASE` up to
         `$_VS_TRUST_TOP` by uid `$_VS_OWNER`, all with no group or other write bit and no ACL (S10);
       - every entry under the stage is owned by `$_VS_OWNER`, has no group or other write bit, and has no ACL entry
         (`/usr/bin/find <stage> ! -user …`, `-perm +022`, `/bin/ls -lReA`), and none is a symlink that points out of the
         stage;
       - `.git/k3dm-verified` holds `<c>`, and `rev-parse HEAD` equals `<c>`;
       - `status --porcelain --untracked-files=all --ignored` prints nothing.

       Git runs through `_vs_git`, with the stage passed as `safe.directory` through `GIT_CONFIG_COUNT` (P3; `-c safe.directory=`
       also works on git 2.50.1, so this is a choice, not a necessity).
    4. **Arguments.** The value after `--ca-file`, `--cloudflared-config` or `--tmux`, and the value of a `PROBE_FILE=` word,
       must start with `/`; otherwise exit 2 with "pass an absolute path". The working directory changes to `/` in step 6, so a
       relative path would point at the wrong file. `WEB_CONSOLE_SSH_PORT`, when set, must match `^[0-9]{1,5}$`; otherwise
       exit 2.
    5. `"$_VS_SUDO" -k` (default `/usr/bin/sudo`), so the installer's first sudo prompts afresh and no earlier ticket is used.
    6. Set `trap '' TSTP` (Q9), then `cd /`, then run the child given by `_vs_child_argv`:
       `/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=<passwd home> LC_ALL=C TERM=<validated or dumb> [TMUX=1 TMUX_PANE=1 STY=1 SSH_CONNECTION=1 SSH_TTY=1] [WEB_CONSOLE_SSH_PORT=<validated>] GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=<stage> /bin/bash -p <stage>/bin/<tool> <args>`.
       - `HOME` is taken from the passwd entry for the real uid (field 9 of `/usr/bin/id -P`), not from the environment, and
         must be absolute with no control character; otherwise exit 2.
       - `LC_ALL=C` replaces `LANG`: the installers parse `ls`, `ps` and `date` output.
       - Each of `TMUX`, `TMUX_PANE`, `STY`, `SSH_CONNECTION`, `SSH_TTY` is passed as the constant `1` only when set in the
         caller. The installers only test whether they are set (`k3dm-web-console-totp:25-26`, `k3dm-promote-authority:35`);
         the worker re-greps all three installers and the lib for any other use and stops if one exists.
       - `TERM` must match `^[A-Za-z0-9._+-]{1,64}$`; otherwise it becomes `dumb`.
       - Everything else is dropped: `CDPATH`, `SCRIPT_DIR`, `DEVELOPER_DIR`, `K3DM_WC_ROOT`, `BASH_ENV`, `POSIXLY_CORRECT`,
         `LANG`, every `GIT_*`, every `DYLD_*` and `K3DM_*`.
       - The child starts as a child process, not via `exec`, so step 7 runs. It inherits the ignored `SIGTSTP`.
       - Bash adds `PWD`, `SHLVL`, `_` and `OLDPWD` itself; tests tolerate exactly those four.
    7. `"$_VS_SUDO" -k` again after the child exits, also from a trap on `EXIT`, `HUP`, `INT` and `TERM`. Exit status: the
       child's status when it exits; `128+n` when `run` itself is ended by signal `n` (the trap records `n` and exits with it;
       a bare `exit` in a trap returns 0, which the probe in rev 2 review showed).
12. **Structure and test seams** (S8). Logic lives in functions; `main` runs only when `"${BASH_SOURCE[0]}" = "$0"`.
    - The constants `_VS_BASE`, `_VS_URL`, `_VS_GIT`, `_VS_GIT_CORE`, `_VS_SELF`, `_VS_TRUST_TOP` (`/`), `_VS_OWNER` (0),
      `_VS_GROUP` (`wheel`) and `_VS_SUDO` are assigned unconditionally at the top, so nothing in the environment can set them.
      Tests source the file and then override them: a scratch base and self path under `$BATS_TEST_TMPDIR`, `_VS_TRUST_TOP` set
      to `$BATS_TEST_TMPDIR`, the test user's uid and gid, and a logging sudo stand-in.
    - The functions tests may override: `_vs_require_root` (EUID check for stage mode) and `_vs_euid` (prints EUID for run mode).
    - Printing helpers: `_vs_git_argv` and `_vs_child_argv` print the exact argv, one word per line, that `_vs_git` and the child
      launch use. Tests compare them with an expected list.
    - Argument and root refusals (M2) are tested by sourcing the file and calling `main` with the seams set, not by executing
      the file: an executed checkout copy always stops at the `$0` check (step 3) first.
    - No `K3DM_VS_*` or other environment variable selects a test path.
13. **`stage …` wrapper** (B1). Run by the operator without sudo. Refuses when EUID is 0 (exit 3). Validates its arguments
    exactly as step 4 (exit 2 before any sudo). Then `"$_VS_SUDO" -k`, `"$_VS_SUDO" "$_VS_SELF" <args>` (records the status),
    `"$_VS_SUDO" -k`, also from an `EXIT`/`HUP`/`INT`/`TERM` trap, and exits with the recorded status. So the pause to compare the
    printed commit with the iPad happens with no live ticket.

### F2. Web-console installers: CLT git (`bin/k3dm-web-console-sshd`, `bin/k3dm-web-console-totp`)

The only change: every `/usr/bin/git` in both installers becomes `/Library/Developer/CommandLineTools/usr/bin/git`. CLT git
ignores `DEVELOPER_DIR` (P8). The fixture shim is keyed by basename (`web_console_common.sh:26`), so fixture tests are unaffected.
Line numbers move (R3's `totp-b` edits the sshd installer), so acceptance is a grep: zero `/usr/bin/git` in both files after the
change, and `git diff -U0` shows no other changed line. No shebang, `main`, lib or test change.

### F3. promote-authority (`bin/k3dm-promote-authority`)

1. **Install ref** (M5). It no longer fetches.
   - An empty `INSTALL_REF` means `HEAD`.
   - A non-empty `INSTALL_REF` must resolve to the same commit as `HEAD^{commit}`; otherwise it dies with "INSTALL_REF must be
     the staged commit".
   - The `fetch origin refs/heads/deploy/hub` line (:72) is removed. The bootstrap fetches and shows whether the commit is the
     `deploy/hub` tip.
   - `make promote-authority-install` (`Makefile:2509`) always passes `INSTALL_REF=$$INSTALL_REF`, so with it unset the make
     target now installs the checkout's `HEAD` instead of the fetched `deploy/hub`. That target is a direct run (residual 6);
     `docs/howto/promote-authority.md:5` is updated to say so and to point at `run`.
2. **values.json re-check** (S3, F-2, Q7). After the `hash-object` loop (:165-172) and before `render-check` (:173), outside plan
   mode: `actual=$(priv /bin/cat "$stage/values.json")` must equal the `printf` string written at :85, rebuilt from `id -u`,
   `id -g` and `$ids`. Otherwise it dies with "Staged values mismatch". `render-check` already re-renders from the staged
   `values.json` and the hash-checked daemon, so verifying `values.json` makes the rendered files covered too.
3. **No new variable names** (F-13). `test_promote_daemon.py:329-355` only allows the names already in `locals_used`. Item 1
   compares inline and item 2 reuses `actual`.
4. **Not in this fix (deferred P3):** shebang `#!/bin/bash -p`, first statements (`PATH`, `unset CDPATH`, `unset -f sudo`,
   `SCRIPT_DIR`), and `sudo -k` in the EXIT traps. Under `run` the child already starts as `/bin/bash -p` under `env -i`.

## External behaviour

All probes: Claude, 2026-11-23, read-only or in the session scratchpad, unless stated.

- m4-air: macOS 26.5.2, git 2.50.1 (Apple Git-155), `/bin/bash` 3.2.57, sudo 1.9.17p2, SIP disabled.
- m5-air (hub, over ssh, read-only): macOS 26.5.1, git 2.50.1 (Apple Git-155), `/bin/bash` 3.2.57, sudo 1.9.17p2.

P16 and P17 are Fable's round-2 probes (m4-air, 2026-11-23, session scratchpad, no sudo).

| # | Probe (m4-air unless stated) | Result | Consequence |
|---|---|---|---|
| P1 | scratch repo: replace the loose object file for blob `12799cc…` (`good`) with a valid zlib object holding `evil`; run `cat-file blob <id>`, `cat-file -p HEAD:f` and `cat-file --batch` | all three print `evil` under the original id; only `git fsck` reports `hash-path mismatch` | a verified commit hash in a writable `.git` does not protect content |
| P2 | `git fetch file://<that repo> HEAD:refs/heads/x` into a fresh bare repo; once by default, once with `fetch.fsckObjects=true` | default: `missing blob object …`, rc 1, no ref. fsck: `index-pack failed`, rc 128 | the receiving side re-hashes every object, so a fetch into root-owned storage is the trust step |
| P3 | `GIT_TEST_ASSUME_DIFFERENT_OWNER=1` | `detected dubious ownership`. With `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=<dir>` git proceeds; `safe.directory` in the repo's own config does not help; `-c safe.directory=<dir>` also proceeds (Fable round 2) | `run` and `_vs_stage_ok` pass `safe.directory` through `GIT_CONFIG_COUNT` |
| P4 | read-only, foreign-owned clone; `ls-files --error-unmatch`, `diff --quiet HEAD --`, `rev-parse HEAD:<path>`, `cat-file blob HEAD:<path>` on the `_wc_sources` paths | rc 0, rc 0, a blob id, the content; still clean after a stat change (Fable round 2) | the installers' existing git checks work in the stage |
| P5 | scratch repo with `core.fsmonitor` in `.git/config` | the command runs on `git status` and `git diff --quiet HEAD` | root never runs git in the operator's repo; `run` sets `GIT_CONFIG_GLOBAL=/dev/null` for the installers |
| P6 | `/bin/bash` 3.2.57 with `BASH_ENV=<marker script>`, `BASH_FUNC_id%%=…`, `SHELLOPTS=xtrace`; with and without `-p`, and under `env -i` | without `-p`: all three take effect. With `-p` or under `env -i`: none | the bootstrap and the `run` child use `/bin/bash -p` |
| P7 | `CDPATH=<evil> /usr/bin/env -i … /bin/bash -p` sourcing `scripts/lib/system.sh` by its relative path, as the web installers do, with `<evil>/scripts/lib/foundation/scripts/lib/system.sh` printing `CDPATH-PWNED` | `CDPATH-PWNED` printed; `_run_command` undefined | `-p` does not ignore `CDPATH`; `run` drops it; residual 6 for direct runs |
| P8 | `DEVELOPER_DIR=<dir>` with `<dir>/usr/bin/xcrun` writing a marker; run `/usr/bin/git --version`, then `/Library/Developer/CommandLineTools/usr/bin/git --version` | `/usr/bin/git`: marker written. CLT git: no marker, normal output | the web installers move to CLT git (F2); `run` drops `DEVELOPER_DIR` |
| P9 | `sudo -n -l` | `timestamp_timeout=60`; ticket type not shown | a ticket stays valid 60 minutes; `stage` and `run` run `sudo -k` |
| P10 | (earlier in this session) zsh 5.9.2 and bash 5.3.20: an alias and a function named `/usr/bin/sudo` | both replace the absolute path | residual 1 |
| P11 | `csrutil status`; ownership | m4-air: SIP **disabled**; m5-air: SIP enabled. `/usr/local` `root:wheel 0755` on both; `/usr/local/libexec` absent on both; `/`, `/private`, `/private/var`, `/private/var/db`, CLT `git` and each of its ancestors are uid 0 mode 755; `/opt/homebrew` belongs to the operator; `/private/tmp` is 0777 (Fable round 2) | residual 3; the walk in F1.3 passes on a stock system; tests need `_VS_TRUST_TOP` |
| P12 | `/etc/sudoers` | `root 0440`, unreadable: `env_reset`, `env_keep`, `secure_path` and `timestamp_type` are unproven. `/var/db/sudo/ts` is `root 0700` (Fable round 2) | **pre-dispatch gate for A (operator, at home):** `sudo /usr/bin/sudo -V \| grep -i timestamp` on m5-air and m4-air; record the result here. `tty` keeps residual 5 as written; `global` or `ppid` means any same-uid process can use the ticket during a run, and residual 5 and the howto must say so **Result (operator, 2026-11-23, screenshot 146):** m4-air and the hub pane both print `Type of authentication timestamp record: tty`, `timeout: 60.0 minutes`, dir `/var/db/sudo/ts`. Residual 5 stands as written; gate for A cleared. |
| P13 | `gh api repos/wilddog64/k3d-manager/rulesets` and `branches/main/protection` | one ruleset `main`: `deletion` and `non_fast_forward`, bypass `RepositoryRole`; 1 approving review, `enforce_admins: true`; public repo, 34 MB | `deploy/hub` and release branches are unprotected (Q1, residual 2) |
| P14 | `SCRIPT_DIR=<evil> /bin/bash -p -c 'source <repo>/scripts/lib/system.sh'` with `<evil>/lib/agent_rigor.sh` printing `SCRIPT_DIR-PWNED` | `SCRIPT_DIR-PWNED` printed | `run` drops `SCRIPT_DIR`; the direct-run fix is deferred (P3) |
| P15 | `/usr/bin/env -i /bin/bash -p -c 'compgen -e'`; a scratch file given `chmod +a "everyone allow write"`, then `/bin/ls -le`, `/bin/ls -lReA \| grep -cE '^ [0-9]+: '`, `chmod -RN`, count again | `PWD SHLVL`. ACL: mode shows `+`, one ` 0: group:everyone allow write` line; count 1, then 0 after `chmod -RN` | no self re-exec; the ACL check and `chmod -RN` work as specified |
| **P16** | `POSIXLY_CORRECT=1 /bin/bash -p -c 'cat < <(echo x)'` | syntax error, rc 2 | `-p` does not ignore `POSIXLY_CORRECT`; the bootstrap unsets it and `set +o posix` first; `run` drops it |
| **P17** | as a normal user: `/usr/bin/install -o root -g wheel <f> <dst>` and `install -d -o root -g wheel <dir>` | file form exits 71; `-d` form prints a chown error | the bootstrap uses `-o "$_VS_OWNER" -g "$_VS_GROUP"`; tests set them to the test user |

## Contract readers

| Where | Reads / writes | Change |
|---|---|---|
| `bin/k3dm-promote-authority:58-75` | `INSTALL_REF`; `fetch origin refs/heads/deploy/hub` (:72) | no fetch; empty = `HEAD`; otherwise it must equal `HEAD` |
| `bin/k3dm-promote-authority:85`, `:151-173` | writes `values.json` in the operator's temp dir; `ditto` to stage; hash-checks the 5 sources only | root re-reads the staged `values.json` and compares it with the expected string before `render-check` |
| `bin/k3dm-promote-authority:43-46` `ruleset-verified` | reads `< "${1#PROBE_FILE=}"` after `run`'s `cd /` | unchanged; `run` requires the `PROBE_FILE=` value to be absolute |
| `Makefile:2509` `promote-authority-install` | passes `INSTALL_REF=$$INSTALL_REF` (empty when unset) | recipe unchanged; behaviour changes: empty now means the checkout's `HEAD`, not the fetched `deploy/hub` |
| `docs/howto/promote-authority.md:5` | "The installer fetches deploy/hub unless you supply INSTALL_REF" | rewritten for `stage`/`run`; states the new empty-`INSTALL_REF` meaning |
| `docs/howto/promote-authority.md:3-18`, `:49`, `:78`, `:92-96` | install steps; fresh-clone workaround | `stage`/`run` form; the workaround's gap |
| `scripts/libexec/k3dm-promote-daemon.py:629-641` `render-check` | staged `values.json` and rendered files | unchanged; covered once `values.json` is checked |
| `scripts/tests/bin/test_promote_daemon.py:329-355` | allowlist of `$var` names in `bin/k3dm-promote-authority` | unchanged; child C adds no name (F3.3) |
| `scripts/tests/bin/promote_authority.bats:35-46` | `*/git` stub: `rev-parse --verify` prints `base` for any ref; anything else returns 99 | prints `base` for `HEAD^{commit}` and `base^{commit}`, another hash for any other ref (S9, F-12); a new `damage=values` mode tampers with the temp dir at the `ditto` call |
| `scripts/tests/bin/promote_authority.bats:120-136`, `:140-147` | `INSTALL_REF=HEAD` runs; source scan | stay valid |
| `scripts/tests/bin/promote_authority.bats:11-16` | Makefile target names, `not-installed.list:48-49` | unchanged |
| `bin/k3dm-web-console-sshd`, `bin/k3dm-web-console-totp` | `/usr/bin/git` (today sshd `:15-20`, `:155`, `:684-686`; totp `:83-88`, `:155`, `:370`) | CLT git; acceptance by grep, not line number |
| `bin/k3dm-web-console-sshd:95-96`, `bin/k3dm-web-console-totp:25-26`, `:29-30`; `bin/k3dm-promote-authority:35` | refuse root; refuse inside tmux/screen/ssh (tested with `${X+set}` only) | unchanged; `run` passes `TMUX`, `TMUX_PANE`, `STY`, `SSH_CONNECTION`, `SSH_TTY` as `1` when set, and refuses EUID 0 |
| `scripts/lib/web_console_common.sh:113-114` | `WEB_CONSOLE_SSH_PORT` used raw on the revoke path | unchanged; `run` requires `^[0-9]{1,5}$` |
| `bin/k3dm-web-console-sshd:269-291` `_wc_route_file`/`_wc_check_routes` | `/opt/homebrew/bin/yq` as the operator in `check` | unchanged (residual 4, F-6) |
| `bin/k3dm-web-console-totp:356-360` | `$PWD` as the checkout for the tmux path check | `$PWD` is `/` under `run`; the totp `--tmux` value is absolute (F1.11.4) |
| `scripts/lib/web_console_common.sh` (whole file), `scripts/lib/system.sh`, `scripts/lib/foundation/` | `_wc_priv`, `_wc_fixture_gate`, `_run_command`, sudo handling | **unchanged** (M7) |
| `scripts/tests/bin/web_console_sshd.bats`, `web_console_totp.bats` | existing suites, including `:117-127` (R-INSTALL/R-SUDO tokens in the web howtos) and `:932-948` | unchanged files; must stay green. The web howtos are not edited by R2 (deferred P3 / R3 `totp-c`) |
| `scripts/ci/test_shard.sh`, `.github/workflows/ci.yml:157` | `make test-shard` on ubuntu-24.04 picks up every `.bats` | the new `verified_stage.bats` skips on non-Darwin (`web_console_sshd.bats:172` pattern); new promote tests skip on non-Darwin only if they use a Darwin-only tool |
| **writer** (new) `bin/k3dm-verified-stage` | creates `/private/var/db/k3dm-verified/{repo.git,stage/<c>}`; installed at `/usr/local/libexec/k3dm/` | new paths. promote-authority uses `/var/db/k3dm-promote` and `/usr/local/libexec/k3dm-promote` (`:9-11`), so nothing collides (grep: no `k3dm-verified` in `bin`, `scripts`, `Makefile`) |
| R3 children `docs/plans/v1.45.1-totp-b-revoked-keys.md`, `v1.45.1-totp-c-guides.md` | `totp-b` edits `bin/k3dm-web-console-sshd`; `totp-c` edits the web howtos | B dispatches after `totp-b` lands, and its base commit (M7, E13) is the branch tip after that landing. D edits no web howto, so it does not wait for `totp-c` |

## Acceptance

```yaml
must:
  M1: stage mode, run as root with a 40-hex commit reachable from the anchor ref, fetches by its constant URL into a root-owned bare repo with fsckObjects on, builds the stage in a temp directory and moves it to /private/var/db/k3dm-verified/stage/<c> (always recreated, owned by the owner constant, no group or other write bit, no ACL), writes .git/k3dm-verified = <c>, prints the commit, the main, deploy/hub and --ref tips, the installer-set blob ids and the next commands in run form by absolute path, and exits 0 without running any installer
  M2: stage mode and --install-self, called through main with the seams set, exit non-zero before any fetch when not root, when the commit is not exactly 40 lowercase hex, or when --ref is malformed; stage mode prints UNPROTECTED REF for any --ref other than main; an executed copy that is not the installed path exits 3
  M3: run mode, as the operator, with a verified stage and an allowlisted tool, runs sudo -k, ignores SIGTSTP, changes to /, starts /bin/bash -p <stage>/bin/<tool> with exactly the allowlisted environment (HOME from passwd, LC_ALL=C, presence variables as 1) plus the fixed git variables, runs sudo -k again when the child exits or run is ended by HUP, INT or TERM, and exits with the child's status, or 128+n when ended by signal n
  M4: every existing promote_authority, web_console_sshd and web_console_totp test and test_promote_daemon.py/test_web_console_totp.py pass; the only edits to existing test files are the promote stub's distinct rev-parse hashes, its damage=values mode, and new tests in promote_authority.bats
  M5: promote-authority install treats an empty INSTALL_REF as HEAD and never runs git fetch
  M6: --install-self <c> replaces the bootstrap at the self path with the stage's copy, owner and group constants, mode 0755, through a temp file and mv, prints old and new blob ids, and refuses --ref
  M7: nothing under scripts/lib/ changes, and the diff of the two web installers against the base commit changes only lines that replace /usr/bin/git with /Library/Developer/CommandLineTools/usr/bin/git
  M9: promote-authority compares the root-owned staged values.json with the expected string before render-check and refuses activation on a mismatch
  M10: the stage wrapper, run as the operator, validates its arguments before any sudo, runs sudo -k, then sudo <self path> <args>, then sudo -k (also on HUP, INT, TERM), and exits with the inner status
must_not:
  N1: stage mode creates a stage for a commit that is not an ancestor of the anchor ref on the fetched remote
  N2: stage mode stages content that differs from the commit's tree when the remote serves a corrupted object, reuses an existing stage directory, or runs git in any repository other than its own repo.git and the stage
  N3: a git call made by the bootstrap carries any environment variable outside its fixed list (GIT_DIR, GIT_CONFIG_PARAMETERS, BASH_ENV and an arbitrary variable set by the caller)
  N4: run mode starts an installer with any environment variable outside its allowlist or with a caller-supplied value for HOME, LANG or a presence variable, from a working directory other than /, as root, with a relative --ca-file/--cloudflared-config/--tmux/PROBE_FILE= value, with a non-numeric WEB_CONSOLE_SSH_PORT, or from a stage that fails any _vs_stage_ok condition (group-writable entry, ACL entry, entry owned by another uid, operator-owned ancestor above the base, wrong marker, HEAD different from the name, untracked or ignored file)
  N5: BASH_ENV, an exported function, SHELLOPTS or POSIXLY_CORRECT in the environment takes effect inside the bootstrap or inside an installer started by run mode
  N6: with CDPATH pointing at an attacker tree, a run-mode installer sources any file outside the stage
  N8: with DEVELOPER_DIR pointing at an attacker tree, a web installer's git call executes a program from that tree
  N10: run mode or the stage wrapper returns without invalidating the sudo ticket on normal exit, a failing child, or termination by HUP, INT or TERM (best-effort: STOP and KILL are residual 5)
  N11: promote-authority installs a payload from a commit other than its HEAD
  N12: promote-authority activates a payload whose staged values.json differs from the operator uid, gid and OPERATOR_IDS it was given
evidence:
  - {id: E1, proves: [M1, N1, N2], kind: offline, intent: "You will see tests source the bootstrap, point it at a scratch bare repo served over file:// and a scratch base, with the owner and group constants set to the test user and the trust top set to the test directory, and find that a commit on main gets a stage with the right marker and tree; a commit only on a side branch is refused; a remote with one corrupted object fails with no stage left; a pre-existing stage holding an extra file is replaced; a leftover .tmp directory is removed; and the logged git argv carries both fsckObjects flags.", command: "bats scripts/tests/bin/verified_stage.bats", red: "today's tree: bin/k3dm-verified-stage does not exist, so every test fails"}
  - {id: E2, proves: [M2, M6, N3], kind: offline, intent: "You will see main, called after sourcing with the root check replaced, refuse a non-root caller, a short or uppercase commit, a bad --ref and --install-self with --ref, all before any git call; an executed copy outside the installed path stop with exit 3; and the printed git argv, taken with GIT_DIR, GIT_CONFIG_PARAMETERS, BASH_ENV and an extra variable set in the caller, contain only the fixed names after env -i.", command: "bats scripts/tests/bin/verified_stage.bats", red: "missing file"}
  - {id: E3, proves: [M3, N4], kind: offline, intent: "You will see run mode tested against a scratch stage whose committed tool is a probe that writes its environment, working directory and SIGTSTP disposition to a file: a good stage gives only the allowlisted names (plus PWD, SHLVL, _ and OLDPWD), HOME equal to the passwd home even when the caller set another, LC_ALL=C with no LANG, TMUX=1 when the caller's TMUX held other bytes, SIGTSTP ignored and the directory /; then a group-writable file, an ACL entry, a file owned by another uid (faked by changing the owner constant), a wrong marker, a HEAD different from the name, an untracked file, an unknown tool name, a relative --ca-file, a relative PROBE_FILE=, a non-numeric WEB_CONSOLE_SSH_PORT and an EUID of 0 each stop before the probe runs, and no probe output appears.", command: "bats scripts/tests/bin/verified_stage.bats", red: "missing file"}
  - {id: E4, proves: [N6], kind: offline, intent: "You will see a scratch stage built from the working tree and an attacker tree whose foundation system.sh writes a marker. Run directly with CDPATH set, the sshd installer's check verb writes the marker, which shows the attack is live. Run through run mode with the same CDPATH, no marker appears. check is read-only and never uses sudo, but outside fixture mode it reads real host state (launchctl, netstat, /etc); that is intended.", command: "bats scripts/tests/bin/verified_stage.bats", red: "today's tree: run mode does not exist; the direct run (today's documented path) writes the marker (P7)"}
  - {id: E5, proves: [N5], kind: offline, intent: "You will see the bootstrap, and a probe tool started through run mode, each started with BASH_ENV pointing at a script that writes a marker, an exported function named git, SHELLOPTS=xtrace and POSIXLY_CORRECT=1; no marker, no call to the function, no trace output, and the process-substitution line in the bootstrap still parses.", command: "bats scripts/tests/bin/verified_stage.bats", red: "today's tree: the bootstrap is missing"}
  - {id: E7, proves: [N8, M7], kind: offline, intent: "You will see a grep find no /usr/bin/git in either web installer, the diff against the base show only lines that swap it for the Command Line Tools git, and a control show why it matters: with DEVELOPER_DIR pointing at a tree whose usr/bin/xcrun writes a marker, /usr/bin/git --version writes the marker and the Command Line Tools git does not.", command: "! grep -n '/usr/bin/git' bin/k3dm-web-console-sshd bin/k3dm-web-console-totp; git diff -U0 <base> -- bin/k3dm-web-console-sshd bin/k3dm-web-console-totp; git diff --stat <base> -- scripts/lib/; scratch DEVELOPER_DIR control (P8)", red: "today's tree: the grep finds 12 /usr/bin/git lines"}
  - {id: E9, proves: [M3, M10, N10], kind: offline, intent: "You will see run mode with a logging sudo stand-in record sudo -k before and after the probe child, after a child that exits 3 (run then exits 3 as well) and after run is sent TERM (exit 143); and see the stage wrapper record sudo -k, the inner call by the self path, and sudo -k, with a bad argument refused before any sudo call and the inner status returned.", command: "bats scripts/tests/bin/verified_stage.bats", red: "today's tree: the bootstrap is missing"}
  - {id: E10, proves: [M5, N11], kind: offline, intent: "You will see promote-authority install, with a git stand-in that gives HEAD and another ref different hashes, run with INSTALL_REF empty, equal to HEAD, and naming the other commit; the first two install HEAD's blobs, the third is refused, and the call log has no fetch.", command: "bats scripts/tests/bin/promote_authority.bats", red: "today's tree: an empty INSTALL_REF logs git fetch origin refs/heads/deploy/hub, and the other commit is installed"}
  - {id: E11, proves: [M9, N12], kind: offline, intent: "You will see promote-authority install where the test changes operator_ids in the operator-owned temp values.json and re-renders it just before the copy into the stage; activation is refused with Staged values mismatch and nothing is bootstrapped.", command: "bats scripts/tests/bin/promote_authority.bats", red: "today's tree: render-check agrees with the tampered values and the payload activates with the attacker's operator_ids"}
  - {id: E12, proves: [M4], kind: offline, intent: "You will see the whole existing promote-authority, console sshd and console TOTP suites and both pytest files pass, the web-console test files unchanged, and the git diff of promote_authority.bats show only the stub change, the damage mode and new tests.", command: "bats scripts/tests/bin/promote_authority.bats scripts/tests/bin/web_console_sshd.bats scripts/tests/bin/web_console_totp.bats; python3 -m pytest scripts/tests/bin/test_promote_daemon.py scripts/tests/bin/test_web_console_totp.py", red: "regression guard: add a new $name to promote-authority and test_promote_daemon.py fails"}
  - {id: E14, proves: [M6], kind: offline, intent: "You will see --install-self run against a scratch self path replace the bootstrap with the staged copy, leave no temp file behind and print both blob ids.", command: "bats scripts/tests/bin/verified_stage.bats", red: "missing file"}
  - {id: E15, proves: [M1, M3, M10, N4, N10], kind: live, intent: "You will see the operator, at home on the hub's physical console, install the bootstrap and end with sudo -k, stage the release commit through the stage wrapper, see sudo -n true fail right after staging, compare the printed commit with GitHub on the iPad, run promote-authority print-plan and web-console-sshd check through run mode, and then see sudo -n true fail right after a run that used sudo. Claude reads the pasted output.", command: "operator, m5-air console: /usr/local/libexec/k3dm/k3dm-verified-stage stage <c>; sudo -n true; /usr/local/libexec/k3dm/k3dm-verified-stage run <c> k3dm-web-console-sshd check; ... run <c> k3dm-web-console-totp status; sudo -n true", red: "n/a (live)"}
interface:
  - "new: /usr/local/libexec/k3dm/k3dm-verified-stage stage <40-hex commit> [--ref <branch>] | stage --install-self <40-hex commit> (operator, no sudo typed); exit 2 usage, 3 run as root, otherwise the inner status"
  - "new: sudo /usr/local/libexec/k3dm/k3dm-verified-stage <40-hex commit> [--ref <branch>] | --install-self <40-hex commit>; exit 0 ok, 2 usage, 3 not root or bootstrap not root-owned or not the installed path, 4 fetch, 5 not reachable, 6 stage"
  - "new: /usr/local/libexec/k3dm/k3dm-verified-stage run <40-hex commit> k3dm-web-console-sshd|k3dm-web-console-totp|k3dm-promote-authority [args]; exit 2 usage, relative path argument or bad port, 3 run as root or bootstrap not root-owned, 7 stage not verified, 128+n when ended by signal n, otherwise the installer's status"
  - "changed: promote-authority INSTALL_REF must equal HEAD, empty means HEAD, no fetch; refuses a staged values.json mismatch"
  - "changed: web installers call the Command Line Tools git by absolute path"
  - "unchanged: _run_command, scripts/lib/ (all of it), Makefile targets, installer verbs and flags, shebangs"
```

Ids keep rev 2's numbering. Removed in rev 3 with the scope cut (moved to the P3): M8, N7, N9, E6, E8, E13 (E7 now covers M7).

## Re-approval (done 2026-11-23)

The operator approved rev 2's intents. Rev 3 changed the meaning of these, and the operator re-approved them on 2026-11-23:

- **E1:** owner/group constants and trust top replace the chown seam (test setup only; result unchanged).
- **E2:** refusals are tested through sourced `main`, plus a new exit-3 check for an executed copy outside the installed path.
- **E3:** adds passwd `HOME`, `LC_ALL=C` with no `LANG`, presence variables as `1`, `SIGTSTP` ignored, relative `PROBE_FILE=`,
  non-numeric port.
- **E4:** adds the sentence that `check` reads real host state, read-only, by intent.
- **E5:** now covers the bootstrap and a run-launched probe only (not the three installers started directly), and adds
  `POSIXLY_CORRECT`.
- **E7:** now a grep, a diff and the P8 control instead of a sourced-installer test; also proves M7.
- **E9:** run part only, plus the stage wrapper and exit 143 on TERM; the web `close.log` and promote-authority trap checks are
  gone.
- **E12:** web-console test files must be unchanged.
- **E15:** the stage wrapper, `sudo -k` at the end of the first install, and `sudo -n true` failing after staging.

Unchanged in meaning: E10, E11, E14.

## Files

| # | File | New? | Child |
|---|---|---|---|
| 1 | `bin/k3dm-verified-stage` | new | A |
| 2 | `scripts/tests/bin/verified_stage.bats` | new | A |
| 3 | `bin/k3dm-web-console-sshd` | | B |
| 4 | `bin/k3dm-web-console-totp` | | B |
| 5 | `bin/k3dm-promote-authority` | | C |
| 6 | `scripts/tests/bin/promote_authority.bats` | | C |
| 7 | `docs/howto/verified-stage.md` | new | D |
| 8 | `docs/howto/promote-authority.md` | | D |

8 files: 3 new, 5 changed (rev 2: 12). Dropped from rev 2: `scripts/lib/web_console_common.sh`,
`scripts/tests/bin/web_console_verified_stage.bats`, `docs/howto/web-console-sshd.md`, `docs/howto/web-console-totp.md` (all to the
P3). No Makefile change, nothing under `scripts/lib/`, no lib-foundation upstream change, `test_promote_daemon.py` and both
web-console test files unchanged.

## Routing

Each child is its own `docs/plans/v1.45.1-r2-<letter>-*.md` with a slice of this Acceptance block. No two children share a file.

- **A — Luna** (`gpt-6-luna`): the bootstrap and its tests (E1, E2, E3, E4, E5, E9, E14). **Gate:** the P12 probe result is
  recorded in this spec first. E4 builds its scratch stage from the working-tree installers and needs nothing from B or C.
- **B — Luna**: CLT git in the two web installers (E7, E12 web part). A two-file path substitution with no `main` or test
  edits. It edits `bin/k3dm-web-console-sshd`, which R3's `totp-b` also edits, so B dispatches after `totp-b` lands, from that
  tip. Small enough to fold into a P3 batch if the WIP limit is tight.
- **C — Luna**: promote-authority (E10, E11, E12 promote part). No dependencies.
- **D — Flash** (`gemini-3.8-flash-medium`): docs, after A-C land. Contents:
  - `verified-stage.md` covers the one-time bootstrap install at the physical console (ending with `sudo -k`), `stage` then
    `run`, the second-channel check on the iPad, the six residuals (residual 5 marked best-effort, with the P12 result), and the
    optional separate admin account;
  - `promote-authority.md:5` states that an empty `INSTALL_REF` now installs the checkout's `HEAD` and that the install should go
    through `run`; `:92-96` says the fresh-clone workaround only defeats tampering done before the clone.
  - A one-line pointer from the web-console howtos to `verified-stage.md` is left to R3's `totp-c` or the P3, not D.

WIP: at most 3 open dispatches. A (after P12) and C can go as soon as slots free. P2 does not exceed the limit.

## Worker definition of done (A-C)

- Change only your child's files. Work offline: no network (use a `file://` scratch remote), no sudo, no Keychain, nothing
  outside `$BATS_TEST_TMPDIR`. Assert the scratch base, self path, trust top and HOME first.
- Never run the bootstrap's `main` as root or for real. Tests source it and override the F1.12 constants and seams. Do not
  invent environment-variable seams.
- Never run a real `sudo` of any kind. Tests replace `_VS_SUDO` with a logging stand-in.
- A: `verified_stage.bats` starts with `[ "$(uname -s)" = Darwin ] || skip` in `setup` (`web_console_sshd.bats:172` pattern):
  the bootstrap uses `stat -f`, `ls -lde`, `chmod -RN`, `find -perm +022` and CLT git. C: if a new test uses a Darwin-only tool,
  skip it the same way.
- A: before writing `_vs_child_argv`, grep the three installers and `scripts/lib/web_console_common.sh` for every use of `TMUX`,
  `TMUX_PANE`, `STY`, `SSH_CONNECTION` and `SSH_TTY`; if any use reads the value (not `${X+set}`/`${X+x}`), stop and report.
- Show each must_not test red on today's tree, then green. Mutations to show:
  - pass `CDPATH`, `DEVELOPER_DIR` or `LANG` through the child allowlist (A);
  - pass the caller's `HOME` or `TMUX` bytes instead of the passwd home / `1` (A);
  - remove `trap '' TSTP` (A);
  - remove `unset POSIXLY_CORRECT` (A);
  - remove the `is-ancestor` check (A, N1);
  - skip removal of the old stage (A, N2);
  - remove each `_vs_stage_ok` condition in turn (A, N4);
  - remove the post-child `sudo -k` and its trap (A, N10), and the wrapper's second `sudo -k` (A, M10);
  - drop `env -i` from `_vs_git` (A, N3);
  - make the bootstrap read the URL from `repo.git` config (A);
  - remove the `fsckObjects` flags (A): E1's argv assertion must go red;
  - restore `/usr/bin/git` in one web installer (B);
  - remove the `values.json` comparison (C);
  - restore the `deploy/hub` fetch (C).
- `shellcheck` on every changed script; `/bin/bash -n` on each; the full runs of the touched suites, with rc and counts.
- Leave changes uncommitted; no push; do not touch `docs/bugs/`. E15 belongs to the operator and Claude.

## Rollout (operator, at home, with sudo)

0. **Before A dispatches:** `sudo /usr/bin/sudo -V | grep -i timestamp` on m5-air and m4-air, then `sudo -k`. Paste the output;
   Claude records it in P12.
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
     - **End with `sudo -k`.**
3. **Each later install, upgrade or uninstall:**
   - Read the commit on GitHub on the iPad.
   - Run `/usr/local/libexec/k3dm/k3dm-verified-stage stage <c> [--ref <branch>]` (no `sudo` typed; it prompts and clears the
     ticket on exit) and compare the printed commit and tips with the iPad.
   - Run the printed `/usr/local/libexec/k3dm/k3dm-verified-stage run <c> <tool> <verb> …` command, without sudo. It clears the
     ticket when the installer exits.
4. **Bootstrap updates** go through `stage --install-self <c>` (main only) and never through step 2 again.
5. **Re-run web-console on m4-air the same way.** Its SIP is disabled (residual 3, Q5).
6. **Claude reads the pasted output (E15).** Then the bug moves to `LIVE-VERIFIED`.

## Open questions

- **Q1 — anchor ref.** Only `main` is protected. promote-authority installs the `deploy/hub` commit, and release-time installs use
  the release branch; neither is protected.
  - Recommended: the default is `main`, and `--ref` is allowed with an `UNPROTECTED REF` banner. Residual 2 says the iPad check
    is the only anchor for those refs.
  - Alternative: refuse anything not on `main` until those branches get rulesets.
- **Q2 — separate admin account.** A dedicated macOS admin user for installs closes residuals 1 and 5.
  - Recommended: document it as optional hardening, not required.
- **Q3 — stage pruning.** Stages are recreated per run but old commits' stages remain. Recommended: no automatic pruning in
  v1.45.1; the howto documents `sudo rm -rf /private/var/db/k3dm-verified/stage/<old>`.
- **Q4 — read-only verbs (decided in rev 2).** `web-console-sshd check` never calls sudo (`k3dm-web-console-sshd:336-365`), so
  it works from anywhere and needs no stage. `web-console-totp status`, `enroll` and `rotate` call sudo
  (`k3dm-web-console-totp:502-517`), and `promote-authority probe-deploy-key` and `ruleset-verified` call `priv`
  (`k3dm-promote-authority:43-48`). Those go through `run`.
- **Q5 — SIP on m4-air.** Disabled today, which widens residual 3. This is the operator's decision, outside this fix.
- **Q6 — hardware-backed signed tags** as a second anchor. Recommended: out of scope for v1.45.1; add a row to `docs/ideas.md`.
- **Q7 — answered (Fable S3, Argon F-2).** The `values.json` re-check is in child C (F3.2, M9, N12, E11).
- **Q8 — Makefile targets.** `make install-web-console-*` and `make promote-authority-install` still run checkout code under
  sudo (residual 6). Changing their recipes would break the recipe assertions in `web_console_sshd.bats:1122-1135` and
  `web_console_totp.bats:114-119`. Leave them in v1.45.1; the howtos point at `run`. Captured in the P3.
- **Q9 — decided (operator, 2026-11-23): `run` inside tmux.** Allowed. `run` ignores `SIGTSTP` and clears the ticket afterwards;
  residual 5 states that STOP and KILL still leave the ticket live. Refusing inside tmux was rejected because it would rule out
  installs from the iPad.

## Rev 3 changes

Fable round 2 on rev 2 (e350217d). Operator decisions: S8 accepted; Q9 allow with `C-z` blocked.

| Finding | Verdict | Change in rev 3 |
|---|---|---|
| Fable B1 (ticket reachable: stage→run gap, first install, `C-z`/STOP/KILL; residual 5 and N10 overstated) | Applied | `stage` wrapper with `sudo -k` before and after (F1.13, M10, E9); Rollout 2 ends with `sudo -k`; `trap '' TSTP` before the child (Q9); traps on HUP/INT/TERM with 128+n; residual 5 and N10 rewritten as best-effort; tmux `send-keys` and signals added to the Attacker list; E15 checks `sudo -n true` after staging. Refusing inside tmux: rejected by the operator (Q9) |
| Fable B1 (prove P12 before dispatch) | Applied | P12 is a pre-dispatch gate for A (Routing, Rollout 0) |
| Fable B2 (`install -o root` as non-root) | Applied | `-o "$_VS_OWNER" -g "$_VS_GROUP"` everywhere; `_VS_GROUP` constant; `_vs_chown` seam dropped (F1.6, F1.8, F1.10, P17) |
| Fable B2 (ancestor walk fails under the test tmp dir) | Applied | `_VS_TRUST_TOP` constant, default `/`, overridden in tests (F1.3, F1.11.3) |
| Fable B2 (self-check on `$0` makes E2 pass for the wrong reason) | Applied | `_VS_SELF` constant; `$0` must equal it when executed; M2/E2 tested through sourced `main` (F1.3, F1.12) |
| Fable B2 (Linux CI) | Applied | Darwin-only skip in `verified_stage.bats` (DoD); CI readers listed |
| Fable S1 (bare command name in exit-7 message) | Applied | absolute path (F1.11.3); stage mode's printed commands are absolute too (F1.9) |
| Fable S2 (`PROBE_FILE=` missed by the absolute-path rule) | Applied | F1.11.4, N4, E3; contract reader row |
| Fable S3 (`POSIXLY_CORRECT`; error mode; `export`) | Applied | first statements `unset POSIXLY_CORRECT CDPATH; set +o posix; set -euo pipefail; export PATH LC_ALL` (F1.2); N5, E5; P16 |
| Fable S4 (`LANG`, `HOME`, presence variables, `WEB_CONSOLE_SSH_PORT`) | Applied | `LC_ALL=C` instead of `LANG`; `HOME` from passwd; presence variables passed as `1`; port validated (F1.11.4, F1.11.6, N4, E3); DoD grep for other uses |
| Fable S5 (mutation list; N2 git-elsewhere evidence; E9 promote grep; F3.5 real `sudo -k`) | Applied / moot | mutations added (DoD). N2's "runs git elsewhere" is covered by E1's logged git argv (every call carries `-C`/`--git-dir` inside the scratch base). E9's promote grep and F3.5 are gone with the scope cut |
| Fable S6 (E6 verb; E4 host state; signal exit status) | Applied / moot | E6 removed (P3); E4 states that `check` reads host state, read-only, by intent; 128+n (F1.11.7, M3, E9) |
| Fable S7 (contract readers) | Applied | `Makefile:2509` behaviour change and `promote-authority.md:5`; CI readers; `web_console_sshd.bats:117-127` noted (web howtos untouched); line references replaced by a grep (F2, E7); B's base is the tip after `totp-b` |
| Fable S8 (cut to ~8 files) | Applied (operator) | 8 files; shebangs, promote first statements, fixture gate, `_wc_priv_close`, promote traps, the web bats and the web howto sections moved to the P3; B is a two-file path substitution |
| Fable S8 optional (drop `run`'s per-entry re-check) | Rejected | kept: it is what makes a stage tampered with by root-level mistakes or a later `chmod` fail closed, and the cost is one `find` per run |
| Nit: `-c safe.directory=` works | Applied | wording corrected (F1.11.3, P3) |
| Nit: walk `git-core` too | Applied | `_VS_GIT_CORE` walked (F1.3) |
| Nit: refuse unless `$-` has `p` | Rejected | too late to help: when started as `bash <file>`, `BASH_ENV` has already run before any line of the file |
| Nit: E13 comparison script unnamed | Moot | E13 removed; M7 is now "nothing under `scripts/lib/` changes", proven by `git diff --stat` in E7 |
| Nit: `K3DM_WC_ROOT` gate of low value | Moot | the fixture gate moved to the P3 |

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

Rev 2 references above (F2.1-F2.4, F3.1-F3.6, M8, N7, N9, E6, E8, E13) name rev 2's numbering; rev 3 removed or renumbered them.
