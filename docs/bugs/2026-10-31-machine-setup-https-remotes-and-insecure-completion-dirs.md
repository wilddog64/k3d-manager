# Bug: machine setup leaves HTTPS remotes and a world-writable ~/.zplug, and its check never opens a shell

**Status:** OPEN
**Priority:** P3
**Approval:** operator, 2026-10-31 ("yes, file a v1.43.13 bug")
**Filed:** 2026-10-31
**Detected by:** the operator, on the first interactive SSH login to the new M5 hub after v1.43.12's
`make machine-setup ROLE=hub`; diagnosed by Claude
**Affected:** `bin/k3dm-machine-setup` (`clone_if_absent`, `clone_config`, `ensure_operator_include`,
check mode); `scripts/etc/machine/repos.list`
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-29-machine-setup-loops-read-manifest-on-stdin.md` (same script);
`docs/howto/machine-setup.md`

## Observed failure

Two days after the M5 setup reported success, the first SSH login into it showed three faults. None
was in the setup output or in `--check`:

1. **direnv hung on `Username for 'https://github.com':`.** `personal.envrc` runs the
   `sync-{claude,gemini,codex,copilot}` scripts, which `git fetch`. The setup had cloned those four
   repos and zshdotfiles over `https://`, and the M5 has no HTTPS credential. Claude switched the five
   remotes to `git@github.com:` by hand on 2026-10-31.
2. **`compdef: command not found` for yq, then `_main_complete:412: _lastcomp`** on every Tab.
   `~/.zplug` was `drwxrwxrwx` with 10,585 group- or world-writable entries. `compaudit` reported the
   folders as insecure, `compinit` stopped, and `compdef` was never defined. Claude fixed it with
   `chmod -R go-w ~/.zplug`. The M2 had 1 such entry (`zcompdump.m2-air.local.1467`); the M4 had 0.
3. The review of the v1.43.12 setup missed both, because they only show in an interactive login shell:
   the setup log, `--check` and the BATS suites never start one.

There is a third risk, which has not happened yet. On 2026-10-31 `~/.ssh/config` on the M4 and M5 became a
symlink into `zshdotfiles/ssh/<host>/config`. When the Include line is missing, `ensure_operator_include`
writes a temp file and `mv`s it over `~/.ssh/config`. That replaces the symlink with a plain file, so the
tracked copy drifts. The M2's config has no Include, so its next setup run would do this.

## Root cause

1. `clone_config` builds `https://github.com/wilddog64/<repo>.git`, and 39 `repos.list` rows are
   `https://`. HTTPS is right for the first clone, because a new Mac has no GitHub key yet. But nothing
   switches the remote once a key exists, and nothing reports it.
2. Setup checks that zplug is installed, not that zsh will load completions from it. Why `~/.zplug` was
   world-writable on the M5 is **not known**. It is a clone of `zplug/zplug`, created 2026-10-30 05:10
   (30 minutes after the Homebrew zplug install), with umask 022 now. The setup log has gone and the
   setup does not create the folder itself. The fix must not depend on knowing the cause.
3. `--check` checks files, links and remotes one at a time. It never runs what the operator runs: a
   login shell over SSH.

## Fix

1. **Remotes.** Add `switch_ssh_remotes`, run after `install_repos`. It runs only when
   `ssh -o BatchMode=yes -o ConnectTimeout=10 -T git@github.com` prints `successfully authenticated`.
   For each repo setup manages (the `repos.list` paths for this role, the four config repos and
   zshdotfiles) whose origin is `https://github.com/wilddog64/...`, it sets origin to
   `git@github.com:wilddog64/<repo>.git`, then runs `git ls-remote origin HEAD`. If that fails, it puts
   the HTTPS URL back. It only touches `wilddog64` remotes that `normalize_github_remote` accepts, so
   upstream clones such as smartcd stay as they are. Report lines: `remote:<path> switched to ssh`,
   `ok`, or `https (no GitHub SSH key yet)`. Without a key this is a report line, not a failure.
   In check mode an `https` wilddog64 remote is a failure only when GitHub SSH works, because only
   then can it be fixed.
2. **Completion folders.** Add `check_completion_dirs`. It looks under `~/.zplug`, `~/.zsh` and
   `$(brew --prefix)/share/zsh` for group- or world-writable entries, using `find -perm -g+w -o -perm -o+w`
   and following no symlinks. The result is one line: `zsh:completion-dirs ok`, or a failure with the
   count and the first path. In setup mode it runs `chmod -R go-w` on paths under `$HOME` only. It never
   changes the Homebrew prefix; it reports it instead.
3. **Do not break a linked ssh config.** `ensure_operator_include`: when `~/.ssh/config` is a symlink,
   add the Include line to the file it points at, not by replacing the link. If that file is not
   writable, report `ssh:config skipped (linked; add the Include in <target>)` and change nothing.
   Make the same change anywhere else in the script that `mv`s over a file under `~/.ssh` or a
   shell-link target.
4. **A login-shell check.** Add `--check-shell HOST` (and `make machine-check-shell HOST=`). It runs
   `ssh -tt -o BatchMode=yes HOST 'exit'` under a 60-second timeout, keeping stdout and stderr. It fails
   if:
   - the run times out (a prompt is waiting);
   - the output matches `Username for|Password for|command not found|insecure directories|compinit|_lastcomp|Permission denied`;
   - the exit code is not 0.

   It prints the matched lines, with home paths and anything token-shaped redacted. It changes nothing on
   either Mac. `docs/howto/machine-setup.md` names it as the last step of a new-Mac setup.
5. Docs: `docs/howto/machine-setup.md` (remote switch, completion folder check, linked ssh config, the
   new check), and a `CHANGELOG.md` entry.

## Files

- `bin/k3dm-machine-setup`
- `Makefile`
- `scripts/tests/bin/machine_setup.bats`
- `docs/howto/machine-setup.md`
- `CHANGELOG.md`

## What NOT to do

- Do not clone over SSH on the first run. A new Mac has no key, and the first clone must still work.
- Do not change any remote that is not `wilddog64`'s, and do not rewrite a remote with a token in it
  except by removing that token.
- Do not run `chmod` outside `$HOME`, and do not touch Homebrew's files.
- Do not replace a symlinked `~/.ssh/config`, `~/.zshrc`, `~/.zshenv` or `~/.zsh`.
- `--check-shell` must not send keys, start a session that stays open, or print the environment.

## Acceptance

```yaml
must:
  M1: with GitHub SSH working, setup switches every https wilddog64 origin it manages to git@github.com and leaves other owners' remotes alone
  M2: without GitHub SSH, setup keeps https, prints `https (no GitHub SSH key yet)` and does not fail; with GitHub SSH working, check mode fails on an https wilddog64 remote
  M3: a group- or world-writable entry under ~/.zplug fails check mode with the count and first path, and setup mode clears it
  M4: when ~/.ssh/config is a symlink without the Include, setup adds the Include to the target file and the symlink is still a symlink afterwards
  M5: --check-shell fails when the login shell prints a credential prompt, `command not found`, or a compaudit warning, or does not exit in 60 s, and passes on a clean shell
must_not:
  N1: no remote is switched when `git ls-remote` over ssh fails; the https URL is restored
  N2: setup never runs chmod on a path outside $HOME (the Homebrew prefix is reported, not changed)
  N3: setup never replaces a symlinked ~/.ssh/config with a regular file
  N4: --check-shell output never contains an unredacted home path or token-shaped string, and it changes no file on either Mac
evidence:
  E1:
    proves: [M1, M2, N1]
    kind: offline
    intent: >-
      You will see setup, with a git and ssh stub that reports "successfully authenticated", switch two
      https wilddog64 fixture clones to ssh and leave a cxreg clone alone; with ls-remote failing, the url
      goes back to https; with no key, the report says https and setup exits 0. It failed if it passes
      against today's setup script.
    what: bats scripts/tests/bin/machine_setup.bats; the fixture asserts HOME is a scratch dir first; the ssh -T output is captured from a real `ssh -T git@github.com` (host and date in a comment)
  E2:
    proves: [M3, N2]
    kind: offline
    intent: >-
      You will see a scratch ~/.zplug with one 0777 file fail check mode naming it, and setup mode leave it
      0755, while a writable fixture "brew prefix" is reported and left unchanged. A paired control shows a
      clean ~/.zplug passing. It failed if the brew fixture's mode changes.
    what: bats scripts/tests/bin/machine_setup.bats
  E3:
    proves: [M4, N3]
    kind: offline
    intent: >-
      You will see a scratch ~/.ssh/config symlink with no Include still be a symlink after setup, its target
      gaining the Include line once. It failed if `[ -L ~/.ssh/config ]` is false afterwards, or the test
      passes against today's script.
    what: bats scripts/tests/bin/machine_setup.bats
  E4:
    proves: [M5, N4]
    kind: offline
    intent: >-
      You will see --check-shell against a stub ssh fail on a captured "Username for 'https://github.com':"
      line, a captured compaudit warning and a hang, print each line redacted, and pass on a clean stub.
      It failed if the clean stub fails or a hanging stub passes.
    what: bats scripts/tests/bin/machine_setup.bats; the stub output is the real text seen on the M5 on 2026-10-31
  E5:
    proves: [M1, M3, M5]
    kind: live
    intent: >-
      You will see `make machine-check-shell HOST=m5-air.local` and `HOST=m2-air.local` pass, and
      `bin/k3dm-machine-setup --role hub --check` on the M5 report every managed remote as ssh and
      zsh:completion-dirs ok. It failed if any shell prints a prompt or error.
    what: Claude runs both checks from the M4 over SSH and records the output
interface:
  - bin/k3dm-machine-setup --role hub|worker|console [--check|--dry-run]
  - bin/k3dm-machine-setup --check-shell HOST
  - make machine-check-shell HOST=
  - ~/.ssh/config, ~/.zplug, git remotes of the clones setup manages
```

**Intent approved:** operator, 2026-10-31 ("as well as those two bugs")
