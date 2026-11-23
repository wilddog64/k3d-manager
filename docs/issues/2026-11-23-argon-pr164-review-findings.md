# Argon blind review of PR #164 (v1.45.0): two low findings, no change

**Date:** 2026-11-23
**PR:** #164 (v1.45.0 release), diff `origin/main...c4a97ef7 -- bin scripts Makefile`
**Reviewer:** Argon (`gemini-4-argon-medium`, agy), spec `docs/plans/release-pr164-v1.45.0-review.md`
**Result:** 0 high, 0 medium, 2 low; both triaged by Claude as no defect today, no code change.
Gates: E1 `git status --short` empty in the review worktree; `_agent_audit` exit 0.

## Finding 1: bugs dashboard "Releases / 7 days" has no upper bound

`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` panel id 34 counts
`k3dm_release_shipped_timestamp_seconds{repo="$repo"} > time() - 7 * 86400`. Argon: at a past range-query step
`t`, a release shipped after `t` would also match, distorting the sparkline.

**Triage: no change.** The gauge for a tag is first pushed by `bin/k3dm-vectordb-metrics` after the tag exists, so at
any step where the series exists its value (the tag's shipped time) is at or before that step. A value newer than the
step needs a series pushed before its own tag, which the writer cannot do. Argon marked it verified-from-code but
gave no input that produces it. Adding `<= time()` would be harmless; it is not needed for correctness.

## Finding 2: `_wc_route_file` checks `$route_yq` but runs `/opt/homebrew/bin/yq`

`bin/k3dm-web-console-sshd:273-277`. Argon: if `route_yq` pointed elsewhere, the function would validate one binary
and run another.

**Triage: no change.** `route_yq` takes two values (`_wc_check_routes`, lines 290-291): `/opt/homebrew/bin/yq` in
production, where `_wc_tool` runs that same path; and `$_WC_PREFIX/bin/yq` in fixture mode, where `_wc_tool` is
`_wc_fixture_call`, which runs `$_WC_PREFIX/bin/${tool##*/}` (`scripts/lib/web_console_common.sh:23-29`), the same
file. The checked binary and the executed binary are identical in both modes. The duplication is a maintenance
hazard only if a third value of `route_yq` is ever added.

## Process note

A blind review spec should ask for a concrete input that triggers each finding; both findings here were
"if X were ever different" scenarios that the code does not allow.
