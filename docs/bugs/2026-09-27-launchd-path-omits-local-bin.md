# Bug — launchd PATH omits `~/.local/bin`, so every Slack-driven `make up` dies at the hub preflight

**Filed:** 2026-09-27
**Branch:** `k3d-manager-v1.39.0`
**Severity:** High — the entire `/cluster-up` Slack path is non-functional, and `/cluster-down`
**Status:** FIXED in `3a25448` (#133) — M1-M3 landed: `bin/cluster-up` and `bin/cluster-down` prepend `~/.local/bin`, and the hub teardown fails loudly when `k3d` is missing. Status line added 2026-09-29 by Claude (cloud session) after checking the code on `k3d-manager-v1.40.0`.
silently skips the hub teardown.
**Discovered by:** job `c7faf86b` (`/cluster-up aws` from Slack) failing with
`make up CLUSTER_PROVIDER=k3s-aws exited 2`.

## Symptom

Job `c7faf86b` reported failed. The remote cluster was in fact provisioned completely — the
CloudFormation stack was created, all three nodes reached `Ready`, the node labels were applied
and the watcher was running. The run died afterwards, at:

```
INFO: [acg-up] Step 3.5/12 — Verifying local Hub cluster (create if missing)...
ERROR: [acg-up] k3d binary not found in PATH — cannot manage Hub cluster. Check PATH includes ~/.local/bin.
```

The same `make up CLUSTER_PROVIDER=k3s-aws` run by hand from a terminal succeeds. That asymmetry
is the whole bug: the failure is **invisible from a shell**, so it cannot be reproduced the
obvious way.

## Root cause

The webhook runs under launchd, and `~/Library/LaunchAgents/com.k3d-manager.webhook.plist` sets
an explicit minimal `PATH`:

```
/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
```

launchd does not read the operator's shell profile, so that string is the entire `PATH` for every
child process — including `make up` → `bin/cluster-up`. But `k3d` is installed at
`~/.local/bin/k3d`, which is not in that list. `_command_exist k3d` at `bin/cluster-up:402`
therefore returns false and the script exits 1.

`k3d` is not the only binary in that directory. `~/.local/bin` also holds `istioctl`,
`k3d-manager`, `agy` and `secret-cli`, so this is a class of failure, not a single missing tool.

## Second defect — `bin/cluster-down` fails *silently*

`bin/cluster-down:326` has no preflight guard at all:

```bash
if k3d cluster list 2>/dev/null | grep -q "^${_HUB_CLUSTER}[[:space:]]"; then
```

With `k3d` absent from `PATH`, that command fails, the condition is false, and the script takes
the `else` branch and prints:

```
INFO: [acg-down] Local Hub cluster not found — skipping
```

So a Slack-driven `/cluster-down` reports **success** while leaving the local hub cluster running,
and states as fact that no hub exists. That is worse than `cluster-up`'s loud exit: cluster-up
tells the truth, cluster-down asserts a falsehood. Both must be fixed in this change.

## Fix

Normalize `PATH` inside the scripts rather than in the plist. The plist is host configuration
outside the repo — editing it fixes this one machine, leaves the repo defective, and is undone by
the next `make install-launchd`. Resolving the binary in-script is durable, is covered by tests,
and travels with the code.

The repo already has this precedent: `bin/k3dm-node-health-watch:11` and
`bin/k3dm-vault-failover:11` each prepend to `PATH` for exactly this reason. This change follows
that form, made idempotent so an interactive run is unaffected.

### M1 — `bin/cluster-up`

Immediately after `set -euo pipefail` (line 19), before the `REPO_ROOT` assignment, insert:

```bash

# launchd starts this script with the plist's minimal PATH, which omits
# ~/.local/bin where k3d and istioctl live. Without this, every Slack-driven
# run dies at the Step 3.5 hub preflight while the same command succeeds from a
# terminal.
if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
  export PATH="${HOME}/.local/bin:${PATH}"
fi
```

Leave the `_command_exist k3d` guard at line 402 exactly as it is — it is still the correct error
when `k3d` genuinely is not installed, and its message already names the right directory.

### M2 — `bin/cluster-down`

Insert the same block immediately after `set -euo pipefail` (line 16), before the `REPO_ROOT`
assignment. Use the identical wording except for the last sentence:

```bash

# launchd starts this script with the plist's minimal PATH, which omits
# ~/.local/bin where k3d and istioctl live. Without this, the hub teardown below
# silently no-ops and reports that no hub cluster exists.
if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
  export PATH="${HOME}/.local/bin:${PATH}"
fi
```

### M3 — make the `cluster-down` hub teardown loud

Replace lines 323–327 of `bin/cluster-down`:

```bash
if [[ "${_keep_hub}" -eq 0 ]]; then
  _info "[acg-down] Tearing down local Hub cluster (${_HUB_CLUSTER})..."
  if k3d cluster list 2>/dev/null | grep -q "^${_HUB_CLUSTER}[[:space:]]"; then
```

with:

```bash
if [[ "${_keep_hub}" -eq 0 ]]; then
  _info "[acg-down] Tearing down local Hub cluster (${_HUB_CLUSTER})..."
  if ! _command_exist k3d; then
    _err "[acg-down] k3d binary not found in PATH — cannot tear down the local Hub cluster. Check PATH includes ~/.local/bin."
    exit 1
  fi
  if k3d cluster list 2>/dev/null | grep -q "^${_HUB_CLUSTER}[[:space:]]"; then
```

Do not change the `else` branch or the `--keep-hub` branch. A missing `k3d` under `--keep-hub` is
not an error, because nothing needs `k3d` on that path.

### M4 — tests

Append to `scripts/tests/bin/cluster_up.bats`:

```bash
@test "acg-up puts ~/.local/bin on PATH before anything reads it" {
  run bash -c "awk '/^set -euo pipefail/{print NR; found=1} found && /HOME\}\/.local\/bin/{print NR; exit}' bin/cluster-up"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
  run bash -c "awk '/HOME\}\/.local\/bin:\\\$\{PATH\}/{print NR; found=1} found && /_command_exist k3d/{print NR; exit}' bin/cluster-up"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n '1p')" -lt "$(printf '%s\n' "$output" | sed -n '2p')" ]
}

@test "acg-up does not prepend ~/.local/bin twice" {
  run bash -c "PATH=\"\${HOME}/.local/bin:/usr/bin:/bin\" bash -c '
    if [[ \":\${PATH}:\" != *\":\${HOME}/.local/bin:\"* ]]; then
      export PATH=\"\${HOME}/.local/bin:\${PATH}\"
    fi
    printf %s \"\${PATH}\"'"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tr ':' '\n' | grep -c "\.local/bin")" -eq 1 ]
}
```

Append to `scripts/tests/bin/cluster_down.bats`:

```bash
@test "cluster-down puts ~/.local/bin on PATH before the hub teardown" {
  run bash -c "awk '/^set -euo pipefail/{print NR; found=1} found && /HOME\}\/.local\/bin/{print NR; exit}' bin/cluster-down"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "cluster-down fails loudly when k3d is missing instead of skipping the hub" {
  run bash -c "awk '/Tearing down local Hub cluster/{found=1} found && /_command_exist k3d/{print NR; exit}' bin/cluster-down"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run grep -nF 'cannot tear down the local Hub cluster' bin/cluster-down
  [ "$status" -eq 0 ]
}
```

**These tests must be proven able to fail.** Before committing, `git stash` is forbidden here —
instead copy the pre-fix `bin/cluster-up` and `bin/cluster-down` from `HEAD` into a scratch
directory, point the new tests at those copies, and confirm all four fail. Paste that output in
the report. A new test that passes against unfixed source proves nothing.

### M5 — documentation

`docs/howto/launchd-daemons.md` — add a `## PATH under launchd` section immediately before
`## Common Operations`, stating:

- launchd does not read the operator's shell profile; the plist's `EnvironmentVariables` `PATH` is
  the complete `PATH` for every child process.
- `~/.local/bin` is deliberately **not** in the webhook plist's `PATH`, and it holds `k3d`,
  `istioctl`, `k3d-manager`, `agy` and `secret-cli`.
- Any `bin/` script that may be invoked by a LaunchAgent must therefore normalize `PATH` itself.
  Name `bin/cluster-up`, `bin/cluster-down`, `bin/k3dm-node-health-watch` and
  `bin/k3dm-vault-failover` as the scripts that currently do.
- A command that works in a terminal and fails under launchd is this bug, not a logic bug —
  check `PATH` first.

**Do not quote, paste or transcribe any value from the plist other than `PATH`.** That file also
holds Slack credentials in the same `EnvironmentVariables` dictionary; never `plutil -p` it
without a targeted key filter.

`CHANGELOG.md` — add to the `### Fixed` section under `## [1.39.0] - 2026-09-27`, as prose, not a
one-liner: name both defects (cluster-up's loud failure and cluster-down's silent skip), the
launchd root cause, and why the fix belongs in the scripts rather than the plist.

## Before You Start

1. `git pull origin k3d-manager-v1.39.0`
2. Read `memory-bank/activeContext.md` — the entry dated 2026-09-27 for job `c7faf86b`.
3. Read all four target files in full before editing: `bin/cluster-up`, `bin/cluster-down`,
   `scripts/tests/bin/cluster_up.bats`, `scripts/tests/bin/cluster_down.bats`.

## Definition of Done

- [ ] M1 — `bin/cluster-up` normalizes `PATH` after `set -euo pipefail`
- [ ] M2 — `bin/cluster-down` normalizes `PATH` after `set -euo pipefail`
- [ ] M3 — `bin/cluster-down` fails loudly on a missing `k3d` in the non-`--keep-hub` path
- [ ] M4 — four BATS tests added, **and proven to fail against pre-fix source in a scratch copy**
- [ ] `bats scripts/tests/bin/cluster_up.bats scripts/tests/bin/cluster_down.bats` — green, paste
      the full output including the `1..N` plan line
- [ ] `shellcheck bin/cluster-up bin/cluster-down` — zero new warnings, paste the output
- [ ] M5 — `docs/howto/launchd-daemons.md` and `CHANGELOG.md` updated
- [ ] Commit message exactly:
      `fix(cluster): normalize PATH so launchd-driven runs can find k3d`
- [ ] `git push origin k3d-manager-v1.39.0` — do not report done until the push succeeds
- [ ] `git rev-parse origin/k3d-manager-v1.39.0` matches your commit
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA

## What NOT to Do

- Do NOT create a PR.
- Do NOT merge anything.
- Do NOT commit to `main`. Work only on `k3d-manager-v1.39.0`.
- Do NOT force-push.
- Do NOT use `--no-verify`.
- Do NOT edit `~/Library/LaunchAgents/com.k3d-manager.webhook.plist` or any file outside the repo.
  The plist is the operator's; this fix deliberately does not touch it.
- Do NOT read, print, echo or log any value from that plist other than `PATH`. It contains Slack
  credentials.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` — they are subtrees.
- Do NOT add `~/.local/bin` to `scripts/lib/system.sh` or any shared library. The blast radius is
  every caller; this change is scoped to the two entry-point scripts that need it.
- Do NOT run `make up`, `make down`, `k3d cluster delete`, or any live cluster or Docker mutation.
  This task is pure source editing plus BATS and shellcheck.
- Do NOT `git stash` at any point.
- Do NOT modify files outside the six listed above (four targets plus the two docs) and the
  memory-bank.
- Do NOT refactor anything you were not asked to change.

## Dedup record

Pass 1 (exact slug, authoritative): `ls docs/bugs/*launchd*`, `*path*`, `*webhook-path*` — no
match. The nearest neighbours are
`docs/bugs/v1.7.1-bugfix-launchd-ensure-bootout-before-bootstrap.md` (agent load ordering) and
`docs/bugs/v1.6.0-bugfix-stale-sudoers-install-path.md` (an install destination), neither of which
is this defect.

Pass 2 (similarity, advisory): `make find-similar-docs` is currently unavailable — the embeddings
credential slot is unset — so this pass could not run. Recorded rather than skipped silently.
