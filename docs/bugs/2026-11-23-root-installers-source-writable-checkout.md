# Bug: root installers source libraries from the operator-writable checkout

**Status:** OPEN — spec rev 1 (pending Fable + Argon review)
**Priority:** P2 (operator, 2026-11-23: doc + bug, does not block v1.45.0)
**Introduced by:** v1.45.0 plans 2c, web-console A and C
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** investigation — since 2026-11-23 (spec review: Fable and Argon, independently)
**Triage:** patch → v1.45.1 (operator, 2026-11-23: "can you spec R2 and have Fable and Argon to review independently")
**Branch:** k3d-manager-v1.45.1
**Intent approved:** pending
**Approval:** pending. This spec is new in v1.45.1, so the operator has not approved its intents yet. Do not dispatch until both reviews are applied and the line above names the operator and a date.
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** a same-uid process becomes root at the operator's next install; defeats the promote authority's goal of surviving a compromised operator uid.
**Findings:** Fable 3 (Medium). Claude: confirmed (`bin/k3dm-promote-authority:3-5` sources `scripts/lib/system.sh`, which provides `_run_command`, from the checkout).

## What is wrong

`bin/k3dm-promote-authority`, `bin/k3dm-web-console-sshd` and `bin/k3dm-web-console-totp` source `scripts/lib/system.sh` (and
`web_console_common.sh`) from the working tree, then run privileged steps through `_run_command` under the operator's sudo. Taking
payload blobs from `HEAD` (`k3dm-promote-authority:76-86`) protects the payload against uncommitted edits only: not the installer,
its sourced libraries, or a local commit.

## Workaround (documented in docs/howto/promote-authority.md)

Run installs from a fresh clone of the protected remote ref, at a commit checked on a second channel.

## Fix direction (rev 0)

Installer refuses to run unless started from a fresh clone at a commit reachable from a ruleset-protected ref, verified against an
operator-typed commit or signed tag; print the commit and blob hashes before asking for sudo.

Rev 1 replaces this with the design below. A check that runs from the clone is itself code in the clone, and the clone sits in a
directory the attacker can write.

## Threat model

**Attacker.** Any process running as the operator's uid: a compromised agent, tool, editor plugin or dependency. It can:

- edit any file in the checkout, including `.git/` (objects, refs, `config`, hooks);
- make local commits and move local refs;
- set environment variables for later processes (`launchctl setenv`, tmux global environment);
- put files earlier on PATH, for example in `~/.local/bin`, or in `/opt/homebrew`, which the operator's account owns;
- run continuously, so it can change a directory in the seconds between a clone and an install.

**Goal.** Become root the next time the operator runs one of the three installers with sudo.

**Defended by this fix:** everything the attacker can do by changing **files and environment variables**: the working tree,
local commits, `.git` objects and config, PATH entries, `GIT_*`, `BASH_ENV`, exported shell functions, `SHELLOPTS`.

**Not defended (residuals, stated in the howto):**

1. **Control of the operator's interactive shell.** An attacker that can write `~/.zshrc`, `~/.zshenv` or set `ZDOTDIR` can
   alias or wrap even an absolute `/usr/bin/sudo` (probe P7). It can then fake the prompt, the bootstrap's output or the
   Touch ID request. No design run from that shell can defend against this. The only full mitigation is to run installs from a
   separate macOS admin account whose home directory the operator uid cannot write (open question Q2).
2. **The operator's GitHub credentials.** A same-uid process may read the operator's `gh` token. If that token can bypass the
   `main` ruleset (`bypass_actors: RepositoryRole`), it can put a commit on `main`. The real anchor is the operator reading the
   commit on a second device before typing its hash. Being reachable from `main` only proves the commit is public and under the
   ruleset.
3. **m4-air runs with SIP disabled** (probe P8). A `DYLD_INSERT_LIBRARIES` set for the operator's session loads into the
   operator's shell, which is residual 1 again. The hub (m5-air) has SIP enabled.
4. **Operator-supplied data inputs** keep their current validation: `CA_FILE`, `--cloudflared-config`,
   `~/.cloudflared/config.yml`, the `--tmux` path and `OPERATOR_IDS`. They are data, not code.
5. **promote-authority's render directory** is an operator-owned `mktemp -d` (`k3dm-promote-authority:76`). This is unchanged.
   The installer re-checks the staged hashes after it copies the files into the root-owned stage. A Fable review should confirm
   that this re-check covers every rendered file.

## Designs considered

| | Design | Defeats the file/env attacker? | Size | Verdict |
|---|---|---|---|---|
| a | Installer refuses unless run from a fresh clone at a verified commit | **No.** The check is code inside the clone. A watcher process can edit a clone in an operator-writable directory between `git clone` and `make install`, and today's workaround has the same gap. Verifying the commit hash does not protect the content either: git does not re-hash loose objects on read (P1) | small | rejected |
| b | Root-owned staging copy taken with `git show <commit>:path` **from the operator's `.git`**, run with `env -i` | **No.** P1: replacing the loose object file makes `cat-file`/`git show` return the attacker's bytes for the verified hash. Running git **as root** in the operator's repo also runs the operator's `.git/config` hooks as root (`core.fsmonitor`, P5) | medium | rejected as stated |
| b′ | A root-owned bootstrap fetches the operator-typed commit **by fixed URL** into a **root-owned** repo (the transfer re-hashes every object, P2), checks the commit is reachable from the anchor ref, checks out a root-owned stage and prints hashes. The operator then runs the installer **from the stage**; installers refuse to call sudo from anywhere else | **Yes**, for files and env | 1 new script; small changes to 3 installers and 2 libs | **recommended** |
| b″ | b′, but the bootstrap also runs the staged installer as root under `env -i` | Yes | large: both web-console installers refuse root by design (`k3dm-web-console-sshd:95`; `k3dm-web-console-totp:29-30` will not show a TOTP secret as root) and use `id -un` and `$HOME` for the operator's identity | rejected: bigger, and it loosens two safety refusals |
| c | Signed tags verified against a key | No. The key lives in an agent the same uid can use, unless it is a hardware key that needs a touch | medium | out of scope (Q6) |
| d | Separate macOS admin account for installs | Yes, including residual 1 | operator setup, no code | optional hardening (Q2) |

**Why b′ is the smallest design that works.** Trusted code has to start somewhere the attacker cannot write. That place is a
root-owned file installed once at the physical console, then updated only through itself. Everything the bootstrap reads comes
over a hash-checking transfer into root-owned storage. Root never runs git inside the operator's repository. Root never runs
installer code either: the installers keep running as the operator, as they do today, so their own refusals stay as they are.

## Fix (spec rev 1, Claude, 2026-11-23)

### F1. Bootstrap `bin/k3dm-verified-stage` (new)

The operator installs it once at `/usr/local/libexec/k3dm/k3dm-verified-stage`, `root:wheel 0755` (see Rollout). The operator
then runs it as `sudo /usr/local/libexec/k3dm/k3dm-verified-stage <commit> [--ref <branch>]` or with `--install-self <commit>`.

1. **Shebang `#!/bin/bash -p`.** In privileged mode bash ignores `BASH_ENV`, `ENV`, exported functions, `SHELLOPTS`, `BASHOPTS`,
   `CDPATH` and `GLOBIGNORE` (P6). Always `/bin/bash` (3.2.57). Never Homebrew bash, because `/opt/homebrew` is writable by the
   operator (P8).
2. **Clean environment.** It refuses unless `EUID` is 0. Unless the environment holds exactly the allowlist (`PATH`, `HOME`,
   `LANG`, `TERM`, `SUDO_UID`, `SUDO_GID`, `SUDO_USER`), it re-execs itself:
   `/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/root LANG=C TERM=<as given or dumb> SUDO_UID=… SUDO_GID=… SUDO_USER=… /bin/bash -p "$0" "$@"`.
   Before the re-exec it checks the three `SUDO_*` values: digits for the ids, `^[a-z_][a-z0-9_-]*$` for the user. The check
   tests what the environment contains, not a marker variable, so a planted variable cannot skip it. The design does not rely on
   sudoers `env_reset`, which is unproven (P9).
3. **Self-check.** `$0` resolves (`cd -P`) to a file and every ancestor directory is owned by uid 0 with no group or other
   write bit (`/usr/bin/stat -f '%u %Lp'`). Otherwise it exits 3 with "bootstrap not root-owned".
4. **Arguments.** The commit must be exactly 40 lowercase hex characters. `--ref` defaults to `main` and must match
   `^[A-Za-z0-9._/-]+$` with no `..`. When it is not `main`, the output says `UNPROTECTED REF <name>` (P10). Anything else
   exits 2.
5. **Git.** Use only `/Library/Developer/CommandLineTools/usr/bin/git`, which is root-owned (P8). Always run it with
   `GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0`. Use `-c transfer.fsckObjects=true -c fetch.fsckObjects=true -c core.hooksPath=/dev/null -c credential.helper=`.
   Run it only against `/var/db/k3dm-verified/repo.git` and the stage. Never run git in the operator's checkout.
6. **Fetch.** `repo.git` is a bare repo, `root:wheel 0700`, created on first use. The URL is a constant,
   `https://github.com/wilddog64/k3d-manager.git`, passed on the command line; it is never read from config. Fetch
   `+refs/heads/main`, `+refs/heads/deploy/hub` and the `--ref` branch into `refs/remotes/origin/*`. A failed fetch exits 4.
7. **Verify.** The commit must exist (`cat-file -e <c>^{commit}`) and satisfy
   `merge-base --is-ancestor <c> refs/remotes/origin/<ref>`. Otherwise exit 5 with the ref tips printed.
8. **Stage.** Path: `/var/db/k3dm-verified/stage/<c>`. If it already exists and passes the guard (F2), reuse it. Otherwise
   remove it and recreate it:
   - `git clone --no-hardlinks --no-checkout /var/db/k3dm-verified/repo.git <stage>`;
   - `checkout --detach <c>`;
   - write `<stage>/.git/k3dm-verified` containing `<c>`;
   - `chown -R root:wheel` and `chmod -R go-w`; directories stay `0755` and files keep their tree mode with `go-w`.

   The stage stays readable by the operator, so the operator can run it but cannot change it. A stage failure exits 6.
9. **Print, then stop.** Print these, in order, and exit 0:
   - the commit;
   - the tips of `origin/main`, `origin/deploy/hub` and `--ref`, and whether the commit equals each one;
   - `git ls-tree -r <c> --` for the installer set: the three installers, `scripts/lib/system.sh`,
     `scripts/lib/foundation/scripts/lib/system.sh`, `scripts/lib/web_console_common.sh`, `scripts/lib/agent_rigor.sh` and
     promote-authority's five `sources`;
   - the exact next commands, for example `<stage>/bin/k3dm-web-console-sshd install`.

   The bootstrap never runs an installer.
10. **`--install-self <c>`.** Run steps 4-8 for `<c>`. Then copy `<stage>/bin/k3dm-verified-stage` to a temp file beside the
    target with `/usr/bin/install -o root -g wheel -m 0755` and `mv` it into place. Print the old and new blob ids.
11. **Structure.** Logic lives in functions. `main` runs only when `"${BASH_SOURCE[0]}" = "$0"`, the same pattern as the
    web-console installers. Path constants (`_VS_BASE`, `_VS_URL`, `_VS_GIT`, `_VS_SELF_DIR`) are assigned unconditionally.
    Tests source the file and override them; nothing in the environment can.

### F2. Guard `_k3dm_verified_stage_check <dir>` (in `scripts/lib/system.sh`, k3d-manager's own wrapper)

Returns 0 only if all of the following hold:

- `<dir>` resolves (`cd -P`) to `${_K3DM_VS_BASE}/stage/<40 hex>`;
- that directory and every ancestor up to `/` is owned by `${_K3DM_VS_OWNER}` and has no group or other write bit;
- `<dir>/.git/k3dm-verified` holds the basename;
- `git -C <dir> rev-parse HEAD`, run in the clean git environment of F3, equals the basename.

`_K3DM_VS_BASE=/var/db/k3dm-verified` and `_K3DM_VS_OWNER=0` are assigned unconditionally in the file (not read from the
environment). Tests source the file and then override them. On failure the guard prints one line:

`run privileged steps from a verified stage: sudo /usr/local/libexec/k3dm/k3dm-verified-stage <commit>`

It then returns 12. The guard does not touch `_run_command`, `_run_command_resolve_sudo` or anything under
`scripts/lib/foundation/`, so lib-foundation is not involved.

The guard is not the security boundary: an attacker can delete it from a checkout copy. What it does is make the safe path the
only one that works, so the operator cannot drift back into running the checkout's installer by accident. The boundary is the
path the operator types (F1 and the stage).

### F3. Installers

1. **Shebang.** All three use `#!/bin/bash -p`. promote-authority today uses `#!/usr/bin/env bash`, which resolves to Homebrew
   bash 5.3 on PATH, so for it this change moves to `/bin/bash` 3.2. Its existing tests must pass under 3.2 (they run the file
   directly, so the shebang applies).
2. **Clean git environment.** Before the first git call, unset every exported `GIT_*` name (`compgen -e`). Then export
   `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_COUNT=1`, `GIT_CONFIG_KEY_0=safe.directory` and
   `GIT_CONFIG_VALUE_0=<resolved repo dir>`. The last three are needed because the stage is root-owned and the installer runs as
   the operator (P3). In `web_console_common.sh` this is a new `_wc_clean_git_env`, called from both `main`s right after the
   common file is sourced, in fixture mode too. In promote-authority it is inline after `repo=`.
3. **Guard at the sudo chokepoints.**
   - `web_console_common.sh` `_wc_priv` (:15-17): call `_k3dm_verified_stage_check "$PWD"` before `_run_command`; both
     installers `cd` to the repo first. Fixture mode replaces `_wc_priv` (:42), so fixture tests never reach the guard.
   - promote-authority `priv` (:18-25, non-plan branch) and the `uninstall` `bootout` (:50) call the guard on `$repo`. The
     `bootout` goes through `priv`, or is guarded the same way.

   Verbs that never call sudo (`print-plan`, promote-authority `status`, `--dry-run`) keep working from a checkout.
4. **promote-authority install ref.** It no longer fetches.
   - An empty `INSTALL_REF` means `HEAD`.
   - A non-empty `INSTALL_REF` must resolve to the same commit as `HEAD`; otherwise it exits non-zero with
     "INSTALL_REF must be the staged commit".
   - The `fetch origin refs/heads/deploy/hub` line (:72) is removed. The bootstrap does the fetch and shows whether the commit is
     the `deploy/hub` tip.

## External behaviour

All probes: Claude, 2026-11-23, read-only or in the session scratchpad. m4-air: macOS 26.5.2, git 2.50.1 (Apple Git-155), `/bin/bash`
3.2.57, sudo 1.9.17p2. m5-air (hub, over ssh, read-only): macOS 26.5.1, git 2.50.1 (Apple Git-155), `/bin/bash` 3.2.57, sudo 1.9.17p2.

| # | Probe (m4-air unless stated) | Result | Consequence |
|---|---|---|---|
| P1 | scratch repo: replace the loose object file for blob `12799cc…` (`good`) with a valid zlib object holding `evil`; run `cat-file blob <id>`, `cat-file -p HEAD:f` and `cat-file --batch` | all three print `evil` under the original id; only `git fsck` reports `hash-path mismatch` | a verified commit hash in a writable `.git` does not protect content. This defeats today's `HEAD:` reads and design b |
| P2 | `git fetch file://<that repo> HEAD:refs/heads/x` into a fresh bare repo; once by default, once with `fetch.fsckObjects=true` | default: `missing blob object …`, `did not send all necessary objects`, rc 1, no ref. fsck: `did not receive expected object`, `index-pack failed`, rc 128 | the receiving side re-hashes every object, so a fetch into root-owned storage is the trust step |
| P3 | `GIT_TEST_ASSUME_DIFFERENT_OWNER=1` (git's own switch that simulates a foreign owner) | `detected dubious ownership`. With `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=<dir>` git proceeds. With `safe.directory` in the repo's own config it still refuses | installers running as the operator in a root-owned stage need the env-supplied `safe.directory` (F3.2); the stage's own config cannot grant it |
| P4 | clone of this repo, `chmod -R a-w`, a tracked installer's mtime touched, P3's env set; `ls-files --error-unmatch`, `diff --quiet HEAD --`, `rev-parse HEAD:<path>`, `cat-file blob HEAD:<path>` on the `_wc_sources` paths | rc 0, rc 0, a blob id, the file content; the index stays read-only | the web-console installers' existing git checks work unchanged in a read-only, foreign-owned stage |
| P5 | scratch repo with `core.fsmonitor` set in `.git/config` | the configured command runs on `git status` and on `git diff --quiet HEAD` | root must never run git in the operator's repo. Installers set `GIT_CONFIG_GLOBAL=/dev/null` so `~/.gitconfig` cannot do the same to them |
| P6 | `/bin/bash` 3.2.57: `BASH_ENV=<file that echoes HIJACK>`; `BASH_FUNC_id%%='() { echo FUNC-HIJACK; }'`; `SHELLOPTS=xtrace`; each run with and without `-p`, and under `env -i` | without `-p`: HIJACK printed, `id` replaced, xtrace on. With `-p`: none of the three. Under `env -i`: none | `#!/bin/bash -p` on the bootstrap and the installers; `env -i` re-exec in the bootstrap |
| P7 | (earlier in this session) zsh 5.9.2 and bash 5.3.20: an alias and a function named `/usr/bin/sudo` | both replace the absolute path | residual 1: no design defends against an attacker in the interactive shell |
| P8 | `csrutil status`; ownership | m4-air: SIP **disabled**; m5-air: SIP enabled. `/usr/local` is `root:wheel 0755` on both; `/usr/local/libexec` is absent on both; CLT `git` and `python3` are root-owned; `/opt/homebrew` belongs to the operator account | residual 3; the bootstrap creates `/usr/local/libexec/k3dm` and never uses Homebrew binaries |
| P9 | `/etc/sudoers` | `root 0440`, unreadable, so `env_reset`, `env_keep` and `secure_path` are unproven | the bootstrap does not depend on them (F1.1, F1.2) |
| P10 | `gh api repos/wilddog64/k3d-manager/rulesets` and `branches/main/protection` | one ruleset `main` (`~DEFAULT_BRANCH`): rules `deletion` and `non_fast_forward`, bypass `RepositoryRole`. Branch protection: 1 approving review, `enforce_admins: true`. The repo is public, 34 MB | `deploy/hub` and the release branches are unprotected (Q1); the fetch needs no credentials |

## Contract readers

| Where | Reads / writes | Change |
|---|---|---|
| `bin/k3dm-promote-authority:1` | shebang `#!/usr/bin/env bash` | `#!/bin/bash -p` (moves to bash 3.2) |
| `bin/k3dm-promote-authority:3-5` | `repo`, sources `scripts/lib/system.sh` | unchanged; clean git env after `repo=` |
| `bin/k3dm-promote-authority:18-25` `priv`, `:50` `bootout` | `_run_command --interactive-sudo` | guard first |
| `bin/k3dm-promote-authority:58-75` | `INSTALL_REF`, `fetch origin refs/heads/deploy/hub` (:72) | no fetch; empty = `HEAD`; otherwise it must equal `HEAD` |
| `Makefile:2509-2510` `promote-authority-install` | passes `INSTALL_REF=$$INSTALL_REF` | none (an empty value now means `HEAD`) |
| `Makefile:647-672` web-console targets | run `bin/k3dm-web-console-*` from the checkout | none. Privileged verbs now refuse with the guard line, which tells the operator to use the stage |
| `bin/k3dm-web-console-sshd:1`, `:2-5` `_wc_main_env`, `:743-772` `main` | shebang, PATH, sourcing | `-p`; `_wc_clean_git_env` after sourcing the common file |
| `bin/k3dm-web-console-sshd:7-23` `_wc_sources`, `:154-155` `_wc_blob`, `:679-682` | `git ls-files`, `diff --quiet HEAD`, `HEAD:` blobs | none; works in the stage (P4) |
| `bin/k3dm-web-console-sshd:95-96`, `bin/k3dm-web-console-totp:29-30` | refuse root | unchanged (why b″ was rejected) |
| `bin/k3dm-web-console-totp:1`, `:2-5` `_wct_main_env`, `:519-546` `main` | shebang, sourcing | `-p`; `_wc_clean_git_env` |
| `bin/k3dm-web-console-totp:72-90` `_wct_sources`, `:155`, `:369-370` | git `HEAD:` reads; `:356-360` uses `$PWD` as the "checkout" for the tmux path check | none; `$PWD` is now the stage |
| `scripts/lib/web_console_common.sh:15-17` `_wc_priv` | `_run_command --interactive-sudo --soft --quiet` | guard first |
| `scripts/lib/web_console_common.sh:32-45` `_wc_fixture_gate` | replaces `_wc_priv` in fixture mode | unchanged; fixture tests bypass the guard by design |
| `scripts/lib/system.sh` | sourced by the dispatcher, bin scripts, Makefile and tests | adds `_k3dm_verified_stage_check` plus two variables; no existing name changes (grep: no `_k3dm_verified_stage` or `k3dm-verified` anywhere in `bin`, `scripts` or `Makefile`) |
| `scripts/lib/foundation/scripts/lib/system.sh:50-200` `_run_command`, `_run_command_resolve_sudo` | sudo handling | **unchanged** (repo rule: never weaken) |
| `scripts/tests/bin/promote_authority.bats:11-16` | greps the Makefile target names and `not-installed.list:48-49` | unchanged |
| `scripts/tests/bin/promote_authority.bats:18-60` | stub `system.sh` defining only `_run_command` | adds a pass-through `_k3dm_verified_stage_check` stub. Its `INSTALL_REF=HEAD` runs (:120-136) stay valid |
| `scripts/tests/bin/web_console_sshd.bats`, `web_console_totp.bats` | fixture mode (`K3DM_WC_ROOT`) | unchanged; must stay green |
| `docs/howto/promote-authority.md:3-7`, `:92-96` | install steps; the fresh-clone workaround | rewritten for the two-step flow; the workaround's gap is stated |
| `docs/howto/web-console-sshd.md:8-22`, `docs/howto/web-console-totp.md:8-57` | `make install-…` / `bin/…` commands | privileged verbs run from the stage |
| **writer** (new) `bin/k3dm-verified-stage` | creates `/var/db/k3dm-verified/{repo.git,stage/<c>}` and `/usr/local/libexec/k3dm/` | new paths. promote-authority uses `/var/db/k3dm-promote` and `/usr/local/libexec/k3dm-promote` (`:9-11`), so nothing collides |
| reader (new) `_k3dm_verified_stage_check` | `/var/db/k3dm-verified/stage/<c>` and `.git/k3dm-verified` | new |

## Acceptance

```yaml
must:
  M1: k3dm-verified-stage, run as root with a 40-hex commit reachable from the anchor ref, fetches by its constant URL into a root-owned bare repo with fsckObjects on, creates /var/db/k3dm-verified/stage/<c> checked out at <c>, owned by root with no group or other write bit, writes .git/k3dm-verified = <c>, prints the commit, the main, deploy/hub and --ref tips, the blob ids of the installer set and the next commands, and exits 0 without running any installer
  M2: k3dm-verified-stage exits non-zero before any fetch when not run as root, when the commit is not exactly 40 lowercase hex, or when --ref is malformed; prints UNPROTECTED REF for any --ref other than main
  M3: _k3dm_verified_stage_check returns 0 for a directory that passes every F2 condition and 12 with the one-line message otherwise
  M4: from a directory that passes the guard, every existing promote_authority, web_console_sshd and web_console_totp test passes, with the only test edit being the promote stub's pass-through guard; promote_authority.bats passes with the installer running under /bin/bash 3.2
  M5: promote-authority install treats an empty INSTALL_REF as HEAD and never runs git fetch
  M6: --install-self <c> replaces /usr/local/libexec/k3dm/k3dm-verified-stage with the stage's copy, root:wheel 0755, through a temp file and mv, and prints old and new blob ids
  M7: scripts/lib/foundation/ and the bodies of _run_command and _run_command_resolve_sudo are byte-identical to the base commit
must_not:
  N1: any installer reaches _run_command --interactive-sudo for any verb when started from a directory that is not a verified stage (a plain checkout, a stage owned by the operator, a stage whose marker or HEAD differs from its name)
  N2: k3dm-verified-stage creates or reuses a stage for a commit that is not an ancestor of the anchor ref on the fetched remote
  N3: k3dm-verified-stage stages content that differs from the commit's tree when the remote serves a corrupted object; it runs git in, or reads objects from, any repository other than its own repo.git and the stage
  N4: a GIT_* variable in the installer's environment (GIT_DIR, GIT_OBJECT_DIRECTORY, GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_CONFIG_GLOBAL pointing at a config with core.fsmonitor) changes which blob an installer reads or runs a command
  N5: BASH_ENV, an exported function or SHELLOPTS in the environment takes effect inside the bootstrap or any installer
  N6: k3dm-verified-stage reaches its fetch with any environment variable outside its allowlist
  N7: promote-authority installs a payload from a commit other than its HEAD
evidence:
  - {id: E1, proves: [M1, N2, N3], kind: offline, intent: "You will see tests source the bootstrap, point it at a scratch bare repo served over file:// and a scratch base directory, and find that a commit on main gets a stage with the right marker and tree, a commit only on a side branch is refused, and a remote with one corrupted object makes the fetch fail with no stage created.", command: "bats scripts/tests/bin/verified_stage.bats", red: "today's tree: bin/k3dm-verified-stage does not exist, so every test fails"}
  - {id: E2, proves: [M2, N6], kind: offline, intent: "You will see the bootstrap run as a normal user refuse at once, a short or uppercase commit refused, a bad --ref refused, and a run with BASH_ENV, GIT_DIR and an extra variable set show (through a logging git stub reached only after the re-exec) that only the allowlisted names were present.", command: "same run", red: "missing file"}
  - {id: E3, proves: [M3, N1], kind: offline, intent: "You will see the guard tested against a scratch base with the owner variable set to the test user: a correct stage passes, and a writable stage, a wrong marker, a HEAD that differs from the name and a plain checkout each fail with the one-line message. Then each installer is run from a plain checkout with a logging _run_command, and no sudo call is logged for install, uninstall, revoke, enroll, rotate, check or status.", command: "bats scripts/tests/bin/web_console_verified_stage.bats scripts/tests/bin/promote_authority.bats", red: "today's tree: _wc_priv and priv call _run_command --interactive-sudo from any checkout, and the logging stub records it"}
  - {id: E4, proves: [N4], kind: offline, intent: "You will see the sshd and TOTP installers run in fixture mode with GIT_DIR pointing at a second repo whose template differs, and with GIT_CONFIG_GLOBAL pointing at a config whose core.fsmonitor writes a marker file; the rendered output matches the stage's own file and the marker never appears.", command: "bats scripts/tests/bin/web_console_verified_stage.bats", red: "today's tree: _wc_sources and _wc_blob read the second repo's blob, and fsmonitor writes the marker"}
  - {id: E5, proves: [N5], kind: offline, intent: "You will see the bootstrap and the three installers started with BASH_ENV pointing at a script that writes a marker file, an exported function named git, and SHELLOPTS=xtrace; no marker, no call to the function, no trace output.", command: "bats scripts/tests/bin/verified_stage.bats scripts/tests/bin/web_console_verified_stage.bats scripts/tests/bin/promote_authority.bats", red: "today's shebangs lack -p: the BASH_ENV marker appears for all three installers"}
  - {id: E6, proves: [M5, N7], kind: offline, intent: "You will see promote-authority install run in the existing scratch tree with INSTALL_REF empty, equal to HEAD, and naming another commit; the first two install HEAD's blobs, the third is refused, and the call log contains no fetch.", command: "bats scripts/tests/bin/promote_authority.bats", red: "today's tree: an empty INSTALL_REF logs git fetch origin refs/heads/deploy/hub, and another commit is installed"}
  - {id: E7, proves: [M4], kind: offline, intent: "You will see the whole existing promote-authority, console sshd and console TOTP suites pass, and the git diff of those .bats files show only the added stub line and new tests.", command: "bats scripts/tests/bin/promote_authority.bats scripts/tests/bin/web_console_sshd.bats scripts/tests/bin/web_console_totp.bats; python3 -m pytest scripts/tests/bin/test_promote_daemon.py scripts/tests/bin/test_web_console_totp.py", red: "regression guard: drop safe.directory from _wc_clean_git_env and run the suites from a stage owned by another user (GIT_TEST_ASSUME_DIFFERENT_OWNER=1); the source checks fail"}
  - {id: E8, proves: [M6], kind: offline, intent: "You will see --install-self run against a scratch self-directory replace the bootstrap with the staged copy, leave no temp file behind, and print both blob ids.", command: "bats scripts/tests/bin/verified_stage.bats", red: "missing file"}
  - {id: E9, proves: [M7], kind: offline, intent: "You will see a diff against the base commit that lists no file under scripts/lib/foundation/, and the two sudo functions extracted from system.sh compared byte for byte.", command: "git diff --stat <base>..HEAD -- scripts/lib/foundation/; diff of _run_command and _run_command_resolve_sudo bodies at base and HEAD", red: "regression guard: any edit to _run_command shows up in the diff"}
  - {id: E10, proves: [M1, N1], kind: live, intent: "You will see the operator, at home on the hub's physical console, install the bootstrap, stage the release commit, compare the printed commit with GitHub on the iPad, then run promote-authority print-plan and web-console-sshd check from the stage; and see make install-web-console-sshd from the normal checkout stop with the guard line before any password prompt. Claude reads the pasted output.", command: "operator, m5-air console: sudo /usr/local/libexec/k3dm/k3dm-verified-stage <c>; <stage>/bin/k3dm-web-console-sshd check; cd ~/src/gitrepo/personal/k3d-manager && make install-web-console-sshd", red: "n/a (live)"}
interface:
  - "new: sudo /usr/local/libexec/k3dm/k3dm-verified-stage <40-hex commit> [--ref <branch>] | --install-self <40-hex commit>; exit 0 ok, 2 usage, 3 bootstrap not root-owned or not root, 4 fetch, 5 not reachable, 6 stage"
  - "new: _k3dm_verified_stage_check <dir> in scripts/lib/system.sh; returns 0 or 12"
  - "new: _wc_clean_git_env in scripts/lib/web_console_common.sh"
  - "changed: installers' privileged verbs return non-zero (the guard's 12 is surfaced or mapped) outside a verified stage; promote-authority INSTALL_REF must equal HEAD, empty means HEAD"
  - "unchanged: _run_command, Makefile target names, installer verbs and flags"
```

## Files

| # | File | New? | Child |
|---|---|---|---|
| 1 | `bin/k3dm-verified-stage` | new | A |
| 2 | `scripts/tests/bin/verified_stage.bats` | new | A |
| 3 | `scripts/lib/system.sh` | | B |
| 4 | `scripts/lib/web_console_common.sh` | | B |
| 5 | `bin/k3dm-web-console-sshd` | | B |
| 6 | `bin/k3dm-web-console-totp` | | B |
| 7 | `scripts/tests/bin/web_console_verified_stage.bats` | new | B |
| 8 | `bin/k3dm-promote-authority` | | C |
| 9 | `scripts/tests/bin/promote_authority.bats` | | C |
| 10 | `docs/howto/verified-stage.md` | new | D |
| 11 | `docs/howto/promote-authority.md` | | D |
| 12 | `docs/howto/web-console-sshd.md` | | D |
| 13 | `docs/howto/web-console-totp.md` | | D |

13 files: 4 new, 9 changed. No Makefile change, nothing under `scripts/lib/foundation/`, no lib-foundation upstream change.

## Routing

The four children share no file. Each is its own `docs/plans/v1.45.1-r2-<letter>-*.md` with a slice of this Acceptance block.

- **A — Luna** (`gpt-6-luna`): the bootstrap and its tests (E1, E2, E5 bootstrap part, E8). Has no dependencies.
- **B — Luna**: the guard, the clean git env and the web-console installers (E3 web part, E4, E5 web part, E7 web part, E9).
- **C — Luna**: promote-authority (E3 promote part, E5 promote part, E6, E7 promote part). Calls `_k3dm_verified_stage_check`
  from B; its tests stub the guard, so it can run alongside B, but it lands after B.
- **D — Flash** (`gemini-3.8-flash-medium`): docs, after A-C land. The new howto covers the one-time bootstrap install at the
  physical console, the two-step flow, the second-channel check on the iPad, the five residuals, and the optional separate admin
  account. promote-authority.md:92-96 says the old fresh-clone workaround only defeats tampering done before the clone.

WIP: three Luna dispatches are open (R4, V4, R1), so A-C queue behind them. P2 does not exceed the limit.

## Worker definition of done (A-C)

- Change only your child's files. Work offline: no network (use a `file://` scratch remote), no sudo, no Keychain, nothing
  outside `$BATS_TEST_TMPDIR`. Assert the scratch base and HOME first.
- Never run the bootstrap's `main` for real. Tests source it and override `_VS_*`, or run it as the normal user to check that
  it refuses.
- Show each must_not test red on today's tree, then green. Mutations to show:
  - drop `-p` from one shebang;
  - drop the guard from `_wc_priv`;
  - read `GIT_DIR` again by removing the unset;
  - make the bootstrap read the URL from `repo.git` config;
  - remove `fsckObjects`. The corrupted-remote test must still fail closed through index-pack, and the test records which
    check caught it.
- `shellcheck` on every changed script; `/bin/bash -n` on each; the full runs of the touched suites, with rc and counts.
- Leave changes uncommitted; no push; do not touch `docs/bugs/`. E10 belongs to the operator and Claude.

## Rollout (operator, at home, with sudo)

1. **Land A-D, then promote** (`make hub-deploy REF=<commit>`; the hub reads `deploy/hub`).
2. **First install of the bootstrap, at the hub's physical console.**
   - **On the iPad:** open
     `https://api.github.com/repos/wilddog64/k3d-manager/contents/bin/k3dm-verified-stage?ref=<c>` and note `sha` (the blob id).
   - **On the Mac:**
     - Download the file as root, without your environment, so `~/.curlrc` cannot act:
       `sudo /usr/bin/env -i /usr/bin/curl -q -fsS -o /var/root/k3dm-verified-stage.new https://raw.githubusercontent.com/wilddog64/k3d-manager/<c>/bin/k3dm-verified-stage`
     - Hash it the same way, outside any repository and with no filters:
       `sudo /usr/bin/env -i /Library/Developer/CommandLineTools/usr/bin/git -C /var/root hash-object --no-filters k3dm-verified-stage.new`
     - The hash must match the iPad. Then install it:
       `sudo /usr/bin/install -d -o root -g wheel -m 0755 /usr/local/libexec /usr/local/libexec/k3dm` and
       `sudo /usr/bin/install -o root -g wheel -m 0755 /var/root/k3dm-verified-stage.new /usr/local/libexec/k3dm/k3dm-verified-stage`
3. **Each later install, upgrade or uninstall:**
   - Read the commit on GitHub on the iPad.
   - Run `sudo /usr/local/libexec/k3dm/k3dm-verified-stage <c>` and compare the printed commit and tips with the iPad.
   - Run the printed `<stage>/bin/…` command.
4. **Bootstrap updates** go through `--install-self <c>` and never through step 2 again.
5. **Re-run web-console on m4-air the same way.** Its SIP is disabled (residual 3, Q5).
6. **Claude reads the pasted output (E10).** Then the bug moves to `LIVE-VERIFIED`.

## Open questions

- **Q1 — anchor ref.** Only `main` is protected. promote-authority installs the `deploy/hub` commit, and release-time installs
  use the release branch, and both are unprotected.
  - Recommended: the default is `main`, and `--ref` is allowed with an `UNPROTECTED REF` banner.
  - Alternative: refuse anything not on `main` until those branches get rulesets.
- **Q2 — separate admin account.** A dedicated macOS admin user for installs closes residual 1.
  - Recommended: document it as optional hardening, not required.
- **Q3 — stage pruning.** Recommended: no automatic pruning in rev 1; the howto documents `sudo rm -rf` of old stages.
- **Q4 — read-only verbs that use sudo.** `web-console-sshd check` and `web-console-totp status` now need the stage too.
  - Recommended: yes. They run checkout code under sudo exactly like install does.
- **Q5 — SIP on m4-air.** Disabled today, which widens residual 3. This is the operator's decision, outside this fix.
- **Q6 — hardware-backed signed tags** as a second anchor. Recommended: out of scope for v1.45.1; add a row to `docs/ideas.md`.
- **Q7 — reviewer check (Fable).** Confirm that promote-authority's post-copy hash re-check covers every rendered file
  (residual 5). If it does not, that is a separate bug, not part of this spec.
