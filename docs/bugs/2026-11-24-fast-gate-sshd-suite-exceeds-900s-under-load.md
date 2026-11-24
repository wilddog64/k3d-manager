# Fast gate: `web_console_sshd.bats` takes ~580 s idle and exceeds the 900 s suite limit under host load

**Status:** OPEN — captured 2026-11-24, not triaged
**Priority:** P3 (test/gate only; the installer behaves correctly; a land retry on a quieter host passes)
**Introduced by:** unknown (the suite grew with v1.45.0 and R3 `totp-b` `d6e1e7a6`; the limit is `scripts/ci/fast_gate.sh:29`)
**Should have been caught by:** none
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-24
**Prior art:** slug ls found no match; `docs/bugs/2026-11-23-web-console-bats-lock-busy-test-races-10s-stale-window.md` (read, same suite family under load, different cause: a lock-age race, not run time); `make find-similar-docs` not run (vector store unavailable on m4)

## Symptom

`land` of `r2-b-web-installers-clt-git` on 2026-11-24 (m4-air, load average ~7 with an independent verifier and two
dispatch workers running) failed the fast gate after rebase: `FAIL scripts/tests/bin/web_console_sshd.bats 900s`,
`timed out after 900s`, with the TAP stream stopped after test 55 of 61. The same suite had passed in full under the
deny-priv sandbox 15 minutes earlier, and test 56 alone passed in 13 s.

## Cause

Not a hang: a timed full run at load ~4 passed 61/61 in **583 s**. The slowest tests: `[M2][M12][N5][N13] journal survives
crashes on both sides of every upgrade rename` 126 s, `[M4] C7 discovers process configs` 75 s, `[M4][N1][N4] local check`
49 s, `[M4][M11] C1 through C10` 48 s. The fast gate gives each suite `FAST_GATE_SUITE_TIMEOUT` (default 900 s,
`scripts/ci/fast_gate.sh:29`), so an idle run already uses about two thirds of it, and host load from parallel agents
pushes it over.

## Fix direction (for triage)

One of, cheapest first: raise the per-suite default for this suite only (an allowlist with its own limit), or split the
four slow tests into a separate suite file, or speed up the slow tests (the journal-crash test re-runs every rename
step; it could sample them). Do not just raise the global default: it hides real hangs in every suite.

## Workaround

Retry `land` when the host is quieter (no verifier or other workers running), or run the suite alone first.
