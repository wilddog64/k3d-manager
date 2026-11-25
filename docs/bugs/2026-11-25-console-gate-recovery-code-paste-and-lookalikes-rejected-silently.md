# Bug: the console gate rejects a pasted recovery code (and 0/1/8 lookalikes) as "Invalid code" without saying why

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-25) — degraded: a recovery code works only when typed by hand, blind, with the right
letters; the person using one is already locked out. Workaround: type it by hand with the letters O and I.
**Triage:** patch → v1.45.1 (operator, 2026-11-25: "go ahead to file P2, have Fable review it then dispatch to Flash")
**Branch:** k3d-manager-v1.45.1
**Introduced by:** totp-a2 (`93ecfb83`, recovery codes accepted at the gate prompt)
**Should have been caught by:** spec (no case for pasted input or lookalike characters at the echo-off prompt)
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-25
**Intent approved:** operator, 2026-11-25
**Intent note:** "go ahead to file P2, have Fable review it then dispatch to Flash"
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

1. **Paste overflow.** The prompt keeps at most 20 bytes (`:335-338`) and treats anything longer as an overflow
   ("Invalid code", `:341-345`, never sent to totpd). With bracketed-paste mode on, a terminal wraps pasted text in
   `ESC [ 2 0 0 ~` … `ESC [ 2 0 1 ~` (12 bytes; XTerm Control Sequences, "Bracketed Paste Mode", `CSI ? 2004 h` enables,
   `CSI ? 2004 l` disables; Terminal.app and iTerm2 implement it). A 19-character code becomes 31 bytes. The mode is set
   by programs on the terminal (zsh's line editor, tmux) and can be left on when the gate's prompt starts. Not captured
   live (the operator did not run the paste case in the checker); the fix below does not depend on it — it turns the
   mode off and drops escape sequences either way.
2. **Lookalikes.** Normalisation (`:340`) removes spaces and dashes and upper-cases, but the digits 0, 1 and 8 typed for
   the letters O, I and B fail `[A-Z2-7]{16}` (`:348`) and are rejected locally.
3. **No hint.** A format rejection and a verifier `NO` both print `Invalid code` with echo off, so the person cannot tell
   a typo from a wrong code, or which kind of code they typed.

## Fix (gate prompt only)

In the prompt read loop of `scripts/libexec/k3dm-console-gate.py`:

1. Prefix the prompt write with `ESC [ ? 2 0 0 4 l` (turn bracketed paste off): `b"\x1b[?2004l\x1b[H\x1b[2J\x1b[3JCode: "`
   at `:301`, and the same prefix on the `b"\nCode: "` re-prompt after Ctrl-C (`:324`).
2. Drop terminal escape sequences from the typed input before they reach `line_buf`: on `ESC` (0x1b), discard it and,
   if the next byte is `[`, discard bytes up to and including the first byte in 0x40–0x7E (a CSI sequence such as
   `ESC[200~`, `ESC[201~` or an arrow key); if the next byte is `O`, discard it and one more byte (SS3); any other byte
   after `ESC` is discarded with it. A sequence still open at Return is discarded. Dropped bytes never count toward the
   20-byte cap. Ctrl-C/Ctrl-Z/Ctrl-\/Ctrl-D, Return and backspace keep their current meaning outside a sequence.
3. After the existing normalisation, if the input is **not** exactly 6 digits, map `0`→`O`, `1`→`I`, `8`→`B` before the
   `[A-Z2-7]{16}` check. A 6-digit TOTP code is never mapped.
4. When the gate rejects input **locally** (overflow, or neither 6 digits nor 16 recovery characters), print
   `Invalid code (6 digits, or a 16-character recovery code: letters A-Z, digits 2-7)` instead of `Invalid code`. A
   verifier `NO` keeps the exact `Invalid code` (no hint about validity). Both still begin with `Invalid code`.

Nothing else in the gate changes: no change to the wire format (`VERIFY <code>`), the 20-byte cap on real characters,
the failed-prompt count, the 2 s delay, the idle re-prompt, or totpd. The code must run on the hub interpreter
(CommandLineTools Python 3.9, `-IS`, stdlib only): no `match`, no `X | Y` type syntax.

Docs: `docs/howto/web-console-totp.md`, in the recovery-code section, one short paragraph: the prompt does not show what
you type; a recovery code can be pasted or typed, with or without dashes, in any case; the letters O, I and B may be
typed as 0, 1 and 8; the two "Invalid code" messages and what each means.

## Files

| File | Change |
|---|---|
| `scripts/libexec/k3dm-console-gate.py` | prompt read loop only (`:291-361`): items 1-4 above |
| `scripts/tests/bin/test_web_console_totp.py` | one new test function (E1, E2), next to `test_gate_recovery_input_normalization_and_cap` (`:3273`) and in its style |
| `docs/howto/web-console-totp.md` | one paragraph (E3) |

## Contract readers

The gate's prompt and message bytes (grep `Invalid code`, `Code: `, `2004` in `scripts/`, `bin/`, `docs/howto/`,
2026-11-25): written only at `k3dm-console-gate.py:301,324,343,352,361`; read only by tests
(`scripts/tests/bin/test_web_console_totp.py:1378,1666,2365,2370,2823,3304,3308`, all `until(b"Invalid code")` or
`b"Invalid code" in …` substring checks, which the new local message still satisfies). `totpctl` prints its own
`Code: ` / `Invalid code` (`k3dm-console-totpctl.py:251,354,367,400`) and is out of scope. No relay or browser code
parses the gate's output. The `VERIFY` wire format to totpd does not change.

## Acceptance

```yaml
must:
  - M1: A recovery code pasted with bracketed-paste markers (input b"\x1b[200~GEZD-GNBV-GY3T-QOJQ\x1b[201~\n") reaches the
        verifier as exactly b"VERIFY GEZD-GNBV-GY3T-QOJQ\n".
  - M2: Lookalikes map for recovery input only: with the fixture code "IBEZ-GNBV-GY3T-QOJQ", the input "18EZ-GNBV-GY3T-Q0JQ"
        (digits 1, 8, 0 for I, B, O) reaches the verifier as exactly b"VERIFY IBEZ-GNBV-GY3T-QOJQ\n"; the 6-digit code
        "108080" reaches it as exactly b"VERIFY 108080\n".
  - M3: Every prompt write (first prompt and the re-prompt after Ctrl-C) begins with b"\x1b[?2004l".
  - M4: A local format rejection prints the hint text "letters A-Z, digits 2-7"; a verifier NO prints "Invalid code"
        followed directly by a newline, with no hint text.
  - M5: The existing gate tests stay green, including test_gate_recovery_input_normalization_and_cap (21 real characters
        still overflow and are not sent).
must_not:
  - N1: Must not reject a bracketed-paste recovery code locally. Red today: the M1 input overflows the 20-byte cap,
        prints "Invalid code" and sends nothing to the verifier.
  - N2: Must not reject a recovery code typed with 0/1/8 for O/I/B locally. Red today: rejected by the [A-Z2-7]{16} check,
        nothing sent.
  - N3: Must not send any ESC byte or escape-sequence byte to the verifier, and must not count escape bytes toward the cap.
        Red today: an arrow key (b"\x1b[D") typed inside a 16-character code puts ESC, "[" and "D" into line_buf, so the
        input fails the format check and nothing is sent; the M1 input is rejected as overflow.
evidence:
  - {id: E1, proves: [M1, M2, M3, N1, N2, N3], kind: offline, intent: "A recovery code you paste, or type with 0/1/8 for O/I/B, gets through the console prompt to the verifier, and a 6-digit code is never altered", command: "python3 -m pytest -q scripts/tests/bin/test_web_console_totp.py -k 'gate_recovery_paste_and_lookalikes' (new test: fake verifier socket as in :3273, captures each VERIFY line; inputs: bracketed paste, arrow key inside the code, digit 0/1/8 lookalikes, '108080'; asserts the captured lines exactly and that every prompt write starts with ESC[?2004l)", red_control: "the new test fails on k3d-manager-v1.45.1@13fb1725: no VERIFY line captured for the paste and lookalike inputs, and the prompt bytes lack ESC[?2004l; positive control in the same test: a plain typed code and '108080' are captured on both pre-fix and post-fix code"}
  - {id: E2, proves: [M4, M5], kind: offline, intent: "When the console refuses what you typed, it tells you a code's form, but never whether a well-formed code was valid", command: "python3 -m pytest -q scripts/tests/bin/test_web_console_totp.py -k 'gate' (whole gate group) plus the new test's message asserts: a 5-character input prints the hint; a fake-verifier NO prints b'\\nInvalid code\\n' exactly", red_control: "the hint assert fails on 13fb1725 (no hint text); the NO assert passes on both (regression guard)"}
  - {id: E3, proves: [M4], kind: offline, intent: "The how-to tells you that a recovery code can be pasted or typed with lookalikes, and what each Invalid code message means", command: "grep -n 'pasted' docs/howto/web-console-totp.md && grep -n 'A-Z' docs/howto/web-console-totp.md && make check-doc-links", red_control: "the greps find nothing in the recovery section on 13fb1725"}
  - {id: E4, proves: [N1], kind: live, intent: "On the hub, a recovery code pasted at the browser or Terminal console prompt logs you in", command: "operator on m5-air after promote and make install-web-console-totp: ssh -p 42722 with the test cert, paste one recovery code at Code:, login works; sudo totpctl recovery-status drops by one; Claude checks the log grew by the two recovery lines", red_control: "the 2026-11-25 L2 attempt (pasted code refused, no totpd line)"}
interface:
  - "gate prompt bytes: b'\\x1b[?2004l' + existing prompt; local rejection message: 'Invalid code (6 digits, or a 16-character recovery code: letters A-Z, digits 2-7)'; verifier NO message unchanged; VERIFY wire format unchanged"
```

## Worker definition of done

- Change only the three files above. Offline only: no sudo, no install, nothing under `/etc`, `/Library` or `/var`; no
  real totpd or tmux beyond what the existing test fixtures start under a scratch directory.
- Show E1 and the E2 hint assert red against `13fb1725` before the fix, then green; run the whole
  `scripts/tests/bin/test_web_console_totp.py` and `make check-doc-links`; `python3 -m py_compile` the gate with the
  hub interpreter if present (`/Library/Developer/CommandLineTools/usr/bin/python3`).
- Leave changes uncommitted; do not push. Claude commits, lands and owns the memory-bank update.
