# Bug: `docs/architecture/webhook-server.md` no longer describes the webhook server

**Date:** 2026-10-09
**Status:** OPEN — dispatched to Codex
**Branch:** `k3d-manager-v1.42.0`
**Severity:** low (documentation); the doc says it describes the server "as it currently exists",
and a reader who trusts it gets the module map, the route table and the extraction status wrong.

## Symptom

The doc was last edited in v1.37.0 (`925c43e7`, 2026-09-25). About 30 webhook commits have landed
since. Measured against the tree on 2026-10-09:

| Doc says | Tree says |
|---|---|
| `bin/k3dm-webhook` is "2,196 lines" (one section) and "4,008 lines" (another) | 2,576 lines (`wc -l bin/k3dm-webhook`) |
| Module table lists 10 modules | 16: also `redact.py`, `ask_docs.py`, `cloud_actions.py`, `job_output.py`, `log.py`, `failure_notes.py` |
| "Secret redaction — `_redact_skip_reason`, `_register_secret`, `_redact_secrets`" still in the monolith | `scripts/lib/webhook/redact.py` exists |
| `MAKE_TARGETS` has 17 targets | 29 |
| Route table ends at `/api/v1/ask` | `_POST_ROUTES` also has `/api/v1/ask-docs` |
| Roadmap table: Phase 4 (diagnostics split) "not started", no `server.py`/`routes.py` | The header says lifecycle/status extraction landed in v1.37.0; the table and the header disagree |
| "What still lives in the monolith" line ranges (e.g. 3497–4008) | Ranges are from a 4,008-line file; none are valid for 2,576 lines |
| Import block quoted at `bin/k3dm-webhook:27` | Imports now start at line 21 and include `log`, `job_output`, `smoke` |

Behaviour that landed since v1.37.0 and is absent from the doc (see `git log 925c43e7..HEAD -- bin/k3dm-webhook scripts/lib/webhook`):

- Slack thread context — top-level jobs, cleanup, status and diagnostics replies stay in the source thread/channel.
- Every relayed slash command is capped at the Slack caller's mapped role (`8aa14053`), not just `/k3dm`.
- Slack event signatures are verified on the full body, not a 4 KB truncation (`f127fd7b`).
- `/ask` bash scope enforcement with an OS read boundary (`b2c45ae3`); the prompt passed after `--` (`7089dd10`); CLI preamble stripped before the ANSWER marker (`e92d1d85`).
- `ask-docs` route and model-failure propagation (`2237bd89`, `7b21ebe5`).
- Cloud test-all metrics published to Pushgateway/Grafana, failed-test details, untriaged-failure classification (`9c987697`, `c67c3a9a`, `e52c0c57`, `2833c894`).
- Infra ArgoCD upgrade requires confirmation (`1f8c09ef`).
- The cloud-runner role and capability set (`scripts/lib/webhook/policy.py` `_ROLE_CAPABILITIES`).

## Root cause

The doc embeds point-in-time measurements (line counts, line ranges, target counts) with no
check that they still hold, and it was not in any of the 30 fix commits' Definition of Done.

## Fix (Codex)

Rewrite `docs/architecture/webhook-server.md` so every factual statement is true of the tree at
the commit you make. Keep the existing section order and the doc's voice; keep the mermaid
diagrams, updated.

1. **Header / Status** — state what is extracted now and what is not, consistently with the roadmap table.
2. **Module layout** — regenerate the import block from `bin/k3dm-webhook` (quote it with its real
   starting line) and the module table from `scripts/lib/webhook/*.py`: one row per module with
   measured `wc -l`, responsibility (read the module docstring and public functions) and intra-package
   imports (read the `from webhook.` / `from .` imports). Update the dependency mermaid to match those imports exactly.
3. **API route table** — regenerate from `_POST_ROUTES` and `_GET_ROUTES`.
4. **What still lives in the monolith** — regenerate from the functions actually defined in
   `bin/k3dm-webhook` (`grep -n '^def \|^class '`). Use function names, **not line ranges** — line
   ranges rot on the next commit. Drop rows whose functions moved to a module.
5. **Makefile as operator interface** — fix the target count (or better, do not state a count;
   point at `make_targets.py` and `/k3dm help`), list the `confirm` targets from `MAKE_TARGETS`, and
   describe the per-caller role cap as it now applies to every relayed slash command.
6. **Testing & operational surfaces** — list the test files that exist now for the webhook
   (`ls scripts/tests/bin/*webhook* scripts/tests/bin/test_*` and `scripts/tests/lib/webhook*.bats`); remove any that do not exist.
7. **Roadmap** — make the phase table agree with the tree. The "measurement that matters" table
   may keep its historical rows, but the "today" row must be the measured count with the date.
8. Add a short section on Slack threading and on the `cloud-runner` role, linking
   `docs/architecture/cloud-bridge.md` rather than repeating it.

Every number you write must come from a command you ran; put the measurement date
(2026-10-09) next to counts.

## Files

| File | Change |
|---|---|
| `docs/architecture/webhook-server.md` | rewrite as above |
| `docs/bugs/2026-10-09-webhook-server-architecture-doc-stale.md` | Status → `FIXED — <describe>` (no SHA needed) |

Nothing else.

## Definition of Done

- [ ] Every module in `scripts/lib/webhook/*.py` (except `__init__.py`) has a row; no row names a missing file.
- [ ] Every route key in `_POST_ROUTES` / `_GET_ROUTES` is in the route table, and nothing else is.
- [ ] No line range anywhere in the doc; no line count that differs from `wc -l` at your commit.
- [ ] `make check-doc-links` passes.
- [ ] Commit message (exact):
  ```
  docs(webhook): rewrite webhook-server architecture doc against the current tree

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] `git push origin k3d-manager-v1.42.0`; `git ls-remote origin k3d-manager-v1.42.0` equals `git rev-parse HEAD`.

## What NOT to do

- Do NOT create a PR or merge; do NOT commit to `main`; do NOT use `--no-verify`.
- Do NOT change any code, test, Makefile, or any doc other than the two files above.
- Do NOT start the webhook, call `:7443`, read Keychain items, or run any `make` lifecycle target or `make -n`.
- Do NOT update memory-bank.
