# `_vcluster_reconcile_namespace` treats the `vcluster list` table header and separator as orphan vClusters

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. Every Tier 1 run logs two bogus "orphan" deletions with failing `vcluster delete` and
`helm uninstall` calls, then continues. A real orphan is still found and deleted, but the noise buries the
deliberate orphan `_warn`, which exists to surface teardown regressions.
**Status:** OPEN
**Related:** `docs/bugs/2026-09-23-e2e-failed-run-leaks-vcluster-and-wedges-all-later-runs.md`, which introduced
the reconcile.

## Evidence (`make e2e`, 2026-10-02, vcluster `0.32.1`)

```
WARN: vCluster '\E[32mNAME\E[0m' is an orphan in namespace 'vclusters' ...
helm command failed (1): helm -n vclusters uninstall $'\E[32mNAME\E[0m' --wait
WARN: vCluster '-------+-----------+--------+---------+-----------+------' is an orphan in namespace 'vclusters' ...
fatal bad flag syntax: -------+-----------+--------+---------+-----------+------
```

## Cause

`scripts/plugins/vcluster.sh` `_vcluster_reconcile_namespace` parses the human `table` output of `vcluster list`.
In `0.32.1` the header is indented and ANSI-colored, so `[[ "$line" == NAME* ]]` never matches, and a
`---+---` separator line follows it. Both reach the delete path as cluster names.

`vcluster list -n <ns> --output json` (supported in `0.32.1`, verified) returns
`[{"Name": "...", "Namespace": "...", ...}]`.

## Fix (`scripts/plugins/vcluster.sh`, `_vcluster_reconcile_namespace` only)

Replace the table parsing with the JSON output:

- `list_output="$(_run_command --no-exit --quiet -- "$_VCLUSTER_BIN" list -n "$VCLUSTER_NAMESPACE" --output json 2>/dev/null || true)"`
- Extract names with `jq -r '.[]?.Name // empty' 2>/dev/null <<< "$list_output" || true` and loop over them
  (`while IFS= read -r cluster_name`). Unparseable or empty output yields no names and the function returns 0.
- Keep the `keep` skip, the `_warn` text, the `vcluster delete` → `helm uninstall` fallback and `return 0`
  unchanged. Keep the comment block above the function.

## Tests (new `scripts/tests/plugins/vcluster_reconcile_namespace.bats`; no cluster)

Stub `_run_command` to answer the `list` call with a fixture and record every other call; stub `_warn`.

1. JSON with two clusters (`keep-me`, `orphan-a`), keep = `keep-me`: exactly one delete, for `orphan-a`; no call
   for `keep-me`.
2. `[]`: no delete calls.
3. Non-JSON output (the old colored table, including `\033[32mNAME\033[0m` and a `---+---` line): no delete calls,
   status 0.
4. Delete failure falls back to `helm -n <ns> uninstall orphan-a --wait`.

Mutation, `cp`-restored and `cmp`-proved: drop `--output json` from the list call → test 1 is red.

## Rules

- `bats scripts/tests/plugins/vcluster_reconcile_namespace.bats` green; `shellcheck scripts/plugins/vcluster.sh` clean.
- No cluster, network or git commits. Leave changes uncommitted. Do not touch `CHANGELOG.md` or memory-bank.
- Update this doc: Status FIXED, plus a short Resolution section.
