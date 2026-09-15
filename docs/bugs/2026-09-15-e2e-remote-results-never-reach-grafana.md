# Bug: remote e2e results never reach the hub (Grafana), and the M4 keeps no failure detail

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-15
**Status:** OPEN
**Files:** `scripts/plugins/e2e.sh`, `scripts/plugins/e2e_remote.sh`, `scripts/tests/plugins/e2e.bats`, `scripts/tests/plugins/e2e_remote.bats`, `CHANGELOG.md`
**Blocks:** `docs/plans/v1.34.0-hermes-scheduled-e2e.md` (Hermes reads the files B3 creates)

## Evidence (2026-09-15)

- The operator ran e2e-remote from Slack (webhook job `59af7edf`, run `1789481773-13798`, runner `m2`): 45 failed, 12 passed, 102 total.
- Grafana shows nothing: the hub has **zero** `k3dm.k3d.io/e2e-result=true` ConfigMaps in `platform-ops`.
- The M4 dispatch transcript `~/.k3dm/e2e/dispatch/m2-20260915T141612Z.log` ends with `WARN: [e2e-remote] M4 publication unavailable; retained 1789481773-13798.publication_pending.json for replay`. The 2026-08-27 run `1787838531-2562` is also still `publication_pending` on the M2.
- The M4 keeps only the dispatch transcript. Per-test failures exist only in the M2's `~/.k3dm/e2e/<run_id>.log`, and the webhook job dir has no log, so Slack `logs` shows nothing.

## Root cause

1. `E2E_M2_PUBLISH_BACK_HOST` is set only in the repo `.envrc` (direnv). The webhook (Slack `/k3dm e2e-remote`) and Hermes run under launchd, which never loads `.envrc`. `e2e_runner_dispatch` therefore passes no publish-back host, and the M2 retains every result.
2. `_e2e_write_summary` records only counts. The publisher schema (`_e2e_publish_build`) rejects unexpected keys, so failure detail cannot ride in the summary.
3. `e2e_runner_dispatch` never copies the run's result files back to the M4.

## Fix

### B1 — `e2e_remote.sh`: publish-back host from an operator conf file

Add `_e2e_remote_load_conf`, called at the start of `e2e_runner_dispatch` and `e2e_runner_replay`:
- Only when `E2E_M2_PUBLISH_BACK_HOST` is empty, read `${K3DM_E2E_REMOTE_CONF:-$HOME/.config/k3d-manager/e2e-remote.env}` if it exists.
- Do **not** `source` it. Accept only a line matching `^E2E_M2_PUBLISH_BACK_HOST=[A-Za-z0-9._@-]+$`; ignore everything else.
- If the host is still empty, `_warn "[e2e-remote] publish-back host not configured; this result will NOT reach the hub/Grafana (set E2E_M2_PUBLISH_BACK_HOST in <conf path>)"`. The warning goes into the transcript, so Slack shows it.
- The env var still wins over the file.

### B2 — `e2e.sh`: failure sidecar

In `_e2e_write_summary`'s Python, also write `${E2E_REPORT_DIR}/${run_id}.failures.json`. It is a JSON list built by walking the Playwright results tree (nested `suites` → `specs` → `tests` → last `results` entry), with one object per test whose last result status is `failed` or `timedOut`:

```json
{"file": "api/cart.spec.ts", "title": "should add item to cart", "status": "failed", "error": "<first 3 non-empty lines, ANSI-stripped, joined with ' / ', max 300 chars>"}
```

- Cap the list at 200 entries.
- Write `[]` when the results block is missing or unparseable. Never raise.
- The summary JSON schema is **unchanged**, because the publisher is strict.
- `_e2e_newest_summary` must keep ignoring the sidecar: extend its exclusion regex to `\.(publication_pending|published|failures)\.json$`.

### B3 — `e2e_remote.sh`: copy result files back to the M4

After the dispatch `ssh … | tee "$transcript"`, and without changing the returned rc:
- Extract the run id from the transcript's last `Summary written to .*/([0-9]+-[0-9]+)\.json`. The run id must match `^[0-9]+-[0-9]+$`; otherwise skip.
- Over the same `_e2e_remote_ssh_opts` SSH connection, `cat` `${E2E_M2_REMOTE_REPORT_DIR}/<run_id>.json` and `<run_id>.failures.json`, each through `head -c 262144`. Save them as `${transcript%.log}.summary.json` and `${transcript%.log}.failures.json`.
- `_info "[e2e-remote] result files: <summary> <failures>"`. A missing file just logs `_warn` and is not written.

## Tests

- `e2e_remote.bats`:
  - conf file sets the host;
  - env beats the file;
  - a line with shell metacharacters (`E2E_M2_PUBLISH_BACK_HOST=a;rm -rf x`) is ignored;
  - missing host prints the "will NOT reach the hub/Grafana" warning;
  - dispatch with a stubbed `ssh` writes `.summary.json`/`.failures.json` next to the transcript and preserves a non-zero rc.
- `e2e.bats`:
  - a fixture log with a nested results tree (2 failed, 1 timedOut, 1 passed) produces a 3-entry sidecar with ANSI stripped and a ≤300-char error;
  - a missing results block produces `[]`;
  - summary keys are unchanged;
  - `_e2e_newest_summary` ignores `*.failures.json`.
- Use stubs and temp dirs only.
- Assert the meaningful tokens; never `grep -F` a whole source line.
- `shellcheck -S warning` stays clean.

## Operator steps (after merge to the branch; the operator runs these)

```bash
mkdir -p ~/.config/k3d-manager
printf 'E2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local\n' > ~/.config/k3d-manager/e2e-remote.env
make e2e-replay RUNNER=m2
```

The replay publishes the two retained results (08-27, 09-15) to the hub.

## What NOT to do

- Do not run a real dispatch, replay, `ssh`, or `kubectl` against the M2 or the hub. Stubs only.
- Do not add keys to the published summary, and do not relax `_e2e_publish_build`.
- Do not `source` the conf file.
- Do not edit `scripts/lib/foundation/` or `scripts/lib/acg/`.
- No PR, no merge, no `main` commit, no force-push, no `--no-verify`. No `git add -A`, no `git stash`.
