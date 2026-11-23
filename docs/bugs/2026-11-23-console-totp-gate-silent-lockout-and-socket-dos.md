# Bug: console TOTP gate: flat silent lockout allows slow brute force and operator lockout; world-writable socket

**Status:** OPEN — captured 2026-11-23
**Priority:** P2
**Introduced by:** v1.45.0 web-console plan C (`1026dbe2`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** the second factor weakens over time unobserved (about 0.4%/day for a cert holder); a cert holder or same-uid process can keep the operator out.
**Findings:** Fable 2 (Medium), Fable 8 (Low). Claude: plausible (constants read; not reproduced: needs root daemon), P2.

## What is wrong

- `scripts/libexec/k3dm-console-totpd.py:789-805`: 5 failures lock for 300 s, then reset (`:744-770`); window ±1 step (`:173-187`).
  About 1,440 guesses a day at 3 in 10^6 each. Failed codes and locks are not logged, counted or alerted (`log_event` call sites).
- No `RevokedKeys` in `scripts/etc/ssh/k3dm-web-console_sshd_config.tmpl`; only the whole-console revoke.
- `:397` sets `totp.sock` to 0666 with 4 admit slots (`:515-525`): a same-uid connect loop blocks console login (it cannot guess).

## Fix direction

Escalating lock (5 min, 30 min, 4 h, then re-enrol); a log line and Pushgateway counter per failure and lock, alert on any lock;
`RevokedKeys` in the template and expected-lines list; short-lived certs; socket 0600 owned by the console uid.

## Operator probe

`ssh-keygen -L -f <console cert>`: certificate validity period.
