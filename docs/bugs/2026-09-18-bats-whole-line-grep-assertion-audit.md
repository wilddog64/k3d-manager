# Bugfix — tree-wide audit of whole-line `grep -F` assertions in BATS

**Date:** 2026-09-18
**Branch:** `fix/bats-whole-line-grep-assertions` — authored on `main` @ `978ea60f`, rebased onto
`main` @ `e259c718` (the v1.35.0 squash) once PR #128 merged. The rebase was conflict-free: these
edits sit at `provider_contract.bats:952`, while #128's rework of the same file was at `:241`.
**Reported by:** Claude, at the user's request after the v1.35.0 close-out.
**Predecessor:** `docs/bugs/v1.33.0-bugfix-stale-bats-grep-assertions.md` — fixed 4 named
sites reactively, after they had already broken CI. This audit applies that spec's fix
idiom to the whole tree, proactively.

## Summary

`scripts/tests/` contains **355** `grep -F` call sites. Most are correct and must be left
alone. **45** are defects of one kind: a BATS case asserting an **entire literal line of
source code**, so the test breaks on any reformat, rename or addition that leaves the
behavior unchanged.

This is not a hypothetical. It has already cost two incidents:

- v1.33.0 failures #3 and #4 — `ALLOWED_COMMANDS` and the `cluster-status` relay line —
  both broke when the worker gained a command and an argument. Neither was a product bug.
- Failure #4 was additionally **misdiagnosed by Claude as a "load-dependent flake"**. A
  `grep` against a static file cannot flake. That misdiagnosis is itself recorded in
  `reference_check_determinism_before_calling_it_a_flake`.

The cost is not just churn. A test that rots this way trains the maintainer to "fix" it by
pasting in the new line, which restores green while asserting nothing the author intended.

## Classification — what counts as a defect

Three populations, only the third is in scope:

| # | Shape | Count | Verdict |
|---|---|---:|---|
| 1 | Short token against a **runtime artifact** (call log, rendered manifest, tmpdir file) — `grep -F -- 'svc/keycloak' "$LOG"` | 198 | **Correct — leave alone.** This is the intended idiom. |
| 2 | Short token against a **source file** — `grep -F 'RESTART_DELAY=2' "$TMPL"` | 71 | **Acceptable.** The token *is* the contract; it does not encode formatting. |
| 3 | **Whole line or long statement against a source file** — a full `if`/`for`/assignment, a complete dict literal, a `def`/`function` signature | **45** | **Defect — in scope.** |

A site is in population 3 when the pattern either exceeds 60 characters or matches a
statement shape (`; then`, `&& {`, `for ((`, `function `, `def `, `return `, `const `, `=$(`,
`await`, `Object.freeze`, `Path.home`, `os.environ.get`, `= {"`, `= new Set`, `= [`).

**The length threshold alone undercounts.** A first pass using only `>60 chars` plus the shell
shapes reported **40**. Widening it to the Python/JS shapes above found **5** more that are
just as brittle while being short — `_ROLE_LEVELS = {"reader": 1, "operator": 2, "admin": 3}`
(55), `def _acg_stack_probe(provider):` (31), `const COMMAND_ROLES     = Object.freeze({` (41),
`event.waitUntil((async () => {` (30), `if ! _pf_alive; then` (20). Counts derived from a
heuristic must be re-derived when the heuristic changes, never carried forward.

### The 45, by file

| File | Sites | What they grep |
|---|---:|---|
| `scripts/tests/plugins/argocd.bats` | 12 | full `if`/assignment lines out of `port-forward-wrapper.sh.tmpl`, `browser-https-wrapper.sh.tmpl`, and `function …()` signatures out of `argocd.sh` |
| `scripts/tests/lib/webhook.bats` | 16 | Python source lines out of `bin/k3dm-webhook` and `scripts/lib/webhook/config.py` — dict literals, `def` signatures |
| `scripts/tests/plugins/slack_slash_commands.bats` | 5 | JS declarations out of `workers/slack-relay/index.js` |
| `scripts/tests/lib/provider_contract.bats` | 5 | full statements out of generated `argocd-port-forward.sh` |
| `scripts/tests/plugins/slack_relay_ack.bats` | 3 | JS statements out of `workers/slack-relay/index.js` |
| `scripts/tests/plugins/argocd_image_updater_install.bats` | 2 | `function …()` signatures |
| `scripts/tests/bin/k3dm_worker_setup.bats` | 1 | a 70-char urlencoded probe body |
| `scripts/tests/lib/observability.bats` | 1 | a full statement |

## The fix idiom — narrow, do not re-paste

Carried over verbatim from the v1.33.0 spec, which called this a **narrowing, not a
weakening**: every semantic requirement survives; only the formatting dependency is
dropped.

**Never** satisfy a broken gate by pasting the new line in. That is what makes it break again.

Three permitted transformations:

**(a) Whole statement → `grep -E` on the meaningful tokens.**

```bash
# before — rots on any reformat of the condition
run grep -F 'if [[ -n "${CONTEXT}" ]] && "${KUBECTL_BIN}" config get-contexts "${CONTEXT}" >/dev/null 2>&1; then' "$TMPL"

# after — asserts the probe happens, tolerant of layout
run grep -Eq 'config get-contexts .*\$\{CONTEXT\}' "$TMPL"
```

**(b) Collection literal → membership assertion per element.**

```bash
# before — breaks when a fourth role is added
run grep -F -- '_ROLE_LEVELS = {"reader": 1, "operator": 2, "admin": 3}' "$WEBHOOK"

# after — each required mapping is still individually required
_levels="$(grep -m1 -E '_ROLE_LEVELS\s*=' "$WEBHOOK")"
for _pair in '"reader": 1' '"operator": 2' '"admin": 3'; do
  [[ "${_levels}" == *"${_pair}"* ]] || { echo "_ROLE_LEVELS missing ${_pair}: ${_levels}"; return 1; }
done
```

**(c) `function …()` / `def …()` signature → interrogate the loaded definition.**

Where the suite already sources the file under test, grepping for a signature is strictly
worse than asking the shell. `setup()` in `argocd.bats` sources `argocd.sh`, so:

```bash
# before
run grep -F 'function _argocd_write_port_forward_wrapper()' "$ARGOCD_SH"
# after
declare -F _argocd_write_port_forward_wrapper >/dev/null
```

For Python targets the suite does not source, fall back to (a):
`grep -Eq '^def _acg_stack_probe\(' "$WEBHOOK"`.

## Rules

- **Test files only.** Do NOT modify `bin/k3dm-webhook`, `scripts/plugins/argocd.sh`,
  `scripts/lib/webhook/config.py`, `workers/slack-relay/index.js`, or any `*.tmpl`.
- Do NOT "fix" production code to match a stale assertion. In all 45 cases the code is correct.
- Do NOT re-paste the current source line. Narrow per (a)/(b)/(c) above.
- Do NOT touch population 1 or 2 sites. A short token against a call log is the idiom, not a bug.
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/` (subtrees).
- No `rg` — `grep` is aliased to `rg` on the maintainer's workstation and CI has no ripgrep.
  See `reference_linux_only_ci_reds_reproduce_locally`.
- No bare `!` negation in BATS assertions — see
  `docs/bugs/2026-09-14-bats-bare-negation-assertions-never-fail.md`.
- Always double-quote variable expansions. LF endings. Minimal patches.

## Definition of Done

- [x] Whole-line source greps: **45 → 3**, measured by the triage classifier, not by eye.
      The 3 survivors are deliberate keeps, listed under **Deliberate keeps** below.
      Measure by regenerating the raw snapshot first — a classifier reading a stale
      `grepF-raw.txt` will happily report success against the pre-fix tree.
- [x] Both suites pass with **no net change in test count** and zero new failures. Measured twice,
      because the rebase changed which targets exist and which suites CI runs:

      *Pre-rebase, on `main` @ `978ea60f`:* `make test` → 923 ok / 1 not ok, and the `bin/` suite
      → 107 ok / 1 not ok. At that base **there was no `make test-bin` target** — `make test` ran
      `./scripts/k3d-manager test all`, covering `scripts/tests/{lib,core,plugins,etc}` and **not**
      `scripts/tests/bin/`, so the `bin/` suite had to be invoked directly as `bats
      scripts/tests/bin/` or the change there was verified by nothing. That is the
      `feedback_verify_makefile_targets` lesson, and it is why the measurement was taken by hand.

      *Post-rebase, on `main` @ `e259c718`:* **v1.35.0 added `make test-bin`** (plus
      `test-python-unit`, `test-pytest`, `test-python` and the `test-all` aggregate) and wired
      `test-bin` into the CI `lint` job. So the `bin/` change in this branch is now gated by CI for
      the first time, and the correct invocation is `make test-bin`, not a bare `bats`. Numbers
      recorded below under **Post-rebase verification**.

      A DoD written against one base does not survive a rebase unexamined. This item asserted
      "there is no `make test-bin` target" — true when written, false the moment #128 landed.
- [x] Each converted assertion demonstrably still fails when its requirement is removed —
      13 mutations, at least one per file, tabulated under **Proof obligation** below.
- [x] `git diff --stat` touches only files under `scripts/tests/` plus this spec.

## Deliberate keeps — 3 classifier matches that are NOT defects

The classifier is a heuristic; these three match it and are correct as written. Do not
"fix" them in a later sweep.

| Site | Pattern | Why it stays |
|---|---|---|
| `slack_slash_commands.bats:93` | `const ALLOWED_COMMANDS = new Set([` | Already the v1.33.0 **fixed** form: it anchors the declaration only, then loops per element. Narrowing it further would assert nothing. |
| `webhook.bats:576` | `os.environ.get("K3DM_GEMINI_BIN", "agy")` | The env var name and its default *are* the contract. |
| `webhook.bats:579` | `return "agy CLI not found — skipping AI analysis"` | A user-visible string; the literal is the requirement. |

## Proof obligation — mutation, not green

A narrowing that stops asserting anything still passes. That is exactly how v1.35.0 shipped
vacuous `run rg` cases. So every conversion was proved by breaking the source and confirming
the test goes red — 13 mutations, one per file minimum, all caught:

| File | Mutation applied to the source | Result |
|---|---|---|
| `argocd.bats` | drop `config get-contexts` from the template | `not ok 17` |
| `argocd.bats` | rename `_argocd_write_port_forward_wrapper` | `not ok 16` (proves `declare -F` bites) |
| `argocd.bats` | socat `verify=0` → `verify=1` | `not ok 18` |
| `webhook.bats` | `cluster-refresh` `operator` → `reader` | `not ok 31` |
| `webhook.bats` | drop `describe-pod` from `allowed_actions` | `not ok 32` |
| `webhook.bats` | drop the `admin` role | `not ok 31` |
| `webhook.bats` | **add** a compatible 4th role `"owner": 4` | **`ok 31`** |
| `slack_slash_commands.bats` | rename `COMMAND_ROLES` | `not ok 6` |
| `slack_relay_ack.bats` | remove `event.waitUntil(` | `not ok 1` |
| `argocd_image_updater_install.bats` | rename the deploy function | `not ok 1` |
| `observability.bats` | rename the rotate function | `not ok 18` |
| `k3dm_worker_setup.bats` | change the probe command | `not ok 2` |
| `provider_contract.bats` | retry budget `30` → `3` | `not ok 26` |

The **`ok 31`** row is the point of the whole audit: adding a behavior-compatible role now
passes, where the old whole-line grep would have broken the build. Every mutated source was
restored from `/tmp/*.bak` and confirmed with an empty `git diff --stat`.

**Run the full suites only when no mutation is in flight.** Two aggregate runs in this session
were contaminated — one overlapped the initial edits, one overlapped the mutation batch, and
the latter reported `_hostinger_refresh_access_layer` failing, which was the deliberate 30→3
break being read by a concurrent `make test`. A contaminated run is worse than no run: it
invites chasing a failure that does not exist.

## What NOT to Do

- ~~Do NOT create a PR while #128 is open~~ — **resolved.** #128 merged as `e259c718` on
  2026-09-18 and this branch has been rebased onto it, so it now carries v1.35.0's
  `SHELL := /bin/bash`, `rg`→`grep` and keycloak-skip fixes. CI on this branch can now be
  trusted; before the rebase it would have gone red for three reasons unrelated to this change.
- Do NOT merge anything. Do NOT commit to `main`. Do NOT `--no-verify`.
- Do NOT re-paste a source line to fix a future red. If one of these 42 assertions breaks, the
  question is whether the *requirement* changed — and if it did, the assertion should be
  rewritten to state the new requirement, not widened until it passes.
