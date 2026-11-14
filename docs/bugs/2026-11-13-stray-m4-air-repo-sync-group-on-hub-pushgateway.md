# Bug: a stray `instance="m4-air"` repo-sync group sits on the hub Pushgateway

**Status:** VERIFIED — live 2026-11-14 by Claude (landed 22ca679c); m4-air group deleted by operator and absent across a full tick
**Priority:** P2 (operator, 2026-11-14, after the recurrence; was P3)
**Intent approved:** operator ("go ahead"), 2026-11-14
**Introduced by:** unknown
**Should have been caught by:** unknown
**Prior art:** exact-slug glob: none; memory `feedback_pushgateway_tests_leak_to_real_hub` (same class). `make find-similar-docs` not run

## Symptom

Read-only GET of the hub Pushgateway (`ssh m5-air.local curl 127.0.0.1:19094/metrics`, 2026-11-13 14:23Z):
`k3dm_repo_sync_promote_lookup_failed{instance="m4-air",job="k3dm_repo_sync",repo="k3d-manager"} 1`, group pushed 2026-11-13 14:03:08Z.

- The M4 is a worker, and its own launchd `com.k3d-manager.repo-sync` exits 1 at startup (`machine-role file missing or empty`), so the M4 job did not publish this group.
- On the M4, 127.0.0.1:19094 is an ssh forward to the hub Pushgateway, so a hub-role `bin/k3dm-repo-sync` run on the M4 without `PUSHGATEWAY_URL` reaches the hub (the default is `http://localhost:19094`, `bin/k3dm-repo-sync:502`).
- Every committed suite that runs repo-sync isolates it: a curl stub or `PUSHGATEWAY_URL=127.0.0.1:9` (repo_sync.bats, repo_sync_promote_backlog.bats, repo_sync_launchd_env.bats; hub_sync.bats does not run repo-sync). The source is therefore probably an ad-hoc reproduction or an agent run around the 14:03Z repo-sync landing, not a suite.

## Impact

Pushgateway groups never expire. A panel that sums `promote_lookup_failed` without filtering `instance` shows 1. If a stray push ever carries `k3dm_repo_sync_promotable`, `K3dmPromoteWaiting` fires for a SHA the hub did not compute.

## Options (operator decision)

1. Delete the group: `curl -X DELETE http://127.0.0.1:19094/metrics/job/k3dm_repo_sync/instance/m4-air` on the M5 (write to the hub; operator runs it).
2. Make the default safe: have repo-sync publish only when the role is hub and the hostname matches the hub host, or require `PUSHGATEWAY_URL` to be set explicitly.
3. Write the M4's machine-role file (`worker`) so the M4 job runs as intended. Its own logs show an error every 5 minutes.

## Update 2026-11-13 15:57Z: the stray group now pages

After the promote of `6375f228` loaded the plan 3 rules at 15:24Z, a read-only GET of hub Prometheus (`ssh m5-air.local curl -s 127.0.0.1:19091/api/v1/alerts`) shows
`K3dmPromoteLookupFailed{instance="m4-air",cluster="hub",job="k3dm_repo_sync",repo="k3d-manager",severity="warning"}` **firing**, active since 15:25:56Z.
The hub's own job (`instance="m5-air"`) is healthy: at the same moment it holds `K3dmPromoteWaiting{sha="cf8cfc2"}` pending.
That alert is false: the M4 is not the hub and computes no promotion. Until option 1 or 2 lands, every K3dmPromoteLookupFailed page has to be checked for `instance`.
The rule could also be scoped to the hub instance, but that only hides the symptom. Options 1 and 2 above still stand.

## Update 2026-11-13 16:25Z: group deleted, M4 role written, cause corrected

- Operator deleted the group on the M5 (`curl -s -X DELETE http://127.0.0.1:19094/metrics/job/k3dm_repo_sync/instance/m4-air`). Claude confirmed: 0 `instance="m4-air"` series on the hub Pushgateway, and `K3dmPromoteLookupFailed` is no longer listed in hub Prometheus alerts (16:20Z); the hub's own `K3dmPromoteWaiting{instance="m5-air"}` is unaffected.
- Push time of the deleted group: `push_time_seconds` 1794578588 = 2026-11-13 14:03:08Z, a single push, never refreshed.
- Correction to "Make the default safe" above: `bin/k3dm-repo-sync` already pushes only when the role is `hub` (`is_hub`, :358, push block :488-509), and the M4 had no role file at all (its launchd job exits 1). So the 14:03Z push came from a run that was **given** a hub role — most likely a test or verifier reproduction with a scratch `XDG_CONFIG_HOME` holding `hub`, and `PUSHGATEWAY_URL` unset. The default `http://localhost:19094` (:502) then reached the hub through the M4's ssh forward (an `ssh` process listens on 127.0.0.1:19094 here).
- Fix shape (option 2, refined): drop the default. Push only when `PUSHGATEWAY_URL` is set; warn and skip otherwise. The hub's launchd template `scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl` does not set it today (only PATH), so it gains `PUSHGATEWAY_URL=http://localhost:19094`. This is a contract change (env var): the spec must list every reader and writer, and rollout must run `make install-repo-sync` on the M5 right after the promote, or the hub stops pushing and its own promote alerts go silent. Tests: unset URL → no curl (with a positive control: set URL → one PUT), plist carries the variable.
- Option 3 done: `~/.config/k3d-manager/machine-role` on the M4 = `worker` (operator go, 16:20Z). `bin/k3dm-repo-sync --check` dry-run: every repo `current`, `skipped:ahead` or `skipped:no-upstream`, nothing would update; worker mode never pushes metrics.
- Ruled out (16:50Z): `scripts/tests/bin/repo_sync.bats` cannot be the source. Since `aa1196ed` (2026-11-12) its `setup()` puts a `curl` stub first on PATH and asserts `command -v curl` is the stub (:81, :119), and the hub-role tests set `PUSHGATEWAY_URL=http://127.0.0.1:9`. The remaining candidate is an ad-hoc verifier or reproduction run of `bin/k3dm-repo-sync` with a hub role between 13:35Z and 14:35Z (independent verifiers ran then); not provable after the fact. The fix above covers it either way.

## Recurrence 2026-11-14: the group is back and paging

- Operator saw the duplicate stats on the Bugs dashboard "deploy/hub behind" panel (2026-11-14 ~12:10Z): two `backlog` and two `lookup failed` values.
- Read-only GET of the hub Pushgateway through the M4's forward (`curl 127.0.0.1:19094/metrics`, 12:14Z): `instance="m4-air"` carries `promote_backlog_commits 1` and `promote_lookup_failed 1`, last `push_time_seconds` 1794639574 = 2026-11-14 06:59Z. The hub's own group (`instance="m5-air"`): backlog 45, lookup_failed 0, promotable `869d736`, pushed 12:13Z.
- Hub Prometheus (`ssh m5-air.local curl -s 127.0.0.1:19091/api/v1/alerts`, read-only): `K3dmPromoteLookupFailed{instance="m4-air"}` firing, active since 06:35:56Z; `K3dmPromoteWaiting{instance="m5-air"}` firing since 08:48:56Z (real).
- The M4's launchd job is not the source: `~/.config/k3d-manager/machine-role` is `worker` (unchanged since 2026-11-13 08:19 local), and `repo-sync.log` holds only worker sync lines.
- Agent work running on the M4 between 06:3xZ and 06:59Z: the promtool Part B Luna dispatch (06:11Z–07:22Z) and the parallel-offline-tests Part B Flash dispatch. Not yet proven which (if either) ran `bin/k3dm-repo-sync` with a hub role.
- The fix shape from the 16:25Z update still stands: push only when `PUSHGATEWAY_URL` is set. A second recurrence within a day argues for P2 (Claude proposal): every recurrence pages falsely until the operator deletes the group.

## Decision 2026-11-14

Operator, 2026-11-14: "go with your recommendations" — raise to **P2** (recurred 2026-11-14, false page each time) and take the fix shape from the 2026-11-13 16:25Z update: push only when `PUSHGATEWAY_URL` is set; the hub's launchd plist template sets it.

## Spec (2026-11-14; drafted by Sonnet, reviewed by Claude)

## Problem

A hub-role run of `bin/k3dm-repo-sync` with `PUSHGATEWAY_URL` unset falls back to `http://localhost:19094` (`bin/k3dm-repo-sync:502`). On the M4 that port is an ssh forward to the hub Pushgateway, so a scratch or verifier run with a hub role writes an `instance="m4-air"` group on the hub. Groups never expire, and `K3dmPromoteLookupFailed` pages falsely (`scripts/etc/prometheus/rules/repo-sync.yaml`, `K3dmPromoteLookupFailed`, `for: 30m`). It recurred 2026-11-14.

## Fix

## 1. `bin/k3dm-repo-sync`: push only when `PUSHGATEWAY_URL` is non-empty

Old block (verbatim, `bin/k3dm-repo-sync:502-509`; the `if is_hub:` header is :488 and `return 0` is :510, both unchanged):

```
502	            url = os.environ.get("PUSHGATEWAY_URL", "http://localhost:19094").rstrip("/")
503	            data = "\n".join(metrics) + "\n"
504	            try:
505	                subprocess.run(["curl", "--silent", "--show-error", "--fail", "-X", "PUT", "--data-binary", data,
506	                                f"{url}/metrics/job/k3dm_repo_sync/instance/{socket.gethostname().split('.')[0]}"],
507	                               check=True, timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
508	            except Exception:
509	                print("WARNING: Pushgateway update failed", file=sys.stderr)
```

New block:

```
            url = os.environ.get("PUSHGATEWAY_URL", "").strip().rstrip("/")
            if not url:
                print("WARNING: PUSHGATEWAY_URL is not set; skipping Pushgateway update", file=sys.stderr)
            else:
                data = "\n".join(metrics) + "\n"
                try:
                    subprocess.run(["curl", "--silent", "--show-error", "--fail", "-X", "PUT", "--data-binary", data,
                                    f"{url}/metrics/job/k3dm_repo_sync/instance/{socket.gethostname().split('.')[0]}"],
                                   check=True, timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except Exception:
                    print("WARNING: Pushgateway update failed", file=sys.stderr)
```

Notes: the warning is printed once per run, inside `if is_hub:` (:488), so worker runs print nothing (they never push, :488). The `metrics` list is still built (harmless, keeps the diff minimal). A whitespace-only value counts as unset. Exit code stays 0 (:510). The existing failure warning text (:509) is unchanged, so no existing assertion on it moves.

## 2. `scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl`: the hub job sets the URL

Old block (verbatim, lines 6-10):

```
6	  <key>EnvironmentVariables</key>
7	  <dict>
8	    <key>PATH</key>
9	    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
10	  </dict>
```

New block:

```
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>PUSHGATEWAY_URL</key>
    <string>http://localhost:19094</string>
  </dict>
```

Render check: `make install-repo-sync` renders with `sed -e "s|{{REPO_ROOT}}|...|g" -e "s|{{HOME}}|...|g"` (`Makefile:72`); it substitutes only those two placeholders, so a literal URL passes through untouched (no `|`, `&` or `\` in it). No Makefile change is needed. The template is installed on every machine, workers included; a worker's job never pushes (role check :488), so the variable is inert there. The M4 worker job additionally exits 1 only if its role file is missing (:337); it is `worker` today (bug doc, 16:25Z update).

## 3. Tests (see Acceptance)

- `scripts/tests/bin/repo_sync.bats`: add E1, E2, E3 next to "hub pushes per-repository metrics to the stub endpoint" (:240-251); reuse `install_stubs`, `prepare_hub_checkout`, `run_sync` (:141) and the curl stub (:83) that logs to `$CURL_LOG` and is asserted first on PATH (:119).
- `scripts/tests/bin/repo_sync_launchd_env.bats`: add E4 beside E1 (the rendered-plist PATH test, :206); it already renders through `make install-repo-sync` into a scratch HOME with `K3DM_AGENT_LOAD=0` (so no launchctl) and reads the plist with Python `plistlib` (`_extract_plist_path`, :177). Add a sibling helper that extracts `PUSHGATEWAY_URL`.
- `scripts/tests/bin/repo_sync_promote_backlog.bats`: no new test. Its `setup()` exports `PUSHGATEWAY_URL="http://127.0.0.1:9"` (:18), so every existing test keeps pushing to the stub curl; leave unchanged.

## Contract readers

Grep of the whole repo for `PUSHGATEWAY_URL` (2026-11-14; docs/bugs, docs/issues, docs/plans, memory-bank, CHANGELOG hits are prose, not readers). The shared contract here is the bare env var `PUSHGATEWAY_URL` as read by `bin/k3dm-repo-sync`. Every other tool uses a differently named variable, so setting the plist variable does not leak into them (launchd gives only this job's environment).

Readers of bare `PUSHGATEWAY_URL` as an environment variable:

| file:line | what it does | changes? |
|---|---|---|
| `bin/k3dm-repo-sync:502` | reads env, default `http://localhost:19094` | **yes**: no default; empty/unset skips the push with a warning |
| none | no other file reads the bare `PUSHGATEWAY_URL` env var; `bin/k3dm-orbstack-upgrade:15` assigns a shell variable of that name from `K3DM_ORBSTACK_PUSHGATEWAY_URL` (default `http://localhost:19094`), so it is not a reader | no |

Writers (anything that sets the bare variable for repo-sync):

| file:line | what it does | changes? |
|---|---|---|
| `scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl:6-10` | EnvironmentVariables holds only PATH | **yes**: gains `PUSHGATEWAY_URL=http://localhost:19094` |
| `Makefile:70-81` (`install-repo-sync`) | renders the template with sed (:72), `bootout`/`bootstrap` the agent unless `K3DM_AGENT_LOAD=0` (:74-77) | no change; this is how the plist reaches the M5 |
| `Makefile:68` (`hub-sync`) -> `bin/k3dm-repo-sync --remote` -> `:307` runs `ssh HOST "cd ... && bin/k3dm-repo-sync >/dev/null && bin/k3dm-repo-sync --hub-summary"` | a non-launchd run on the hub over ssh with the ssh session's environment, which has no `PUSHGATEWAY_URL` | no code change, but behaviour changes: the ssh-triggered run no longer pushes (it warned/pushed through the default before). Its stderr is captured by `run()` (:28, `stderr=PIPE`) and not printed, so the operator sees nothing new. The hub's own metrics now come only from the launchd job (every 300 s, `StartInterval`, plist:11). Accepted; stated here so a reviewer does not call it a regression |
| `scripts/tests/bin/repo_sync.bats:243-244, 256, 291, 334, 458, 552, 612` | `export PUSHGATEWAY_URL=http://127.0.0.1:9` (stub curl, asserted first on PATH :119) | no change (positive control for the new behaviour) |
| `scripts/tests/bin/repo_sync_promote_backlog.bats:18` | `export PUSHGATEWAY_URL="http://127.0.0.1:9"` in `setup()` | no change |
| `scripts/tests/bin/repo_sync_launchd_env.bats:200` | `env -i ... PUSHGATEWAY_URL="http://127.0.0.1:9"` for the job-env run | no change |
| `docs/howto/checkout-auto-sync.md:9` | mentions `make install-repo-sync` / `uninstall-repo-sync` only; no Pushgateway text | **docs**: add a sentence (see Files) |
| `docs/howto/hub-promote.md` | no `PUSHGATEWAY_URL` / install-repo-sync text found | no |

Not readers (different variable, named so to avoid confusion): `scripts/lib/webhook/config.py:36` reads `K3DM_PUSHGATEWAY_URL` into a Python constant named `PUSHGATEWAY_URL`, imported at `bin/k3dm-webhook:35` and used at :1767, :1785-1786; `bin/k3dm-test-metrics:17` has a constant `DEFAULT_PUSHGATEWAY_URL = "http://localhost:9091"`; `docs/guides/grafana-dashboards/k3dm-deployments.md:50` and `scripts/tests/lib/webhook.bats:84` describe the webhook's empty-`K3DM_PUSHGATEWAY_URL` early exit (`if not PUSHGATEWAY_URL: return`), the pattern this fix copies.

## Other pushers with their own `localhost:19094` default (out of scope; same stray-push hazard on a worker with an ssh forward)

Each defaults to `http://localhost:19094`, so a run on a machine where that port forwards to the hub writes to the hub Pushgateway. Whether it also writes a misleading group depends on whether the instance label is the hostname.

| file:line | variable | same hazard? |
|---|---|---|
| `bin/k3dm-hermes:601` | `K3DM_KINE_PUSHGATEWAY_URL` | yes (default 19094) |
| `bin/k3dm-hermes:643, 698, 726` | `K3DM_VECTORDB_PUSHGATEWAY_URL` | yes |
| `bin/k3dm-hermes:890` | `K3DM_ORBSTACK_PUSHGATEWAY_URL` | yes |
| `bin/k3dm-hermes:937` | `K3DM_PR_CHECKS_PUSHGATEWAY_URL` | yes |
| `bin/k3dm-vectordb-metrics:39` | `K3DM_VECTORDB_PUSHGATEWAY_URL` | yes |
| `bin/k3dm-disk-metrics:94` | `K3DM_DISK_PUSHGATEWAY_URL` | yes |
| `bin/k3dm-dispatch-metrics:2806` | `K3DM_DISPATCH_PUSHGATEWAY_URL` | yes (the dispatch dashboard runs on the M4 by design, so for that one the push is intended) |
| `bin/dr-drill-publish:6` | `K3DM_DR_DRILL_PUSHGATEWAY_URL` (full job path, default 19094) | yes |
| `bin/k3dm-orbstack-upgrade:15, 168, 181` | `K3DM_ORBSTACK_PUSHGATEWAY_URL`, default 19094; curl at :168, :181 | yes (default 19094) |
| `bin/k3dm-webhook:1767` | `K3DM_PUSHGATEWAY_URL`, default `http://localhost:9091` (`config.py:36`) | different port; empty value skips already |

Candidate follow-ups (not part of this fix): (1) one bug per pusher above that is hub-only by intent, applying the same set-or-skip rule; (2) a pre-push role check shared by `bin/` pushers; (3) a Pushgateway staleness alert on `push_time_seconds` (below).

## What the operator sees if the hub stops pushing

If the promote lands but `make install-repo-sync` is not run on the M5, the hub's already-loaded agent keeps its old plist (no `PUSHGATEWAY_URL`), so from the next 5-minute run it warns `WARNING: PUSHGATEWAY_URL is not set; skipping Pushgateway update` to `~/.local/share/k3d-manager/logs/repo-sync.log` (plist StandardErrorPath) and pushes nothing. Pushgateway keeps the last `instance="m5-air"` group forever, so:

- `K3dmRepoSyncStale` (`scripts/etc/prometheus/rules/repo-sync.yaml`, expr `time() - k3dm_repo_sync_last_success_timestamp_seconds{repo="k3d-manager"} > 3600`, `for: 10m`, severity warning, label `result="stale"`) **does catch it**, about 70 minutes after the last push: "k3d-manager checkout sync is stale". Its description ("inspect state.json") is misleading, because state.json is still fresh; the real cause is in repo-sync.log. Add this to the rollout checklist and `docs/howto/checkout-auto-sync.md`.
- `K3dmPromoteWaiting` and `K3dmDeployPending` and `K3dmPromoteLookupFailed` hold their last pushed value. A promotable SHA that was `1` stays firing with a stale SHA; a new promotable SHA never appears, so a real "waiting to promote" page is silently missed; a firing alert will not resolve.
- No rule uses `absent()` or `push_time_seconds` (grep of `repo-sync.yaml` finds neither), so nothing pages in the first hour. Hence the explicit rollout step and the live check below.

## Acceptance

```yaml
must:
  M1: with PUSHGATEWAY_URL unset (or empty) and a hub machine role, bin/k3dm-repo-sync invokes curl zero times and writes one "PUSHGATEWAY_URL is not set" warning line to stderr
  M2: with PUSHGATEWAY_URL set to a URL, a hub run invokes curl exactly once, as a PUT to "<URL>/metrics/job/k3dm_repo_sync/instance/<host>" (positive control for M1)
  M3: the rendered repo-sync launchd plist carries EnvironmentVariables PUSHGATEWAY_URL=http://localhost:19094 next to PATH, produced by make install-repo-sync without any Makefile change
  M4: with a worker machine role, bin/k3dm-repo-sync never invokes curl whether or not PUSHGATEWAY_URL is set, and prints no Pushgateway warning
  M5: the sync outcome is unchanged by the missing URL: exit status 0, state.json written, checkout updated as before
must_not:
  N1: a hub run with the URL unset reaches any host (no curl invocation, no default localhost:19094 fallback)
  N2: the rendered plist PATH value changes, or the plist loses any existing key
  N3: the pushed metric names, labels or values change when the URL is set
evidence:
  - {id: E1, proves: [M1, N1, M5], kind: offline, intent: "You will see a hub-role run with the URL unset leave the curl stub's log empty, one warning line on stderr, exit 0 and the state file written. Today the stub log shows one PUT to localhost:19094."}
  - {id: E2, proves: [M2, N3], kind: offline, intent: "You will see the same run with the URL set to a stub address make exactly one PUT to that address, with the same metric lines as before."}
  - {id: E3, proves: [M4], kind: offline, intent: "You will see a worker-role run, with the URL set and unset, produce no curl call and no Pushgateway warning."}
  - {id: E4, proves: [M3, N2], kind: offline, intent: "You will see make install-repo-sync render a plist in a scratch home that has PUSHGATEWAY_URL=http://localhost:19094 and the same PATH string as before."}
  - {id: E5, proves: [M1, M2], kind: live, intent: "You will see the hub's instance=m5-air group on its Pushgateway keep advancing: push_time_seconds moves forward on consecutive 5-minute runs after the promote and make install-repo-sync on the M5, and no instance=m4-air group appears. Operator or Claude runs it; never Gemini."}
interface:
  - "bin/k3dm-repo-sync (environment variable PUSHGATEWAY_URL; stderr warning)"
  - "scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl (EnvironmentVariables)"
```

Test sketch (worker may adapt names):

- E1 (repo_sync.bats): `install_stubs; prepare_hub_checkout; unset PUSHGATEWAY_URL; run_sync "$HUB_ROOT"`; assert `[ "$status" -eq 0 ]`, `[ ! -s "$CURL_LOG" ]`, `[[ "$output" == *"PUSHGATEWAY_URL is not set"* ]]` (bats `run` merges stderr into `$output`), `[ -s "$SCRATCH/state/state.json" ]`. Repeat with `export PUSHGATEWAY_URL=""`. Fixture assertions first: `[ "$(command -v curl)" = "$SCRATCH/stubs/curl" ]` (already in `install_stubs`, :119) and `[ -z "${PUSHGATEWAY_URL:-}" ]`.
- E2 (same file, positive control in the same test body or the adjacent existing test :240): `export PUSHGATEWAY_URL=http://127.0.0.1:9`; assert `[ "$(wc -l < "$CURL_LOG" | tr -d ' ')" -eq 1 ]` and `grep -q -- '-X PUT' "$CURL_LOG"` and `grep -q 'http://127.0.0.1:9/metrics/job/k3dm_repo_sync/instance/' "$CURL_LOG"`; the existing body asserts at :248-250 stay.
- E3: write `worker` to `$XDG_CONFIG_HOME/k3d-manager/machine-role` (see how the "hub branch stops at deploy/hub while worker follows its upstream" test at :359 does it), run with and without the URL, assert `[ ! -s "$CURL_LOG" ]` and output without `PUSHGATEWAY_URL`.
- E4 (repo_sync_launchd_env.bats): after the same `make ... install-repo-sync` as E1, extract the value with `plistlib` (`env.get("PUSHGATEWAY_URL")`) and assert it equals `http://localhost:19094`; also assert the PATH string equals the E1 literal (`/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`).
- Every `must_not` must be red on today's code: N1 via E1 (today's code PUTs to the default); N2 and N3 are guards that are green before and after (state this in the report, and prove N3 by diffing `$CURL_BODY` before/after the change).

## Files

| File | Change |
|---|---|
| `bin/k3dm-repo-sync` | :502-509 set-or-skip push, warning |
| `scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl` | :6-10 add `PUSHGATEWAY_URL` |
| `scripts/tests/bin/repo_sync.bats` | E1, E2, E3 |
| `scripts/tests/bin/repo_sync_launchd_env.bats` | E4 |
| `docs/howto/checkout-auto-sync.md` | one sentence: the hub job gets `PUSHGATEWAY_URL` from the plist; re-run `make install-repo-sync` after pulling this change; a manual or ssh run without it skips the push; a stalled hub shows as `K3dmRepoSyncStale` ~70 min later, cause in repo-sync.log |

## Rollout

Order matters. Run on the hub (M5), in the operator's tmux, right after the promote:

1. `make hub-promote REF=<commit-ish>` (the hub reads `deploy/hub`; nothing here takes effect before it). The promote updates the checkout the launchd job runs from (`{{REPO_ROOT}}`), so the new `bin/k3dm-repo-sync` is live on the next run, but the loaded agent still has the OLD plist environment.
2. **Immediately** `make install-repo-sync` on the M5 (renders the new plist, `bootout` + `bootstrap`). Do not wait for the next 5-minute tick: between step 1 and step 2 a scheduled run will warn and skip the push.
3. Confirm: `plutil -p ~/Library/LaunchAgents/com.k3d-manager.repo-sync.plist` shows `PUSHGATEWAY_URL`; within 5 minutes `curl -s 127.0.0.1:19094/metrics | grep 'push_time_seconds{.*k3dm_repo_sync.*m5-air'` shows an advancing time (E5); `tail ~/.local/share/k3d-manager/logs/repo-sync.log` has no `PUSHGATEWAY_URL is not set` line after the install.
4. If step 2 is forgotten or fails, the hub stops pushing silently for about 70 minutes (see "What the operator sees"). Rollback: `make hub-rollback`, or just `make install-repo-sync` once the new template is present.
5. Workers (the M4): no action. Optionally `make install-repo-sync` to refresh the plist; the job is inert because it exits on a worker role before any push.
6. Use `make hub-promote-status` to confirm the promote landed before step 3 (CLAUDE.md hub rule).

## Worker definition of done

- Change only the files above. Offline only: put a `curl` stub first on PATH and assert `command -v curl` is the stub; use a scratch HOME and `XDG_CONFIG_HOME`; never a real Pushgateway, never `launchctl` (use `K3DM_AGENT_LOAD=0` for install-repo-sync tests); do not run `bin/k3dm-repo-sync` outside the bats fixtures; do not run `make install-repo-sync` against the real HOME.
- Show E1 red on today's code (stub log has one PUT to localhost:19094), then green after the fix; E2, E3, E4 green; mutation check: restore the default `"http://localhost:19094"` and show E1 red again, then remove it.
- Run from the repo root: `bats scripts/tests/bin/repo_sync.bats scripts/tests/bin/repo_sync_promote_backlog.bats scripts/tests/bin/repo_sync_launchd_env.bats` and `shellcheck`/lint steps the repo requires for touched files. Paste each command, its rc, and the proving lines (the empty `$CURL_LOG` assertion, the one-PUT assertion, the plist value). List every error seen, including sandbox-only reds, and say whether each also occurs on the base commit.
- Leave all changes uncommitted.

## Residual / notes for the reviewer

- Behaviour change accepted: ad-hoc and ssh (`make hub-sync`) hub runs no longer push; only the launchd job does.
- Not fixed here: an existing stray group is already deleted by the operator; if one reappears before the promote, delete it with `curl -X DELETE http://127.0.0.1:19094/metrics/job/k3dm_repo_sync/instance/m4-air` on the M5.

## Landed 2026-11-14

- Luna's diff landed as `22ca679c` (Claude), pushed. Claude added `unset PUSHGATEWAY_URL` to `repo_sync.bats` `setup()` after a Fable review finding: two hub-role tests ("unrelated update alone", "hub branch stops at deploy/hub") called the real `curl` and, before this fix, always pushed to `localhost:19094` as the test machine's hostname. Probe, m4-air 2026-11-14: with `PUSHGATEWAY_URL=http://127.0.0.1:9` and a logging curl first on PATH, 0 pushes with the unset and 16 PUT attempts as `instance/m4-air` without it. That is a likely source of the stray m4-air group.
- Verification: `dispatch verify` pass. Fix tree 30/30; pre-fix tree with the new tests: rc=1, `not ok 8` (E1) and `not ok 28` (E4). Independent Opus verifier (Acceptance only): PASS E1–E4; a mutant restoring the old default URL goes red at `repo_sync.bats:274`. N3: pushed metric bodies byte-identical with the URL set.
- Fable finding 1 (medium, not fixed here): after the promote the hub runs the new script with the old installed plist (no URL) and stops pushing until `make install-repo-sync`; a frozen `deploy_pending=1` could keep `K3dmDeployPending` firing. Run `make install-repo-sync` on the M5 in the same session as the promote. The lasting guard (reinstall an agent when its plist template changed) is the hub-deploy row in `docs/ideas.md`.
- Fable finding 3 (low, accepted): `make hub-sync` no longer pushes, so the moved checkout's sample waits for the next launchd run (≤5 min).
- E5 (live): m5-air `push_time_seconds` advancing after the reinstall, and no m4-air group.

## Live check 2026-11-14 (Claude, read-only over ssh to m5-air.local)

After the promote of `6ba89b3f` (contains `22ca679c`) and `make install-repo-sync` on the M5 (~14:40Z):

- **Hub half passes.** The M5 plist has `PUSHGATEWAY_URL => http://localhost:19094`; `instance="m5-air"` `push_time_seconds`
  advanced on consecutive runs, 14:47:40Z then 14:53:02Z; no `PUSHGATEWAY_URL is not set` line in the M5 log.
- **A stale `instance="m4-air"` group is present**, last pushed 13:52:27Z and unchanged at 14:53:36Z. The fix reached
  the M4 checkout by fast-forward at 13:50:03Z, so that push is most likely a run that started on the old script; the M4
  job has run about 11 times since (log written 14:42Z) without pushing. E5's "no m4-air group" therefore needs the
  group deleted once (rollout residual): `curl -s -X DELETE http://127.0.0.1:19094/metrics/job/k3dm_repo_sync/instance/m4-air`
  on the M5 (operator, hub write), then one more check that it does not return.

## Verified 2026-11-14 (Claude)

After the operator's DELETE on the M5 (`/metrics/job/k3dm_repo_sync/instance/m4-air`), two samples of the hub
Pushgateway (localhost:19094) six minutes apart showed only `instance="m5-air"`: 14:55:26Z (push 14:53:02Z) and
15:01:27Z (push 14:58:21Z). The M4 job wrote its log at 15:00:13Z within that window and did not push. E5 passes.
