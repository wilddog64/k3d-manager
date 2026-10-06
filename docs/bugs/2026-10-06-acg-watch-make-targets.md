# Make targets for the ACG sandbox TTL watcher

**Status:** OPEN
**Branch:** `k3d-manager-v1.41.0` (k3d-manager only — do NOT touch `scripts/lib/foundation/`)
**Follow-up to:** lib-foundation v0.5.1, `scripts/lib/foundation/docs/bugs/2026-10-06-acg-watch-misses-extend-window-and-reads-expired-as-22h.md`

## Problem

lib-foundation v0.5.1 moved the sandbox TTL watcher to a 30-minute interval. Picking that up on a
running sandbox means reinstalling the launchd agent, and the only way to do that, or to check how
much time the sandbox has left, is to call library functions and module scripts by hand:

```
./scripts/k3d-manager acg_watch_start
./scripts/k3d-manager acg_watch_stop
cd scripts/lib/foundation/scripts/lib/acg && bin/acg-extend-test "<url>" --check
```

The Makefile already wraps the neighbouring ACG agents (`chrome-cdp` / `chrome-cdp-stop`,
`acg-restart`), so these three belong there too.

## Fix

Add three targets. `URL=` is optional on each; when unset, `acg_watch_start` already falls back to
`_ACG_SANDBOX_LIST_URL` (it uses `${1:-...}`, so an empty argument also takes the default), and
`acg-watch-check` falls back to `ACG_SANDBOX_LIST_URL`, then to the sandbox list page — the same
default lib-foundation uses.

### 1. `Makefile` — `.PHONY` (line 30)

In the `.PHONY` line, replace:

```
chrome-cdp chrome-cdp-stop acg-restart acg-recover
```

with:

```
chrome-cdp chrome-cdp-stop acg-watch acg-watch-stop acg-watch-check acg-restart acg-recover
```

### 2. `Makefile` — targets

Insert directly after the `chrome-cdp-stop` target (after line 225, before the `## Recover an
expired ACG sandbox` comment):

```make
## Install the ACG sandbox TTL watcher launchd agent; checks every 30m (URL=<sandbox-url> optional)
acg-watch:
	scripts/k3d-manager acg_watch_start "$(URL)"

## Uninstall the ACG sandbox TTL watcher launchd agent
acg-watch-stop:
	scripts/k3d-manager acg_watch_stop

## Read-only: print the sandbox's remaining minutes without extending (URL=<sandbox-url> optional)
acg-watch-check:
	@_url="$(URL)"; cd scripts/lib/foundation/scripts/lib/acg && bin/acg-extend-test "$${_url:-$${ACG_SANDBOX_LIST_URL:-https://app.pluralsight.com/hands-on/playground/cloud-sandboxes}}" --check
```

Recipe lines are indented with a TAB.

### 3. `Makefile` — `help`

After the line

```
	@echo "    make chrome-cdp-stop   Uninstall Chrome CDP launchd agent"
```

insert:

```
	@echo "    make acg-watch     Install the sandbox TTL watcher (checks every 30m; URL= optional)"
	@echo "    make acg-watch-stop    Uninstall the sandbox TTL watcher"
	@echo "    make acg-watch-check   Print the sandbox's remaining minutes without extending"
```

### 4. `docs/howto/makefile.md` — Credential Extraction table

After the row

```
| `make chrome-cdp-stop` | Uninstall the launchd agent |
```

insert:

```
| `make acg-watch` | Install the sandbox TTL watcher launchd agent (checks every 30 minutes) |
| `make acg-watch-stop` | Uninstall the sandbox TTL watcher |
| `make acg-watch-check` | Print the sandbox's remaining minutes without extending it (read-only) |
```

And after the paragraph that begins ``make chrome-cdp` installs a `launchd` plist`` (the paragraph
ending "without a manual browser launch."), add a blank line and this paragraph:

```
`make acg-watch` wraps `acg_watch_start`: it installs the `com.k3d-manager.acg-watch` launchd agent,
which checks the sandbox every 30 minutes and clicks Extend once 65 minutes or less remain. `make up`
installs it too (Step 12); run `make acg-watch` on its own to pick up a newer lib-foundation without
a full `make up`. `make acg-watch-check` is read-only: it prints `REMAINING_MINS:<n>` and never
clicks Extend — a zero or negative value means the sandbox has already expired. Both accept
`URL=<sandbox-url>` (default: the sandbox list page). See
`scripts/lib/foundation/docs/api/acg.md` ("Sandbox TTL watcher and extend") for how a pass works.
```

### 5. `CHANGELOG.md` — `## [Unreleased]`

Add an `### Added` subsection directly under `## [Unreleased]` (above the existing `### Fixed`):

```
### Added

- `make acg-watch`, `make acg-watch-stop` and `make acg-watch-check` wrap the sandbox TTL watcher:
  install or remove the launchd agent (`acg_watch_start` / `acg_watch_stop`), and print the
  sandbox's remaining minutes without extending it (`acg-extend-test --check`). Reinstalling the
  agent was the step needed to pick up lib-foundation v0.5.1's 30-minute interval, and it had no
  make target. `URL=` is optional on all three. See `docs/bugs/2026-10-06-acg-watch-make-targets.md`.
```

### 6. New test `scripts/tests/bin/makefile_acg_watch.bats`

Follow `scripts/tests/bin/makefile_gh_secret.bats`: copy the `Makefile` into
`${BATS_TEST_TMPDIR}/work`, put stubs at the paths the recipes call, and run
`make --no-print-directory -C "${WORK}" <target>`. Stubs (all `chmod +x`, `set -euo pipefail`):

- `${WORK}/scripts/k3d-manager` — appends `ARGS:` + each arg as ` <arg>` + newline to `${CALL_LOG}`.
- `${WORK}/scripts/lib/foundation/scripts/lib/acg/bin/acg-extend-test` — appends `PWD:<pwd>` on one
  line and `ARGS:` + ` <arg>` per arg on the next to `${CALL_LOG}`.

Run every `make` with `env -u ACG_SANDBOX_LIST_URL` plus `CALL_LOG=...` so a value in the operator's
environment cannot change the default. Tests:

1. `make acg-watch` (no URL) → log line is exactly `ARGS: <acg_watch_start> <>`.
2. `make acg-watch URL=https://example.test/sb` → `ARGS: <acg_watch_start> <https://example.test/sb>`.
3. `make acg-watch-stop` → `ARGS: <acg_watch_stop>`.
4. `make acg-watch-check` (no URL) → `ARGS: <https://app.pluralsight.com/hands-on/playground/cloud-sandboxes> <--check>`
   and the `PWD:` line ends with `/scripts/lib/foundation/scripts/lib/acg`.
5. `make acg-watch-check` with `ACG_SANDBOX_LIST_URL=https://env.test/list` in the env (and no URL) →
   `ARGS: <https://env.test/list> <--check>`.
6. `make acg-watch-check URL=https://example.test/sb` with `ACG_SANDBOX_LIST_URL=https://env.test/list`
   also set → `ARGS: <https://example.test/sb> <--check>` (URL wins).
7. The `.PHONY` line of the real Makefile names `acg-watch`, `acg-watch-stop` and `acg-watch-check`,
   and `make help` output contains all three target names.

Assert with `grep -Fx` against `${CALL_LOG}` (exact line), never with a bare `! grep`
(use `run !` or `|| false`).

## Before You Start

1. `git pull origin k3d-manager-v1.41.0` in `/Users/cliang/src/gitrepo/personal/k3d-manager`.
2. Read this spec, `Makefile` lines 25–35, 215–235 and the `help` target (~line 1275–1330),
   `docs/howto/makefile.md` "Credential Extraction", the top of `CHANGELOG.md`, and
   `scripts/tests/bin/makefile_gh_secret.bats`.

## Rules

- `bats scripts/tests/bin/makefile_acg_watch.bats` must pass; paste the output.
- RED check: the new test file must FAIL against the pre-change Makefile. Prove it on a temp copy
  (e.g. `git show HEAD:Makefile > "$TMPDIR/Makefile.orig"` and point a run at it) — do NOT
  `git checkout`/`git stash` the working tree.
- `shellcheck` the stubs embedded in the BATS file is not required; `make help` must still run.

## Definition of Done

- [ ] `Makefile`: `.PHONY`, three targets, three `help` lines — exactly as above.
- [ ] `docs/howto/makefile.md`: three table rows + one paragraph.
- [ ] `CHANGELOG.md`: `### Added` entry under `[Unreleased]`.
- [ ] `scripts/tests/bin/makefile_acg_watch.bats`: 7 tests, all `ok`; RED shown against the old Makefile.
- [ ] Commit on `k3d-manager-v1.41.0` with exactly this message:
      `feat(make): acg-watch, acg-watch-stop and acg-watch-check targets for the sandbox TTL watcher`
- [ ] `git push origin k3d-manager-v1.41.0`; report the SHA and `git rev-parse origin/k3d-manager-v1.41.0`.
      If the commit or push is denied by the sandbox, stop, leave the changes in the working tree,
      and report that — do not retry with other flags.

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside: `Makefile`, `docs/howto/makefile.md`, `CHANGELOG.md`,
  `scripts/tests/bin/makefile_acg_watch.bats`. In particular never edit `scripts/lib/foundation/`
  (subtree; upstream-only) or `memory-bank/`.
- Do NOT commit to `main`.
- Do NOT run `make acg-watch`, `make acg-watch-stop`, `make acg-watch-check`, `make up` or any
  target against the real repo root — they touch launchd and the live sandbox. Only run targets
  inside the BATS temp copy with stubs.
- Do NOT run `make -n` on any target.
