# Web console part B capture kit — a2: browser side (recorder, supervisor, c8/c9, root-checks, end-to-end)

**Status:** LANDED 2026-11-28 (`7ddd5b52`, Luna, 2 runs; Claude verified outside the sandbox: make test-pytest 3135 passed, own mutant real-HOME caught; P3 gap filed `docs/bugs/2026-11-28-wcb-capture-c8-cloudflared-guard-call-untested.md`) — child of [`web-console-b-capture-kit.md`](web-console-b-capture-kit.md) rev 3; dispatch approved 2026-11-28;
starts after `a3` lands (uses a1's `isolation`/`requests` and a3's `filters`/`scan` and CLI)
**Filed:** 2026-11-27
**Intent approved:** operator, 2026-11-27
**Intent approval words:** "agree, and itents approved" (parent K-E1..K-E10; this child carries K-E2, K-E3, K-E6b and
K-E4e, intents unchanged)
**Approval:** operator, 2026-11-27 ("can this task split across Luna/Terra/Flash? worth a try?", then "go ahead")
**Release / branch:** v1.47.0, carried enabling work of v1.45.0 plan 4 part B, outside the cap (operator 2026-11-28, rule `docs/process/rules.md#enabling-work`); `k3d-manager-v1.47.0`
**Risk:** high (decides whether a capture counts; the recorder is what Safari shows)
**Implementer:** Luna (`codex`, `--model gpt-6-luna`). **Verifier:** Claude, from Acceptance.

## Before You Start

1. Read the parent's §4 (profiles), §5 (recorder), §6 (supervisor), §8 (`c8`, `c9`), §9 (`root-checks`), `## Method
   changes`, `## Contract between children` and `## What NOT to Do`.
2. Read the landed `isolation.py`, `requests.py`, `rootd.py` (a1) and `filters.py`, `scan.py`, `bin/k3dm-wcb-capture`
   (a3); use them, do not reimplement them.
3. Read `docs/captures/2026-11-19-web-console-c/c14-raw.txt` (raw control bytes over a real pty) and
   `docs/captures/2026-11-19-web-console/sshd-prod.log` (sshd log shape, no timestamps).
4. Python 3.9-compatible, stdlib only; the recorder's first line is
   `#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS`. Never run `sshd`, `ssh`, `ssh-keyscan`, `cloudflared`,
   `sudo` or `launchctl` for real; stubs are injected by constructor argument.

## Behaviour (scope)

- `recorder.py`: §5 for every profile in §4's table, with the attended start, previous-session question, terminal modes,
  timeouts as constructor arguments (short in tests), c5 idle hold, c4 inspection and void rule, c15 question, markers.
- `supervisor.py`: §6 (sequence, connector line and token-file check, request submission through `requests.submit`,
  "up" read from `root-steps.log`, result/skip/stop commands, re-offer on abandoned, byte-offset sshd slices, the c15
  field-2 fingerprint comparison and void rule, resume at the first profile without `done-*`).
- `c8c9.py`: §8 `main_c8` (close-tabs prompt, scratch `HOME`, slices, fail/candidate-pass/void, all-void summary, (d)
  recorded `not run` when the method is unavailable) and `main_c9` (steps 1-6 with timestamps, `c9-hold` heartbeat
  reading, private-tab prompt for step 2, `dscacheutil` check through an injected runner).
- `rootchecks.py`: §9 (C13(c) through `up-c13-ca1`/`up-c13-ca2` requests and a local client stub, C7 key generation in
  `(1)/ca/` and `install-c7-key`, outputs as exit codes).
- `scripts/tests/bin/test_wcb_capture_e2e.py`: the parent's K-E4 e2e run: every subcommand of the CLI against recording
  stubs for `launchctl`, `sudo`, `netstat`, `sshd`, `curl`, `security`, `cloudflared`, `ssh`, asserting K-N1.

## Files

| File | Change |
|---|---|
| `scripts/lib/wcb_capture/recorder.py` | new |
| `scripts/lib/wcb_capture/supervisor.py` | new |
| `scripts/lib/wcb_capture/c8c9.py` | new |
| `scripts/lib/wcb_capture/rootchecks.py` | new |
| `scripts/tests/bin/test_wcb_capture_browser.py` | new |
| `scripts/tests/bin/test_wcb_capture_e2e.py` | new |

## What NOT to Do

- No file outside `## Files`; do not edit a1's or a3's modules (a needed change is raised to Claude).
- The recorder never starts a shell and never executes or evaluates input.
- `c8` never reports anything other than `fail` when the sshd slice for (a) or (d) shows a connection; it never decides
  `pass` (Claude does, from the connector slice).

## Acceptance

```yaml
must:
  - id: K-M2
    text: "as the parent's K-M2"
  - id: K-M3
    text: "as the parent's K-M3"
  - id: K-M6
    text: "as the parent's K-M6"
must_not:
  - id: K-N1
    text: "as the parent's K-N1"
  - id: K-N5
    text: "as the parent's K-N5"
evidence:
  - id: K-E2
    proves: [K-M2]
    kind: offline
    command: "the parent's K-E2 in scripts/tests/bin/test_wcb_capture_browser.py, with its red controls (a)-(b)"
    intent: "When you log in from Safari, the screen tells you exactly what to press and records it for you; if a session reconnects by itself while you are away, it is not counted as one of your tests."
  - id: K-E3
    proves: [K-M3, K-N5]
    kind: offline
    command: "the parent's K-E3, with its red control"
    intent: "The Mac switches its test setup between your logins by itself, and a host-key test that would give a false answer is thrown out instead of counted."
  - id: K-E6b
    proves: [K-M6, K-N5]
    kind: offline
    command: "pytest -k c8: over byte-offset slices of fixture logs, fail when the (a) sshd slice shows a connection, candidate-pass for a clean (a) with (b) and (c) reached, void when (c) fails, all-void summary. Red control: make c8 return candidate-pass when sshd saw (a) — a named test fails"
    intent: "The enforcement test can only pass when the evidence really shows it, the staging step uses exactly the reviewed commit, and one command cleans everything up afterwards."
  - id: K-E4e
    proves: [K-N1]
    kind: offline
    command: "python3 -m pytest scripts/tests/bin/test_wcb_capture_e2e.py -q: every CLI subcommand runs against recording stubs (fixture asserts each stub logged its own invocation and every scratch root is under tmp_path); recorded writes stay inside fake (1)/(2)/collect dir, labels are only capture-sshd, ports only 42723, no cloudflared create/login/--token argv. Red control: make one subcommand write outside (1) — the e2e test fails. Then ruff on the four new modules and two test files rc 0; CLT python3 -IS -m py_compile rc 0; make test-pytest rc 0"
    intent: "The part that runs as root only does the few things it is built for, only from files you could not have tampered with, never deletes or writes in your own scratch folder, and can never touch your real web console."
interface: "recorder (profile argv), supervisor.main, c8c9.main_c8, c8c9.main_c9, rootchecks.main as in the parent's Contract between children."
```

## Worker definition of done

Report each command, its rc and the proving lines; show each red control failing and `git diff --stat` after restoring
it; list every error seen. Run the tests under `/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin` as well. Commit
nothing; Claude lands.
