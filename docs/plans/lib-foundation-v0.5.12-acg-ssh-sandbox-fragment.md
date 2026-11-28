# v0.5.12 — ACG writes sandbox SSH hosts to its own fragment, never the operator's `~/.ssh/config`

**Status:** SPEC rev 1 — folds blind reviews (Fable + Neon, both NEEDS FIXES on rev 0); awaiting operator intent
approval and decisions D1–D3 (k3d-manager child spec)
**Filed:** 2026-11-27
**Intent approved:** operator, 2026-11-27
**Operator decisions:** D1–D3 (k3d-manager child spec) accepted as defaults, 2026-11-27.
**Intent approval words:** "Approve all three"; W3 D1 "a: leave unmanaged"; W4 "Accept all defaults" (D1 ~/.ssh/k3dm-sandbox.conf, D2 fail before VM, D3 operator dotfile Include + stale m4 blocks); WIP "Approve 4/3"
**Approval:** operator, 2026-11-27 (k3d-manager session: P2 re-triage "check first in v1.46.0 — close if already
resolved, else decide"; check found it still present; "can you start first group - 5 P2s (review by Fable/Neon)").
Dispatch: Claude; not a hub or Hostinger change. Running a real ACG sandbox is the operator's step.
**Branch:** `release/v0.5.12` (cut from `main` after v0.5.11, `d1a58b2`; Claude creates it after intent approval)
**Risk:** medium — every ACG `make up` path depends on `ssh ubuntu` resolving to the new server; a missing or
misplaced `Include` would break provisioning, so it is now checked **before** the stack is created.
**Implementer:** Luna (`codex`, `gpt-6-luna`). **Verifier:** Claude, from Acceptance.
**Requested by:** k3d-manager
[`docs/bugs/2026-11-21-acg-ssh-hosts-written-into-tracked-ssh-config.md`](https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.46.0/docs/bugs/2026-11-21-acg-ssh-hosts-written-into-tracked-ssh-config.md)
(P2). k3d-manager consumes this through a subtree pull (its child spec
`docs/plans/v1.46.0-acg-ssh-config-fragment.md`), which reuses the shared helper file added here.

## Rev 1 changes (from the reviews)

- New shared file `scripts/lib/ssh_fragment.sh` holds the fragment logic once; `acg.sh`, the k3d-manager GCP/Azure
  providers and `shopping_cart.sh` all call it (Fable: one helper, not three copies).
- Paths resolve at **call time** (functions), not at source time (Neon B5): tests and callers can set
  `K3DM_SSH_SANDBOX_FRAGMENT` after sourcing.
- No `_err` anywhere (it `exit`s — Neon B3): errors are `printf 'ERROR: %s\n' "[ssh-fragment] …" >&2; return 1`.
- The `_agent_audit` 8-`if` rule is spelled out (Neon B2): every new or edited helper uses the `function` keyword,
  `acg_teardown` (already 8/8) gets no new `if`, and embedded Python `if` lines count.
- Include handling: a **static pre-flight before the stack is created** (fail-fast, operator decision D2 in the child
  spec) plus a post-write **effect check** with `ssh -G` (catches a stale `Host ubuntu` above the `Include`), warned
  once per process (Fable; Neon M6, M8).
- Writes are one atomic `mktemp` → `chmod 600` → `mv`, the symlink check (`-L`) runs on write **and** teardown, and
  values reach Python through `sys.argv`, never interpolated (Neon M7).
- Teardown placement and return code are fixed (Neon M10); files are `CHANGE.md` and `docs/api/acg.md`, the gate is
  `AGENTS.md`, not `docs/contrib.md` (Neon B4); symlinked `~/.ssh/config` test and an offline `ssh -G` control added
  (Neon m13); readers and line ranges corrected (Neon m14).

## Problem

`scripts/lib/acg/acg.sh` edits the operator's main SSH config in place:

- `:18` `_ACG_SSH_CONFIG="${HOME}/.ssh/config"` (bound at source time).
- `:71-91` `_acg_update_ssh_config <ip>`: `mkdir -p` + `touch` the main config; inline Python (with the path, alias
  and IP interpolated into the source, and a `re.DOTALL` pattern that can run into the next `Host` block) rewrites the
  `HostName` of `Host ubuntu` and `Host ubuntu-tunnel`, then calls `_acg_upsert_ssh_host ubuntu <ip>`.
- `:93-117` `_acg_upsert_ssh_host <alias> <ip>`: returns 0 if the main config is missing, else rewrites the alias's
  `HostName` or appends `Host <alias> / HostName / User ubuntu / IdentityFile ~/.ssh/k3d-manager-key.pem /
  StrictHostKeyChecking no`. Python `open(path, 'w')` writes **through** a symlinked config.
- Callers: `_acg_cf_deploy` `:320` (server) and `:324` (`ubuntu-1..N` agents), reached from `acg_provision` `:571`;
  `acg_status` `:596`. Help text `:522`, `:538`; `acg_teardown --help` `:904-906`.
- `acg_teardown` (`:899-964`) removes the `ubuntu-k3s` kube context but never the SSH entries.

Each sandbox therefore leaves a change in the operator's dotfiles repo, with dead IPs and `StrictHostKeyChecking no`.

## Proven facts (read-only, Claude, 2026-11-27)

- **m4-air and m5-air link both `~/.ssh/config` and `~/.ssh/config.d` into the `zshdotfiles` repo**; `~/.ssh` itself
  is a real `drwx------` directory on both. m2-air: neither is linked.
- **A file under `~/.ssh/config.d/` lands inside the dotfiles repo and is not ignored** there
  (`git -C zshdotfiles check-ignore ssh/m4-air/config.d/k3dm-sandbox` prints nothing). Default fragment:
  `$HOME/.ssh/k3dm-sandbox.conf`.
- **The stale damage is already committed on m4**: `~/.ssh/config` line 1 `Include ~/.ssh/config.d/operator`, then
  `Host ubuntu-1` (3), `Host ubuntu-2` (8), `Host ubuntu` (13) (`grep -n '^Include\|^Host'` only). Cleaning it is an
  operator dotfile change (child spec D3).
- **Include lines today:** m4 `1: Include ~/.ssh/config.d/operator`; m5 `1:` same, `5: Include ~/.orbstack/ssh/config`;
  m2 `4:` colima, `9:` orbstack.
- OpenSSH takes the first value it finds for each option and expands `Include` in place. An `Include` is only
  unconditional when it appears **before the first `Host`/`Match` line**; after one, it belongs to that block.
- `ssh -G` resolves configuration without connecting, but expands `~` from the passwd home directory, not `$HOME`;
  tests must therefore use an absolute `Include <fragment>` path under `$BATS_TEST_TMPDIR` and `-F <config>`.
- `scripts/lib/agent_rigor.sh:131-144` resets the `if` count only on lines matching `^[[:space:]]*function[[:space:]]+`
  and counts every line matching `^[[:space:]]*if[[:space:](]`, including Python inside a heredoc. Private helpers in
  `acg.sh` before `:437` have no `function` keyword and are not audited; a helper without the keyword placed **after**
  a `function` is counted into that function. `acg_teardown` is at 8/8 today.
- `system.sh:2160` `_err` prints and `exit 1`s.

## Behaviour

1. **New file `scripts/lib/ssh_fragment.sh`** (sourced by `acg.sh` as `"${_LIB_ACG_ROOT}/../ssh_fragment.sh"`, next to
   the existing `cdp.sh` / `vars.sh` sources). Every function uses the `function` keyword and has ≤ 8 `if` lines:
   - `_ssh_fragment_path` — prints `${K3DM_SSH_SANDBOX_FRAGMENT:-${HOME}/.ssh/k3dm-sandbox.conf}` at call time.
   - `_ssh_fragment_main_config` — prints `${HOME}/.ssh/config` at call time (read-only use only).
   - `_ssh_fragment_upsert <alias> <block-file>` — replaces the stanza for exactly `<alias>` (or appends it) with the
     block text in `<block-file>`. Refuses (`ERROR`, return 1, target untouched) if the fragment path is `-L` (dangling
     links included). Creates a missing parent directory with `(umask 077 && mkdir -p -- "$dir")`; never chmods an
     existing directory. Builds the whole new file in `mktemp "$dir/.k3dm-sandbox.XXXXXX"`, `chmod 600` it, then
     `mv -f -- "$tmp" "$fragment"`; removes the temp file on any failure. Stanzas are bounded by the next line matching
     `^[[:space:]]*(Host|Match)[[:space:]]` (case-insensitive); a stanza matches only when its `Host` line holds the
     alias as a whole token.
   - `_ssh_fragment_set_hostname <alias> <ip>` — rewrites `HostName` inside that alias's stanza only, if the stanza
     exists; same symlink refusal and atomic write.
   - `_ssh_fragment_remove <mode> <alias…>` — removes stanzas whose single `Host` token equals one of the aliases;
     mode `acg` also removes any stanza whose token is exactly `ubuntu-[0-9]+`. Same symlink refusal; deletes the
     fragment when only blank lines remain. Never matches by prefix (`ubuntu` never removes `ubuntu-gcp`).
   - `_ssh_fragment_hostname <alias>` — read-only: prints the `HostName` for the alias from the fragment, else from the
     main config, else nothing (used by k3d-manager `shopping_cart.sh`, which cannot use `ssh -G` in tests).
   - `_ssh_fragment_include_preflight` — static check: the main config has, **before its first `Host`/`Match` line**,
     an `Include` (case-insensitive keyword, any whitespace, optional quotes) whose argument is the fragment's
     absolute path, its `~/`-form, or, when the fragment is under `~/.ssh`, its path relative to `~/.ssh`. Missing →
     `ERROR` naming the exact line to add (formatted from the resolved fragment path, `~/`-form when under `$HOME`) and
     "before any Host block", return 1. `K3DM_SSH_SANDBOX_PREFLIGHT=warn` downgrades to a `WARN` and return 0 (for
     operators who manage SSH another way). A missing main config fails the same way.
   - `_ssh_fragment_check_resolves <alias> <ip>` — effect check after a write: `ssh -G -F "$(main config)" <alias>`
     must report `hostname <ip>`; otherwise one `WARN` naming the fragment and the Include line, and return 0. Warned
     at most once per process (global `_SSH_FRAGMENT_WARNED`); skipped silently when `ssh` is not on `PATH`.
   - Python, if used, gets every path, alias and IP through `sys.argv` and runs as `_run_command -- python3 - …` (no
     flag other than `--`, so the k3d-manager test stub `shift; "$@"` still works). Pure `awk -v` is equally fine.
2. **`acg.sh` writers.** `_acg_update_ssh_config` and `_acg_upsert_ssh_host` (both converted to the `function`
   keyword) write only through the helpers, with the same block contents as today (`User ubuntu`,
   `IdentityFile ~/.ssh/k3d-manager-key.pem`, `StrictHostKeyChecking no` — unchanged on purpose, sandbox IPs are
   reused; it now lives only in the sandbox file). `_acg_update_ssh_config` updates `ubuntu-tunnel`'s `HostName` only
   if that stanza exists **in the fragment**, then upserts `ubuntu`, then calls `_ssh_fragment_check_resolves ubuntu
   <ip>`. `_acg_upsert_ssh_host` no longer returns early when the main config is missing. Remove `_ACG_SSH_CONFIG`
   (`:18`); nothing else reads it (`grep -n _ACG_SSH_CONFIG` before and after).
3. **Pre-flight.** `acg_provision` calls `_ssh_fragment_include_preflight || return 1` immediately before
   `_acg_cf_deploy` (`:571`) — a `||` line, not a new `if`. A missing Include stops the run before any CloudFormation
   call. `acg_status` does not pre-flight (it only refreshes an IP).
4. **Teardown.** New `function _acg_remove_ssh_hosts()` calls `_ssh_fragment_remove acg ubuntu ubuntu-tunnel`.
   `acg_teardown` calls it as `_acg_remove_ssh_hosts || _warn "[acg] could not clean SSH aliases from <fragment>"`
   on the line before `_info "[acg] Teardown complete"` (`:963`): after the kube context removal, so the rc 1/2/3
   early-return paths keep the fragment (like kubeconfig) and both rc 0 paths (stack deleted, no stack) clean it.
   `acg_teardown`'s return code stays 0 when only SSH cleanup failed (k3d-manager `bin/cluster-down` would otherwise
   report the cloud teardown UNVERIFIED). No new `if` line inside `acg_teardown`.
5. **Help and docs.** `acg.sh:522`, `:538`, `:904-906` and `docs/api/acg.md` (`acg_provision`, `acg_teardown`) name
   the fragment, the one-time Include line and that teardown removes the aliases. `CHANGE.md`: one line under
   `## [Unreleased]`.

## Files

- `scripts/lib/ssh_fragment.sh` (new)
- `scripts/lib/acg/acg.sh`
- `scripts/tests/lib/acg.bats`
- `scripts/tests/lib/ssh_fragment.bats` (new)
- `docs/api/acg.md`
- `CHANGE.md` (one line under `## [Unreleased]`)

## Contract readers

- **Writers of the sandbox SSH aliases** (all move to the fragment): `scripts/lib/acg/acg.sh:71-91`, `:93-117`;
  callers `:320`, `:324` (in `_acg_cf_deploy`, from `acg_provision:571`), `:596` (`acg_status`). k3d-manager writers
  `scripts/lib/providers/k3s-gcp.sh:84-106,286-295` and `k3s-az.sh:86-106,287-296` move in the k3d-manager child,
  through this file's helpers.
- **Readers via `ssh`/`autossh`** (unchanged, resolve through the Include): k3d-manager `bin/cluster-up:945,
  1460-1463` and the reverse tunnel `:1455-1456`; `scripts/plugins/argocd.sh:1635,1656`;
  `scripts/plugins/shopping_cart.sh:61,549,1355,1437,1566`; `scripts/plugins/tunnel.sh:13,99,145`
  (`TUNNEL_SSH_HOST`, set to `ubuntu`/`ubuntu-gcp`/`ubuntu-azure` by `bin/cluster-refresh`); `acg.sh` `_acg_check_k3s`
  `:338-340`; `ssh ubuntu …` in k3d-manager `docs/howto/acg.md:213`.
- **Readers that parse the file directly (break without a change):** k3d-manager `scripts/plugins/shopping_cart.sh`
  `_k3sup_join_agent:1224-1231`, `_k3s_agent_address:1246-1255`, `deploy_app_cluster:1464-1469` (`awk` on
  `${HOME}/.ssh/config`; awk does not follow `Include`). Fixed in the k3d-manager child with `_ssh_fragment_hostname`.
- **Tests asserting the old path:** this repo `scripts/tests/lib/acg.bats:119-172` (three `_acg_update_ssh_config`
  tests) — **authorized to change** to assert the fragment; intent (create, idempotent, keep agent aliases, update
  server + tunnel) kept. k3d-manager `scripts/tests/lib/acg.bats:94-147` and `scripts/tests/plugins/acg.bats:13,82-142`
  change in the child.
- **Env vars (new):** `K3DM_SSH_SANDBOX_FRAGMENT`, `K3DM_SSH_SANDBOX_PREFLIGHT` — reader: `ssh_fragment.sh` only.
- **Related, unchanged:** k3d-manager `scripts/lib/ssh_config_guard.sh` (operator fragment `config.d/operator`,
  `K3DM_SSH_CONFIG`) and `bin/k3dm-machine-setup:503-524` (`ensure_operator_include`). No writer of `~/.ssh/config` is
  added.

## What NOT to Do

- Never write, `touch`, `mkdir` against, chmod or `mv` the main `~/.ssh/config`; never write or delete through a
  symlink (write or teardown).
- Never call `_err` (it exits the caller's shell).
- Do not change `StrictHostKeyChecking`, `IdentityFile`, the key name, or any AWS call.
- Do not touch `~/.ssh/config.d/`.
- No network, no real `aws`; never read real `~/.ssh` contents. `ssh -G` only with `-F <fixture>`.
- Every new or edited function uses the `function name() {` form and has ≤ 8 `if` lines (embedded Python counts).
  `acg_teardown` and `acg_provision` gain no `if` line. k3d-manager's pre-commit `_agent_audit` refuses the subtree
  pull otherwise (it blocked the v0.5.8 pull, k3d-manager `docs/plans/v1.45.1-istioctl-a2-lib-foundation-split.md:22-27`).

## Test design (the implementer cannot ask)

- `setup()` keeps `HOME=$BATS_TEST_TMPDIR/home` (`acg.bats:5-10`); `ssh_fragment.bats` does the same and sources
  `scripts/lib/ssh_fragment.sh` with minimal `_info`/`_warn` stubs and the flag-stripping `_run_command` stub from
  `acg.bats:550`. First lines of every new or changed test: `[[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]` and
  `[[ "$(_ssh_fragment_path)" == "$HOME"/* ]]`.
- **Main-config guard, regular file:** write a known main config (`Include <abs fragment>` + `Host keep`), record
  `shasum` and mode; after provision-writer, status-writer and teardown calls, both unchanged. **Symlinked:** main
  config is a symlink to a fixture outside `$HOME/.ssh`; afterwards still `-L`, target `shasum` unchanged. **Absent:**
  still absent afterwards.
- **Fragment:** created 0600 in a new 0700 dir; an existing dir's mode unchanged; idempotent (one `Host ubuntu` after
  two calls); `ubuntu-1..3` upserted; an existing fragment `ubuntu-tunnel` updated; a `ubuntu-tunnel` in the main
  config untouched; a `Host ubuntu` stanza with no `HostName` followed by `Host ubuntu-gcp` — `ubuntu-gcp` unchanged.
- **Injection:** an alias/IP value containing `'` and `$(touch <sentinel>)` is written literally or refused, never
  executed (the sentinel file must not appear).
- **Pre-flight:** fails (non-zero, message names the exact line) with no Include; fails when the Include sits after a
  `Host` line; passes for `Include ~/.ssh/k3dm-sandbox.conf`, the absolute form, `include  "<abs>"` and the relative
  form; `K3DM_SSH_SANDBOX_PREFLIGHT=warn` → 0 with a WARN. `acg_provision --confirm` with a failing pre-flight and a
  recording `aws` stub: no `cloudformation` call recorded.
- **Effect check (offline `ssh -G` positive control):** main config with `Include <abs fragment>` first → no WARN;
  main config with `Host ubuntu / HostName 1.2.3.4` **above** the Include → one WARN; three writes in one process →
  still one WARN. Use `skip` only if `ssh` is absent, and report it.
- **Symlinked fragment** (also dangling): write and teardown each return non-zero, link and target unchanged.
- **Teardown:** removes `ubuntu`, `ubuntu-tunnel`, `ubuntu-3`; keeps `ubuntu-gcp`, `ubuntu-azure`, `ubuntu-1x`;
  deletes the file when empty; `acg_teardown --confirm` with stubs on the no-stack path returns 0 and cleans; on the
  rc 2 path keeps the fragment.
- **Override:** `K3DM_SSH_SANDBOX_FRAGMENT` set **after** sourcing is honoured.

## Acceptance

```yaml
must:
  - id: A-M1
    text: "_acg_update_ssh_config and _acg_upsert_ssh_host write the server, tunnel and ubuntu-<n> aliases only to the fragment (default $HOME/.ssh/k3dm-sandbox.conf, K3DM_SSH_SANDBOX_FRAGMENT read at call time), file 0600, new dir 0700, atomic, idempotent"
  - id: A-M2
    text: "acg_provision stops before any CloudFormation call when ~/.ssh/config lacks an unconditional Include of the fragment, naming the exact line; K3DM_SSH_SANDBOX_PREFLIGHT=warn downgrades to a warning"
  - id: A-M3
    text: "after a write, if ssh -G does not resolve ubuntu to the new IP (e.g. a stale Host ubuntu above the Include), one WARN per process names the fragment and the Include line"
  - id: A-M4
    text: "acg_teardown on its rc 0 paths removes ubuntu, ubuntu-tunnel and ubuntu-<n> stanzas, keeps other aliases, deletes an empty fragment, and still returns 0 if only the SSH cleanup failed"
must_not:
  - id: A-N1
    text: "any ACG function changes the bytes, mode, existence or symlink-ness of ~/.ssh/config"
    red_on_current: "red: today _acg_update_ssh_config appends Host ubuntu to ~/.ssh/config (shasum guard fails; symlinked case: target shasum changes)"
  - id: A-N2
    text: "a symlinked or dangling-symlink fragment path is written through or deleted"
    red_on_current: "green on current (no fragment); mutant 'drop the -L check' turns the write and teardown symlink tests red"
  - id: A-N3
    text: "teardown removes a non-ACG stanza (ubuntu-gcp, ubuntu-azure, ubuntu-1x)"
    red_on_current: "green on current (no teardown); mutants 'delete the whole fragment' and 'prefix match ubuntu' each turn a keep test red"
  - id: A-N4
    text: "a missing Include lets acg_provision reach aws cloudformation"
    red_on_current: "red: current acg_provision calls _acg_cf_deploy with no pre-flight (recording stub sees cloudformation deploy)"
  - id: A-N5
    text: "an alias or IP value is evaluated as code"
    red_on_current: "red on current acg.sh: values are interpolated into the Python source (sentinel test)"
  - id: A-N6
    text: "a test reads or writes the real ~/.ssh"
    red_on_current: "guard assertions at the top of each test fail if HOME or the fragment is outside BATS_TEST_TMPDIR"
evidence:
  - id: A-E1
    proves: [A-M1, A-M2, A-M3, A-M4, A-N1, A-N2, A-N3, A-N4, A-N5, A-N6]
    kind: offline
    command: "env -i bats scripts/tests/lib/acg.bats scripts/tests/lib/ssh_fragment.bats and the AGENTS.md gate (shellcheck on every touched .sh, env -i BATS, agent_rigor _agent_audit with AGENT_AUDIT_MAX_IF=8 on the staged files) pass; A-N1, A-N4, A-N5 tests fail against current acg.sh; each mutant red, then reverted"
    intent: "An ACG sandbox no longer edits your ~/.ssh/config: its aliases go into a separate sandbox file, a missing Include line stops make up before anything is created, and teardown removes the aliases."
  - id: A-E2
    proves: [A-M1, A-M2, A-M4]
    kind: live
    command: "deferred to the next ACG sandbox run (operator: make up / make down on k3s-aws after the k3d-manager subtree pull and the Include line): zshdotfiles shows no change; ~/.ssh/k3dm-sandbox.conf holds ubuntu/ubuntu-<n> during the run (Claude reads Host/HostName lines only) and is gone after teardown; ssh ubuntu works. An expired sandbox skips acg_teardown in bin/cluster-down, so stale stanzas then stay until the next make up overwrites them — not a failure."
    intent: "After your next sandbox, your dotfiles repo stays clean and ssh ubuntu still reaches the sandbox."
interface:
  - "file: scripts/lib/ssh_fragment.sh (new; sourced by acg.sh, reused by k3d-manager providers and shopping_cart.sh)"
  - "env: K3DM_SSH_SANDBOX_FRAGMENT (default $HOME/.ssh/k3dm-sandbox.conf), K3DM_SSH_SANDBOX_PREFLIGHT (unset = fail, warn = warn)"
  - "functions: _ssh_fragment_path, _ssh_fragment_upsert, _ssh_fragment_set_hostname, _ssh_fragment_remove, _ssh_fragment_hostname, _ssh_fragment_include_preflight, _ssh_fragment_check_resolves, _acg_remove_ssh_hosts"
  - "line the operator adds near the top of ~/.ssh/config, before any Host block: Include ~/.ssh/k3dm-sandbox.conf"
```

## Worker definition of done

`env -i bats scripts/tests/lib/acg.bats scripts/tests/lib/ssh_fragment.bats` passes, plus the `AGENTS.md` gate
(`shellcheck` on every touched `.sh`, the `env -i` BATS suites, `_agent_audit` on the staged files); A-N1, A-N4 and A-N5
tests fail against the current `scripts/lib/acg/acg.sh`; each mutant run, red, reverted (report failing test names);
`git status` shows only the files in `## Files`.
