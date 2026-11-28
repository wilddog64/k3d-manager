# Web console part B capture kit — a1: root side (root driver, isolation, stage, templates)

**Status:** SPEC — child of [`web-console-b-capture-kit.md`](web-console-b-capture-kit.md) rev 3 (Fable + Neon reviewed rev 1,
Fable re-reviewed rev 2); not dispatched
**Filed:** 2026-11-27
**Intent approved:** operator, 2026-11-27
**Intent approval words:** "agree, and itents approved" (parent K-E1..K-E10; this child carries K-E4a, K-E6a and K-E7a,
the parent's K-E4, K-E6 and K-E7 restricted to this child's files, intents unchanged)
**Approval:** operator, 2026-11-27 ("can this task split across Luna/Terra/Flash? worth a try?", then "go ahead")
**Release / branch:** v1.47.0 plan 2 (operator 2026-11-28: "Slot now, displace plan 2"); `k3d-manager-v1.47.0`
**Risk:** high (code that runs as root on m4; in this slice nothing runs as root: every privileged call is stubbed)
**Implementer:** Terra (`codex`, `--model gpt-6.1-terra`; confirm the `model:` line in the run's `codex.log`). Runs
first, alongside `b`. **Verifier:** Claude, from Acceptance.

## Before You Start

1. Read the parent's §1 (isolation), §3 (stage and root driver), §4 (profiles, baseline, read-back gate,
   `principals-any`), `## Contract between children` and `## What NOT to Do`. They are the behaviour; this file only
   scopes it.
2. Read `docs/captures/2026-11-19-web-console/c17-readback.txt` (the `sshd -T` read-back shape your gate normalises) and
   `docs/captures/2026-11-19-web-console/root-steps.log` (log format).
3. Python 3.9-compatible, stdlib only. Confirm with
   `/Library/Developer/CommandLineTools/usr/bin/python3 -IS -m py_compile <file>`.
4. Never run `sudo`, `launchctl`, `sshd`, `ssh-keygen` against real system paths, `cloudflared` or `security`. Tests
   stub every external command through constructor arguments, never `PATH` or environment variables.

## Behaviour (scope)

- `isolation.py`: every public function in the contract, both modes (`operator`, `root`), the realpath deny-list and
  allow-list of §1, structural `cloudflared` argv parsing, `refuse_multiplexer` (TMUX, STY, ancestor `tmux`/`screen`).
  The production label prefix is built at run time (`"com.k3d-manager." + "web-console-"`).
- `requests.py`: `submit(verb)` with the lock and sequence rule of the contract.
- `rootd.py`: the whole of §3's root driver and `--teardown`, §4's read-back tables (normalised, per profile, required
  and forbidden), first-host-key generation, `rekey`, `install-ca`, `install-c7-key`, the `c13-ca1`/`c13-ca2` CA switch
  without restart, the definition of "up", signals and lifetime, blob-id verification against `--expect`. All roots, the
  uid-0 owner check, the clock and the timeouts are constructor arguments of a `RootDriver` class; `main()` builds the
  production instance and accepts no argv or environment override of them.
- `stage.py`: §3 stage (dirty-tree refusal for the kit paths, `git show` of HEAD, blob ids, the confirmation prompt,
  `install` with owners and modes through an injected runner, the printed driver line with `--expect`, creation of the
  empty `zdotdir`).
- Templates: `sshd_config.base` (§4 baseline with placeholders `rootd` fills), `capture-sshd.plist` (`RunAtLoad` true, no
  `KeepAlive`, stderr to `(2)/sshd.log`), `principals-any` (invoked as `principals-any <login> %u %t %k`).
- `scripts/etc/machine/not-installed.list`: one row `capture-sshd|not installed by setup: scratch LaunchDaemon bootstrapped
  from /private/var/db/k3dm-capture-<date>/ by bin/k3dm-wcb-capture during part B captures, removed by its down
  (docs/plans/web-console-b-capture-kit.md)`.

## Files

| File | Change |
|---|---|
| `scripts/lib/wcb_capture/isolation.py` | new |
| `scripts/lib/wcb_capture/requests.py` | new |
| `scripts/lib/wcb_capture/rootd.py` | new |
| `scripts/lib/wcb_capture/stage.py` | new |
| `scripts/lib/wcb_capture/templates/sshd_config.base` | new |
| `scripts/lib/wcb_capture/templates/capture-sshd.plist` | new |
| `scripts/lib/wcb_capture/templates/principals-any` | new |
| `scripts/etc/machine/not-installed.list` | add the `capture-sshd` row |
| `scripts/tests/bin/test_wcb_capture_root.py` | new |

## What NOT to Do

- No file outside `## Files` (a3 creates `scripts/lib/wcb_capture/__init__.py`; until then your tests add
  `scripts/lib/wcb_capture` to `sys.path` themselves).
- No argv or environment variable may change roots, the owner check, the clock or timeouts.
- `rootd` never writes, renames or unlinks anything in (1); never executes or imports a file that is not root-owned.
- Do not weaken a check to make a test pass.

## Acceptance

```yaml
must:
  - id: K-M4
    text: "as the parent's K-M4"
  - id: K-M7a
    text: "stage refuses a dirty kit tree, installs from git show of the commit with root:wheel ownership and the stated modes, and prints commit and blob ids; rootd --teardown boots out the label, confirms 42723 free, removes (2) only on the exact path pattern, works without (1), takes the lock, and is idempotent"
  - id: K-M8
    text: "as the parent's K-M8, for isolation's functions"
must_not:
  - id: K-N3
    text: "as the parent's K-N3"
  - id: K-N6
    text: "as the parent's K-N6"
evidence:
  - id: K-E4a
    proves: [K-M4, K-M8, K-N3, K-N6]
    kind: offline
    command: "python3 -m pytest scripts/tests/bin/test_wcb_capture_root.py -q -k 'rootd or isolation': every case of the parent's K-E4 except the e2e run (that is a2's K-E4e). Fixtures assert fake (1)/(2) are under tmp_path and every stub logged its own invocation. Red controls (a)-(f) of the parent's K-E4, each restored byte-identical"
    intent: "The part that runs as root only does the few things it is built for, only from files you could not have tampered with, never deletes or writes in your own scratch folder, and can never touch your real web console."
  - id: K-E6a
    proves: [K-M7a]
    kind: offline
    command: "pytest -k 'stage or teardown': stage refuses a dirty tree; with stub git, sudo and install it installs from git show with root:wheel and the stated modes and prints blob ids and the driver line with --expect; teardown without (1) present removes a fake (2) matching the pattern, refuses one outside it, refuses while the lock is held, and a second run exits 0. Red control: stage from the working tree — a named test fails"
    intent: "The enforcement test can only pass when the evidence really shows it, the staging step uses exactly the reviewed commit, and one command cleans everything up afterwards."
  - id: K-E7a
    proves: [K-M4]
    kind: offline
    command: "ruff check -- scripts/lib/wcb_capture/isolation.py scripts/lib/wcb_capture/requests.py scripts/lib/wcb_capture/rootd.py scripts/lib/wcb_capture/stage.py scripts/tests/bin/test_wcb_capture_root.py rc 0; CLT python3 -IS -m py_compile on each .py rc 0; bats scripts/tests/bin/agent_classification.bats rc 0; make test-pytest rc 0"
    intent: "The kit runs on the Mac's built-in Python, passes the repo's checks, and the step-by-step guide and the two corrected plans say what the kit actually does."
interface: "isolation, requests, rootd (RootDriver, main), stage (main) as in the parent's Contract between children."
```

## Worker definition of done

Report each command, its rc and the proving lines; show each red control failing and `git diff --stat` after restoring
it; list every error seen. Run the tests under `/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin` as well. Commit
nothing; Claude lands.
