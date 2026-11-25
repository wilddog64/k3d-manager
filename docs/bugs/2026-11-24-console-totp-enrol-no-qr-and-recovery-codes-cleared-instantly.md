# Bug: console TOTP enrolment shows no QR code, and the recovery codes are wiped from the screen the instant they appear

**Status:** OPEN — spec rev 2, 2026-11-24 (rev 2: Fable review NEEDS FIXES applied — Python 3.9 syntax, pty harness, UNAVAILABLE pause, QR constants, SGR form, window height, type-ahead, Ctrl-C, how-to lines, CodeQL note)
**Priority:** P2 (enrolment works only by hand-typing a 32-character secret, and the ten recovery codes cannot be saved; workaround: phone app "Enter a setup key", and `totpctl recovery-regen` later, which has the same instant clear)
**Triage:** patch → v1.45.1 (blocks the operator's first enrolment and the TOTP live checks of the open release)
**Branch:** k3d-manager-v1.45.1
**Introduced by:** totp-a (enrol design: codes printed then cleared in `finally`); no QR since the start
**Should have been caught by:** spec (no step said the operator must be able to copy the codes before the clear; no scannable form was asked for)
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-24
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
- Reference QR matrices: segno 1.6.6 (scratch venv on m4-air, 2026-11-24), `segno.make(uri, version=6, error='L', mode='byte',
  mask=0, boost_error=False)`; the URI form is `otpauth://totp/k3dm-console-<host>?secret=<32>&issuer=k3dm-console` (88 bytes + host).
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

segno 1.6.6, version 6, error L, byte mode, mask 0, m4-air 2026-11-24. Secret `JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP` is the
RFC-example test value, not a real secret. Each row is 41 bits as 11 hex digits, most significant bit = leftmost module.
Put them in the test with this provenance comment.

```text
# len=94 otpauth://totp/k3dm-console-m5-air?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=k3dm-console
1fcaccaee7f
104e6777e41
175cdffc05d
1743fffc25d
1746d55de5d
104a3f3ee41
1fd5555557f
001eaaaef00
1df8009ddc4
0916bc9c149
0e445444065
13aceeffc51
13fd77559e0
1c2bfffe149
124bf7300eb
1e0d99dfca2
0af322bd8cf
1d3b73518ea
075d9889cef
0cba2103c12
02d80003ae9
193eaaa18c9
017cc001cb7
090eeeafc71
1c6c00cbbce
0e93fbd9160
194544448cf
0397ccddd32
07fd5577bc8
0e17f77d14f
1347b7348c7
0d85d9ddf83
15ff222bbfe
001b4701312
1fd48998b57
10540000b10
175020019f3
174a2a21618
175044c4997
1052eaac9aa
1fd4d108903
# len=128 otpauth://totp/k3dm-console-hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=k3dm-console
1fcbee66e7f
104a6ea7a41
175d115045d
174045dde5d
1748ef8885d
1048babbf41
1fd5555557f
001d8888f00
1dff9999dc4
0f39111094b
167f1d54467
113faeaf8d1
17c3ae2c1d1
05af1547301
1ac754451cf
0f959b88eb2
084bb9b98c3
170999990e9
0fed1d5dc6f
1fa2eeafc51
16ea7bf3eda
12921133f09
15484455dbb
15969ba8f51
17f1b99b9ca
1a159999961
0d695190ccd
1326aaa9d72
1c7f7aa33e8
092b113772b
16d744558d3
0f1988aac82
15d799b99f1
00111119b13
1fd99154757
105e2ee8b12
17523eb01f0
174e1173612
1758444599c
1052b8ba9e2
1fddb99a9cb
```

## Worker definition of done

- Change only the three files (and only the parts the Files table allows). Offline only: no sudo, no install, no real admin socket, nothing under `/etc` or `/Library`.
- Show N1, N4 and the E1 matrix case red against the pre-fix file first, then green; the whole `test_web_console_totp.py` and `web_console_totp.bats` green.
- Leave changes uncommitted; do not push.
