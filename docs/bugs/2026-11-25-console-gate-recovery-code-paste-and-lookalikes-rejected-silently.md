# Bug: the console gate rejects a pasted recovery code (and 0/1/8 lookalikes) as "Invalid code" without saying why

**Status:** LIVE-VERIFIED — `16199b9c` on `k3d-manager-v1.45.1` (2026-11-25); E1-E3 offline PASS (independent verifier; gaps e/j closed by Claude); E4 live PASS on m5-air 2026-11-25 (promoted `c7c8f8d1`)
**Live evidence:** 2026-11-25 · run operator-e4-m4-to-m5-console · env m5-air · scenario pasted-recovery-code-unlocks-console-count-9-to-8 · commit c7c8f8d1 · proves E4
**Fix commit:** 16199b9c
**Priority:** P2 (operator, 2026-11-25) — degraded: a recovery code works only when typed by hand, blind, with the right
letters; the person using one is already locked out. Workaround: type it by hand with the letters O and I.
**Triage:** patch → v1.45.1 (operator, 2026-11-25: "go ahead to file P2, have Fable review it then dispatch to Flash")
**Branch:** k3d-manager-v1.45.1
**Introduced by:** totp-a2 (`93ecfb83`, recovery codes accepted at the gate prompt)
**Should have been caught by:** spec (no case for pasted input or lookalike characters at the echo-off prompt)
**Introducing change reviewed:** unknown
**Intent approved:** operator, 2026-11-25
**Intent note:** "go ahead to file P2, have Fable review it then dispatch to Flash"
**Review:** Fable 2026-11-25 rev 1 → "ready after should-fix" (1 blocker, 6 should-fix, 4 nits), all taken in rev 2
**Prior art:** `ls docs/bugs/*recovery*` none; `make find-similar-docs` not run (vector store not reachable from m4) — none above threshold
**Filed:** 2026-11-25
**Detected by:** operator + Claude, v1.45.1 L2 live check on m5-air, 2026-11-25

## Observed (m5-air, macOS 26.5.1, gate blob `26f36500`, totpd blob `0b924122`, 2026-11-25)

- A recovery code pasted at the console `Code:` prompt was refused with "Invalid code". The totpd log has no
  `totp-recovery-failure` line: Claude matched the log size (332 B) byte for byte to the event lines the operator
  pasted, so the gate rejected the input before asking the verifier (totpd logs the first wrong recovery code at once,
  `scripts/libexec/k3dm-console-totpd.py:1078-1081`).
- The same code typed by hand passed a scratch checker that reads input exactly like the gate (echo off, byte by byte,
  20-byte cap; reports structure only, never the code): 19 bytes, 16 characters, form right. Typed at the console, it
  logged in and `totpctl recovery-status` went 10 → 9 (log +113 B = `totp-unlock source=recovery` +
  `totp-recovery-used remaining=9`). See `docs/plans/v1.45.1-totp-a2-recovery-codes.md` "Live check — L2".
- Also seen: at the echo-off prompt the operator typed the 6-digit code out of habit twice while meaning to type the
  recovery code; nothing on screen says which kind of code the gate saw.

## Cause (code read, `scripts/libexec/k3dm-console-gate.py:291-361`)

1. **Pasted-input overflow (root cause not proven; the fix hardens every candidate).** The prompt keeps at most 20
   bytes (`:335-338`) and treats anything longer as an overflow ("Invalid code", `:341-345`, never sent to totpd).
   Spaces are counted at read time and stripped only afterwards (`:340`). Candidates that turn a 19-character pasted
   code into a local reject, none captured live:
   - bracketed-paste markers `ESC [ 2 0 0 ~` … `ESC [ 2 0 1 ~` (12 bytes; XTerm Control Sequences, "Bracketed Paste
     Mode", `CSI ? 2004 h`/`l`; Terminal.app and iTerm2 implement it). zsh turns the mode off before running a command,
     so a fresh `ssh` normally starts with it off; it can be left on after a tmux attach ends (idle re-prompt, or a
     killed client, `:531`);
   - leading or trailing spaces, a tab, or a list indent in the copied text;
   - non-ASCII dashes (an en dash is 3 bytes in UTF-8, so a dashed code with three becomes 25 bytes).
   If E4 is red after landing, the bug goes back to `**Waiting on:** investigation` and the operator runs the paste case
   of the scratch checker (`~/k3dm-code-check.py` on m5-air: byte count and structure only) to name the cause.
2. **Lookalikes.** Normalisation (`:340`) removes spaces and dashes and upper-cases, but the digits 0, 1 and 8 typed for
   the letters O, I and B fail `[A-Z2-7]{16}` (`:348`) and are rejected locally.
3. **No hint.** A format rejection and a verifier `NO` both print `Invalid code` with echo off, so the person cannot tell
   a typo from a wrong code. (Which kind of code a well-formed input was is deliberately not shown after a verifier `NO`.)

## Fix (gate prompt only)

In the prompt read loop of `scripts/libexec/k3dm-console-gate.py`:

1. **Bracketed paste off.** The first prompt write at `:301` becomes
   `b"\x1b[?2004l\x1b[H\x1b[2J\x1b[3JCode: "`, and the Ctrl-C re-prompt at `:326` becomes `b"\x1b[?2004l\nCode: "`.
   The idle re-prompt re-enters through `:301`, so it is covered.
2. **Input filter, a byte-at-a-time state machine** (states NORMAL, ESC, CSI, SS3), applied before a byte reaches
   `line_buf`:
   - Reset to NORMAL at each prompt start (where `line_buf` is created, `:304`) and on the Ctrl-C family.
   - In every state, `\x03 \x1a \x1c \x04` and `\r \n` act exactly as today (the Ctrl-C family clears and re-prompts;
     Return ends the read, and an open sequence is simply dropped).
   - NORMAL: `ESC` (0x1b) → ESC (dropped). Space (0x20), tab (0x09) and any byte ≥ 0x80 are dropped. Backspace and every
     other byte behave as today.
   - ESC: `[` → CSI; `O` → SS3; `ESC` stays in ESC; any other byte: drop the ESC only, return to NORMAL and handle that
     byte as in NORMAL (so a lone Esc keypress does not eat the next character).
   - CSI: a byte in 0x40–0x7E ends the sequence → NORMAL; any other byte stays in CSI. All dropped.
   - SS3: the next byte is dropped → NORMAL.
   - Backspace inside a sequence is dropped and does not pop `line_buf`.
   - Dropped bytes never touch `line_buf` or `overflow`, so they never count toward the 20-byte cap.
   - OSC/DCS (`ESC ]`, `ESC P`) are out of scope: `]`/`P` after ESC is handled as "any other byte" (pre-existing; the
     relay handles late terminal replies only after attach).
3. **Lookalikes.** After the existing normalisation (dashes removed, upper-cased; spaces no longer arrive), if the
   input is **not** exactly 6 digits, map `0`→`O`, `1`→`I`, `8`→`B` before the `[A-Z2-7]{16}` check. A 6-digit TOTP code
   is never mapped. No other mapping: 1 is always I (never L); 5/S, 2/Z and 6/G are distinct valid characters; 9 stays
   invalid. Every input still maps to at most one canonical code, so the per-attempt guess space is unchanged.
4. **Hint on local rejection.** When the gate rejects input locally (overflow, or neither 6 digits nor 16 recovery
   characters), it writes `b"\nInvalid code (6 digits, or a 16-character recovery code: letters A-Z, digits 2-7)\n"`
   instead of `b"\nInvalid code\n"`. A verifier `NO` keeps exactly `b"\nInvalid code\n"`. Both paths keep the 2 s sleep
   (no new timing signal). The hint is visible for about 2 s before the next prompt clears the screen; accepted.

Nothing else in the gate changes: no change to the wire format (`VERIFY <code>`), the 20-byte cap on real characters,
the failed-prompt count, the 2 s delay, the idle re-prompt, or totpd. The code must run on the hub interpreter
(CommandLineTools Python 3.9, `-IS`, stdlib only): no `match`, no `X | Y` type syntax.

Docs: `docs/howto/web-console-totp.md`, in the recovery-code section (near `:89`), one short paragraph: the prompt does
not show what you type; a recovery code can be pasted or typed, with or without dashes or spaces, in any case; codes are
letters A-Z and digits 2-7 only, there is no digit 0, 1, 8 or 9, and 0, 1, 8 typed for O, I, B are accepted; the two
"Invalid code" messages and what each means.

## Files

| File | Change |
|---|---|
| `scripts/libexec/k3dm-console-gate.py` | prompt read loop only (`:291-361`): items 1-4 above |
| `scripts/tests/bin/test_web_console_totp.py` | one new test function (E1, E2), next to `test_gate_recovery_input_normalization_and_cap` (`:3273`) and in its style |
| `docs/howto/web-console-totp.md` | one paragraph (E3) |

## Contract readers

The gate's prompt and message bytes (grep `Invalid code`, `Code: `, `2004` in `scripts/`, `bin/`, `docs/howto/`,
2026-11-25): written only at `k3dm-console-gate.py:301,326,343,352,361`; read only by tests
(`scripts/tests/bin/test_web_console_totp.py:1378,1666,2365,2370,2823,3304,3308`, all `until(b"Invalid code")` or
`b"Invalid code" in …` substring checks, which the new local message still satisfies; plus many `until(b"Code: ")` readers, also substrings).
Described in `docs/plans/v1.45.1-totp-a2-recovery-codes.md:131,209` (docs only, no change needed). `totpctl` prints its own
`Code: ` / `Invalid code` (`k3dm-console-totpctl.py:251,354,367,400`) and is out of scope. No relay or browser code
parses the gate's output. The `VERIFY` wire format to totpd does not change.

## Acceptance

Test notes for the worker: drive the gate with `GateProcess` and a fake verifier socket exactly as
`test_gate_recovery_input_normalization_and_cap` (`test_web_console_totp.py:3273`) does. The pty has ONLCR, so `\n`
written by the gate arrives as `\r\n` on the master, and `GateProcess.until` consumes the buffer through its marker:
assert with the contiguous markers below.

```yaml
must:
  - id: M1
    text: "A bracketed-paste recovery code b'\x1b[200~GEZD-GNBV-GY3T-QOJQ\x1b[201~\n' reaches the verifier as exactly b'VERIFY GEZD-GNBV-GY3T-QOJQ\n'; so do b'  GEZD-GNBV-GY3T-QOJQ\t\n' (spaces, tab) and the code with each dash replaced by an en dash (UTF-8 e2 80 93)."
  - id: M2
    text: "With the fixture code IBEZ-GNBV-GY3T-QOJQ, the input b'18EZ-GNBV-GY3T-Q0JQ\n' reaches the verifier as exactly b'VERIFY IBEZ-GNBV-GY3T-QOJQ\n'; b'108080\n' reaches it as exactly b'VERIFY 108080\n' (never mapped); a 16-character input containing 9 is still a local reject."
  - id: M3
    text: "The first prompt reads until(b'\x1b[?2004l\x1b[H\x1b[2J\x1b[3JCode: '); the Ctrl-C re-prompt reads until(b'\x1b[?2004l\r\nCode: ')."
  - id: M4
    text: "A local rejection (e.g. b'GEZD\n') reads until(b'Invalid code (6 digits, or a 16-character recovery code: letters A-Z, digits 2-7)\r\n'); a verifier NO reads until(b'\r\nInvalid code\r\n\x1b[?2004l\x1b[H') (proves no hint)."
  - id: M5
    text: "Existing gate tests stay green, including test_gate_recovery_input_normalization_and_cap; 21 real characters with an escape sequence inside (b'GEZDGNBVGY3TQOJQXXXXX\x1b[D\n') still overflow and send nothing; no ESC byte ever reaches the verifier (every captured VERIFY line matches ^VERIFY ([0-9]{6}|[A-Z2-7]{4}(-[A-Z2-7]{4}){3})\n$)."
must_not:
  - id: N1
    text: "Must not reject a pasted recovery code locally, including a whole-line copy where the newline is inside the brackets: b'\x1b[200~GEZD-GNBV-GY3T-QOJQ\n\x1b[201~' then b'GEZD-GNBV-GY3T-QOJQ\n' gives two identical VERIFY lines (the trailing ESC[201~ is read at the next prompt and dropped). Red today: the M1 input (31 bytes) overflows and sends nothing; in the whole-line case both inputs are 25 bytes and overflow."
  - id: N2
    text: "Must not reject a recovery code typed with 0/1/8 for O/I/B locally. Red today: b'18EZ-GNBV-GY3T-Q0JQ\n' fails [A-Z2-7]{16} and sends nothing."
  - id: N3
    text: "Must not reject a code because an escape sequence arrived inside it, and must not count escape bytes toward the cap. Red today: b'GEZDGNBV\x1b[DGY3TQOJQ\n' (arrow key) and b'GEZDGNBV\x1bOAGY3TQOJQ\n' (SS3) send nothing; after the fix both give b'VERIFY GEZD-GNBV-GY3T-QOJQ\n'."
evidence:
  - {id: E1, proves: [M1, M2, M3, M5, N1, N2, N3], kind: offline, intent: "A recovery code you paste (even with stray spaces, fancy dashes or terminal paste markers), or type with 0/1/8 for O/I/B, gets through the console prompt to the verifier, and a 6-digit code is never altered", command: "python3 -m pytest -q scripts/tests/bin/test_web_console_totp.py -k gate_recovery_paste_and_lookalikes (new test; fake verifier captures each VERIFY line; every input in M1-M3, M5, N1-N3; asserts the captured lines exactly)", red_control: "the new test, written and run before the gate is edited, fails on k3d-manager-v1.45.1@9cca0789 (no VERIFY captured for the paste, whitespace, en-dash, lookalike and escape inputs; prompt bytes lack ESC[?2004l); positive controls in the same test: the plain code and 108080 are captured on both pre-fix and post-fix code"}
  - {id: E2, proves: [M4, M5], kind: offline, intent: "When the console refuses what you typed, it tells you a code's form, but never whether a well-formed code was valid", command: "python3 -m pytest -q scripts/tests/bin/test_web_console_totp.py -k gate (whole gate group, 26 tests) including the new test's M4 markers", red_control: "the local-rejection hint marker fails on 9cca0789; the verifier-NO marker without the ESC[?2004l part passes on both (regression guard)"}
  - {id: E3, proves: [M4], kind: offline, intent: "The how-to tells you a recovery code can be pasted or typed with lookalikes, and what each Invalid code message means", command: "grep -n 'pasted' docs/howto/web-console-totp.md && grep -n 'A-Z' docs/howto/web-console-totp.md && make check-doc-links", red_control: "both greps find nothing on 9cca0789"}
  - {id: E4, proves: [N1], kind: live, intent: "On the hub, a recovery code pasted at the console prompt logs you in", command: "operator on m5-air after promote and make install-web-console-totp: ssh -p 42722 with the test cert, paste one recovery code at Code:, login works; sudo totpctl recovery-status drops by one; Claude checks the log grew by the two recovery lines", red_control: "the 2026-11-25 L2 attempt (pasted code refused, no totpd line); if E4 is red, see Cause 1"}
interface:
  - "first prompt bytes b'\x1b[?2004l\x1b[H\x1b[2J\x1b[3JCode: '; Ctrl-C re-prompt b'\x1b[?2004l\nCode: '; local rejection b'\nInvalid code (6 digits, or a 16-character recovery code: letters A-Z, digits 2-7)\n'; verifier NO b'\nInvalid code\n' (unchanged); VERIFY wire format unchanged"
```

## Worker definition of done

- Change only the three files above. Offline only: no sudo, no install, nothing under `/etc`, `/Library` or `/var`; no
  real totpd or tmux beyond what the existing test fixtures start under a scratch directory.
- Write the new test first and run it against the unedited gate (`9cca0789`): E1 and the E2 hint marker must fail; then
  edit the gate and show them green; run the whole
  `scripts/tests/bin/test_web_console_totp.py` and `make check-doc-links`; `python3 -m py_compile` the gate with the
  hub interpreter if present (`/Library/Developer/CommandLineTools/usr/bin/python3`).
- Leave changes uncommitted; do not push. Claude commits, lands and owns the memory-bank update.

## Verification (Claude, 2026-11-25)

- Worker (Flash) diff reviewed against Fix items 1-4: in scope (3 files), Python 3.9 parse OK (`/usr/bin/python3` 3.9.6, `-IS`).
- Independent verifier (Acceptance only, scratch copies): new test `1 passed` fixed / `1 failed` on the 9cca0789 gate (positive
  controls plain code and `108080` captured on both); `-k gate` 27 passed; whole file 194 passed; E3 greps hit line 89 fixed, rc 1
  on 9cca0789. Mutants red: CSI filter off, ESC-[ to NORMAL, no 0/1/8 map, map on 6 digits, ESC counted to cap, hint on NO,
  ESC[?2004l dropped from either prompt, bytes >= 0x80 kept, space/tab counted. Green (test gaps): (e) lone Esc eats the next byte,
  (j) Ctrl-C keeps CSI state.
- Claude added test section 1b (`b'\x1bGEZD-GNBV-GY3T-QOJQ\n'`; `b'\x1b[\x03'` then the code): mutants e and j both fail at the
  1b assert; fixed gate passes. ruff 0.15.8 clean; `git diff --check` clean.
- Land `16199b9c`: test_web_console_totp.py 194 passed, web_console_totp.bats PASS (341 s), doc-links PASS.
- E4 (live, operator): after promote and `make install-web-console-totp` on m5-air, paste one recovery code at `Code:`; login works;
  `sudo totpctl recovery-status` drops by one.

## Live result (E4, m5-air, 2026-11-25)

- Promote: operator `make hub-deploy REF=c7c8f8d1` (`ahead of deploy/hub: 0`), `make install-web-console-totp`. Claude (read-only
  SSH): installed `/Library/PrivilegedHelperTools/k3dm-web-console/forced-command` blob `1751a026…` (25467 B) = the gate at
  `c7c8f8d1`; totpd running under CommandLineTools Python 3.9.
- Operator from m4: `ssh -t m5-air.local 'ssh -p 42722 -i ~/.ssh/k3dm-console-test -o IdentitiesOnly=yes cliang@127.0.0.1'`, pasted
  one recovery code at `Code:` (bracketed paste through two ssh hops), console session opened.
- Log `/var/log/k3dm-web-console-totp.log` (root 600; Claude byte counts): 499 B (last entry 05:30:37, `remaining=9`) → 612 B at
  07:24:56 PST, +113 B = exactly the two lines the operator pasted:
  `2026-11-25T15:24:56Z event=totp-unlock source=recovery`, `2026-11-25T15:24:56Z event=totp-recovery-used remaining=8`.
  No `totp-recovery-failure` line, no code in the log.
- `sudo …/totpctl recovery-status` → `8 recovery codes remaining` (9 → 8).
- Red control: the 2026-11-25 L2 attempt where a pasted code was refused at the gate with no totpd line.
