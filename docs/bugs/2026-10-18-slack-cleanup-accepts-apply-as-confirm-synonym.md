# Bug: Slack confirmation keyword is `confirm` everywhere except cleanup-stale-sandbox, which also takes `apply`

**Filed:** 2026-10-18 (Claude, from the operator's request)
**Status:** OPEN
**Priority:** P3 — inconsistent UX; no wrong mutation today
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "some command use apply and some use confirm. we should unify them to be consistent" (filing + fix); "yes ... dispatch bug to codex" (dispatch, 2026-10-18). Requiring `confirm` on `/cluster-down` is deferred for later discussion — out of scope here
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `bin/k3dm-webhook` (`cleanup-stale-sandbox` Slack parser and labels)
**Related:** `docs/bugs/2026-10-07-slack-stale-sandbox-cleanup-misleading-reporting.md` (documented
`apply` as an alias)

## Symptom

To authorize a mutating Slack command, the operator has to remember two words:

| Surface | How to authorize |
|---|---|
| `/k3dm <target> ... confirm` (`e2e-sandbox-provision`, `e2e-runner-unlock`, `fix-delete-pod`, `fix-force-sync`) | the word `confirm`; `apply` is rejected with the usage line |
| `/cleanup-stale-sandbox [preview\|confirm\|apply]` | `confirm` **or** `apply` |
| HTTP API (`/api/v1/...`) | `"confirm": true` |

The cleanup output adds a third and fourth label: the queued line says `(apply)` or `(dry-run)` and
the thread header says `(apply)` or `(preview)`. The "unknown command" help lists
`cleanup-stale-sandbox [confirm]`.

## Root cause

`bin/k3dm-webhook`:
- line ~961: `if _cleanup_action not in ("preview", "confirm", "apply")`, then
  `_confirm = _cleanup_action in ("confirm", "apply")`;
- line ~962: usage `cleanup-stale-sandbox [preview|confirm|apply]`;
- line ~967: `_tag = "apply" if _confirm else "dry-run"`;
- line ~507: the thread header uses `'apply' if confirm else 'preview'`.

## Fix

`confirm` is the one keyword, because the `/k3dm` targets, the HTTP API and the `CONFIRM=1` make
variable already use it. The preview label is `preview`.

- **F1.** In the `cleanup-stale-sandbox` branch, accept only `preview` and `confirm`. On `apply`,
  run nothing and reply: ``❌ `apply` is no longer accepted — use `cleanup-stale-sandbox confirm`.``
  Any other word still gets the usage line, now `cleanup-stale-sandbox [preview|confirm]`.
- **F2.** Labels: the queued line and the thread header both say `(confirm)` or `(preview)`. Remove
  `dry-run` and `apply` from both.
- **F3.** Tests in `scripts/tests/bin/test_webhook_stale_cleanup.py`: change the existing `apply`
  case to `confirm`, and add an `apply` case that asserts no cleanup thread starts and the reply
  names `confirm`.
- **F4.** `docs/howto/slack-slash-commands.md`: a short "Confirming a mutating command" note:
  `confirm` is the only keyword on Slack, `"confirm": true` on the API, `CONFIRM=1` on make.
  `/cluster-up` and `/cluster-down` are out of scope (they run by default and take `dry-run`).

Do not change `/k3dm`, the HTTP API, `cluster-up`/`cluster-down`, or `bin/cleanup-stale-sandbox`.

## Files

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_stale_cleanup.py`
- `docs/howto/slack-slash-commands.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: "cleanup-stale-sandbox confirm" starts the cleanup with confirm=True; "cleanup-stale-sandbox" and "cleanup-stale-sandbox preview" start it with confirm=False.
  - id: M2
    text: The queued line and the thread header label a confirmed run "(confirm)" and a preview "(preview)".
  - id: M3
    text: The usage line and the howto list only preview and confirm.
must_not:
  - id: N1
    text: "cleanup-stale-sandbox apply" must not start a cleanup (red on pre-fix, which runs it with confirm=True).
  - id: N2
    text: No cleanup message may contain "(apply)" or "(dry-run)" (red on pre-fix).
  - id: N3
    text: /k3dm target parsing, the /api/v1/cleanup-stale-sandbox handler and its admin role gate must not change.
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    text: pytest scripts/tests/bin/test_webhook_stale_cleanup.py and the existing webhook policy/role tests, with the cleanup runner stubbed; N1 and N2 shown red on the pre-fix parser.
  - id: E2
    proves: [M3]
    kind: offline
    text: grep the usage string and the howto for "apply" next to cleanup-stale-sandbox (0 matches).
  - id: E3
    proves: [M1, N1]
    kind: live
    text: After make restart-webhook, the operator sends /cleanup-stale-sandbox apply (refused, names confirm) and /cleanup-stale-sandbox (preview); Claude reads the screenshot.
interface:
  - bin/k3dm-webhook Slack command dispatch for "cleanup-stale-sandbox <word>" (the function test_webhook_stale_cleanup.py already calls)
  - _run_stale_sandbox_cleanup(job_id, confirm, channel_id)
```

## Definition of Done

- [ ] F1–F4 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 and N2 shown red against the pre-fix parser.
- [ ] `pytest scripts/tests/bin` green.
- [ ] Commit: `fix(webhook): confirm is the only Slack confirmation keyword`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT run the real cleanup or contact Slack; stub them.
- Do NOT add `apply` (or any other synonym) to `/k3dm`.
