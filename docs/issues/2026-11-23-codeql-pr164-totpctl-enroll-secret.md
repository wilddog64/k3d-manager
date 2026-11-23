# CodeQL on PR #164: totpctl enrollment secret flagged as clear-text storage

**Date:** 2026-11-23
**PR:** #164 (v1.45.0 release)
**Alerts:** code-scanning #38 and #39, `py/clear-text-storage-sensitive-data`, high
**Disposition:** false positive, dismissed (operator approved 2026-11-23: "approved")

## Finding

CodeQL flagged `scripts/libexec/k3dm-console-totpctl.py:98-99`:

- `fout.write(f"Secret: {secret}\n")`
- `fout.write(f"URI: {uri}\n")`

## Why it is intended

`totpctl enroll` / `rotate` must show the newly generated TOTP secret once so the operator can add it to an
authenticator app. The web-console C spec (`docs/plans/v1.45.0-web-console-c-totp-gate.md`, Behaviour 2, line 69)
requires the root process to open `/dev/tty` itself and print the base32 secret and the `otpauth://` URI there only;
neither goes to stdout, stderr, argv, the environment or a log. N5 (by absence, E3) covers stdout, argv, subprocess
argv and temp files. `fout` is the opened `/dev/tty` (tests inject a stream through `tty_out`).

The only stored copy is the daemon's `state.json` (`0600`) under `/var/db/k3dm-web-console` (`root:wheel`, `0700`),
which is the design's secret store, not this write.

## Why no code change

Removing the display would make enrollment impossible. Any rendering (QR, URI) still carries the secret, so CodeQL
would flag it the same way.

## Process note

Python code that deliberately shows a secret to a terminal will trip this query. Note the expected alert in the
spec's review section so the release PR does not stall on it.
