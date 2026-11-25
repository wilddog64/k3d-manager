# Bug: console TOTP enrolment shows no QR code, and the recovery codes are wiped from the screen the instant they appear

**Status:** LANDED — `6eccd121` on `k3d-manager-v1.45.1` (2026-11-24); verify pass (independent Sonnet verifier, 11/15 red on 0420904b); E4 live pending (operator enrol on m5-air after promote). Spec rev 3.
**Priority:** P2 (enrolment works only by hand-typing a 32-character secret, and the ten recovery codes cannot be saved; workaround: phone app "Enter a setup key", and `totpctl recovery-regen` later, which has the same instant clear)
**Triage:** patch → v1.45.1 (blocks the operator's first enrolment and the TOTP live checks of the open release)
**Branch:** k3d-manager-v1.45.1
**Introduced by:** totp-a (enrol design: codes printed then cleared in `finally`); no QR since the start
**Should have been caught by:** spec (no step said the operator must be able to copy the codes before the clear; no scannable form was asked for)
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** "go ahead to make the change: option 1" (option 1 = enrolment shows the QR code itself and pauses on the recovery codes until Enter)
**Prior art:** `ls docs/bugs/*totp*` → three TOTP bugs (tests connect-before-listen, A1 decay, silent lockout/socket DoS), all different root causes; `make find-similar-docs` not run (vector store not reachable from m4) — read, different root cause
**Detected by:** operator, first enrolment on m5-air, 2026-11-24: clicking the `URI:` line opened Passwords.app's file import; no way to add the code without hand entry; Claude read the code path and found the codes are cleared with no pause (`scripts/libexec/k3dm-console-totpctl.py`, `finally` after the commit)

## Evidence (code read, Claude, 2026-11-24)

- Enrol/rotate (`k3dm-console-totpctl.py`, `cmd in ("enroll", "rotate")`): prints `Secret:` and `URI:`, reads the code, prints
  `Recovery codes (each works once):` and the ten codes, sends the commit, prints `enrolled`, returns; the `finally` writes
  `\x1b[3J\x1b[H\x1b[2J` (clear scrollback, home, clear screen) at once. Same in `recovery-regen` after `recovery codes replaced`.
- totpctl runs as root under `python3 -IS` from `/Library/PrivilegedHelperTools/k3dm-web-console/totpctl` (single file, no site
  packages, `bin/k3dm-web-console-totp:505`). `qrencode` is not installed on m5-air (checked 2026-11-24), and a root helper must not
  run a Homebrew binary the operator's account can replace.
- Reference QR matrices: python-qrcode 8.0, decoded back with zxing-cpp 2.3.0 (scratch venv on m4-air, 2026-11-24; rev 3 —
  segno 1.6.6 pads non-canonically); the URI form is `otpauth://totp/k3dm-console-<host>?secret=<32>&issuer=k3dm-console` (88 bytes + host).
  Version 6-L byte mode holds 134 bytes, so hosts up to 46 characters fit; segno accepted a 41-character host.

## Fix

`scripts/libexec/k3dm-console-totpctl.py` only. It runs on the CommandLineTools `python3`, **3.9.6** on the hub
(`totpctl.py:1`, `bin/k3dm-web-console-totp:12`): no `X | Y` type unions, no `match`, nothing newer than 3.9 that is evaluated
at import. Annotations may be omitted.

1. A pure-standard-library QR encoder inside totpctl (no import outside the standard library, no subprocess, no file written):
   `_qr_matrix(data)` takes bytes and returns a 41×41 list of rows of bools (True = dark) for QR version 6, error level L, byte
   mode, mask pattern 0, or `None` when `len(data) > 134`. Constants (verified against segno 1.6.6 by Fable, 2026-11-24):
   172 total codewords, 2 blocks of 68 data + 18 EC codewords, interleaved; GF(256) primitive polynomial 0x11D, generator of
   degree 18; mode indicator `0100`, 8-bit character count, terminator up to 4 zero bits, pad to a byte, pad bytes `0xEC 0x11`
   alternating; finder patterns at three corners with separators; timing patterns on row 6 and column 6; one alignment pattern
   centred at (34, 34); dark module at (row 33, col 8); 7 remainder bits; format bits for L + mask 0 `111011111000100`; mask 0
   = invert data modules where `(row + col) % 2 == 0`; no version-information block (versions below 7).
2. `_qr_render(matrix)` returns the text to print: a 4-module light quiet zone on every side (49×49 modules); each output line
   covers two module rows; each cell is written exactly as `"\x1b[" + fg + ";" + bg + "m" + "\u2580"` (▀, written as that
   escape in the source) with fg = the top module (`30` dark, `97` light) and bg = the bottom module (`40` dark, `107` light);
   each line ends with `\x1b[0m\n`; the last odd module row pairs with a light row (25 lines).
3. Enrol and rotate print, before `Secret:`, the line `Scan this with your phone's camera or authenticator app:` and the
   rendered QR of the URI (UTF-8 bytes), to `fout` only. When `fout` is a TTY and its height (`os.get_terminal_size(fout.fileno())`)
   is under 34 rows, first print `Enlarge this window to at least 34 rows so the whole QR code is visible.` When `_qr_matrix`
   returns `None`, print `QR not shown (URI too long); enter the Secret line in your authenticator` instead. `Secret:` and `URI:`
   stay as they are.
4. After the commit reply is `OK` (enrol/rotate print `enrolled`; recovery-regen prints `recovery codes replaced`) **or
   `UNAVAILABLE`** (`commit not confirmed; run web-console-totp-status` — the state may be committed, so the codes may be live),
   pause: on a TTY call `termios.tcflush(fin, termios.TCIFLUSH)` (drop type-ahead), write
   `Save the recovery codes now (not on your travel device), then press Enter to clear the screen: `, flush, and read one line
   with `fin.readline(1024)` — on a TTY only after `select` reports it readable within 600 s. EOF, the timeout, `KeyboardInterrupt`
   and `OSError` during the pause all end the pause silently; the function then returns what it would have returned without the
   pause (0 after OK, 1 after UNAVAILABLE), and the existing `finally` clears the screen. On the invalid-code path (commit
   refused, codes void) there is no pause and the clear stays immediate.

`docs/howto/web-console-totp.md`: the enrolment section (around line 18–27) says a QR code appears; enlarge the Terminal window
if needed; scan it with the phone camera or an authenticator app; type the 6-digit code; save the recovery codes; press Enter;
do not click the URI. Lines 93 and 105 (codes shown, then the scrollback is cleared) say the screen clears after you press Enter.
Keep every phrase that `scripts/tests/bin/web_console_totp.bats:49-59` greps for.

Expected CodeQL: the QR write to the tty will probably raise `py/clear-text-storage-sensitive-data` like the existing
`Secret:` line (`docs/issues/2026-11-23-codeql-pr164-totpctl-enroll-secret.md`); it is the same intended tty-only display and is
dismissed the same way, with a reference to this spec.

## Files

| File | Change |
|---|---|
| `scripts/libexec/k3dm-console-totpctl.py` | QR encoder + render; enrol/rotate QR; post-commit pause in enrol/rotate/recovery-regen |
| `scripts/tests/bin/test_web_console_totp.py` | new cases below; the real-pty harness `admin_commit_at_pty` (:1441-1535) may wait for the pause prompt and write `\n` on the success and UNAVAILABLE paths only; no other existing case changes (the regen case at :3059 passes unchanged via EOF) |
| `docs/howto/web-console-totp.md` | enrolment steps; lines 93 and 105 wording |

## Contract readers

The `/dev/tty` dialogue is read only by the operator. Callers: `bin/k3dm-web-console-totp:505,511` (enroll, rotate), reached from
`Makefile:671-675` (`web-console-totp-enroll`, `web-console-totp-rotate`); `totpctl recovery-regen` (how-to). `status --wire`
(read by `_wct_repeat_check`, `bin/k3dm-web-console-totp:259`) is unchanged, but it runs the same file under 3.9.6, so an
import-time syntax error would break install and status too (M7). The installer hash of `totpctl` changes, so a reinstall
replaces it (`:253`). How-to phrases are read by `scripts/tests/bin/web_console_totp.bats:49-59`.

## Acceptance

```yaml
must:
  - M1: _qr_matrix(uri.encode()) equals the reference matrix bit for bit for both reference URIs below.
  - M2: _qr_matrix returns None for 135 bytes and a 41x41 matrix for 134 bytes.
  - M3: _qr_render output, parsed as cells of the exact form "\x1b[<fg>;<bg>m\u2580", equals the matrix padded with a 4-module
        light quiet zone (49 cells per line, 25 lines), every line ending with "\x1b[0m\n".
  - M4: An enrol run (stub admin socket, injected tty) prints the scan line and the QR before "Secret:"; Secret and URI lines unchanged.
  - M5: totpctl imports only standard-library modules and contains no subprocess, os.system, os.exec*, os.spawn* or popen use.
  - M6: Existing cases stay green; the only existing test change is the pty harness answering the pause prompt (Files).
  - M7: totpctl imports and runs "status --wire" against a stub socket under the hub interpreter
        /Library/Developer/CommandLineTools/usr/bin/python3 when that path exists (skip otherwise, with the reason).
must_not:
  - N1: Must not clear the screen after a successful enrol, rotate or recovery-regen before a further line is read from the tty.
        Test: tty_in is a reader object (readline(n), isatty() False) fed the needed lines (code; for regen "yes" then code) that
        records the output length each time readline is called; assert an extra readline happened after the codes, and that the
        clear sequence was absent at that moment and present after. Red today: no extra readline; the clear follows the codes.
        Real-tty form: in admin_commit_at_pty, on the success path, the clear is absent from the pty output before "\n" is written.
  - N2: Must not print an enrolment without a scannable QR when the URI fits (<=134 bytes). Red today: no QR at all.
  - N3: Must not pause on the invalid-code path: the commit is refused, no pause prompt is printed and the clear is immediate
        (control for N1).
  - N4: Must not lose live codes on UNAVAILABLE: after "commit not confirmed" the pause prompt is printed before the clear.
        Red today: immediate clear.
evidence:
  - {id: E1, proves: [M1, M2, M3, N2, M4], kind: offline, intent: "Enrolment shows a QR code your phone can scan, so you never type the secret", command: "python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k 'qr'", red_control: "fails on the pre-fix file: _qr_matrix does not exist; enrol output has no scan line"}
  - {id: E2, proves: [N1, N3, N4], kind: offline, intent: "The recovery codes stay on screen until you press Enter", command: "same file -k 'pause'", red_control: "N1 and N4 cases fail on the pre-fix file (no extra read; clear written at once)"}
  - {id: E3, proves: [M5, M6, M7], kind: offline, intent: "The root helper still runs nothing outside itself, works on the hub's Python 3.9, and nothing else changes", command: "python3 -m pytest scripts/tests/bin/test_web_console_totp.py; bats scripts/tests/bin/web_console_totp.bats", red_control: "not applicable (regression guard); M7 is red if a 3.10-only construct is introduced"}
  - {id: E4, proves: [M4, N1], kind: live, intent: "You enrol on the hub by scanning the screen with your iPhone and can copy the recovery codes", command: "operator on m5-air after promote: make install-web-console-totp, then make web-console-totp-enroll in a plain Terminal window at least 34 rows tall; scan, type code, codes stay until Enter; make web-console-totp-status prints enrolled", red_control: "the 2026-11-24 attempt (no QR; codes cleared at once)"}
interface:
  - "_qr_matrix(data) -> list of 41 lists of 41 bools, or None; _qr_render(matrix) -> str (module-level in totpctl, Python 3.9)"
```

## Reference vectors

python-qrcode 8.0 (`version=6, ERROR_CORRECT_L, mask_pattern=0`, byte mode), each decoded back to the exact URI with zxing-cpp
2.3.0; m4-air, 2026-11-24. Rev 3: replaces the rev 1-2 segno 1.6.6 vectors, which insert a non-canonical `0x00` before the
`EC 11` padding (still decodable, but not the canonical stream). Secret `JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP` is the RFC-example
test value. Each row is 41 bits as 11 hex digits, most significant bit = leftmost module.

```text
# len=94 otpauth://totp/k3dm-console-m5-air?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=k3dm-console
1fca4426e7f
1046abbbe41
1758133005d
1746aaa825d
17468008e5d
10490c0ce41
1fd5555557f
001f999df00
1dfa22bfdc4
08163414149
16c89888065
0a2c2233c51
09ec22019e0
120eaaaa149
1278c4000eb
182eaaefca2
0ef1009d8cf
0c33fbd98ea
0e595445cef
14beedcfc12
03d15557ae9
133ffff58c9
014ff331cb7
0b0ddd9fc71
1c4e22ebbce
1f9b7351160
094188888cf
13970011d32
04640023bc8
0ea2a22914f
154484048c7
0f86eaedf83
11fd000bbfe
0013cf89312
1fdc4554b57
1054ccccb10
175175559f3
174f7f75618
175377f4997
1051d99c9aa
1fd6f328903
# len=128 otpauth://totp/k3dm-console-hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=k3dm-console
1fcbee66e7f
10426ea7a41
1751115045d
174c45dde5d
174bef8885d
1048babbf41
1fd5555557f
001d8888f00
1dff9999dc4
1e31111094b
07771d54467
08b3aeaf8d1
1d42ae2c1d1
0b8a1547301
1ec454451cf
0b869b88eb2
0c49b9b98c3
060999990e9
0f611d5dc6f
06aaeeafc51
046f7bf3eda
1e971133f09
176b4455dbb
13a59ba8f51
17d3b99b9ca
0b151999961
0c659190ccd
022a2aa9d72
06723aa33e8
071e113772b
14d444558d3
0d2a88aac82
11f599b99f1
00199119b13
1fd15154757
105aeee8b12
17577eb01f0
174f5173612
175b444599c
1051b8ba9e2
1fdfb99a9cb
```

## Worker definition of done

- Change only the three files (and only the parts the Files table allows). Offline only: no sudo, no install, no real admin socket, nothing under `/etc` or `/Library`.
- Show N1, N4 and the E1 matrix case red against the pre-fix file first, then green; the whole `test_web_console_totp.py` and `web_console_totp.bats` green.
- Leave changes uncommitted; do not push.
