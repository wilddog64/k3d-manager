# Web console part B capture kit — a3: data side and CLI (api, filters, scan, collect, down)

**Status:** SPEC — child of [`web-console-b-capture-kit.md`](web-console-b-capture-kit.md) rev 3; not dispatched;
starts after `a1` lands (imports `isolation`)
**Filed:** 2026-11-27
**Intent approved:** operator, 2026-11-27
**Intent approval words:** "agree, and itents approved" (parent K-E1..K-E10; this child carries K-E1, K-E5 and K-E6c,
intents unchanged)
**Approval:** operator, 2026-11-27 ("can this task split across Luna/Terra/Flash? worth a try?", then "go ahead")
**Release / branch:** unslotted (v1.47.0 candidate, groom 2026-11-29); `k3d-manager-v1.47.0` once slotted
**Risk:** high (handles the Cloudflare capture token and decides what private data reaches the repo)
**Implementer:** Luna (`codex`, `--model gpt-6-luna`). **Verifier:** Claude, from Acceptance.

## Before You Start

1. Read the parent's §1 (where and when, tmux refusal, capture header), §2 (`api`), §7 (filters, scan, collect), §10
   (`status`, `down`), `## Contract between children` and `## What NOT to Do`.
2. Read `scripts/lib/wcb_capture/isolation.py` (landed by a1) and use its functions; do not reimplement them.
3. Read `docs/captures/2026-11-19-web-console/` (`sshd-prod.log`, `c17-readback.txt`, `root-steps.log`): K-E5 must show
   filtered copies of them pass the scan.
4. Python 3.9-compatible, stdlib only. Never run `curl`, `security`, `sudo` or `launchctl` for real; stubs are injected
   by constructor argument.

## Behaviour (scope)

- `bin/k3dm-wcb-capture`: the CLI and dispatch of the contract, `status` and `c14-plain` inline, `isolation.Refused` →
  exit 2, the tmux/screen refusal for `api`, `browser-up`, `c8`, `c9`, `collect`, `c14-plain`.
- `scripts/lib/wcb_capture/__init__.py`: empty.
- `api.py`: the whole of §2 (absolute binaries with an empty environment, token validation, exact curl argv and stdin
  config, id validation accepting 32-hex or UUID for app and tunnel ids, the call list, `--after-disable`, 403
  recording, the top-level handler, raw and filtered outputs, `(1)/terms`, the CA two-field extraction into
  `(1)/ca/access_ca.pub`).
- `filters.py`, `scan.py`: §7 exactly, including the allowed loopback literals, algorithm names, OpenSSH suffixes and
  `HH:MM:SS`, and `filter_text`/`scan_file` as the contract defines them.
- `collect.py`: `main_collect` (scan, show, `y`/`n`, copy to `docs/captures/<date>-web-console-b/` with the README table)
  and `main_down` (operator side of §10: `quit`, the `sudo rootd.py --teardown` line through an injected runner, the
  collect-or-discard rule for (1), the dashboard cleanup checklist, idempotence).

## Files

| File | Change |
|---|---|
| `bin/k3dm-wcb-capture` | new |
| `scripts/lib/wcb_capture/__init__.py` | new |
| `scripts/lib/wcb_capture/api.py` | new |
| `scripts/lib/wcb_capture/filters.py` | new |
| `scripts/lib/wcb_capture/scan.py` | new |
| `scripts/lib/wcb_capture/collect.py` | new |
| `scripts/tests/bin/test_wcb_capture_data.py` | new |

## What NOT to Do

- No file outside `## Files`; do not edit a1's modules (a needed change is raised to Claude).
- The token never reaches argv, environment, a file, stdout, stderr, a log or an exception message.
- The scan never prints the matched text.

## Acceptance

```yaml
must:
  - id: K-M1
    text: "as the parent's K-M1"
  - id: K-M5
    text: "as the parent's K-M5"
  - id: K-M7c
    text: "down (operator side) sends quit, runs the teardown line, removes (1) only after collect or discard, prints the cleanup checklist and is idempotent"
  - id: K-M9
    text: "as the parent's K-M9"
must_not:
  - id: K-N2
    text: "as the parent's K-N2"
  - id: K-N4
    text: "as the parent's K-N4"
evidence:
  - id: K-E1
    proves: [K-M1, K-N2]
    kind: offline
    command: "the parent's K-E1, in scripts/tests/bin/test_wcb_capture_data.py, with its red controls (a)-(d)"
    intent: "The script that reads your Cloudflare settings can only read, never change anything, and your capture token never shows up in a command line, log, file or error message."
  - id: K-E5
    proves: [K-M5, K-N4]
    kind: offline
    command: "the parent's K-E5 (filters, scan on pre-filtered files including the real 2026-11-19 files, collect y/n under tmp_path), with its red controls (a)-(b)"
    intent: "Nothing private (tokens, keys, emails, account ids, addresses, your login name) can end up in a capture file I read or in the repo, even if the scrubbing step missed it."
  - id: K-E6c
    proves: [K-M7c, K-M9]
    kind: offline
    command: "pytest -k 'down or tmux or header or port': down refuses (1) removal before collect or discard and a second run exits 0 (stub runner records the teardown line); each of the six subcommands refuses with TMUX set, with STY set and with a stub ancestor named tmux; the version header is present in a text and a JSON capture (_capture_header); the CLI maps isolation.Refused to exit 2. Red control: drop the STY check — a named test fails. Then ruff check -- bin/k3dm-wcb-capture scripts/lib/wcb_capture/{__init__,api,filters,scan,collect}.py scripts/tests/bin/test_wcb_capture_data.py rc 0; CLT python3 -IS -m py_compile on each rc 0; make test-pytest rc 0"
    intent: "The enforcement test can only pass when the evidence really shows it, the staging step uses exactly the reviewed commit, and one command cleans everything up afterwards."
interface: "CLI bin/k3dm-wcb-capture; api.main, collect.main_collect, collect.main_down, filters.filter_text, scan.scan_file as in the parent's Contract between children."
```

## Worker definition of done

Report each command, its rc and the proving lines; show each red control failing and `git diff --stat` after restoring
it; list every error seen. Run the tests under `/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin` as well. Commit
nothing; Claude lands.
