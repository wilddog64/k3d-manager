# Bug: root installers run directly (not through `k3dm-verified-stage run`) take the caller's environment

**Status:** OPEN
**Priority:** P3 — hygiene; the supported path (`k3dm-verified-stage run`, R2) scrubs the environment, this covers direct runs only
**Introduced by:** v1.45.0 plans 2c, web-console A and C
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-23
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); parent [2026-11-23-root-installers-source-writable-checkout.md](2026-11-23-root-installers-source-writable-checkout.md) — deferred from its rev 2 scope (operator, 2026-11-23: "Cut to ~8 files")
**Filed:** 2026-11-23
**Detected by:** Fable review of R2 rev 1 (B1-B6) and round 2 (S8 scope cut)

## What is wrong

R2 rev 3 (parent) makes `k3dm-verified-stage run` the supported way to run `k3dm-web-console-sshd`, `k3dm-web-console-totp`
and `k3dm-promote-authority`. Running them any other way (`bin/<tool>`, `<stage>/bin/<tool>`, `make install-web-console-*`,
`make promote-authority-install`) gets none of `run`'s scrub. This is the parent's residual 6. Reproduced paths (parent,
External behaviour): `CDPATH` (P7), `SCRIPT_DIR` (P14), `BASH_ENV`/exported functions/`SHELLOPTS` without `-p` (P6),
`POSIXLY_CORRECT` (P16), PATH lookups in promote-authority, `K3DM_WC_ROOT` fixture mode, and the 60-minute sudo ticket left after
an install (P9).

## Deferred items (rev 2 numbering of the parent)

- **F2.1 / F3.1:** shebang `#!/bin/bash -p` on the three installers.
- **F3.2:** promote-authority first statements: `export PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `unset CDPATH POSIXLY_CORRECT`,
  `unset -f sudo`, `SCRIPT_DIR` set before `source` (N7, E6; E6 must name the verb `print-plan`).
- **F2.3:** `_wc_fixture_gate` refuses fixture mode for a script under `/private/var/db/k3dm-verified` (N9, E8).
- **F2.4:** `_wc_priv_close` (`sudo -k`) at web installer exit (M8, web part of E9).
- **F3.5:** promote-authority `sudo -k` in its EXIT traps; tests must use a stand-in, never the real `/usr/bin/sudo -k`, which
  drops the developer's ticket (Fable round 2 S5).
- **New test file:** `scripts/tests/bin/web_console_verified_stage.bats`, Darwin-only skip.
- **Howtos:** `docs/howto/web-console-sshd.md` and `web-console-totp.md` sections on `stage`/`run`; keep the R-INSTALL/R-SUDO
  tokens that `web_console_sshd.bats:117-127` greps for. Coordinate with R3 `totp-c`.
- **Q8:** `make install-web-console-*` and `make promote-authority-install` recipes; changing them breaks the recipe assertions in
  `web_console_sshd.bats:1122-1135` and `web_console_totp.bats:114-119`.

## Expected

A direct run either refuses or behaves like `run` for the environment paths above.

## Notes

- Fable round 2 judged the `K3DM_WC_ROOT` gate low value once `run` drops the variable; re-check before speccing it.
- Fable round 2 nit: a `[[ $- == *p* ]]` refusal does not help, because `BASH_ENV` runs before the script's first line.
