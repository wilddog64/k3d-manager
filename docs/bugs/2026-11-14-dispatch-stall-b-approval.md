# Bug (child B): approve a stalled-dispatch correction from Slack, then resume once

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-14)
**Waiting on:** operator decision — since 2026-11-14 (spec intent)
**Approval:** drafted by Sonnet for Claude review 2026-11-14
**Release:** v1.45.0 plan 5 `dispatch-stall-recovery` (operator, 2026-11-14: "go with your recommendation"); Fable review findings on the parent apply
**Intent approved:** pending
**Introduced by:** pre-existing
**Should have been caught by:** none
**Prior art:** docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md (parent) — child spec
**Parent:** docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md
**Depends on:** child A (`docs/bugs/2026-11-14-dispatch-stall-a-detector.md`: `bin/k3dm-dispatch-stall-watch` calls the executable named by `K3DM_STALL_DRAIN_CMD` every tick). Child C (`docs/bugs/2026-11-14-dispatch-stall-c-diagnose.md`) writes the files this child reads; B is testable alone with fixture stall directories.

## What this child does

The parent's step 4 and 5: after the stall watcher has stopped a stuck dispatch and the diagnosis step has written a correction, the
operator gets a Slack card with Approve and Deny. Approve re-checks that nothing changed and resumes the dispatch once with that
correction. Deny, or no click, does nothing. B does not detect, diagnose or kill anything.

## Findings (read-only, 2026-11-14)

- The relay already carries the whole approval path, built for Hermes. `workers/slack-relay/index.js:4` fixes the action id shape
  `HERMES_ACTION_ID_RE = /^r[0-9]+-[0-9a-f]{8}$/` and `:5` the nonce `/^[0-9a-f]{16}$/`. It is checked once, at
  `index.js:259-260` (`handleInteractivity`). A click needs the signed Slack request, an allowlisted approver (`:207-210`, `approverAllowed`)
  and a live `/hermes-auth` re-auth (`:403` writes `reauth:<user>`, 24h TTL `:3`; checked in `handleInteractivity`). Approve then stores `approval:<id>` in KV with a 3600s TTL
  (`:275-277`, `:2`). Deny writes nothing to KV (`:280`, it only replaces the card).
- The drain routes accept any id of `[A-Za-z0-9-]{1,64}` (`index.js:222-244`: GET lists up to 50 `approval:` keys at `:223`; DELETE matches
  `:239-240`). The pattern is enforced by the client, not by the drain route. Both M5 Hermes and a new M4 drain would see every key.
- Hermes filters on the client. `scripts/lib/hermes/approvals.py:14` `ACTION_ID_RE = ^r[0-9]+-[0-9a-f]{8}$`; `fetch_approvals` (`:23-40`) drops
  every item that does not match it, and `delete_approval` (`:43-45`) refuses any id that does not match it. So an item with a `d` id is
  never returned to Hermes and so never reaches Hermes's delete-unknown branch (`bin/k3dm-hermes:313-315`). That is the fact this spec
  depends on, and the first positive-control test below proves it with today's code before anything changes.
- Hermes' own use: `bin/k3dm-hermes:304-330` (`_drain_approvals`), nonce per incident `:271-272,288` (`state["incident_nonce"] = secrets.token_hex(8)`),
  card posting `:985-989`, one attempt per incident `scripts/lib/hermes/repairs.py:373-374`
  (`repairs_attempted_this_incident`). B copies the idea (nonce per incident, re-check on approve, one attempt), not the code path:
  `repairs.approve()` is Hermes-only and stays untouched.
- Buttons work only when the card is posted through the relay's own Slack app (`docs/guides/hermes.md` step 3 under Slack approvals; operator
  2026-11-08): the `k3dm-slack-webhook` item must be an incoming webhook of the `k3d-manager` app (channel `#grafana-notification`). A card
  posted through `k3dm-notices` shows "not configured to handle interactive responses".
- Resume: `bin/k3dm-codex-dispatch:1313-1375` (`_dispatch_resume`). It needs `--slug`, `--prompt-file` (non-empty, copied to `prompt-<n>.md`),
  `--reason correction` (`:1322`), refuses a running worker (`:1343-1345`), and rejects `--model` for an agy run (`:1348`). With no `--model`
  it inherits the recorded one. `_dispatch_release_branch` (`:730-735`) requires the main checkout to be on a `k3d-manager-vX.Y.Z` branch, so the
  drain must run from that checkout.
- Dispatch state: `_dispatch_status` (`:1003-1040`) derives `state` from files in `<root>/<version>/<slug>.run`:
  `landed`, `exit` (`exited successfully` or `exited nonzero (N)`), `running`. The number of resumes is the count of
  `prompt-[0-9]*.md` files there (`:1027-1029`, printed as `resumes: N`). Worktree root is `K3DM_WORKTREE_ROOT`
  or `~/.local/share/k3d-manager/worktrees` (`:11`).
- M4 has no copy of either item today: `scripts/etc/machine/secrets.worker.list` lists four other items; both items sit in
  `secrets.hub.list:8,17` (hub role only).

## Design

### 1. Relay: accept a `d` action id beside the `r` id

- `workers/slack-relay/index.js:4` becomes `/^[rd][0-9]+-[0-9a-f]{8}$/`. Nothing else in the relay changes: the signature check, approver
  allowlist, re-auth, KV key shape, TTL, drain auth and button action ids (`hermes_approve` / `hermes_deny`) stay as they are.
- Known wording gap, deliberately not fixed here (spec says nothing else changes): the replaced card says "applying on the next Hermes
  poll (up to ~5 min)" (`index.js:278`). For a `d` id the next drain is the M4 stall-watch tick (5 minutes, child A). Same time scale,
  slightly wrong name. Listed under Open questions.

### 2. `scripts/lib/hermes/approvals.py`: an optional id pattern

- `fetch_approvals(drain_url, token, opener=..., timeout=10, id_pattern=ACTION_ID_RE)` and
  `delete_approval(drain_url, token, action_id, opener=..., timeout=10, id_pattern=ACTION_ID_RE)`. The default is the same compiled object as
  today, so every existing call (`bin/k3dm-hermes:310,314,319`) is byte-for-byte the same behaviour. Add `DISPATCH_ACTION_ID_RE =
  re.compile(r"^d[0-9]+-[0-9a-f]{8}$")` next to it. The new parameter goes last, after `timeout`, so positional calls keep working.
- `interactive_blocks` is reused as is. Its confirm text says "Approve repair?"; accepted for now.

### 3. New drain: `bin/k3dm-dispatch-recover` (python3, reuses `scripts/lib/hermes`)

Called with no argument by `K3DM_STALL_DRAIN_CMD` (child A) on the M4 every 5 minutes; also runnable by hand. It never blocks longer than the
HTTP and subprocess timeouts below, and exits 0 unless it is misused.

Inputs, none from argv:
- Drain token: Keychain `k3dm-hermes-approval-drain-token` (`APPROVAL_DRAIN_SERVICE`, `approvals.py:13`) via `hermes.sensors._keychain_secret`
  (argv carries the service name, never a value; `sensors.py:381-390`).
- Slack card URL: Keychain `k3dm-slack-webhook` through the same function.
- Drain URL: `K3DM_HERMES_APPROVAL_DRAIN_URL` (same variable and value as `scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl:25`).
  Unset, or either Keychain item empty: print one line `dispatch-recover: approvals not configured` and exit 0 (fail closed, no card).
- Worktree root: `K3DM_WORKTREE_ROOT` or the default above. State file: `K3DM_DISPATCH_RECOVER_STATE`, default
  `~/.local/state/k3d-manager/dispatch-recover.json`, mode 0600, written atomically (temp file plus rename), guarded by an exclusive
  `fcntl.flock` on a sibling lock file; a second concurrent run exits 0 at once.

**(a) Propose.** For every `<root>/<version>/<slug>.run/stall-<ts>/` that holds `correction.md` and `diagnosis.md`:
1. Skip if state already has this stall directory (any status).
2. Validate: `slug` matches `^[A-Za-z0-9._-]{1,120}$`; `correction.md` resolves (realpath) inside that run directory and is non-empty and under 64 KiB.
3. If the state already has a proposal for this slug (any earlier stall) then this is a second stall of the same run: record
   `{"status": "paged"}` for the stall directory and `post_summary` one plain line (slug, stall dir name, "second stall, no proposal, operator
   action needed"). No card, no approval id.
4. Otherwise generate `action_id = f"d1-{secrets.token_hex(4)}"` and `nonce = secrets.token_hex(8)`, build one proposal item
   `{"action_id", "name": "Resume stalled dispatch <slug> with Claude's correction", "blast_radius": "one resume of <slug> in its own worktree, prompt = correction.md (sha256 first 12 chars shown)"}`,
   and post the diagnosis summary (first 2000 characters of `diagnosis.md`, with the slug, the stall time and the correction hash) with
   `post_interactive(relay, text, interactive_blocks(text, [item], nonce))`. On failure to post, record nothing (retry next tick).
5. Only after a successful post, write the proposal to state: `{stall_dir, slug, version, action_id, nonce, proposed_at, expires_at (proposed_at + 2h),
   resume_count, correction_sha256, worktree_sha256, status: "proposed"}`. `resume_count` is the number of `prompt-[0-9]*.md` files in the run
   directory at proposal time. `worktree_sha256` is the sha256 of `git -C <worktree> diff HEAD --binary` followed by, for every untracked
   path from `git ls-files -o --exclude-standard -z`, `git hash-object --no-filters -- <path>` (so a changed untracked file also changes it).

**(b) Drain.** `fetch_approvals(drain_url, token, id_pattern=DISPATCH_ACTION_ID_RE)`; for each item:
1. Find the state proposal with that `action_id` and the same `nonce`. None, wrong nonce, or `status != "proposed"` (already handled): delete the
   approval, post `dispatch-recover: dropped stale or unknown approval <id>`, continue. An approval whose proposal has `expires_at` in the past:
   mark `expired`, refuse (below).
2. Mark the proposal `attempting` and save the state file BEFORE any resume, so a crash, a retry or a second approval of the same id can never start
   a second attempt (fail closed; a stuck `attempting` is cleared only by hand).
3. Re-check, all must hold (each failure is a distinct refusal reason):
   - dispatch state is `exited` (`<run>/exit` exists, `<run>/landed` absent, `<run>/violation` absent) and no worker runs for it;
   - `prompt-[0-9]*.md` count equals the recorded `resume_count` (no one resumed it meanwhile);
   - sha256 of `correction.md` equals `correction_sha256`;
   - worktree hash recomputed as above equals `worktree_sha256`;
   - the main checkout's branch is `k3d-manager-<version>` (else `_dispatch_release_branch` would fail);
   - no earlier proposal for this slug is `attempted`, `attempting` or `resumed` (one attempt per incident).
4. If all hold: run, with `subprocess.run([...], cwd=<repo root>, capture_output=True, text=True, timeout=300, check=False)` and an argv list
   (no shell), `bin/k3dm-codex-dispatch resume --slug <slug> --prompt-file <abs path of correction.md> --reason correction --coordinator anthropic/claude-opus-5-5`.
   No `--model` (an agy resume rejects it, `bin/k3dm-codex-dispatch:1348`; the recorded model is inherited). Status becomes `resumed` on rc 0, `resume_failed` otherwise;
   neither is retried.
5. Whatever happened, `delete_approval(..., id_pattern=DISPATCH_ACTION_ID_RE)` and `post_summary` one line: `Dispatch <slug> resumed with the approved correction (by <@approver>)`,
   or `Dispatch <slug> resume refused: <reason> (requested by <@approver>)`, or the resume failure with the last stderr line (scrubbed of anything matching the URL or token).
6. Deny writes no approval (relay, `index.js:280`), so there is nothing to drain: the proposal stays `proposed` until `expires_at`, then is marked
   `expired` by the next run, and an Approve of it after that is refused. This is stated in the card text ("Deny or ignore to do nothing").

Security properties, as tests (see Acceptance): no token or webhook URL ever in argv, log or Slack text; only `d` approvals are fetched or deleted by this
drain and only `r` by Hermes; `correction.md` is passed by path, never interpolated into a shell; the slug and paths are validated before use.

### 4. Keychain and relay deploy

M4 needs two items copied from the M5. Registry: add both to `scripts/etc/machine/secrets.worker.list`
(`k3dm-hermes-approval-drain-token|k3dm|Dispatch stall approval drain|operator: see docs/guides/hermes.md` and
`k3dm-slack-webhook|k3dm|Dispatch stall Slack card relay|operator: see docs/guides/hermes.md`). The operator copies the values (they prompt; never `-w <value>`).

## Contract readers

Contract 1: action id shape `^r[0-9]+-[0-9a-f]{8}$` in the approval path (becomes `^[rd]...` in the relay, parameterised on the client).

Readers and validators:
- `workers/slack-relay/index.js:4` definition; used only at `:259-260` (`handleInteractivity`). Change: widen to `[rd]`.
- `workers/slack-relay/index.js:239` DELETE route regex `[A-Za-z0-9-]{1,64}`: already accepts a `d` id; no change. `:222-238` GET lists any `approval:` key; no change.
- `scripts/lib/hermes/approvals.py:14` `ACTION_ID_RE`, used at `:38` (`fetch_approvals`) and `:45` (`delete_approval`): default unchanged; optional parameter added.
- `bin/k3dm-hermes:35` imports, `:310` fetch, `:314,319` delete: call with no pattern argument, so Hermes keeps the r-pattern; unchanged.
- `scripts/lib/hermes/repairs.py` proposals use `r<N>-<hex8>` action ids (`approve`, `:363-374`): unchanged; never produces a `d` id.
- Tests: `scripts/tests/hermes/test_approvals.py:51-69` (valid item `r2-0123abcd`, `bad`), `workers/slack-relay/test/relay.test.mjs:7,134-142,160-166` (value `r2-0123abcd|...`, malformed values): unchanged and still green.
- Docs: `docs/guides/hermes.md` Slack approvals section (one added paragraph); `docs/plans/v1.33.0-hermes-slack-approval.md` is history, not edited.
- Writers of action ids (`d`): only the new `bin/k3dm-dispatch-recover` (`d1-<hex8>`; the leading number is the incident counter, always 1 in this child).

Contract 2: Keychain item `k3dm-hermes-approval-drain-token` (account `k3dm`) and the relay secret `APPROVAL_DRAIN_TOKEN` it must equal.
Readers (grep `k3dm-hermes-approval-drain-token|APPROVAL_DRAIN_SERVICE|APPROVAL_DRAIN_TOKEN`, 2026-11-14):
- `scripts/lib/hermes/approvals.py:13` constant; `bin/k3dm-hermes:35` import, `:308` read in `_drain_approvals`, `:982` read to decide whether to post buttons (M5).
- `bin/k3dm-hermes-setup:70-73` presence check, message only (M5).
- `workers/slack-relay/index.js:212-215` `drainAuthorized` reads the Worker secret `APPROVAL_DRAIN_TOKEN` (length at least 32, constant-time compare).
- `scripts/etc/machine/secrets.hub.list:8` registry entry (hub role), `Makefile:1313,1320` reads for `hermes-drain-token`.
- NEW: `bin/k3dm-dispatch-recover` (M4). `scripts/etc/machine/secrets.worker.list` (new line).
- Tests that name it: `scripts/tests/hermes/test_approvals.py:97`, `scripts/tests/bin/makefile_hermes_approvals.bats:29`, `workers/slack-relay/test/relay.test.mjs:71-178` (the Worker secret).
Writers:
- `Makefile:1313-1325` `hermes-drain-token`: creates or reuses the item (`security -i`, token not in argv), then `wrangler secret put APPROVAL_DRAIN_TOKEN`; `ROTATE=1` rotates both. Consequence for B: a rotation on the M5 makes the M4 copy stale, so the M4 drain gets 401, which `fetch_approvals` turns into `[]` (silent). B therefore reports a 401 as one Slack line per day (see "Drain health").
- `.github/workflows/deploy-worker.yml` sets only `WEBHOOK_TOKEN` and `SLACK_SIGNING_SECRET` (`deploy-worker.yml` secrets block); it does not write `APPROVAL_DRAIN_TOKEN`, so a relay redeploy does not touch it. `Makefile:899-915` `deploy-worker` likewise puts only those two secrets.
- NEW: the operator's M4 copy (below).

Contract 3: Keychain item `k3dm-slack-webhook` (account `k3dm`), the incoming webhook of the `k3d-manager` app.
Readers (grep, 2026-11-14): `bin/k3dm-hermes:429,443,453,980,1114` (M5), `bin/k3dm-slack-notify:14` (M5, and M4 if run there), `bin/k3dm-hermes-setup:31` and `scripts/lib/foundation/scripts/lib/system.sh:2282` (install-time presence checks for the Hermes agent, M5), `scripts/etc/machine/secrets.hub.list:17`, `scripts/tests/bin/machine_setup.bats:659`; NEW `bin/k3dm-dispatch-recover`.
Writers: none in the repo (operator creates it by hand; `docs/guides/hermes.md` step 3 says which app and channel). The M4 copy is another hand-made copy.

Contract 4: env var `K3DM_HERMES_APPROVAL_DRAIN_URL`. Reader `bin/k3dm-hermes:981`; writer `scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl:25` (value `https://k3dm-slack-relay.k3dm.workers.dev/hermes/approvals`; `scripts/tests/hermes/test_app_health.py:153` asserts it). NEW reader `bin/k3dm-dispatch-recover`, which gets it from the environment that child A's launchd plist sets for the stall watcher (child A owns that plist; B depends on it passing this one variable, and falls back to nothing).

Contract 5: the stall-directory files written by child A/C and read here: `<run>/stall-<ts>/correction.md`, `diagnosis.md` (child C writes; child A creates the directory). B only reads them. B writes `<run>/stall-<ts>/` nothing; its only writes are the state file and Slack/relay calls.

Contract 6: `bin/k3dm-codex-dispatch resume` flags and `<run>/prompt-N.md`, `exit`, `landed`, `violation`: B reads them and calls `resume` exactly as the operator does by hand; no change to the dispatcher.

## Drain health (so a bad token is not silent)

`fetch_approvals` returns `[]` on any error (`approvals.py:32-33`), including 401 and DNS. B adds, in its own file only, one cheap probe
per run: if a proposal is `proposed` and not expired and the relay GET answers 401/403, post one Slack line per 24h:
`dispatch-recover: the drain token on this Mac is rejected by the relay; rerun the Keychain copy (docs/guides/hermes.md)`. The probe uses its own
`urllib` call with the same header; it does not alter `approvals.py`.

## Acceptance

```yaml
must:
  M1: the relay accepts an interactivity click whose value is a d-id plus nonce (for example d1-0123abcd|0123456789abcdef): after an allowlisted, re-authenticated Approve it stores approval:d1-0123abcd with a 3600s TTL, and the drain GET lists it with its nonce
  M2: the relay still refuses a malformed id (no letter prefix, wrong prefix such as x1-0123abcd, uppercase hex, short hex, extra characters) with no KV write and no outbound call, and still refuses an unauthorised or not re-authenticated user for a d id exactly as for an r id
  M3: fetch_approvals and delete_approval called with no pattern behave exactly as before (r ids returned and deletable, d ids not returned and not deletable); called with the d pattern they return and delete d ids and never r ids
  M4: bin/k3dm-dispatch-recover posts one Approve/Deny card (post_interactive, blocks from interactive_blocks) for a stall directory holding correction.md and diagnosis.md, with action id matching ^d1-[0-9a-f]{8}$ and a 16-hex nonce, and records stall dir, slug, resume count, sha256 of correction.md and the worktree hash before the first drain can use it
  M5: on an approved d id whose precondition still holds it runs exactly one bin/k3dm-codex-dispatch resume with --slug, --prompt-file <that run's correction.md>, --reason correction and --coordinator anthropic/claude-opus-5-5, with no --model, then deletes the approval and posts one Slack line
  M6: on an approved d id with an unknown or wrong nonce, an expired proposal, a running dispatch, a changed resume count, a changed correction.md, a changed worktree (tracked diff or untracked file), or a wrong release branch, it runs nothing, deletes the approval and posts a refusal line naming the reason
  M7: a second stall of a slug that already has a proposal gets no card and no action id: one plain Slack line only
  M8: the state is written as attempting before resume starts, so a repeated approval of the same id, or a rerun after a crash, never starts a second resume
must_not:
  N1: Hermes (default patterns) ever fetches or deletes an approval whose id starts with d
  N2: this drain ever fetches or deletes an approval whose id starts with r
  N3: resume runs when the worktree changed after the proposal, when correction.md changed, or when the resume count moved
  N4: a second resume for one incident, by a repeated approval, a rerun, or a new stall directory of the same slug
  N5: the drain token, the Slack webhook URL or the relay URL appears in any subprocess argv, in the state file, in a log line or in Slack text
  N6: the relay change loosens anything but the id shape (no new route, no new KV key shape, no change to approver, re-auth or drain auth checks)
  N7: a Deny, or no click, runs anything
evidence:
  - {id: E1, proves: [M1, M2], kind: offline, intent: "You will see the relay's node tests: a d-id Approve is recorded and listed by the drain, and six malformed ids leave KV and the outbound call list empty. Today the d-id test fails because the relay ignores the value, so it is red before the change."}
  - {id: E2, proves: [M3, N1, N2], kind: offline, intent: "You will see Python tests where a fake relay returns one r item and one d item: the default call returns only the r item and the d pattern returns only the d item, and the default delete refuses a d id. The first assertion passes on today's code (the baseline Hermes behaviour), the second needs the new parameter and is red today."}
  - {id: E3, proves: [M3, N1], kind: offline, intent: "You will see the existing scripts/tests/hermes tests pass unchanged and a poll test showing Hermes with a d item in the queue neither deletes nor reports it. As a positive control the same queue with an r item for an unknown action id is deleted and reported 'dropped' by the Hermes drain."}
  - {id: E4, proves: [M4, M7], kind: offline, intent: "You will see tests with a stub urlopen and a fixture run directory: one stall directory yields one card with a d1 id, a recorded proposal and a hash; a second stall of the same slug yields one plain line and no card; a stall directory without diagnosis.md yields nothing. Today the script does not exist, so every test errors."}
  - {id: E5, proves: [M5, M6, N3], kind: offline, intent: "You will see, for one fixture dispatch, the unchanged case run resume once, then six runs each changing one thing after the proposal (a tracked file edit, a new untracked file, correction.md rewritten, a new prompt-N.md, a running worker, another release branch) each refused with a named reason and no resume call. The unchanged case is the positive control: without it a stub that never runs resume would pass the refusals."}
  - {id: E6, proves: [M8, N4], kind: offline, intent: "You will see the same approval drained twice and a second stall directory for the same slug approved: the stub codex-dispatch is called once in total; and a state file left at attempting by a simulated crash blocks a rerun."}
  - {id: E7, proves: [N5], kind: offline, intent: "You will see a run with a distinctive fake token and fake webhook URL: the recorded argv of every subprocess, the state file and the captured stdout and stderr contain neither string, while the stub opener did receive the token as an Authorization header (positive control that the token was in use)."}
  - {id: E8, proves: [N7, M8], kind: offline, intent: "You will see an empty drain after a Deny: no subprocess call, the proposal untouched, and after its expiry time a rerun marks it expired and refuses a late Approve."}
  - {id: E9, proves: [M1, M5], kind: live, intent: "You will see, after the operator redeploys the relay and copies the two Keychain items to the M4, a staged toy dispatch that has been stopped by the stall watcher produce a card in #grafana-notification with working buttons; one Approve click resumes the toy dispatch (status shows it running with resumes incremented) and a Slack line confirms it. Run by operator or Claude, never Gemini."}
  - {id: E10, proves: [N7, M2], kind: live, intent: "You will see a second staged toy stall where the operator clicks Deny: no resume, status stays exited, no approval remains in the relay (an empty authorised drain GET). Run by operator or Claude."}
interface:
  - "bin/k3dm-dispatch-recover (no argv; env K3DM_HERMES_APPROVAL_DRAIN_URL, K3DM_WORKTREE_ROOT, K3DM_DISPATCH_RECOVER_STATE; Keychain k3dm-hermes-approval-drain-token and k3dm-slack-webhook; exit 0)"
  - "scripts/lib/hermes/approvals.py: fetch_approvals(..., id_pattern=ACTION_ID_RE), delete_approval(..., id_pattern=ACTION_ID_RE), DISPATCH_ACTION_ID_RE"
  - "workers/slack-relay/index.js: HERMES_ACTION_ID_RE = ^[rd][0-9]+-[0-9a-f]{8}$"
```

Regression-guard note: N1, N2, N5 and N7 hold vacuously on today's tree for the parts that do not exist yet (no `d` item is ever written, no drain
exists). They are guards with positive controls, named in E2, E3, E5 and E7: each repeats the same assertion on a case that must go the other way (an `r` item for
Hermes, a `d` item for the new drain, an unchanged worktree, a token that was visibly used). Pre-fix red: M1 (E1), the `id_pattern` half of M3 (E2), and every M4 to M8 test (script absent).

## Files

| File | Change |
|---|---|
| `workers/slack-relay/index.js` | line 4: `HERMES_ACTION_ID_RE` accepts `[rd]` |
| `workers/slack-relay/test/relay.test.mjs` | new tests: `d` id Approve stored and listed (E1), malformed ids refused, unauthorised `d` refused |
| `scripts/lib/hermes/approvals.py` | `DISPATCH_ACTION_ID_RE`; optional `id_pattern` on `fetch_approvals` and `delete_approval` |
| `scripts/tests/hermes/test_approvals.py` | new tests E2, E3 (existing tests untouched) |
| `bin/k3dm-dispatch-recover` | new, executable, python3, LF |
| `scripts/tests/hermes/test_dispatch_recover.py` | new: E4 to E8 (load the script with `SourceFileLoader` like `test_approvals.py:15-18`; stub `urlopen`, `subprocess.run`, `_keychain_secret`; scratch HOME and worktree root; fixture git repo made in `tmp_path`) |
| `scripts/etc/machine/secrets.worker.list` | two lines (Design 4); `scripts/tests/bin/machine_setup.bats` suites that read the worker list must stay green |
| `docs/guides/hermes.md` | one paragraph in Slack approvals: `d` ids belong to dispatch recovery, the M4 needs the two items, a drain-token rotation must be re-copied to the M4 |

No change to `bin/k3dm-hermes`, `repairs.py`, `bin/k3dm-codex-dispatch`, the Makefile, `.github/workflows/`, `wrangler.toml` or any launchd template. Child A owns the stall-watch plist, its install target and its `K3DM_STALL_DRAIN_CMD` setting.

## Rollout

1. Land on the release branch, CI green. The relay is not live until deployed; `deploy-worker.yml` (`on: push` to `main`, paths `workers/slack-relay/**`, plus `workflow_dispatch`) will deploy it after the release merge, which is later than this work needs. To get it sooner the operator runs, in their own terminal, `make deploy-worker` (`Makefile:899-915`; puts `WEBHOOK_TOKEN` and `SLACK_SIGNING_SECRET` from Keychain, runs `wrangler deploy`, then a signed `/cluster-status` probe). It does not touch `APPROVAL_DRAIN_TOKEN`, `APPROVER_ALLOWLIST` or KV.
2. On the M4, the operator copies the two items. On the M5: `security find-generic-password -s k3dm-hermes-approval-drain-token -a k3dm -w` is a read that prints the value; to avoid a value in a shell or history use the file-free path the machine setup already offers (`make machine-setup ROLE=worker FROM=m5-air.local`, `docs/howto/machine-setup.md:58`) or, by hand on the M4, `security add-generic-password -U -s k3dm-hermes-approval-drain-token -a k3dm -w` and `security add-generic-password -U -s k3dm-slack-webhook -a k3dm -w`, each of which prompts for the value (never `-w <value>` on the command line, which would put it in argv). The webhook must be the `k3d-manager` app's, the same value as the M5 item.
3. Child A installs the watcher with `K3DM_STALL_DRAIN_CMD=<repo>/bin/k3dm-dispatch-recover` and the drain URL in its environment. Until A and C land, run the script by hand against a fixture to check cards.
4. Live E9 and E10 with a toy dispatch (operator or Claude). The approver must have run `/hermes-auth` in Slack within 24h.
5. A drain-token rotation on the M5 (`ROTATE=1 make hermes-drain-token`) now also needs the M4 copy refreshed; the docs paragraph says so.

## Worker definition of done

- Change only the files in the table. Offline tests only: no network, no cluster, no real Keychain, no Slack. Stub `urlopen` (never contact `k3dm-slack-relay.k3dm.workers.dev`), `subprocess.run` for `bin/k3dm-codex-dispatch` and `security`, and `curl` if any code path reaches it. Scratch HOME; `PUSHGATEWAY_URL=http://127.0.0.1:9`. The fixture git repo and worktree root live under `tmp_path`. The recorded relay replies in tests are shaped from `workers/slack-relay/index.js:222-238` (read 2026-11-14 on this checkout), not guessed.
- Python: `/opt/homebrew/bin/python3 -m pytest scripts/tests/hermes -q`. Show E2 and the `id_pattern` half red on today's tree, then green; show E4 to E8 red (script missing) then green. Also run `bats scripts/tests/bin/machine_setup.bats scripts/tests/bin/makefile_hermes_approvals.bats`.
- Relay (node is on the M4 at `/opt/homebrew/bin/node`): `node --test workers/slack-relay/test/relay.test.mjs`. Show the new `d` test red before the one-line change, then green; if node is absent, say so and do not claim E1. There is no `package.json` and no CI or Makefile step that runs this file (grep 2026-11-14); do not add one.
- Mutation-test the guards: for E5, delete one re-check at a time in a scratch copy of the script and show the matching refusal test goes red; for E7, add a `print(token)` to a scratch copy and show E7 goes red.
- Paste each command, rc and proving lines, and list every error seen. Leave changes uncommitted; do not push; no live check (E9, E10 belong to the operator or Claude); do not touch `docs/bugs/`.

## Open questions

1. Does child A pass `K3DM_HERMES_APPROVAL_DRAIN_URL` and a PATH that finds `python3` and `security` to the drain command, and does it call it with no argument? B assumes yes (child A's spec was not on disk when this was drafted).
2. Should the relay's replaced-card text name the dispatch drain for `d` ids (`index.js:278`, "next Hermes poll")? Left alone because the brief says nothing else in the relay changes.
3. Is the `k3dm-slack-webhook` value on the M5 the `k3d-manager` app webhook (per `docs/guides/hermes.md` step 3), so the M4 copy gets working buttons? Not checkable from the repo.
4. Proposal expiry is 2 hours (longer than the 1 hour approval TTL, shorter than the 24h re-auth): operator to confirm.
