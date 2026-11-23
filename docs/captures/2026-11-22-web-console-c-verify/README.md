# web-console C (TOTP gate): independent offline verification, 2026-11-22

Verifier: Claude (Sonnet subagent), from `## Acceptance` only, throwaway worktree at `3fad525c`, every run under the
sudo/launchctl-deny sandbox-exec profile; worktree `git status --short` empty afterwards.

| Item | Result | Red control |
|---|---|---|
| E1 | pass | base: pytest 142 errors, bats 34/34 not ok; mutants no replay check, window 3, no lockout, `==` for compare_digest, state written in place: all red |
| E2 | pass | no launchctl pid check, no listener uid0 check, no listener chain tail: red; peer-uid check at top of `admit` removed: survives (later chain uid check still rejects; not a named mutant) |
| E3 | pass | base red by absence; named E3 mutants not run |
| E4 | pass | no reply deadline, no tmux timeout, ISIG left on, attach -d, attach without -E: red |
| E5 | pass | TCSADRAIN restore, new-session -t work, attach -d: red; blocking relay, finally cleanup, list-clients polling, lock-after-time not run |
| E6 | pass | env python3 shebang, -S removed: red |
| E7 | pass | no TMUX refusal, no root refusal, uid from EUID: red |
| E8 | pass | gate before daemon, custody check removed, console_port from env, plist without KeepAlive, agents.hub.list entry, tmux from command -v: red; unmutated control 34/34 ok |
| E9 | pass | base: how-to missing (test -f exit 1); doc-links OK |
| E10, E11 | not run | live, owed (need part B's Access path) |

Totals: pytest 142 passed; `web_console_totp.bats` 34/34; `web_console_sshd.bats` 58, `machine_setup_acceptance` 49,
`agent_classification` 3, `launchd_plist_path` 9 all pass. `machine_setup.bats` test 95 (tty_machine timeout) fails
on this head and on the base extract too: pre-existing, not part C.

Weaknesses (not acceptance failures): the D4 peer-uid mutant survives; several named mutants for E3, E5 (N4, N12
partly) were not run; the how-to's R-DENIAL wording is awkward to satisfy greps.
