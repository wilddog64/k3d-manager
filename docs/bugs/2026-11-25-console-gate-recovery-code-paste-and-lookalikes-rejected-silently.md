# Bug: the console gate rejects a pasted recovery code (and 0/1/8 lookalikes) as "Invalid code" without saying why

**Status:** OPEN
**Priority:** P2 (proposed) — degraded: a recovery code works only when typed by hand, blind, with the right letters; the
person using one is already locked out
**Introduced by:** totp-a2 (`93ecfb83`, recovery codes at the gate prompt)
**Should have been caught by:** spec (no case for pasted input or lookalike characters at the echo-off prompt)
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-25
**Prior art:** `ls docs/bugs/*recovery*` none; `make find-similar-docs` not run — none above threshold
**Filed:** 2026-11-25
**Detected by:** operator + Claude, v1.45.1 L2 live check on m5-air, 2026-11-25

## Observed

- A recovery code pasted at the console `Code:` prompt was refused with "Invalid code"; the totpd log has no
  `totp-recovery-failure` line (log bytes fully accounted for), so the gate rejected it before asking the verifier.
- The same code typed by hand passed (`~/k3dm-code-check.py`, a scratch checker that reads input exactly like the gate:
  echo off, byte by byte, 20-byte cap; reports structure only). The real login with it then worked (count 10 → 9).

## Cause (code read, `scripts/libexec/k3dm-console-gate.py:291-352`)

- The prompt keeps at most 20 bytes and calls anything longer an overflow ("Invalid code"). A paste wrapped in
  bracketed-paste markers (`ESC[200~` … `ESC[201~`, 12 bytes) is 31 bytes for a 19-character code. Not confirmed live
  (the operator did not run the paste case in the checker).
- Normalisation removes spaces and dashes and upper-cases, but a digit 0/1/8 typed for the letter O/I/B fails
  `[A-Z2-7]{16}` (checker offline cases, 2026-11-25).
- Format rejection and a verifier "NO" print the same "Invalid code", and echo is off, so the person cannot tell what went
  wrong.

## Expected

The gate strips terminal escape sequences (bracketed-paste markers) before the length check, maps 0→O, 1→I, 8→B for
recovery-format input, and on a format rejection says "Recovery codes are 16 characters, letters A-Z and digits 2-7"
(without revealing whether a well-formed code was valid).

## Workaround

Type the recovery code by hand; use the letters O and I.
