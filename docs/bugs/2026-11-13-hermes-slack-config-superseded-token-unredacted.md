# Bug: Hermes Slack config sensor leaves the superseded token pair unredacted after a rotate; regenerate evidence does not lead with the hint

**Status:** VERIFIED — `1db4e68b` independently verified 2026-11-13 at e9c375c4 (Acceptance-only Opus verifier, own harness: 16/16 on fix, 16/16 red on 1db4e68b^, final-pair secrets_seen mutant red on both E1 cases; 14 regenerate strings 117–128 chars; suite 388 passed, guard hits 0; Claude checked the saved outputs); landed 1db4e68b on k3d-manager-v1.44.0 2026-11-13 (Claude verified: pre-fix red, mutant red, Fable review no high/medium); originally captured 2026-11-13 from the independent Acceptance verification of plan 5 (Opus verifier, items N1 and N5; Claude reproduced)
**Priority:** P2 (a superseded token stays valid; reaching the record needs Slack to echo it, so practical risk is low)
**Introduced by:** `58237c77` (v1.44.0 plan 5 `hermes-slack-config-sensors`)
**Should have been caught by:** offline test (the redaction test covered only the tokens held at the end of the cycle)
**Prior art:** exact-slug glob: none; `docs/bugs/2026-11-13-hermes-slack-config-r5-residual-lows.md` read, different items. `make find-similar-docs` not run
**Approval:** operator, 2026-11-13: "go ahead for those three fix intents"
**Dispatch go:** operator, 2026-11-13: "go ahead for those three fix intents"
**Intent approved:** operator, 2026-11-13
**Intent approval words:** "go ahead for those three fix intents", in reply to Claude's three proposed intents

## Symptom

1. N1: after a successful rotate, `slack_app_config` (`scripts/lib/hermes/sensors.py` ~227) reassigns `access, refresh = new_access, new_refresh`; `secrets_seen` (~290) is built from those final values only. A manifest that echoes the OLD access or refresh token (e.g. a slash-command url `.../slack/events?<old access>`) leaves it unredacted in the record findings and in `state["slack_config"]["record"]`. Superseded tokens stay valid (spec capture 4).
2. N5: Acceptance says a rejected rotate reports unknown "with the regenerate hint first in the evidence". Actual: `Slack config token rejected (invalid_refresh_token): regenerate the config token at api.slack.com/apps`.

## Fix

Collect every token value read from or written to the store during the cycle (initial reads, re-reads, rotate results) into `secrets_seen` and redact all of them. Make every regenerate-flag evidence string start with the hint, using the spec Design wording, e.g. `Regenerate the Slack config token at api.slack.com/apps and re-store both Keychain items (token rejected: invalid_refresh_token)`, at most 140 characters.

## Acceptance

```yaml
must:
  M1: every token value read from or written to the store during a cycle is redacted from the record, persisted state and logs
  M2: every regenerate-flag evidence string starts with "Regenerate" and is at most 140 characters
must_not:
  N1: after a successful rotate, a manifest echoing the old access or old refresh token leaves either value anywhere in the returned record, persisted state, stdout, stderr or caplog
  N2: rotation behaviour changes (rotate count, flag handling, Keychain writes) for any existing test scenario
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "You will see a test where the rotation succeeds and Slack echoes the old tokens: neither old nor new token appears in the record, the saved state or any log. It fails on today's code."}
  - {id: E2, proves: [M2], kind: offline, intent: "You will see the rejected-rotate, manifest-sourced and rotate-sourced regenerate evidence each start with 'Regenerate…' and fit 140 characters; it fails on today's wording."}
  - {id: E3, proves: [N2], kind: offline, intent: "You will see the whole Hermes suite pass with guard hits 0, with only wording assertions updated."}
interface:
  - "scripts/lib/hermes/sensors.py slack_app_config(...) record and state"
```

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/sensors.py` | `slack_app_config`: secrets_seen; regenerate evidence wording |
| `scripts/tests/hermes/test_slack_sensors.py` | E1, E2; wording assertions |

## Worker definition of done

- Change only the files above. No network, no real Keychain/`security`/`ssh`/`curl`, HOME is `tmp_path`, no make target that touches the hub. Show E1 and E2 red on today's code, then green; give a mutant (secrets_seen from the final pair only) → RED. Paste the full output of `PYTHONPATH=scripts/lib python3 -m pytest scripts/tests/hermes -q` with rc and the guard hit count, and `ruff check` on the touched files (`RUFF` may point at a venv ruff). Leave changes uncommitted.

## Residual lows (P3 batch candidates)

- Low (Fable): `store.writable()` (`sensors.py:207`) reads and rewrites the Keychain item outside `read_token`, so a value re-stored mid-cycle is not remembered; the test store never reads.
- Low (Fable; confirmed by the 2026-11-13 verifier: a 48-char code from persisted `last_error` gives 155): the 140-char cap is not enforced; a persisted `last_error` of 34+ chars gives up to 155 (record() truncates at 200).
- Low (Fable): `clean()` replaces in insertion order; a token that is a prefix of another leaves the longer one's tail. Sort by length descending.
- Fixed before landing (Claude): three negative assertions still checked the old wording (vacuous) and the account_inactive replay lost its code check; restored and flip-tested.
