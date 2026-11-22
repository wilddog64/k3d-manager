# dispatch-metrics: `-xhigh` agy runs are counted as unpriced

**Status:** OPEN — captured 2026-11-16 from Argon's blind review of the PR #161 post-Copilot delta
**Priority:** P3 — cost metrics only, and only for a model tier no dispatch has used yet
**Introduced by:** the commit "chore(metrics): allow and price gemini-4-hydrogen for dispatch runs" (k3d-manager-v1.44.0, 2026-11-15)
**Should have been caught by:** offline test
**Introducing change reviewed:** no (pushed after Copilot's last review of PR #161 at 34112fe3)
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Minor metrics hygiene gap where `-xhigh` tier runs are not stripped for price lookup and default to unpriced sessions.)
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match. `make find-similar-docs` not run.
**Filed:** 2026-11-16

## Symptom

`bin/k3dm-dispatch-metrics:45` allowlists `gemini-4-hydrogen-xhigh`, but `_agy_run_usage` strips only `-(low|medium|high)` before the price lookup (`bin/k3dm-dispatch-metrics:752`). An xhigh run keeps its full name, `prices.get("gemini-4-hydrogen-xhigh")` returns `None` (the table is keyed by family, `scripts/etc/agent/codex-model-prices.json:13`), and the run drops out of `k3dm_dispatch_api_cost_usd` and adds to `k3dm_dispatch_api_cost_unpriced_sessions`.

Verified by Claude 2026-11-16 by reading lines 45, 752 and the price table. Not reproduced by a test run.

## Fix

Add `xhigh` to the stripping alternation (`-(?:low|medium|high|xhigh)$`), plus a test that an xhigh run is priced at the family rate and a positive control that `-medium` still is.
