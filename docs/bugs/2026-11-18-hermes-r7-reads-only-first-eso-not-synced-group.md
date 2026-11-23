# Hermes r7 precondition reads only the first `N/M not synced` group in two-cluster ESO evidence

**Status:** OPEN — captured 2026-11-18 from Fable's blind diff review of PR #163 (v1.44.2), verified by Claude
**Priority:** P2 (Argon P2 accepted, grooming 2026-11-22, operator; was: P3 — wrong r7 offer/withhold in a two-cluster layout)
**Triage:** carry → v1.46.0 — grooming 2026-11-22, operator
**Branch:** `k3d-manager-v1.46.0`
**Introduced by:** fadf8438 (Hermes r7 gate, v1.44.2) — the regex predates it
**Should have been caught by:** offline test
**Introducing change reviewed:** yes (Fable spec review)
**Classified:** P2 by gemini-4-argon-medium, 2026-11-22 (Broken `_r7_precondition` parsing in two-cluster ESO evidence can wrongly offer or withhold repair r7 depending on which cluster's count appears first.)
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-18

## Symptom

`_r7_precondition` (`scripts/lib/hermes/repairs.py:199-202`) uses `re.match(r"(\d+)/(\d+) not synced", evidence)`. When the
app context is not the hub, ESO evidence is `<app>; Hub <hub>` (`scripts/lib/webhook/smoke.py:702-704`), so only the app
cluster's count is read: `1/20 …; 19/20 not synced: cosign-public-key, …` offers r7 although 19 hub secrets fail, and the
reverse case never offers it. The `<= 2` boundary is also untested (tests use 1 and 19), and `2/20 not synced:
cosign-public-key, ghcr-pull-secret` offers r7 while the card says only the cosign key is missing.

## Fix sketch

Parse every group and require the group that names `cosign-public-key` to be the only failure. Tests: the two-cluster
strings above, and 1/20 vs 2/20 at the boundary.
