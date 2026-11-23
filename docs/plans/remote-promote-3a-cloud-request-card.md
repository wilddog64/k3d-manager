# v1.46.0 — Remote promote, part 3a: `promote-request` cloud action and the Slack approval card

**Status:** DRAFT v1 — 2026-11-22, not reviewed
**Priority:** P2
**Version:** v1.46.0 candidate — placed at the next /release-groom (v1.46.0 is over its 5-plan cap; needs a displacement); implement on the release timeline, do not dispatch before placement
**Release:** v1.46.0 candidate, Part 3a of the remote-promote umbrella `docs/plans/v1.45.0-remote-promote-approval.md` ("Part 3 outline")
**Branch:** `k3d-manager-v1.46.0` (not cut yet)
**Filed:** 2026-11-22
**Intent:** pending operator approval
**Risk:** hub. The change runs inside `bin/k3dm-cloud-bridge`, an always-on launchd agent that reads requests a cloud session can write
  freely, and it now makes that agent call the root promote authority (`bin/k3dm-promote-client request`) and post to the operator's Slack
  channel. A mistake here can (a) let cloud-session text reach Slack markup or a client argv, (b) leak the record's nonce onto the public
  `cloud-requests` branch, (c) let a cloud session use up the engine's single-pending and 3-per-hour budget so the operator's own request is
  refused (a lockout, never a promote), or (d) stall the poller behind a slow client call. The approval itself stays out of this part: it
  needs the operator's Slack user id and a TOTP code, which no cloud session has.
**Depends on:** Parts 1, 2a, 2c, 2d and 2e live on the hub (the authority installed and enrolled; Part 2b landed or not, 3a does not call
  `bin/k3dm-hub-promote`). Part 3b (relay: `/hermes-totp`, the Worker-signed envelope, widened action-id pattern) for the end-to-end path;
  3a is testable and mergeable without it, and its live check E8 needs it.
**Implementer:** Luna. **Verifier:** Claude, plus an independent verifier working from `## Acceptance` only.
**Red-team gate:** `docs/plans/v1.45.0-red-team-gate.md` may change Part 2 (wire format, client ops, rate limits) before this lands. Every
  Part 2 citation below is to the landed tree at HEAD `bc8276f0` (2026-11-22); re-cite after the gate.
**Do not dispatch until Open question Q1 is answered** (where the early policy check runs); the Behaviour 3 seam is written so the answer
  changes one function, not the contract.

## Problem

Part 2 gives the hub a root promote authority with an approval record, a TOTP check and a Worker-signed approval envelope. Nothing yet lets a
cloud session ask for one, and nothing posts the card the operator presses.

Today a cloud session can file only the read-only actions in `ACTION_ALLOWLIST` (`scripts/lib/webhook/cloud_actions.py:17-52`). Each one is
sent to the local webhook by `_call_webhook` (`bin/k3dm-cloud-bridge:327`). `promote-request` has no webhook path: the bridge itself must
validate the sha, ask the authority for a record, and post the card. That is the first cloud action with a local side effect, so it needs
its own gate, response shape and final-response path.

Facts the umbrella's Part 3 outline did not have, found by reading the landed tree (each repeated in Contract readers):
- **There is no standalone `evaluate`.** The umbrella says "the same policy evaluation as Part 2d (`evaluate`)". Part 2d landed
  `Mover.move` (`scripts/lib/promote_mover.py:288-368`), which fetches, evaluates and pushes in one call, runs only in the root daemon, and
  needs credentials the bridge cannot read (the read token and deploy key under `/var/db/k3dm-promote/creds`, Part 2c A.2). See Q1.
- **The card builder cannot be reused.** `interactive_blocks` (`scripts/lib/hermes/approvals.py:62-83`) builds repair cards: it needs
  `name` and `blast_radius` per item and its confirm dialog reads "Approve repair?".
- **The `--wait-final` path is job-only.** `bin/k3dm-cloud-request:127-129` stops unless `body.status == "queued"` and `body.job_id` is set,
  and the watch ledger (`bin/k3dm-cloud-bridge:477-503`) drops any entry without `job_id`, which would also erase a promote entry the next
  time `_write_commit` rewrites `ledger/watching.txt` (`:505-585`).
- **`_spawn_capture_text` merges stderr into stdout** (`scripts/lib/webhook/proc.py:28-31`, `DUP2 1,2`). `bin/k3dm-promote-client` prints
  the envelope to stdout and the message to stderr (`:144-145`), so the bridge sees two lines and must parse only the first.
- **The engine already rate-limits** (one pending record in total, one non-final per sha, 3 per hour, 5 non-final;
  `scripts/lib/hub_approval.py:328-332`), stricter than the umbrella's "one open pending per sha and three per hour".
- **`requested_by` in a cloud request is free text a cloud session controls** (`REQUIRED_FIELDS` only requires the key,
  `bin/k3dm-cloud-bridge:39`; the helper writes `claude-cloud`, `bin/k3dm-cloud-request:102`). The engine accepts
  `[A-Za-z0-9._:@-]{1,64}` (`scripts/lib/hub_approval.py:97`) and records it as display text only.

## Behaviour

**A. The action**

1. **Table row.** `scripts/lib/webhook/cloud_actions.py` gains `SHA40_RE = re.compile(r"[0-9a-f]{40}")`, a frozenset `LOCAL_ACTIONS =
   frozenset({"promote-request"})` and the row `"promote-request": ("LOCAL", "", {"sha": SHA40_RE}, "promote-request")`.
   - The method `"LOCAL"` is the marker. A request has exactly one argument, `sha`, 40 lowercase hex (the cloud-request surface stays 40
     only, as the umbrella says; the authority accepts 40 or 64, see Contract readers).
   - `bin/k3dm-cloud-request` and `bin/k3dm-cloud-bridge` both read `ACTION_ALLOWLIST`, so the helper accepts `promote-request --arg
     sha=<40hex>` and the bridge validates the same value with the same regex (`validate_request`, `bin/k3dm-cloud-bridge:75-103`).
2. **Never the webhook.** `_call_webhook` (`:327`) refuses a `LOCAL_ACTIONS` action before it builds a URL, reads a token or opens a socket:
   it raises `ValueError`. `_request_body` (`:314`) does the same. A test counts HTTP opens (zero) and token reads (zero).
3. **Dispatch.** In `process_tick`, the branch at `:639-643` gains, before `_call_webhook(request)`: when `request["action"] in
   LOCAL_ACTIONS`, call `handle_promote_request(request_id, request)` and use its return value as `response`; the rest of the loop
   (artifacts, outbox, `_write_commit`) is unchanged. `SLOW_ACTIONS` is not used for it.

**B. Early policy check (seam; Q1 decides the implementation)**

4. `handle_promote_request` first calls one function, `promote_precheck(sha) -> Precheck`, where `Precheck` carries `verdict`
   (`ok`, `refused`, `unknown`), `branch` (the newest release branch, or `None`), `code` and `message` (for non-ok) and the optional card facts
   `subject` and `ahead` (a list of at most five `"<sha7> <subject>"` strings, or `None`).
   - Verdict `refused`: respond `status: "rejected"`, `http_status: 0`, `reason: "<code>: <message>"` (the existing rejected shape,
     `bin/k3dm-cloud-bridge:129-142`). No record, no card, and the client is not called. The message states the reason: not the newest release
     branch's newest green commit, with the newest green sha named, or not green, or not contained.
   - Verdict `unknown` (a lookup failed): respond `status: "error"`, `reason: "could not evaluate; retry later"`. No record.
   - Verdict `ok`: continue with `branch`.
   - Policy is the Part 2d policy and nothing weaker: newest `k3d-manager-vX.Y.Z` branch (leading-zero names ignored; integer-tuple sort,
     `scripts/lib/promote_mover.py:142-160`), the commit is the first green commit of the first 20 first-parent commits (`:272-283`), no
     `BREAK_GLASS` or `SKIP_CHECK_RUNS` switch exists. This early check is advisory: the authority repeats the full evaluation at promote
     time (`Mover.move`) and the engine's `begin_promote` binds the record to the sha, so a wrong early answer can only waste an approval,
     never move `deploy/hub`.
   - The function takes its collaborators as parameters (git runner, check-runs reader, clock) so tests inject fakes; it reads no
     environment variable beyond the bridge's existing ones.

**C. The record**

5. **Client call.** On `ok`, the bridge runs `[<ROOT>/bin/k3dm-promote-client, "request", "--sha", sha, "--branch", branch, "--channel",
   "cloud-session", "--requested-by", "claude-cloud"]` through `_spawn_capture_text` with a 20 s timeout, never through a shell string.
   - `--requested-by` is the constant `claude-cloud`; the request's own `requested_by` value is ignored (it is validated for presence only,
     and is untrusted text).
   - Channel is the constant `cloud-session`; `--socket` is never passed (it is a test seam, Part 2c F.17).
   - No secret is in argv: the values are a validated sha, a validated branch name and two constants. Each value matches its regex
     (`SHA40_RE`; `^k3d-manager-v[0-9]+\.[0-9]+\.[0-9]+$`) before it reaches argv, so none can begin with `-` (the client takes `--flag value`
     pairs and has no `--` form, `bin/k3dm-promote-client:43-60`).
6. **Reply parse.** Only the first output line is parsed as JSON (stderr is merged in, see Problem). It must be exactly the keys `v`,
   `result`, `code`, `message`, `data`, with `v` the integer 1. On `result: "ok"` and `code: "ok"`, `data` must be exactly `id`, `nonce`,
   `expires`, `check` with `id` matching `^p[0-9]+-[0-9a-f]{8}$`, `nonce` `^[0-9a-f]{16}$`, `expires` an integer and `check`
   `^[0-9A-HJKMNP-TV-Z]{4}$`. Anything else is `error`, `reason: "authority reply was not understood"`; the raw line is never copied into a
   response, a log or an exception message.
   - Exit and reply mapping (client contract, Part 2a B.6): exit 0 valid -> continue. Exit 1 (`refused`) -> `rejected`, `reason:
     "<code>: <message>"` (for `rate_limited` the message names the existing pending id, which is not secret). Exit 2 -> `error`,
     `reason: "authority rejected the request"`. Exit 75, a timeout, or an unspawnable client -> `error`, `reason: "promote authority
     unavailable; retry later"`.
   - The nonce is held in memory only until the card is posted. It is never written to a response, the outbox (`bin/k3dm-cloud-bridge:182`),
     the claim file, a log line or `cloud-requests` (a public GitHub branch).

**D. The card**

7. **Builder.** A new stdlib-only module `scripts/lib/hermes/promote_card.py` provides `promote_card(record, precheck, now) -> (text, blocks)`.
   It is a new module, not an edit of `approvals.py`, because `approvals.py` imports `hermes.sensors` (`approvals.py:13`), which the bridge
   must not load. Contents:
   - header line: `Promote request <id>` and the requester `claude-cloud (cloud session)`;
   - `sha7`, the full sha in a code span, the branch, `subject` and `ahead` when present (otherwise the single line `commit details not
     available`);
   - expiry as `HH:MM UTC` from `expires` plus the remaining minutes;
   - the check value, written exactly as returned (`check`);
   - the instruction line `After Approve, send /hermes-totp <id> <check> <code>`;
   - the timing lines (umbrella Part 3 acceptance, "Delivery window"): wait for the next code when fewer than 10 s remain on the current one,
     and do not use the code showing when this card was posted (a code from the record's creation step is refused `early_code` and counts
     as a failure, Part 2a G.20 step 8);
   - one `actions` block with `block_id` = the id and two buttons: `action_id` `hermes_approve` (style primary, with a confirm dialog titled
     `Approve promote?` and text naming sha7 and the branch) and `hermes_deny` (style danger), both with `value` `"<id>|<nonce>"`. These are
     the action ids the relay accepts (`workers/slack-relay/index.js:259`).
   - **Markup safety.** Every cloud- or git-derived string (subject, ahead lines, branch) has `&`, `<` and `>` replaced by `&amp;`, `&lt;`,
     `&gt;` and is cut to 120 characters, so a commit subject such as `<!channel>` cannot ping or link. The text field stays under 2900
     characters (the cap `interactive_blocks` uses, `approvals.py:64`).
8. **Post.** The bridge reads the relay URL with `webhook.auth._keychain_secret("k3dm-slack-webhook")` (same Keychain account and service
   Hermes reads, `scripts/lib/hermes/sensors.py:383-391`) and calls `post_interactive(relay_url, text, blocks)`
   (`scripts/lib/hermes/slack.py:47`). It never calls `post_summary` for this card (no fallback to a card without buttons: a card with no
   buttons is a dead end for an operator who cannot approve).
   - Card delivered: respond `status: "ok"`, `http_status: 202`, `body: {"status": "approval-pending", "id": <id>, "sha": <sha>,
     "branch": <branch>, "expires": <epoch int>}`. No `nonce`, no `check`.
   - Not delivered (empty URL or post failure): respond `status: "error"`, `http_status: 0`, `reason: "card not delivered; record <id>
     stays pending until <expires ISO>; no new request is accepted until then"` and file no watch entry. The record cannot be denied from
     the bridge (it has no approver id), so this is a known cost (residual R3a-3, Q4).
9. **Idempotence.** A request id is handled once (the existing claim and processed ledgers). A bridge restart between the client call and the
   response commit is handled by `_recover_orphaned_claims` (`bin/k3dm-cloud-bridge:236-253`), which commits the existing `error`
   "outcome unknown — file a new request"; the new request is then refused `rate_limited` naming the still-pending id, and the operator can
   still press the card if it was posted. 3a does not re-post a card.

**E. The final response**

10. **Watch entry.** After a delivered card the bridge adds a watch entry to `ledger/watching.txt`: `{"kind": "promote", "request_id": <rid>,
    "approval_id": <id>, "created_at": <time.time()>, "timeout": 900}`.
    - `_read_watching` (`:477-490`) accepts a `promote` entry (keys `kind`, `request_id`, `approval_id`, `created_at`, `timeout`) as well
      as the job entry it accepts today; `_write_commit` (`:505-585`) preserves both kinds when it rewrites the file; the job-status watch loop
      (`:603-621`) skips `promote` entries and a new loop handles them. A job entry still needs its four keys.
    - `_watch_entry` (`:493-503`) is not changed (it is for jobs); the promote entry is built by `handle_promote_request`'s caller and
      added with `watch_add`.
11. **Poll.** Each tick, for at most `MAX_PER_TICK` (`:34`) promote entries, the bridge runs `[<ROOT>/bin/k3dm-promote-client, "show", "--id",
    <id>]` (15 s timeout, first line parsed as in 6; the `show` reply has no nonce, Part 2c C.9) and acts on `data.state`:
    - `pending` or `approved`: keep watching. `approved` is not terminal (the promote is run later, by Hermes, Part 3 outline item 3).
    - `consumed`: write the final response `body: {"status": "promoted", "id", "sha", "old", "new", "tag"}` (`new` equal to the requested
      sha, tag matching `^hub-promote/[0-9]{8}T[0-9]{6}Z$`; any mismatch is `error`, not `promoted`). The words are "deploy/hub moved"; the
      body does not say the platform steps ran (that is `bin/k3dm-hub-deploy`, Part 2b).
    - `denied`, `expired`: `body: {"status": "denied"|"expired", "id": <id>}`.
    - `refused`: `body: {"status": "refused", "id": <id>, "reason": <record.reason code, or "unknown">}`; `reason` is one of the engine's
      fixed codes, never free text.
    - A `show` that returns `not_found`, or any exit other than 0 or 1, is retried next tick; an entry older than `timeout + 600` s gets the
      existing "watch expired" error final (`:598-601`) and is removed.
    - The final is written with `_write_commit(..., final=True, record_processed=False)` and `watch_remove`, to `responses/<rid>.final.json`
      (the existing shape, `:565-575`).
12. **Helper.** `bin/k3dm-cloud-request` `--wait-final` (`:127-129`) treats `body.status == "approval-pending"` like `queued` (it then
    waits for `responses/<rid>.final.json`) and no longer requires `job_id` for that status. Behaviour for `queued` is unchanged. The usage
    text and `docs/howto/cloud-session-requests.md` say to pass `--timeout 1000` (the default 300 s ends before the 900 s approval window).
    The module docstring (`:2`, "read-only") is corrected.

**F. Security properties**

13. **The cloud session cannot approve.** `approve`, `deny`, `promote` and `status` are never in argv of any bridge call (only `request` and
    `show` are), and no table row maps to them. A cloud request carries one input, `sha`; branch, channel, requester, check and nonce are
    chosen by the bridge or the authority. `approve` needs the operator's Slack user id (in `operator_ids`, Part 2a), the check value, a TOTP
    code and a Worker signature over them (K4), none of which a cloud session holds.
14. **Budgets are the engine's.** The bridge adds no counter of its own (Q3). A `rate_limited` refusal is returned as `rejected` and is not
    retried by the bridge.
15. **Docs.**
    - `docs/howto/cloud-session-requests.md`: "What you can ask for" (`:60`) gains the `promote-request` row (arg `sha`, what comes back:
      `approval-pending`, then a final of `promoted`, `denied`, `expired` or `refused`); "What you cannot ask for, and why" (`:167`) says it
      files a request that only the operator can approve, with a code, on a phone; the opening claim of a "read-only credential" (`:23`) and
      the boundary sentence (`:162`) are corrected to say `promote-request` is the one action that is not read-only and why it still cannot
      change anything alone.
    - `docs/howto/hub-promote.md`: an "Approve from Slack" paragraph after "Everyday promote" (`:24`): the card, the check value, the code
      timing, and that `bin/k3dm-hub-deploy <ref> --approval <id>` follows (Part 2b); a link to `docs/howto/promote-authority.md`.
    - `docs/architecture/cloud-bridge.md`: one paragraph on the local action. `CLAUDE.md` is not edited.

## Contract readers

All by `grep -n` on one file or directory each, 2026-11-22, HEAD `bc8276f0`. The worker re-cites after the red-team gate and after 2b lands.

- **The cloud-request action table (`ACTION_ALLOWLIST`, writer: `scripts/lib/webhook/cloud_actions.py:17-52`; adds `promote-request`).**
  Readers:
  - `bin/k3dm-cloud-request:16`, `:32` (`choices=sorted(ACTION_ALLOWLIST)`), `:44`, `:50`: changes only by gaining a choice;
  - `bin/k3dm-cloud-bridge:23`, `:84`, `:89` (validation), `:316` (`_request_body`), `:329` and `:331` (`_call_webhook`), `:499`
    (`_watch_entry`): `_request_body` and `_call_webhook` change (refuse `LOCAL_ACTIONS`); the rest are unchanged;
  - `scripts/tests/bin/test_cloud_bridge.py:199` (asserts `method in ("GET","POST")` and that path placeholders equal the params: changes, the
    local row is excluded and its marker asserted), `:214`, `:766-768` (helper and bridge tables agree: unchanged and a positive control),
    `:785`, `:793`, `:803`, `:811` (make-target checks: unchanged, the loops filter on `make-`), `:852-857` (calls `_call_webhook` for every
    action and expects a token per action: changes, local actions are skipped and tested separately).
  - `docs/howto/cloud-session-requests.md:60-90` (the table, changes), `:167` (cannot-ask section, changes).
  - No other reader: `grep -rnI 'ACTION_ALLOWLIST\|cloud_actions' bin scripts .github Makefile docs/howto docs/architecture` finds only the
    files above plus `docs/architecture/cloud-bridge.md` prose (`:21`, `Validation: cloud_actions.py`).
- **`ledger/watching.txt` on the `cloud-requests` branch.**
  - Writer: `_write_commit` (`bin/k3dm-cloud-bridge:505-585`); `_watch_entry` builds job entries (`:493-503`); the job watch loop removes
    them (`:603-621`). New writer: the promote watch (Behaviour 10-11).
  - Reader: `_read_watching` (`:477-490`, called by `_write_commit` at `:513` and `process_tick` at `:603`). Changes: accepts the `promote`
    kind. A grep of `ledger/watching` finds no other reader in the repo; the cloud session does not read it (it reads `responses/`).
- **`responses/<id>.json` and `responses/<id>.final.json`.**
  - Writers: the bridge only (`_write_commit` `:565-575`). New bodies: `approval-pending`, `promoted`, `denied`, `expired`, `refused`.
  - Readers: `bin/k3dm-cloud-request:119`, `:136` (the helper: `--wait-final` changes, Behaviour 12) and the cloud session by hand
    (`docs/howto/cloud-session-requests.md` "Reading the response", `:228`). `grep -n 'queued' bin/k3dm-cloud-request
    docs/howto/cloud-session-requests.md` was re-run for every use of the `queued` literal.
- **The approval record and its fields** (`id`, `nonce`, `expires`, `check` from `request`; `state`, `old`, `new`, `tag`, `reason` from
  `show`; writer: the engine in the root daemon, `scripts/lib/hub_approval.py:335` for the new record and `:176-190` for `show`).
  - Readers of the `request` reply: `bin/k3dm-promote-client:30-35` (key set `id nonce expires check`, validates the envelope, unchanged),
    Part 2b's `bin/k3dm-hub-promote` (no: it never calls `request`). New reader: this part's bridge (Behaviour 6). Future reader: Hermes
    (Part 3, deferred, Q2).
  - Readers of `show`: `bin/k3dm-promote-client` and Part 2b's `promote` flow by id. New reader: the bridge watch (Behaviour 11).
  - Part 2a's engine owns the schema; 3a changes none of it.
- **Promote id format `p<serial>-<8hex>`** (`^p[0-9]+-[0-9a-f]{8}$`).
  - Writer: the engine (`hub_approval.py:12`, minted at `:334`). Readers: `scripts/lib/promote_mover.py:11`, `bin/k3dm-promote-client`
    (no id regex of its own; the engine's `bad_input`), the relay `HERMES_ACTION_ID_RE = /^[rd][0-9]+-[0-9a-f]{8}$/`
    (`workers/slack-relay/index.js:4`; does not accept `p` yet, which is Part 3b), `scripts/lib/hermes/approvals.py:16` (`ACTION_ID_RE`,
    `r` only) and `:17` (`DISPATCH_ACTION_ID_RE`, `d`, read by `bin/k3dm-dispatch-recover:21`, `:217`). 3a adds readers of the id: the
    bridge (its own regex check, Behaviour 6) and the card builder (Behaviour 7). Not changed here: the relay and `approvals.py` patterns
    (3b).
- **Slack card action ids `hermes_approve` / `hermes_deny` and button value `<id>|<nonce>`.**
  - Writers: `interactive_blocks` (`approvals.py:72-82`, repair cards) and `bin/k3dm-dispatch-recover:201`; new writer: `promote_card`.
  - Reader: `handleInteractivity` (`workers/slack-relay/index.js:247-283`, checks `:259-260`, writes `approval:<id>` at `:274`).
    Unchanged by 3a. 3b's widened pattern is a precondition for a `p` press to be recorded; until then a press on a 3a card is dropped
    silently (`:260-262` returns 200 with no effect). E8 needs 3b.
- **The relay webhook URL (Keychain `k3dm-slack-webhook`, account `k3dm`).**
  - Writers: the operator's setup (`make update-webhook-slack` family in `Makefile`, unchanged).
  - Readers: `bin/k3dm-hermes:1000` (`_keychain_secret("k3dm-slack-webhook")`), `bin/k3dm-dispatch-recover` (via the same helper),
    the webhook (`SLACK_WEBHOOK_URL`, `scripts/lib/webhook/agent.py:59`). New reader: the bridge, through `webhook.auth._keychain_secret`
    (`scripts/lib/webhook/auth.py:22-30`, same account `k3dm`). The launchd plist
    (`scripts/etc/launchd/com.k3d-manager.cloud-bridge.plist.tmpl:11-17`) sets no Keychain item and needs none.
- **The promote client and socket.** `bin/k3dm-promote-client` (ops `request`, `show`, `approve`, `deny`, `promote`, `status`,
  `bin/k3dm-promote-client:12-19`), socket `/var/run/k3dm-promote/sock` (`:11`), peer-uid check in the daemon (Part 2c B.5). New caller:
  the bridge (`request`, `show` only). The socket is mode 0600 owned by the operator uid, which is also the bridge's launchd uid, so no
  grant changes.
- **Environment variables and paths.** None new. The bridge keeps `K3DM_CLOUD_BRIDGE_STATE`, `K3DM_CLOUD_BRIDGE_HTTP_TIMEOUT` and
  `K3DM_CLOUD_ARTIFACT_KEEP` (`bin/k3dm-cloud-bridge:34-45`). The client path is `<ROOT>/bin/k3dm-promote-client` with no environment override
  (Part 2b's rule, kept).
- **`ROOT` on the hub** is the hub checkout, which repo-sync moves to `deploy/hub` (Part 2c Contract readers), so the bridge reaches the
  client only after a promote carries this change. Rollout: promote, then `make restart-cloud-bridge`.

## Captures needed before dispatch

Stubs must come from a real read-only capture, with host and date. None of these exists yet; the worker must not invent the output.
Where a capture needs a request, it is listed as live evidence instead (E8), because `request` writes a record.

- **C1.** `bin/k3dm-promote-client show --id <existing id>` from the enrolled hub daemon, one capture per terminal state (`consumed`,
  `denied`, `expired`, `refused`) and for `approved` and `pending`. Needs Part 2c live on the hub and one record per state; the operator
  or Claude runs it read-only on the hub after E8-style setup. Until then the unit tests stub from the Part 2a B.5/G.19 contract and the
  client's own validator (`bin/k3dm-promote-client:22-35`), and carry the comment `stub of the Part 2c client, not a capture`, as Part 2b does.
- **C2.** One real `request` reply line from the hub client (`id`, `nonce`, `expires`, `check`), taken from the E8 run with the nonce
  redacted before it is written anywhere.
- **C3.** The relay webhook's reply to a Block Kit post with buttons and a confirm dialog (status code and body), captured once by posting
  the existing repair card to the private channel in the E8 run. The offline tests assert only the structure the relay and Slack are known
  to accept: the shape of `interactive_blocks` output (`approvals.py:62-83`), which is in production use.
- **C4.** `gh api repos/<repo>/commits/<sha>/check-runs` and `git ls-remote origin 'refs/heads/k3d-manager-v*'` as the bridge would run
  them, only if Q1 is answered B (bridge-side evaluation). The mover's own captures (Part 2d Proof of external behaviour) cover the
  daemon side.

## Acceptance

```yaml
must:
  - id: M1
    text: "ACTION_ALLOWLIST has promote-request with method LOCAL, one argument sha matching exactly 40 lowercase hex, and LOCAL_ACTIONS equals {promote-request}; bin/k3dm-cloud-request accepts promote-request --arg sha=<40hex> and files a request whose args are exactly {sha}; the bridge's validate_request accepts it and rejects a missing sha, an extra argument, 39 or 41 hex, upper-case hex and 64 hex with the existing reasons"
  - id: M2
    text: "_call_webhook and _request_body refuse a LOCAL_ACTIONS action with ValueError before any URL, token read or socket; a request for promote-request in process_tick never reaches _call_webhook"
  - id: M3
    text: "with promote_precheck returning refused, the response is status rejected with reason '<code>: <message>' naming the newest green sha when given, and neither the client nor Slack is called; returning unknown gives status error 'could not evaluate; retry later' with no client call; returning ok continues"
  - id: M4
    text: "on ok the bridge calls bin/k3dm-promote-client exactly as [client, request, --sha, <sha>, --branch, <branch>, --channel, cloud-session, --requested-by, claude-cloud] in that order, with --requested-by the constant even when the request's requested_by is another value, and no other client subcommand"
  - id: M5
    text: "the reply is parsed from the first output line only (a stub whose second line is the stderr message passes; a stub with trailing text on the first line, a wrong key set, v true, a bad id, nonce or check, a non-integer expires, or result ok with a non-ok code gives status error 'authority reply was not understood'); client exit 1 maps to rejected with '<code>: <message>', exit 2 to error, 75 / timeout / unspawnable to error 'promote authority unavailable; retry later'"
  - id: M6
    text: "the card has the header with the id, sha7 and full sha, branch, expiry, the check value exactly as returned, the line 'After Approve, send /hermes-totp <id> <check> <code>', the next-code and early_code instructions, an actions block whose block_id is the id with buttons hermes_approve (primary, confirm 'Approve promote?') and hermes_deny (danger) both carrying value '<id>|<nonce>', a text field under 2900 characters, and '&', '<', '>' in subject, ahead lines and branch escaped and cut to 120 characters"
  - id: M7
    text: "the card is posted with post_interactive to the Keychain relay URL; on success the response is status ok, http_status 202, body exactly {status approval-pending, id, sha, branch, expires}; on an empty URL or a failed post the response is status error naming the record id and its expiry and no watch entry is filed; post_summary is never called for the card"
  - id: M8
    text: "a delivered card files a promote watch entry that _read_watching returns and _write_commit preserves alongside job entries, and the job watch loop ignores it; a tick with show returning consumed writes responses/<rid>.final.json with body status promoted, id, sha, old, new (equal to the requested sha) and a hub-promote tag, removes the entry and does not mark the request processed twice; denied, expired and refused give their finals with the engine reason code only; pending and approved write nothing; a show error leaves the entry; an entry older than timeout plus 600 s gets the 'watch expired' final"
  - id: M9
    text: "bin/k3dm-cloud-request --wait-final accepts approval-pending, then waits for and prints responses/<rid>.final.json and returns its status mapping; the queued path and its job_id requirement are unchanged"
  - id: M10
    text: "the docs carry the promote-request row, the cannot-approve-alone sentence, the corrected read-only wording, --timeout 1000, the Slack approve paragraph and the architecture paragraph"
must_not:
  - id: N1
    text: "the nonce appears in any response, outbox file, claim file, log line, exception text, or the final response; the check value appears in any response. Positive control: the card payload sent to the stub Slack DOES carry the nonce (in the button value) and the check (in the text), so the stub was reached with a real record"
  - id: N2
    text: "the cloud request chooses the branch, channel, requested_by, check or nonce, or a client subcommand other than request and show is run (approve, deny, promote, status), or any bridge code path reads a TOTP code, a Slack user id or a signature. Positive control: the recorded client argv for a valid request is exactly the M4 list"
  - id: N3
    text: "cloud-session or git-derived text reaches Slack markup or a client argv unescaped: a subject of '<!channel> <@U123|x> &amp;' and a branch-like value containing '-' or spaces. Positive control: a plain subject passes through unchanged and reaches the card"
  - id: N4
    text: "a failed early check, rate_limited refusal, authority outage or undelivered card creates a second record, retries the client request, or posts a card. Positive control: a valid request creates exactly one record and one card"
  - id: N5
    text: "the final response says promoted for a record that is not consumed, for a consumed record whose new differs from the requested sha, or for an approved record. Positive control: a consumed record with matching new gives promoted"
  - id: N6
    text: "the bridge poll blocks the tick beyond its bounds: more than MAX_PER_TICK promote entries per tick, or any client call without a timeout. Positive control: with MAX_PER_TICK plus one entries, exactly MAX_PER_TICK show calls are made and the other entry is handled next tick"
  - id: N7
    text: "the existing actions change behaviour: every other row of ACTION_ALLOWLIST keeps its tuple, token choice and request body, and the queued/job watch path is byte-identical in the responses it writes. Positive control: the existing tests in scripts/tests/bin/test_cloud_bridge.py pass unchanged apart from the three edits named in Contract readers"
  - id: N8
    text: "the early check is weaker than the Part 2d policy: it accepts a sha that is not the first green of the first 20 first-parent commits of the newest release branch, treats a pending or failing check run as green, or exposes any switch that skips a check. Positive control: the newest green sha itself gives ok"
evidence:
  - id: E1
    kind: offline
    how: "pytest in scripts/tests/bin/test_cloud_bridge.py and the new scripts/tests/bin/test_cloud_bridge_promote.py: table row and regex cases (M1), helper filing, _call_webhook and _request_body refusal with an HTTP-open counter and a token-read counter at zero, process_tick on a bare-repo fixture with one promote-request (M2); fixture first asserts the bridge state dir and repo are under tmp_path"
    proves: [M1, M2, N7]
    intent: "Operator can trust a cloud session can file promote-request but that the request can never reach the webhook, and that every other cloud action is unchanged"
  - id: E2
    kind: offline
    how: "pytest with an injected promote_precheck and a recording stub client (a script on a tmp path that records argv and env and prints a configurable first line plus a second stderr-style line, labelled stub of the Part 2c client, not a capture): refused, unknown, ok, each client exit and malformed reply, the constant requested_by, the argv list equal to the M4 list, a request id handled once, a restart between client call and response commit (the orphaned-claim error, then rate_limited on the next request, no second card)"
    proves: [M3, M4, M5, N2, N4]
    intent: "Operator can trust the bridge asks the authority only through request, with only constants and a validated sha, and fails closed and once"
  - id: E3
    kind: offline
    how: "pytest in scripts/tests/hermes/test_promote_card.py on promote_card with a fixed clock: every field of M6, the escape table (&, <, >, <!channel>, long subject, 5 ahead lines), the 2900-character cap with the maximum inputs, the button values, the confirm dialog, and the absence of the nonce from the visible text; a second case posts through the real post_interactive with a stub opener and asserts the request body is the same JSON"
    proves: [M6, M7, N1, N3]
    intent: "Operator can trust the card shows what to press and what to type, cannot be hijacked by commit text, and carries the nonce only in the button"
  - id: E4
    kind: offline
    how: "pytest with a stub Slack opener (success, HTTP error, exception, empty URL) and a nonce-scan: the whole state dir, outbox, claim file, every committed blob of the bare-repo fixture and captured log output are searched for the nonce and the check value after a full request and final cycle (zero hits), with the card payload as the positive control"
    proves: [M7, N1, N4]
    intent: "Operator can trust the secret that lets an Approve press count never reaches the public cloud-requests branch"
  - id: E5
    kind: offline
    how: "pytest on a bare-repo fixture: promote watch entry written, read back, preserved by a job response commit and by a final commit, skipped by the job loop; show stubs for pending, approved, consumed (matching and mismatched new), denied, expired, refused, not_found, exit 75, timeout; MAX_PER_TICK plus one entries; an entry older than timeout plus 600"
    proves: [M8, N5, N6]
    intent: "Operator can trust the cloud session gets a truthful final answer and that an unfinished approval never produces a false promoted"
  - id: E6
    kind: offline
    how: "pytest for bin/k3dm-cloud-request: --wait-final with a response body approval-pending then a final file, with queued unchanged, with a timeout, and with a response of any other status (same mapping as today)"
    proves: [M9]
    intent: "Operator can trust the cloud session waits for the operator's decision and then sees it"
  - id: E7
    kind: offline
    how: "string-presence tests of docs/howto/cloud-session-requests.md, docs/howto/hub-promote.md and docs/architecture/cloud-bridge.md, passing on the edited files and failing on pre-change copies under scripts/tests/fixtures/remote-promote-3a-docs/; the early-check policy cases (newest green gives ok, an older green gives not_newest_green naming the newest, red, pending, none-in-20, not the newest release branch, leading-zero branch ignored) run through the Q1 implementation with fake git and check-run readers"
    proves: [M10, N8]
    intent: "Operator can trust the docs describe the request and its limit, and that the early check applies the same policy as the promote itself"
  - id: E8
    kind: live
    how: "operator or Claude on the hub after 3a is promoted and make restart-cloud-bridge, with Part 3b's relay deployed, the signer key set and one enrolled operator id: a cloud session (or by hand from a laptop checkout) files bin/k3dm-cloud-request promote-request --wait-final --timeout 1000 --arg sha=<newest green sha>; the card appears in the private channel with the check value; Approve, /hermes-totp, then the promote path (Part 3b and Part 2b) runs; the cloud-requests branch shows approval-pending, then the final promoted; a second run with a non-newest sha is rejected with no card; a Deny press gives a denied final; a request left alone gives an expired final after 900 s. Capture C1-C3 are taken here. The nonce is grepped for in the cloud-requests branch history (zero hits)"
    proves: [M3, M5, M6, M7, M8, M9, N1]
    intent: "Operator can see a real request travel from a cloud session to a Slack card to an approved promote and back, with nothing secret on the branch"
interface:
  - "bin/k3dm-cloud-request promote-request --arg sha=<40 lowercase hex> [--wait-final --timeout 1000]; stdout the request id, then the immediate and final response JSON lines; exits 0 ok, 3 rejected, 4 error, 5 timeout"
  - "cloud request JSON: schema 1, action promote-request, args {sha}; response body {status approval-pending, id, sha, branch, expires}; final body {status promoted|denied|expired|refused, id, ...} per Behaviour 11"
  - "bin/k3dm-promote-client request --sha --branch --channel cloud-session --requested-by claude-cloud, and show --id (client contract of Part 2a B.5-B.6 and Part 2c F.17)"
  - "Slack: one Block Kit card via the relay webhook, buttons hermes_approve and hermes_deny with value '<id>|<nonce>'"
  - "scripts/lib/hermes/promote_card.py: promote_card(record, precheck, now) -> (text, blocks); bin/k3dm-cloud-bridge: handle_promote_request(request_id, request), promote_precheck(sha)"
```

**Pre-fix red.** The base is the release branch head before this part. The verifier copies the fix commit's test files onto the base
(`git -C <base worktree> checkout <fix_sha> -- <test files>`), runs each command below and records a `pre_fix_sha`, `pre_fix_command` and
nonzero `pre_fix_rc` per command. `Found no tests` or a missing file is not red.
- `pytest scripts/tests/bin/test_cloud_bridge_promote.py scripts/tests/bin/test_cloud_bridge.py -k 'promote'`: on the base
  `promote-request` is an unknown action (`bin/k3dm-cloud-request:32` rejects the choice, `validate_request` returns "unknown action"), so
  M1-M5 and M7-M9 fail.
- `pytest scripts/tests/hermes/test_promote_card.py`: the module does not exist on the base (import error is the red; the verifier records
  the failing test names, not the import alone).
- the three docs tests of E7: the pre-change docs lack every string.

Each `must_not` that only states an absence is not claimed red on the base. It has a positive control and a named mutant, recorded
separately from the triples (the verifier applies the mutant to the fixed code, records the red test, restores):
- N1: mutant "put `nonce` (or `check`) in the pending body, or log the raw client line" -> E4.
- N2: mutant "pass the request's `requested_by` to `--requested-by`", mutant "run `promote` or `approve` after `request`" -> E2.
- N3: mutant "drop the escape of `<` in `promote_card`" -> E3.
- N4: mutant "retry `request` once on 75", mutant "post `post_summary` when the card fails" -> E2, E4.
- N5: mutant "treat `approved` or a mismatched `new` as promoted" -> E5.
- N6: mutant "iterate all promote entries per tick", mutant "drop the show timeout" -> E5.
- N7: mutant "route `LOCAL` actions through `_call_webhook`" -> E1.
- N8: mutant "treat a pending or failed first-20 commit as green" -> E7.

## Files

Edit only these (all in `scripts/`, `bin/` and `docs/` under the repo root; the dispatch grants this list and no other):

- `scripts/lib/webhook/cloud_actions.py`
- `bin/k3dm-cloud-request`
- `bin/k3dm-cloud-bridge`
- `scripts/lib/hermes/promote_card.py` (new)
- `scripts/tests/bin/test_cloud_bridge.py`
- `scripts/tests/bin/test_cloud_bridge_promote.py` (new)
- `scripts/tests/hermes/test_promote_card.py` (new)
- `scripts/tests/fixtures/remote-promote-3a-docs/` (new: pre-change copies of the three doc files, E7)
- `docs/howto/cloud-session-requests.md`
- `docs/howto/hub-promote.md`
- `docs/architecture/cloud-bridge.md`

Conditional on Q1 (not in the grant until answered): `scripts/lib/promote_mover.py` and `bin/k3dm-promote-authority` / `bin/k3dm-promote-client`
(answer A, a daemon `evaluate` op), or a new `scripts/lib/hermes/promote_policy.py` (answer B). `bin/k3dm-hermes` and
`scripts/lib/hermes/approvals.py` are NOT in this list: see Q2.

## Open questions

The umbrella leaves these undecided or contradicts the landed tree; each needs the operator (and, for Q1 and Q5, a red-team-gate answer).

- **Q1. Where does the early policy check run? (blocks dispatch.)** Three candidates, none decided:
  - A. A new read-only daemon op `evaluate` (sha in, verdict and card facts out). It needs `Mover.move` split so evaluation can run with no
    record (`promote_mover.py:288-368` fuses them), a new key set in Part 2c C.7 (today any other op is `bad_input`) and a client change.
    One policy implementation, run with the credentials that exist for it; touches Part 2 files and the red-team gate.
  - B. The bridge evaluates itself as the operator user (`git ls-remote`, `gh api .../check-runs` through the existing reader credential).
    No Part 2 change, but a third copy of the policy (bash promoter, mover, bridge) that can drift, and no access to the root read token.
    It is advisory only, since the daemon repeats the check at promote time.
  - C. No early check: the bridge derives the newest release branch and creates the record; the daemon refuses a bad sha at promote time.
    Smallest, but the operator can approve (spending a TOTP code and the 15-minute slot) a sha that can never move, and the card cannot show
    the subject or commits ahead.
  - The umbrella's wording ("`evaluate` ... without a record or a move") describes A but no `evaluate` exists.
- **Q2. Is the Hermes `p` branch part of 3a?** The umbrella lists `bin/k3dm-hermes` and `approvals.py` under 3a (Part 3 outline, "Part 3a
  (hub side, about 7 files ...") but the branch consumes the Worker-signed `signed:<id>` envelope that 3b creates, the `fetch_approvals`
  pattern is `r`-only (`approvals.py:16`) and Hermes must run `bin/k3dm-hub-deploy` (Part 2b) and a wake path with a 20 s bound. This draft
  leaves it out and proposes it as 3c (or the tail of 3b), so 3a has no dependency on unlanded relay behaviour. Confirm.
- **Q3. Should the bridge keep its own request limiter?** The engine already limits (1 pending, 1 non-final per sha, 3 per hour, 5 non-final).
  A cloud session that files requests can hold the single pending slot or the hourly budget and make the operator's own request, including a
  `cli` request, `rate_limited`. The umbrella's "one per sha and three per hour" is weaker than the engine. Options: accept the engine's
  limits (this draft), add a bridge-side cap (for example one `promote-request` per 15 minutes per cloud session), or have the engine count
  by channel (a Part 2a change).
- **Q4. An undelivered card leaves a pending record.** The bridge has no approver id, so it cannot deny. The record expires in 900 s and
  meanwhile no new request is accepted. Options: accept (this draft), let `deny` carry a bridge identity (an engine change), or post the card
  first with a placeholder id (impossible: the id and nonce come from `request`).
- **Q5. Which fields of the record may the cloud session see?** This draft returns `id`, `sha`, `branch`, `expires` and never `nonce` or
  `check`. The check value only matters to the operator, but the id is a stable handle for a later `show` by the operator. Confirm that
  returning the id on the public branch is acceptable (it is not a secret in Part 2a).
- **Q6. Response and final shape.** `http_status: 202` for `approval-pending` and the new watch entry kind are this draft's choices. The
  alternative is a separate `ledger/promote-watching.txt` so `_read_watching` keeps its single job-shaped schema.
- **Q7. Poller blocking.** The client's `request` has a 15 s socket budget (`bin/k3dm-promote-client:70`), and the bridge handles one request
  at a time. This draft uses a 20 s timeout in the poller thread. Options: use the slow-request queue (`SLOW_ACTIONS`, `:46`, `:639`) or
  accept the stall.
- **Q8. Relay wording for promote presses.** After an Approve the relay replies "applying on the next Hermes poll (up to ~5 min)"
  (`workers/slack-relay/index.js:275`), wrong for promote (the next step is the code). That is 3b's file, but the card is the only place the
  operator learns the next step until 3b lands.
- **Q9. Reauth friction.** Until the reauth bug is fixed, Approve also needs `/hermes-auth` (`index.js:270`); the card text does not say so.
  Should the card mention `/hermes-auth` if not authenticated in the last 24 h (the bridge cannot know)?

## Residuals

- **R3a-1.** The early check is advisory; the authority is the only enforcement. A mistaken `ok` wastes one approval.
- **R3a-2.** A cloud session can file a promote-request for any 40-hex sha; with a valid sha that fails Q1's early check, nothing is created.
  With one that passes, the record binds to that sha and only the operator can approve.
- **R3a-3.** An undelivered card keeps a pending record for up to 900 s (Q4).
- **R3a-4.** Until Part 3b, a press on the card is dropped by the relay (`index.js:260-262`); 3a alone produces cards that do nothing.
- **R3a-5.** The bridge process sees the nonce in memory and in the temporary output file `_spawn_capture_text` writes (mode 0600, then
  read and removed, `proc.py:24-26`, `:70`-onward) for the duration of the call; a same-user process can read it. The nonce is a
  binding token, not an authenticator: it needs the TOTP code and the signature on top (Part 2a, K4).

## Worker definition of done

1. **Red first, two columns.** Every must and must_not test has its positive control. The hand-off reports the pre-change result and a mutant
   result per test (the mutants listed after the Acceptance block).
2. **Fixtures first.** Fixtures assert their target first: a tmp state directory, a tmp bare repo, a stub client on a tmp path (never
   `/var/run/k3dm-promote/sock`), a stub Slack opener (no network), a fixed clock, no real Keychain read (`_keychain_secret` patched, asserted).
3. **Stub label.** Every stub client reply carries the comment `stub of the Part 2c client (Part 2a B.5-B.6 contract), not a capture`.
4. **Re-cite.** Every line citation is re-cited after the red-team gate and after Part 2b lands.
5. **Checks.** `make test-pytest` (agent-doc drift included), `make test-bin` and the new pytest files pass; `shellcheck` is not involved (no shell
   file changes). `scripts/tests/bin/test_cloud_bridge.py` changes are limited to the three named in Contract readers.

## What NOT to do

- No `approve`, `deny`, `promote` or `status` call from the bridge; no argument other than `sha` from a cloud session.
- No token, nonce, check value or Slack user id in argv, logs, responses or the `cloud-requests` branch.
- No environment variable for the client path, the socket, the relay URL or the branch.
- Do not edit the relay (`workers/slack-relay/`), `scripts/lib/hermes/approvals.py` or `bin/k3dm-hermes` (Q2, Part 3b).
- Do not change the existing actions' tuples, token choice or watch behaviour.
- Do not decide any Open question inside the code; the seam in Behaviour 4 isolates Q1.
