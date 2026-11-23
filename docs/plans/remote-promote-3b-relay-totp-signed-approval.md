# v1.46.0 — Remote promote, part 3b: the Slack relay signs the approval (`/hermes-totp`, K4)

**Status:** DRAFT v1 — 2026-11-22, not reviewed
**Version:** v1.46.0 candidate — placed at the next /release-groom (v1.46.0 is over its 5-plan cap; needs a displacement); implement on the release timeline, do not dispatch before placement
**Priority:** P2
**Release:** none yet (umbrella `docs/plans/v1.45.0-remote-promote-approval.md`, "Part 3 outline", Part 3b paragraph, lines 132-139)
**Branch:** implement on `k3d-manager-v1.46.0` after that release branch is cut
**Filed:** 2026-11-22
**Intent:** pending operator approval
**Approval:** none yet. Needs operator approval of intent and of the placement before any dispatch (hub-authority risk).
**Risk:** critical. This part creates the authority that lets a Slack message lead to a root-daemon promote. Under K4 (umbrella
Decisions table, line 201) the root daemon accepts only an approval whose HMAC was made by the Worker, so the Worker's signing key and
the conditions under which the Worker signs are the whole remote-approval trust boundary:
- a Worker that signs when it should not (no pressed approval, another user, an unlisted user, a replay) lets a Slack-side attacker
  or a hub-side attacker who holds the drain token feed the daemon approvals it would otherwise refuse;
- a key that leaks (a log line, a Slack reply, an error body, a KV value, the repo) lets any holder forge approvals offline;
- a mismatch between this part's canonical bytes and the daemon's (Part 2a `approval_mac`) refuses every genuine approval, silently
  and for every promote, so the contract vector is a gate and not a nicety.
The change is edit-only on one Worker file and its test plus docs, but its effect is live only after operator steps (secret, Slack app
command, deploy) that no agent runs.
**Depends on:**
- Part 2c live: landed at `c17eae59` (2c Status line, `docs/plans/v1.45.0-remote-promote-2c-root-daemon.md:3`), "verify pending". The
  verifier of this part's signature is Part 2a's engine inside the 2c daemon, and the key file `creds/relay_hmac.key` is written by 2c
  enrol stage 2. Live use of 3b needs 2c installed and enrolled on the hub (2c E8-E14).
- Part 3a for the end-to-end path (card, `p` drain and wake path, `bin/k3dm-promote-client approve` call). 3b alone is testable offline
  and live up to "the Worker returns a signed envelope on the drain GET"; it cannot be live-verified through a promote without 3a.
- The two OPEN bugs that edit `workers/slack-relay/index.js` have landed (one dispatch per file):
  - `docs/bugs/2026-11-09-hermes-reauth-lasts-24h-and-is-reusable.md`: Waiting on `fix running` since 2026-11-22. It changes
    `REAUTH_TTL_SECONDS` (`index.js:3`), the `reauth:` write (`:403`) and the `reauth:` read and delete in `handleInteractivity`
    (`:270`).
  - `docs/bugs/2026-11-08-slack-hostinger-status-duplicates-cluster-status.md`: Waiting on `dispatch` since 2026-11-12. It removes
    `/hostinger-status` from `ALLOWED_COMMANDS` (`:1`) and `COMMAND_ROLES` (`:12`) and its handler.
  3b dispatches only after both have landed. Every `index.js` line citation below was taken at HEAD `bc8276f0` on 2026-11-22 and must
  be re-cited by the worker after both land (Worker definition of done 4). Citations to the umbrella and to the 2a and 2c specs are
  by section and line at the same HEAD.
**Implementer:** Luna
**Verifier:** Claude, plus an independent verifier tasked from `## Acceptance` only. Live evidence by the operator or Claude, never Gemini.

## Problem

Part 3 of the umbrella lets a cloud session ask for a promote and lets the operator approve it from Slack. The hub's root daemon
verifies an approval envelope `{id, nonce, approver, totp, check, at, sig}` (2a `approve`, `scripts/lib/hub_approval.py:272-276`)
and refuses one whose `sig` does not verify, or whose `at` is outside `[now - 300, now + 120]`, before it looks at the code, the check
value or the nonce. Nothing produces such an envelope today:
- `workers/slack-relay/index.js` knows only `r` and `d` action ids (`HERMES_ACTION_ID_RE`, `:4`), has no command that carries a TOTP
  code, and holds no signing key. `/hermes-totp` is answered `Unknown command` (`:397`).
- The drain GET (`:222-238`) returns only `{action_id, approved_by, approved_at, nonce}` per `approval:` item.

3b gives the Worker the three pieces: accept `p` ids on the Approve press, accept `/hermes-totp <id> <check> <code>` from the operator,
and sign what it received. The key exists only as the Worker secret `PROMOTE_RELAY_HMAC_KEY` and, on the hub, in the root-only
`creds/relay_hmac.key` (K4). A hub-side process running as the operator's user can read an envelope in transit but cannot make one.

Two facts the umbrella states differently from the tree (see `## Open questions` 5 and 6 and the report's disagreement list):
- the Worker's id pattern today is `^[rd]...`, not `^[r]...`. The umbrella's "widen to `^[rp]`" would drop `d` (Hermes dispatch
  recovery ids, `bin/k3dm-dispatch-recover:217`, test `workers/slack-relay/test/relay.test.mjs:553-577`). This spec widens to `^[rdp]`.
- the umbrella says 3b widens `scripts/lib/hermes/approvals.py` as well; its own 3b file list omits that file, and Part 3a's list
  includes it. This spec does not edit it.

## Behaviour

Each item is a requirement. Citations are `workers/slack-relay/index.js` at `bc8276f0` unless another file is named.

1. **Promote ids on the Approve and Deny press.** `HERMES_ACTION_ID_RE` (`:4`) becomes `/^[rdp][0-9]+-[0-9a-f]{8}$/`.
   - The nonce pattern (`:5`, `^[0-9a-f]{16}$`), the button `action_id`s `hermes_approve` and `hermes_deny` (`:259`) and the stored
     value `{approved_by, approved_at, nonce}` under `approval:<id>` with `expirationTtl` 3600 (`:275-277`) are unchanged.
   - A `p` press follows exactly the path an `r` press follows: allowlist (`:268`), reauth (`:270`, as the reauth bug leaves it), then
     the write. Nothing in the press path signs anything: signing happens only at item 2.
   - An id outside the pattern, or a press from an unlisted user, writes nothing (existing behaviour, kept).
2. **`/hermes-totp <id> <check> <code>`.**
   - `/hermes-totp` is added to `ALLOWED_COMMANDS` (`:1`) and to `COMMAND_ROLES` (`:9-24`) with role `admin`, as `/hermes-auth` (`:19`),
     so an unlisted command role never defaults to `reader` (`:393`).
   - It is handled beside the `/hermes-auth` branch (`:399-405`), before every relay-to-webhook branch. It never calls `relay()` (`:285`)
     and never touches `WEBHOOK_URL`.
   - Parse `text` (already trimmed, `:387`) as exactly three space-separated tokens: `id` matching `^p[0-9]+-[0-9a-f]{8}$` (not `r`,
     not `d`: only promote approvals are signed), `check` matching `^[0-9A-Za-z]{4}$`, `code` matching `^[0-9]{6}$`. Anything else
     replies an ephemeral usage line (`jsonReply(..., threadTs, true)`, `:335`) that echoes none of the three values, signs nothing
     and writes nothing.
   - Refuse, ephemerally and without signing, when: `APPROVALS_KV` is not bound (as `:400-401`); `PROMOTE_RELAY_HMAC_KEY` is absent or is
     not exactly 64 lowercase hex characters (a configuration refusal that names the secret but never shows a value); the caller is not
     `approverAllowed` (`:207-210`); there is no `approval:<id>` item; the stored `approved_by` is not the calling `user_id`; or a
     `signed:<id>` item already exists for this id (item 5).
   - Otherwise build the envelope: `id`; `nonce` from the `approval:<id>` item; `approver` = the calling `user_id`, which equals the
     stored `approved_by`; `check` = the typed value **upper-cased**; `totp` = the typed six digits; `at` = `String(Math.floor(Date.now() / 1000))`
     (ten digits, the Worker's own clock; no request header, field or environment value can set it).
   - Sign it (item 3), write KV `signed:<id>` = `JSON.stringify({id, nonce, approver, check, totp, at, sig})` with `expirationTtl` 120,
     and reply ephemerally that a code was recorded for `<id>` and that the hub applies it shortly. The reply contains the id and no
     other envelope field: not the code, the check, the nonce or the `sig`.
   - The Worker does not and cannot check the code against a TOTP secret (it has none) and does not check the check value (it cannot
     derive it); the engine does both (2a F.16, G.20).
3. **Signing (K4).** `sig` is the lowercase hex HMAC-SHA256, under the 32 bytes obtained by hex-decoding `PROMOTE_RELAY_HMAC_KEY`, of
   the ASCII bytes `k3dm-promote-approve:v1\n` + `id` + `\n` + `nonce` + `\n` + `approver` + `\n` + `check` + `\n` + `totp` + `\n` + `at` + `\n`
   (2a F.16a, `docs/plans/v1.45.0-remote-promote-2a-approval-store.md:262-265`; the reference is `approval_mac`,
   `scripts/lib/hub_approval.py:67-69`).
   - Use `crypto.subtle.importKey('raw', <decoded 32 bytes>, {name: 'HMAC', hash: 'SHA-256'}, false, ['sign'])` and `crypto.subtle.sign`,
     as `verifySlack` does for the Slack signature (`:183-187`). The key bytes are the hex-decoded value, as the daemon decodes the key
     file (`scripts/libexec/k3dm-promote-daemon.py:161`, `bytes.fromhex`). Importing the 64 hex characters as text signs a different
     MAC and refuses every genuine approval; the contract vector (E1) catches it.
   - The secret is read as the global `PROMOTE_RELAY_HMAC_KEY` guarded with `typeof ... === 'undefined'`, the style of `approvalsKv`
     (`:203-205`), `approverAllowed` (`:207-210`) and `drainAuthorized` (`:212-216`).
   - The key, its decoded bytes and `sig` are never written by `console.log` or any other log call, never put in a `Response` body or
     header, never put in a Slack reply, an error text, the `response_url` post, or any KV value other than `signed:<id>`'s `sig`
     field (which is a MAC, not the key). The Worker has no `console.log` today; none is added that takes any envelope field.
4. **Drain: the signed envelope beside the approval.**
   - The drain GET (`:222-238`) returns, for each `approval:` item, the existing four fields, and for a `p` id that has a live
     `signed:<id>` item also `signed`: the stored envelope object with exactly `{id, nonce, approver, check, totp, at, sig}`. An item
     whose `signed:<id>` is absent, expired or unparsable has no `signed` key. `r` and `d` items are returned exactly as today.
   - Extra keys are tolerated by the existing consumers: `fetch_approvals` filters on `action_id`, `nonce` and `approved_by` only
     (`scripts/lib/hermes/approvals.py:42-45`), so the added key does not break the `r` drain, which also drops `p` ids by pattern
     (`approvals.py:16`).
   - The drain DELETE (`:240-243`) for `/hermes/approvals/<id>` deletes `approval:<id>` and `signed:<id>` together. The path pattern
     (`^[A-Za-z0-9-]{1,64}$`, `:239`) is unchanged.
   - The drain token check (`drainAuthorized`, `:212-216`) is unchanged and still the only authentication of the drain.
5. **One signing per press.** A second `/hermes-totp` for an id whose `signed:<id>` is still present is refused, ephemerally, with no
   second signature. After the drain DELETE (which removes both items) the operator must press Approve again before another code can
   be signed. This is a Worker-side guard on top of the engine's own replay defence (the TOTP high-water mark, 2a F.17), not instead of
   it; KV is eventually consistent (`## Captures needed before dispatch` 3), so the guard is best effort and the engine remains the
   single-use authority. See Open question 3.
6. **No other behaviour changes.** `/hermes-auth`, the `reauth:` handling as the reauth bug leaves it, the `r` and `d` paths, every
   other command, `verifySlack`, `relay()`, the Slack-signature freshness window (`:180`, 300 s) and the response helpers are untouched.

## Operator steps (live, operator-run; Claude and agents never handle the key value)

These are not part of the dispatch. They are listed so the spec can be verified end to end (Decision 19, umbrella line 198). Each is
run by the operator in Terminal.app on a device the operator controls, after 3b has landed and after 2c enrol has generated the key.
1. **Create the Worker secret.** 2c enrol stage 2 prints the 64-hex value once on the hub's console (2c E.13). The operator sets it
   as the Worker secret from their own device with `wrangler secret put PROMOTE_RELAY_HMAC_KEY` and pastes the value at wrangler's
   prompt. The value is never in argv, in `make`, in shell history, in a file, in a chat or in a message to an agent. Do not extend
   `make deploy-worker` to put this secret: `deploy-worker` reads its secrets from the Keychain (`Makefile:972-978`, `WEBHOOK_TOKEN`
   and `SLACK_SIGNING_SECRET`), and the relay key must exist only as the Worker secret and the root-only file (K4). `wrangler` is not
   installed on m4-air (2c proof owed 9, `docs/plans/v1.45.0-remote-promote-2c-root-daemon.md:660-662`); the device and version the
   operator uses are recorded with the date.
2. **Register the slash command.** In the Slack app `k3d-manager` (the app whose signing secret the relay holds), register
   `/hermes-totp` with Request URL `https://k3dm-slack-relay.k3dm.workers.dev/slack/commands`, the same URL as every other slash
   command and not the interactivity URL (`docs/guides/hermes.md:87`, 2026-11-08 precedent).
3. **Deploy.** `make deploy-worker` (`Makefile:970-987`). It re-puts `WEBHOOK_TOKEN` and `SLACK_SIGNING_SECRET`, runs `wrangler deploy`
   and checks that a signed `/cluster-status` POST returns 200. It does not touch `PROMOTE_RELAY_HMAC_KEY`, and a deploy never clears
   an existing Worker secret.
4. **Rotation** (Open question 1): when 2c `enrol --rotate relay-key` is run, an envelope signed with the old key is refused `signature`
   until the operator repeats step 1 with the new value (2c lines 274-275).

## Contract readers

All by grep at HEAD `bc8276f0`, 2026-11-22, on `bin scripts workers Makefile docs/guides docs/architecture docs/howto .github`, tests
excluded unless named. After the two `index.js` bugs land the worker re-greps every line.

- **Promote action id pattern (`^p[0-9]+-[0-9a-f]{8}$`; the Worker pattern widens to `^[rdp]...`).**
  - Worker: `workers/slack-relay/index.js:4` defines it, `:260` is the only use (press path). Changes (widened, `d` kept). New use in the
    `/hermes-totp` branch with the narrower `p`-only pattern.
  - Hub, Python: `scripts/lib/hermes/approvals.py:16` (`r` only), `:17` (`d`), `:26` and `:47` (defaults). Unchanged by 3b. Part 3a adds
    the `p` branch and its pattern (umbrella line 130 says 3b widens it; this spec does not, Open question 6). Readers of those:
    `bin/k3dm-hermes:326` (`fetch_approvals` default, `r`), `bin/k3dm-dispatch-recover:217-267` (`d`). Unchanged.
  - Engine: `scripts/lib/hub_approval.py:12` (`ID = r'p[0-9]+-[0-9a-f]{8}'`). Unchanged.
- **The signed approval envelope `{id, nonce, approver, check, totp, at, sig}` and its canonical bytes.**
  - Writer: the Worker (new, this part).
  - Readers: `scripts/lib/hub_approval.py:67-69` (`approval_mac`) and `:272-276` (verification and freshness); the daemon's key load
    `scripts/libexec/k3dm-promote-daemon.py:150-163` (`relay_hmac.key`, 64 lowercase hex plus newline, `bytes.fromhex`); the field shape
    checks `hub_approval.py:220` (`approver` `USER` pattern, `check` `^[0-9A-Za-z]{4}$`, `totp` `[!-~]{1,16}`, `at` `^[0-9]{10}$`, nonce
    16 hex); `bin/k3dm-promote-client` forwards the seven values unchanged (2c F.17, `bin/k3dm-promote-client`). All unchanged.
  - Pass-through (Part 3a, not edited here): Hermes `_drain_approvals` (`bin/k3dm-hermes:320-345`) will carry the envelope to the client.
    It must not alter, re-case or log any field. Listed so 3a's spec cites it.
- **The signing-key secret name `PROMOTE_RELAY_HMAC_KEY`.**
  - Writers: the operator (`wrangler secret put`, operator step 1); 2c enrol stage 2 writes the matching hub file
    (`creds/relay_hmac.key`) and prints the hex once (2c E.13). No script in the tree writes the Worker secret: the grep of
    `PROMOTE_RELAY_HMAC_KEY` under `bin scripts workers Makefile docs` finds only plan documents and the 2c and 2a code comments, no
    code. `make deploy-worker` does not, and must not (operator step 1).
  - Readers: the Worker's new signing function (this part). The hub reads only its own file, not the Worker secret.
  - Secret listing precedent: `workers/slack-relay/wrangler.toml:9-10` names `APPROVER_ALLOWLIST` and `APPROVAL_DRAIN_TOKEN` in a
    comment; this part adds `PROMOTE_RELAY_HMAC_KEY` to that comment (comment only; no `[vars]` entry, which would put it in the
    repo). `wrangler.toml` is edited for that comment only (`## Files`).
- **KV `approval:<id>` (`{approved_by, approved_at, nonce}`, TTL 3600) and the new `signed:<id>` (the envelope, TTL 120).**
  - `approval:` writer: `index.js:275-277` (press; changes only by the widened id pattern, and by whatever the reauth bug does to the
    surrounding reauth read). `approval:` readers: the drain GET `:222-238` (changes: adds `signed`), the drain DELETE `:240-243`
    (changes: also deletes `signed:<id>`), and the new `/hermes-totp` branch (reads it).
  - Tests that read or write it: `workers/slack-relay/test/relay.test.mjs:91-103`, `:134-142`, `:553-577` (unchanged assertions for
    `r` and `d`; the `r` and `d` drain shape must not gain a `signed` key).
  - `signed:` writer: the `/hermes-totp` branch only. Readers: the drain GET and DELETE only. No hub component reads KV directly.
  - Hub reader of the drain response: `scripts/lib/hermes/approvals.py:26-45` and `bin/k3dm-dispatch-recover:217`. Unchanged (extra key
    tolerated, item 4).
  - The umbrella names the second item `signed:<id>` (line 132) and, in its acceptance list, `totp:<id>` (line 139). This spec uses
    `signed:<id>`; Open question 7.
- **Slash-command names.**
  - `/hermes-totp` is new. Registered in the Slack app (operator step 2); allowlisted at `index.js:1`; role at `:9-24`.
  - Readers of the command list: `docs/architecture/cloudflare-slack-relay.md:77-83` (changes: adds `/hermes-totp`);
    `docs/guides/hermes.md:77`, `:87` (changes: promote flow and registration, `## Files`); the Slack app settings sensor
    `scripts/lib/hermes/sensors.py:30` (`SLACK_REQUIRED_COMMANDS = ("/hermes-auth",)`): unchanged by 3b, so a missing `/hermes-totp`
    registration is not detected. Open question 8.
  - `docs/howto/slack-slash-commands.md` is cited by the architecture doc (`cloudflare-slack-relay.md:164`) as the target table; it
    lists `/k3dm` targets, not the Hermes commands. Unchanged.
- **`make deploy-worker` (`Makefile:970-987`).** Reader of `workers/slack-relay/` only. Unchanged. Listed: the secret is deliberately
  not added to its Keychain reads.

## Captures needed before dispatch

The Worker runs on Cloudflare's runtime and the command arrives from Slack. Offline tests share this spec's assumptions about both, so
the following must be captured (read-only; host, date and version beside each) and pasted into `## Proof of external behaviour` before
the part is dispatched. Do not invent a stub from the docs.
1. **A real slash-command POST body.** The shape of a `/hermes-auth` (or any) command as Slack delivers it to `/slack/commands`:
   form fields (`command`, `text`, `user_id`, `user_name`, `response_url`, `channel_id`), how multiple spaces and a trailing space in
   `text` arrive, and that `text` for `/hermes-totp p1-0123abcd 03Q1 287082` is the single string after the command. Source: a Slack
   request inspector capture by the operator from the real app (fields only; the signature, the `response_url` and any token redacted
   before they reach the spec). The test harness today builds command bodies by hand (`relay.test.mjs:168-175`).
2. **WebCrypto HMAC in the deployed runtime.** 2a's vectors were probed on Python 3.13.6, `/usr/bin/python3` 3.9.6 and node v26.13.1
   (2a F.16a), not in Cloudflare's runtime. Owed: the four-row contract vector reproduced by a throwaway Worker (`wrangler dev` or a
   deployed scratch Worker) using the key 0x00..0x1f and no production secret, with the wrangler version and date. `hex-decoded raw key`
   and `crypto.subtle` `importKey('raw')` must give the 2a values.
3. **KV read-after-write.** `approval:<id>` is written at the Approve press and read at `/hermes-totp`; `signed:<id>` is written at
   `/hermes-totp` and read at the drain GET and by the item-5 guard. KV is eventually consistent across locations. Owed: a measured
   write-then-read gap from a different location (or a statement from Cloudflare's docs for the account's tier, URL and date) so that
   Open question 3 and the live 20 s window (umbrella line 137) are decided on a number. `expirationTtl` lower bound (60 s) at the
   deployed API, since the item-2 TTL is 120.
4. **`wrangler secret put` from a prompt.** 2c proof owed 9 (`docs/plans/v1.45.0-remote-promote-2c-root-daemon.md:660-662`): that it
   reads the value at its prompt and not from argv, on the operator's device and version. Owed by 2c; 3b only cites it.

## Proof of external behaviour

Empty until the captures above are taken. Re-verified in the repo at HEAD `bc8276f0`, 2026-11-22 (local, read-only): `crypto.subtle` HMAC
is used by `verifySlack` (`index.js:176-194`); the sandbox harness exposes node's `webcrypto` (`relay.test.mjs:26-33`); the existing
tests sign their own Slack requests with the real clock (`relay.test.mjs:48-55`), which the vector test must replace with a fixed
clock (E1).

## Acceptance

**Pre-fix red.** The pre-fix base is the parent of the worker's first commit for this part, i.e. HEAD after both relay bugs have landed.
The verifier copies this part's edited test file onto the base and records each command below as a `pre_fix_sha` / `pre_fix_command` /
`pre_fix_rc` triple with a nonzero rc (`bin/k3dm-codex-dispatch:700-709`):
- `node --test workers/slack-relay/test/relay.test.mjs` (the new `p` press, `/hermes-totp` and drain tests). On the base a `p` press is
  ignored (`:260` returns an empty 200), `/hermes-totp` answers `Unknown command` (`:397`), and the drain has no `signed` key, so the
  tests fail. A run that reports no tests or a missing file does not count; the verifier records the failing test names.
A `must_not` that states only an absence is not claimed red on the base. Each has a positive control and a named mutant, recorded
separately from the triples (the verifier applies the mutant to the fixed code, records the red test, restores):
- N1: mutant "sign without a pressed approval item", "skip the `approved_by` equals caller check", "skip the allowlist" -> E2.
- N2: mutant "sign with the key text instead of the
  decoded bytes", and "drop `id` or `check` from the canonical bytes", and "do not upper-case `check`" -> E1.
- N3: mutant "log, return or reply the key, the decoded bytes or `sig`" -> E3.
- N4: mutant "drop the `signed:<id>` presence check", "DELETE removes only `approval:<id>`" -> E4.
- N5: mutant "widen the pattern to `^[rp]...`" (drops `d`) -> E5 (the existing `d` tests at `relay.test.mjs:553-577` fail); mutant
  "`/hermes-totp` signs `r` or `d` ids" -> E2.
- N6: mutant "take `at` from a request field or header" -> E1.
- N7: mutant "add `PROMOTE_RELAY_HMAC_KEY` to `deploy-worker` or `wrangler.toml [vars]`" -> E6.

```yaml
must:
  - id: M1
    text: "a hermes_approve press whose value is a p id (^p[0-9]+-[0-9a-f]{8}$) and a 16-hex nonce, by an allowlisted user with the reauth state the code requires, writes approval:<id> {approved_by, approved_at, nonce} with expirationTtl 3600; an r id and a d id still do; an id outside ^[rdp][0-9]+-[0-9a-f]{8}$ (uppercase hex, 7 or 9 hex, an extra suffix, another letter, no id) writes nothing and posts nothing"
  - id: M2
    text: "/hermes-totp <id> <check> <code> from an allowlisted user whose id equals the stored approved_by of an existing approval:<id>, with id ^p[0-9]+-[0-9a-f]{8}$, check ^[0-9A-Za-z]{4}$ and code ^[0-9]{6}$, writes KV signed:<id> = {id, nonce, approver, check, totp, at, sig} with expirationTtl 120, where nonce is the stored nonce, approver the caller, check upper-cased, totp the typed code, at the Worker's own clock in whole seconds (ten digits) and sig the lowercase 64-hex HMAC-SHA256 under the hex-decoded PROMOTE_RELAY_HMAC_KEY of the 2a F.16a canonical bytes; the reply is ephemeral and names the id only"
  - id: M3
    text: "the Worker reproduces the four 2a F.16a contract vectors exactly (key 0x00..0x1f unless stated; nonce 00112233aabbccdd; approver U0123ABCD; totp 287082; at 1700000059): p1-0123abcd/03Q1 -> 5f45ca7b5b3724c6b0d50e0600af206effbb5669d2fb86b530d9ba913d5d572e; p2-0123abcd/03Q1 -> 799b39e7ee50769fe1347bd35435fb5fb31f40f696d1b2ca7ea149a6ad21c2ce; p1-0123abcd/KTR0 -> 4f306c720a47babf86b68f8123e0ef11c3801dd9b25852a4a33987ea7ca54d87; p1-0123abcd/03Q1 with a 32-zero-byte key -> 88c6897a91018fc0411e238afab1caca540e211888c55d6a3bb72c0bdf905626; the test recomputes each with node:crypto createHmac over the documented bytes and compares both"
  - id: M4
    text: "a typed lowercase check (for example 03q1) is signed as its upper-case form (03Q1): the sig equals the vector row for 03Q1 and the stored check is 03Q1"
  - id: M5
    text: "the drain GET returns, for a p id with a live signed:<id>, the four existing fields plus signed with exactly the keys id, nonce, approver, check, totp, at, sig; an r id, a d id and a p id with no signed:<id> have no signed key and are otherwise byte-identical to today's items"
  - id: M6
    text: "the drain DELETE /hermes/approvals/<id> with a valid bearer deletes both approval:<id> and signed:<id> and answers 204; the path pattern and the 401 and 404 behaviour are unchanged"
  - id: M7
    text: "after the DELETE of M6, a /hermes-totp for the same id is refused (no approval item); after a fresh Approve press it signs again (a new envelope, new at)"
  - id: M8
    text: "/hermes-totp is in ALLOWED_COMMANDS with COMMAND_ROLES role admin; every other command, /hermes-auth, the r and d press paths and the Slack signature check behave as before (the whole existing relay.test.mjs passes unchanged except the assertions this spec names)"
must_not:
  - id: N1
    text: "the Worker signs, writes signed:<id> or replies with any envelope value when: no approval:<id> exists; the stored approved_by differs from the calling user; the caller is not on the allowlist; the id is an r or d id or malformed; the check is not 4 alphanumerics; the code is not exactly six digits; APPROVALS_KV is unbound; PROMOTE_RELAY_HMAC_KEY is absent, empty, upper-case hex, 63 or 65 characters or non-hex (positive control: the same fixture with every condition met signs and writes)"
  - id: N2
    text: "a request whose Slack signature is missing, wrong or stale reaches the /hermes-totp branch or signs anything (positive control: the same body signed correctly signs)"
  - id: N3
    text: "the key (hex or decoded bytes), or any sig, appears in any Response body or header, any Slack reply or response_url post, any error text, any console output, or any KV value other than the signed:<id> sig field; the typed code, check and nonce do not appear in any reply (positive control: the signed:<id> item and the drain GET do carry them, as specified, and the key is observably configured because a signature was made)"
  - id: N4
    text: "a second /hermes-totp for an id whose signed:<id> is still present produces a second signature or overwrites signed:<id> (positive control: the first call signs; after the DELETE and a fresh press a new call signs)"
  - id: N5
    text: "the d press and drain behaviour changes: the d tests at relay.test.mjs:553-577 fail or are edited, an r id or d id is signed by /hermes-totp, or the widened pattern accepts an id the engine's ID pattern (hub_approval.py:12) would not for the p form"
  - id: N6
    text: "a client can choose at, nonce, approver or id of the signed envelope: at comes only from the Worker clock, nonce only from the stored approval item, approver only from the Slack-signed user_id (positive control: the envelope carries the stored nonce and the Slack-signed user)"
  - id: N7
    text: "a cloud session, or any holder of the drain token alone, produces a valid approval: with no Slack signing secret the command endpoint refuses; with the drain token alone the drain can list, return and delete but cannot create a signed:<id> or an approval:<id>; no Worker route returns the key or accepts a key (positive control: with a valid Slack-signed press and command the envelope is produced)"
  - id: N8
    text: "an r id path changes: an r press, the r drain item shape and the r DELETE behave exactly as before 3b (positive control: the existing tests at relay.test.mjs:91-103 and :134-142 pass unchanged)"
  - id: N9
    text: "PROMOTE_RELAY_HMAC_KEY appears in the repo: in index.js as a literal, in wrangler.toml [vars], in the Makefile, in a test fixture other than the all-zero and 0x00..0x1f contract keys, or in any doc (positive control: the contract-vector test keys are present)"
evidence:
  - id: E1
    kind: offline
    how: "node --test workers/slack-relay/test/relay.test.mjs: the sandbox gets a fixed Date (now = 1700000059000) and a signed-request helper that stamps the Slack timestamp from it (the existing signed() uses the real clock, relay.test.mjs:48-55); PROMOTE_RELAY_HMAC_KEY set to the hex of bytes 0x00..0x1f; the four vector rows run through press then /hermes-totp then drain GET; each sig compared with the literal vectors and with node:crypto createHmac over the documented bytes; a mixed-case check; a request carrying at, nonce or approver fields in the form body is ignored"
    proves: [M2, M3, M4, N6]
    intent: "Operator can trust the Worker signs exactly the bytes the hub daemon verifies, so a real approval is accepted and a forged one is not"
  - id: E2
    kind: offline
    how: "node --test: one test per N1 refusal built so only that condition fails, each asserting kv.puts is unchanged, no fetch, no signed:<id>, and the reply is ephemeral and echoes no value; the unlisted-user and other-user cases use a different Slack user for the command than the presser; paired with the all-conditions-met control; r and d ids to /hermes-totp"
    proves: [N1, N5]
    intent: "Operator can trust only the person who pressed Approve, on the allowlist, gets a signed approval"
  - id: E3
    kind: offline
    how: "node --test: run the full press, command, drain and DELETE flow with the console, every Response (body and headers), every response_url post and every KV value captured; assert the key hex, its decoded bytes, and the sig appear nowhere except the signed:<id> sig field and the drain GET signed.sig; assert the code, check and nonce are absent from every reply; a source scan of index.js for console calls, for the key name used in a string other than the global read, and for the key literal"
    proves: [N3, N9]
    intent: "Operator can trust the signing key and the typed code never leave through a log, a Slack reply or an error"
  - id: E4
    kind: offline
    how: "node --test: sign once; a second command for the same id refused with signed:<id> byte-identical; DELETE; command refused (no approval); press again; command signs a new envelope; drain GET shows signed only while live; drain GET and DELETE need the bearer (401 without)"
    proves: [M5, M6, M7, N4, N7]
    intent: "Operator can trust a code is signed once per Approve press and the envelope disappears when Hermes has taken it"
  - id: E5
    kind: offline
    how: "node --test: the p press and the malformed-id table of M1 (the existing d table copied for p and extended); the whole existing relay.test.mjs run unchanged for r and d"
    proves: [M1, M8, N5, N8]
    intent: "Operator can trust adding promote ids did not disturb Hermes repairs or dispatch approvals"
  - id: E6
    kind: offline
    how: "a grep test (or the verifier's own scan) over index.js, wrangler.toml, Makefile deploy-worker and the test directory: the key name appears only as the global read in index.js, in the wrangler.toml comment, and in tests as the set-up of the sandbox global; no literal 64-hex key other than the contract keys"
    proves: [N9]
    intent: "Operator can trust the signing key is nowhere in the repo or the deploy script"
  - id: E7
    kind: live
    how: "operator, on the deployed Worker after the operator steps, with a throwaway promote id that Part 3a or a manual Slack press creates: press Approve on a real card for a test id, send /hermes-totp <id> <check> <code>, then read the drain with the hub's drain token from the hub (read-only GET): the item for that id carries signed with the seven keys, at within a few seconds of the hub clock, sig 64 lowercase hex. Then feed that envelope to 'bin/k3dm-promote-client approve' on the hub (after 2c is installed and enrolled): the engine accepts the signature (a genuine code approves; a wrong code is refused totp and counted, which proves the signature step passed, never signature). Host, date, wrangler and macOS versions recorded; the key value is never shown, pasted or logged by Claude"
    proves: [M2, M3, N7]
    intent: "Operator can see a real Slack approval become an envelope the real root daemon accepts, end to end"
  - id: E8
    kind: live
    how: "operator, after E7: with the Worker secret deliberately wrong (set a different 64-hex value, then restore the enrolled one), the same flow is refused signature by the daemon with the approval kept, then accepted after restore; a /hermes-totp with the secret unset answers a configuration refusal and signs nothing"
    proves: [M2, N1]
    intent: "Operator can see a mismatched or missing key fails closed instead of approving"
  - id: E9
    kind: live
    how: "operator or Claude, read-only: a cloud session (no Slack, no Cloudflare access) tries to cause an approval: it can file a promote-request (3a) but the Worker never signs without a Slack-signed press by an allowlisted user and a Slack-signed /hermes-totp; the verifier records that the only credential the session has (GitHub) cannot reach the Worker's command or interactivity endpoints with a valid Slack signature (the endpoints answer 401 to an unsigned POST, the existing sensor)"
    proves: [N7]
    intent: "Operator can see a cloud session cannot approve its own promote"
interface:
  - "POST /slack/interactivity: block_actions hermes_approve and hermes_deny with value '<id>|<nonce>', id ^[rdp][0-9]+-[0-9a-f]{8}$, nonce ^[0-9a-f]{16}$; approval:<id> {approved_by, approved_at, nonce} TTL 3600"
  - "POST /slack/commands command=/hermes-totp text='<id> <check> <code>' user_id=<Slack id>: reply ephemeral; KV signed:<id> {id, nonce, approver, check, totp, at, sig} TTL 120"
  - "GET /hermes/approvals (Bearer drain token): list of {action_id, approved_by, approved_at, nonce[, signed{id, nonce, approver, check, totp, at, sig}]}; DELETE /hermes/approvals/<id> removes approval:<id> and signed:<id>"
  - "sig = lowercase hex HMAC-SHA256(hex-decoded PROMOTE_RELAY_HMAC_KEY, b'k3dm-promote-approve:v1\\n' + id + '\\n' + nonce + '\\n' + approver + '\\n' + check + '\\n' + totp + '\\n' + at + '\\n'), check upper-cased, at ten decimal digits of the Worker clock; contract vectors in M3"
  - "test command: node --test workers/slack-relay/test/ (docs/guides/hermes.md:708)"
```

## Files

Edit only these:

- `workers/slack-relay/index.js`
- `workers/slack-relay/test/relay.test.mjs`
- `workers/slack-relay/wrangler.toml` (the secrets comment only)
- `docs/guides/hermes.md` (the Slack approvals section, around `:71-95`: promote flow, `/hermes-totp`, the new Worker secret, the operator steps, the 2c rotation note)
- `docs/architecture/cloudflare-slack-relay.md` (the allowed-command list around `:77-83` and a short section on the signing step)

`docs/howto/hub-promote.md` and `docs/howto/cloud-session-requests.md` belong to Part 3a. The umbrella's 3b list (about 3 files:
`index.js`, its test, `docs/guides/hermes.md`) is widened here by the architecture doc and the `wrangler.toml` comment, which the
contract readers above require; both are doc-only.

## Worker definition of done

1. **Red first, two columns.** Every must and must_not test has its positive control. The hand-off reports the pre-change result and a
   mutant result per test. The `pre_fix_*` triple is the one command at the head of `## Acceptance`; the mutants N1-N7 are recorded
   separately.
2. **Fixtures first.** The harness asserts its target: the sandbox `WEBHOOK_URL` is the stub `https://webhook.test`, the KV is the fake,
   the key is a contract-test key, and no real Cloudflare, Slack or Keychain is reached.
3. **Contract vector before logic.** The four vectors of M3 pass before any other `/hermes-totp` test is written, and the test says in
   a comment that they are copied from 2a F.16a (2026-11-19 probe), not from this implementation.
4. **Re-cite.** Every `index.js` line number in this spec is re-cited after both relay bugs have landed; a changed citation is noted
   in the hand-off.
5. **No new runtime dependency**, no network call from the new branch, no `console` call that takes an envelope field.
6. **Checks.** `node --test workers/slack-relay/test/` passes, `make test-pytest` (agent-doc drift) passes, `make check-doc-links`
   passes for the two docs.

## What NOT to do

- Do not run `wrangler`, `make deploy-worker`, any Cloudflare, Slack or Keychain command, or `make` at all against a live target. Do not
  generate, read, print, paste or store the key. Test keys are the two contract keys only.
- Do not add the key to `deploy-worker`, `wrangler.toml [vars]`, the Keychain targets or any file.
- Do not edit `scripts/lib/hermes/approvals.py`, `bin/k3dm-hermes`, `scripts/lib/hermes/sensors.py` or any hub file: they are Part 3a's.
- Do not add a clock, key or `at` override (header, form field, environment).
- Do not narrow or remove `d` from the id pattern.
- Do not decide the open questions below; implement the behaviour as written and flag any case the spec leaves open.

## Open questions

Each is left to the operator. None is decided here.
1. **Key rotation.** 2c `enrol --rotate relay-key` (2c lines 274-275) replaces the hub file and, from then, envelopes signed with the old
   Worker secret are refused `signature` until the operator re-puts the new value. There is no overlap window, and the Worker holds one
   key. Is a short outage during rotation acceptable, or does the Worker need to sign under a "current" key with a second "next"
   secret? How often is rotation expected (it is never automatic)?
2. **Clock skew and the `at` window.** The engine refuses `at` outside `[now - 300, now + 120]` (`hub_approval.py:275`; 2a G.20 step
   0b), measured against the hub clock, with `at` from the Worker clock. Are those bounds final? Should the Worker refuse to sign if
   it cannot observe its own clock sanity, or is NTP on both sides assumed? The umbrella also says a code is "useless after one use or
   90 s" (line 132); no component in 2a or 2c enforces 90 s (the engine enforces the TOTP step window and the 300 s `at` window), and
   KV's `signed:<id>` TTL is 120 s. Which number is the intended bound?
3. **Replay and the nonce/single-use store.** The Worker's one-signing-per-press guard (Behaviour 5) rests on KV, which is eventually
   consistent, so two commands a moment apart can both sign. The engine's high-water mark and nonce handling are the real defence (2a
   F.17, G.20). Is a best-effort Worker guard enough, or does the operator want a stronger store (Durable Object) or a stored
   per-id "signed once" marker with its own TTL (and how long: the 3600 s approval TTL, or the record's 2a expiry)?
4. **Is `reauth:<user>` required at `/hermes-totp`?** Today the press requires it (`:270`). After the reauth bug the re-auth lasts
   10 minutes and is single use, deleted after a successful decision, so by the time the operator types the code the re-auth is gone
   (the umbrella's "three Slack steps", lines 78-88). Does `/hermes-totp` require a fresh `/hermes-auth` (four steps), or rely on
   the pressed approval item and the allowlist alone?
5. **The `d` ids.** The umbrella's "widen to `^[rp]`" would drop dispatch approvals. This spec widens to `^[rdp]`. Confirm, and
   confirm the umbrella text is corrected at the next grooming.
6. **Who widens `approvals.py`?** Umbrella line 130 says 3b widens the relay and `approvals.py`; the 3b paragraph and file list (about
   3 files) omit it; 3a's list has it. This spec leaves it to 3a. Confirm.
7. **KV key name.** Umbrella line 132 names the signed item `signed:<id>`; line 139 says the drain "deletes the `totp:<id>` item". This
   spec uses `signed:<id>` throughout. Confirm or rename.
8. **Slack-app sensor.** `scripts/lib/hermes/sensors.py:30` requires only `/hermes-auth`. Should `/hermes-totp` join
   `SLACK_REQUIRED_COMMANDS` so a missing registration pages the operator? That edit is a hub file (3a's or a bug), not this part's.
9. **Deny after Approve.** A `hermes_deny` press writes nothing (`:279-281`) and does not remove an existing `approval:<id>` or
   `signed:<id>`. Should a deny of a `p` id delete both (so a stale envelope cannot be drained after the operator denied)? The engine
   refuses it `not_pending` once the record is denied (2a R2a-5), so this is a hygiene question.
10. **Worker-side attempt limit.** Each `/hermes-totp` needs a pressed approval and an allowlisted user, and the engine counts failed
    codes (five per record, ten global). Does the Worker also rate-limit commands per user?
11. **Test gate.** `node --test workers/slack-relay/test/` is run by hand today (`docs/guides/hermes.md:708`); no `make` target or CI
    job runs it (grep of `Makefile` and `.github` found none). Should this part's acceptance require wiring it into `make test` or CI, or
    is the hand-off run enough?

## Handoff notes for the release groom

- Placement: needs a displacement in v1.46.0 (over its 5-plan cap) before this spec can leave DRAFT; sequence it after the two relay
  bugs, after Part 3a is written, and after 2c has live-verified on the hub.
- The captures in `## Captures needed before dispatch` and the intent approval are the two items between DRAFT and READY.
