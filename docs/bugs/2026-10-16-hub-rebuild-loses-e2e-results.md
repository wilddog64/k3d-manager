# Bug: a hub rebuild silently erases all e2e results, and no alert notices (2026-10-16)

**Status:** IMPLEMENTED — landed `af654222` (Codex; Claude verified: BATS 113/113 with promtool; all 4 spec mutations red. Claude fixed: the promtool test always skipped and was broken once run (annotations), its present-case now uses a failing-only run so the absent(success) mutation goes red; restored 2 `.PHONY` entries Codex dropped; removed a Slack table row that advertised e2e-republish as a slash command; moved the selector into `_e2e_republish_select` for the if-count audit). Live proof pending.
**Priority:** P3 — the dashboard is empty and staleness is unalerted, but no workload is affected
**Branch:** `k3d-manager-v1.43.2`
**Release:** v1.43.2
**Filed:** 2026-10-16, at operator request
**Approval:** explicit 2026-10-16 "file rebuild-loses-e2e-history bug as P3 and dispatch to codex" (operator)
**Component:** `scripts/plugins/e2e_remote.sh`, `scripts/etc/argocd/platform-ops/prometheusrule.yaml`, `make e2e-*`
**Related:** `docs/howto/hub-rebuild-from-gitops-vault.md` (what survives a rebuild),
`docs/bugs/2026-10-05-e2e-alert-refires-on-exporter-rollout.md` (same exporter, different defect)

## Observed

After the 2026-10-15 hub rebuild, every panel of the **E2E Verification** dashboard shows
*No data*, and **Failing runs** shows 0. Read-only checks on 2026-10-16:

- The hub has zero `e2e_*` series.
- The producer, `vulnerability-inventory-exporter` in `platform-ops`, is running. It reads
  ConfigMaps labelled `k3dm.k3d.io/e2e-result=true`, and the hub has **none**.
- The m2 runner (`~/.k3dm/e2e`) still holds every summary, the newest from 2026-10-14 04:34.
  There are no `*.publication_pending.json` files, so `make e2e-replay RUNNER=m2` has nothing to send.

## Root cause

1. **Results live only in hub ConfigMaps.** `e2e_result_publish` writes one ConfigMap per run
   into `platform-ops`. A rebuild deletes the cluster; hub-data restore does not cover these
   ConfigMaps. The runner keeps the summaries, but nothing republishes them:
   `e2e_runner_publish_replay` sends only `publication_pending` files, which exist only when the
   original publish failed.
2. **No alert can see the gap.** `E2EVerificationStale` is `time() - max by (...) (e2e_last_success_timestamp_seconds) > 259200`.
   With no series it evaluates to nothing, so an empty hub is indistinguishable from a healthy
   one. The staleness signal disappears exactly when it matters most.

## Fix

Work only in the worktree and branch you were launched in. Read
`scripts/plugins/e2e_remote.sh` (especially `e2e_result_publish`, `_e2e_publish_build`,
`e2e_runner_replay`, `_e2e_remote_ssh`), `scripts/tests/plugins/e2e_remote.bats`,
`scripts/tests/plugins/e2e_observability.bats`, and the `e2e.alerts` group of
`scripts/etc/argocd/platform-ops/prometheusrule.yaml` in full first.

### 1. `e2e_runner_republish <runner>` — M4-side, in `scripts/plugins/e2e_remote.sh`

Add it directly after `e2e_runner_replay`, with a comment in the same style. It runs entirely on
the M4: the runner's checkout is only refreshed by `e2e_runner_dispatch`, so a runner-side
function would not exist there until the next run.

1. `_e2e_remote_load_conf`; require `runner` (usage error otherwise); refuse a runner not in
   the allowlist (`_e2e_runner_allowed`), and an unreachable one (`_e2e_remote_ssh "true"`),
   with the same messages as `e2e_runner_replay`.
2. Make a temp dir with `mktemp -d` and remove it on `RETURN`. Fetch the runner's summaries in
   **one** SSH call, as a tar stream:
   `_e2e_remote_ssh "cd ${E2E_M2_REMOTE_REPORT_DIR} && tar -cf - -- [0-9]*.json 2>/dev/null" | tar -xf - -C "$tmp"`.
   A failed or empty fetch → `_warn` "nothing to republish" and return 0.
3. Select with `python3`, reading the temp dir only:
   - consider only names matching `^[0-9]+-[0-9]+\.json$`. That excludes `.failures.json`,
     `.publication_pending.json` and `.published.json`;
   - skip, with a count, any file that is not a JSON object with string `service`, `tier` and
     `timestamp`;
   - keep the file with the greatest `timestamp` (parsed with `datetime.fromisoformat`, `Z`
     accepted) per `(service, tier)`;
   - print the kept paths **oldest first**, so publish order matches run order.
4. Publish each kept file through the existing validator and writer, in a subshell so its
   `_err` cannot end the loop: `( e2e_result_publish < "$f" )`. Count successes and failures.
   Do **not** reimplement validation, naming or pruning: `e2e_result_publish` already does all
   three. Its ConfigMap name is deterministic per `run_id`, so a republish is idempotent.
5. `_info "[e2e-remote] republish complete: published=<n> failed=<n> skipped=<n>"`. Return
   non-zero only when `failed > 0`.

This needs neither `E2E_M2_PUBLISH_BACK_HOST` nor the publisher SSH key. The exporter reads the
run's own `timestamp` (`run_seconds`), not the publish time, so republished results show their
true age. Old results therefore correctly raise `E2EVerificationStale` instead of looking fresh.

### 2. `make e2e-republish`

In `Makefile`, after `e2e-replay`, mirroring it exactly (usage check, `RUNNER=` required):

```make
## Republish a runner's newest E2E result per service and tier to the hub (after a hub rebuild). RUNNER=m2 required.
e2e-republish:
	@if [ -z "$(RUNNER)" ]; then echo "usage: make e2e-republish RUNNER=m2" >&2; exit 2; fi
	./scripts/k3d-manager e2e_runner_republish $(RUNNER)
```

Add `e2e-republish` to the `.PHONY` line, and a help line after the `e2e-replay` one:
`make e2e-republish Republish a runner's newest E2E results to the hub after a rebuild (RUNNER=m2)`.

### 3. Alert on an empty hub — `prometheusrule.yaml`, group `e2e.alerts`

Append, after `E2EVerificationStale`:

```yaml
        - alert: E2EResultsMissing
          expr: absent(e2e_last_run_pass)
          for: 6h
          labels:
            group: e2e
            severity: warning
          annotations:
            summary: "no e2e results on the hub"
            description: "The hub has no e2e result ConfigMaps (k3dm.k3d.io/e2e-result=true), so E2EVerificationStale cannot fire. After a hub rebuild run make e2e-republish RUNNER=m2; otherwise check vulnerability-inventory-exporter in platform-ops."
```

It has no `tier` label, so the static `tier: e2e` problem on its sibling does not apply. Do not
change `scripts/etc/prometheus/alertmanager.yaml.tmpl`: the `severity = warning` route already
delivers it to `platform-warning`.

### 4. Docs

- `docs/howto/hub-rebuild-from-gitops-vault.md`:
  - under **Does not survive**, add one bullet: e2e result ConfigMaps (`platform-ops`, label
    `k3dm.k3d.io/e2e-result=true`); the runner keeps the summaries;
  - under **5. Verify**, add a checkbox: `make e2e-republish RUNNER=m2`, then confirm the E2E
    Verification dashboard has data.
- The e2e guide or how-to that documents `make e2e-replay` (find it with
  `grep -rln 'e2e-replay' docs/guides docs/howto`; if none documents it, use
  `docs/howto/makefile.md`): one short paragraph on `e2e-republish`, covering how it differs
  from `e2e-replay` and when to run it.
- `docs/guides/alerting.md`: add `E2EResultsMissing` where the other e2e alerts are listed.
- `CHANGELOG.md` `[Unreleased]`: one `Fixed:` entry.

## Files

| File | Change |
|---|---|
| `scripts/plugins/e2e_remote.sh` | item 1 |
| `Makefile` | item 2 |
| `scripts/etc/argocd/platform-ops/prometheusrule.yaml` | item 3 |
| `scripts/tests/plugins/e2e_remote.bats` | tests below |
| `scripts/tests/plugins/e2e_observability.bats` | tests below |
| `docs/howto/hub-rebuild-from-gitops-vault.md`, the e2e-replay doc, `docs/guides/alerting.md`, `CHANGELOG.md` | item 4 |

No other file.

## Tests (each new one shown failing against the pre-change code, on a temp copy)

### `e2e_remote.bats`

Stub `ssh` (or `_e2e_remote_ssh`) to emit a tar stream built from fixture files, and stub
`e2e_result_publish` to record the `run_id` read from stdin. No real SSH, kubectl or hub.

1. Fixtures: two `product-catalog/vcluster` summaries (older and newer), one
   `basket/vcluster`, plus `X.failures.json`, `X.publication_pending.json` and a malformed
   `9-9.json`. Only the newer product-catalog run and the basket run are published, oldest
   first; `skipped=1` is reported.
2. One publish failure → non-zero return, `failed=1`, and the remaining file is still published.
3. Empty or failed fetch → return 0 and no publish call.
4. Allowlist and reachability refusals, mirroring the existing `M4 replay enforces...` test.
5. Add `e2e_runner_republish` to the "public failure/ops functions are dispatchable" list.
6. The existing guard test that `E2E_PUBLISH_KUBECONFIG` never appears in an `_e2e_remote_ssh` line stays green.

### `e2e_observability.bats`

1. The `e2e.alerts` list test expects
   `["E2EVerificationFailing", "E2EVerificationStale", "E2EResultsMissing"]`.
2. Tests that loop over every rule in `e2e.alerts` (the `max by` and `$labels.runner` checks)
   skip `E2EResultsMissing` by name and keep their assertions for the other two.
3. A promtool rule-unit test, beside the existing ones: no `e2e_last_run_pass` series for 7h
   → `E2EResultsMissing` fires. With one series present → it does not fire.
4. `make validate-manifests`, or the repo's existing YAML check for this file, stays green.

### Mutations (Claude, at verification)

Each must turn a test red:

- select the oldest instead of the newest per `(service, tier)`;
- drop the suffix exclusion;
- let one failure stop the loop;
- `absent(e2e_last_success_timestamp_seconds)` in place of `absent(e2e_last_run_pass)`.

The last one must fail a fixture where a target has only failing runs.

## Operational Requirements

| Item | Requirement |
|---|---|
| Resources | No new workload. `e2e-republish` is operator-run, never scheduled. Its SSH is one bounded read; publishing reuses the existing validator. |
| Security | No new credential or SSH principal; the publish kubeconfig never leaves the M4. Not added to the webhook allowlist (`scripts/lib/webhook/make_targets.py`). |
| Rollback | Revert. Republished ConfigMaps are ordinary results, pruned by the existing keep-20 rule. |
| Proof it works | After merge, the operator runs `make e2e-republish RUNNER=m2`. The E2E dashboard then shows the 2026-10-14 runs, and `E2EVerificationStale` fires for them, because they are older than 3 days. That is the correct, now-visible signal. |

## Definition of Done

- [ ] Items 1–4 exactly as written; `shellcheck scripts/plugins/e2e_remote.sh` reports no new warning.
- [ ] `bats scripts/tests/plugins/e2e_remote.bats scripts/tests/plugins/e2e_observability.bats` green; paste the summary.
- [ ] Leave the changes **uncommitted**. Claude verifies, commits and lands them with:
  `fix(e2e): republish runner results after a hub rebuild, and alert when the hub has none`

## What NOT to Do

- Do NOT contact the m2 runner, the hub or any cluster; tests use stubs only.
- Do NOT change `e2e_result_publish`, `_e2e_publish_build`, `_e2e_publish_prune`, the exporter,
  hub-data export, or the alertmanager template.
- Do NOT add `e2e-republish` to the webhook make-target allowlist.
- Do NOT create a PR, commit, switch branches, or use `--no-verify`.
- Do NOT modify files outside the Files table, including `memory-bank/`.
