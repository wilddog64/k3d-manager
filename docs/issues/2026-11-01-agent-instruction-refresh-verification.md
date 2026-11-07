# Agent-instruction refresh verification environment

The agent-instruction task was tested on `m4-air.local` on 2026-11-01. `agy` could not start inside the restricted sandbox because its log directory and localhost bind were denied. A sandboxed agy session run with loopback access from a scratch directory reported both unique markers, `ALPHA-AGENT-714` and `BRAVO-GEMINI-926`, in its initial context. The CLI reported language-server version 1.4.12. This is a self-report from the installed session, not a guarantee for other versions.

The first independent `make test` used the host's Python 3.15.2 and produced the existing `load_module` compatibility failure (tracked by `docs/bugs/2026-10-15-webhook-bats-load-module-removed-in-python-3-15.md`):

```text
not ok 491 smoke test ESO wiring samples app and hub through helper
# (in test file scripts/tests/lib/webhook_hub_eso.bats, line 155)
#   `[ "$status" -eq 0 ]' failed

Focused rerun with printed output:
1..1
not ok 1 smoke test ESO wiring samples app and hub through helper
# Last output:
# Traceback (most recent call last):
#   File "<stdin>", line 7, in <module>
# AttributeError: 'SourceFileLoader' object has no attribute 'load_module'. Did you mean '.exec_module' instead of '.load_module'?
```

With Python 3.13.6 the focused case passed (`1..1`, `ok 1`), and the curated BATS gate exited 0 with 1,979 cases, 0 failures, and these skips:

```text
ok 42 _acg_sync_known_hosts prunes stale managed AWS IPs and records current ones # skip Feature not yet implemented: see docs/issues/2026-05-13-acg-up-maintain-known-hosts-for-managed-aws-ips.md
ok 119 copilot binary is operational with COPILOT_GITHUB_TOKEN # skip K3DM_COPILOT_LIVE_TESTS not set — skipping live binary check
ok 154 N1: pre-fix sweep must fail the empty-list safety case # skip
ok 155 N2: pre-fix sweep must fail the young-file safety case # skip
ok 378 read_lines falls back on bash <4 # skip legacy bash not available
ok 400 stale-ref check flags the f03df202 data-layer rename # skip fixture commit f03df202 not reachable in this clone (orphaned by branch cleanup)
ok 401 stale-ref check flags the 4c89dabb trivy split # skip fixture commit 4c89dabb not reachable in this clone (orphaned by branch cleanup)
ok 402 stale-ref check is quiet on a commit that touched no etc files # skip fixture commit e3a75f1f not reachable in this clone (orphaned by branch cleanup)
ok 466 Level 1: POST queues job and GET /status returns job output # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 467 Level 1: GET /status output field is non-empty after job completes # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 468 Level 2: POST current chart version returns success without running make up # skip set K3DM_WEBHOOK_LEVEL2=1 to enable (requires cluster)
ok 469 Level 3: tunnel rejects wrong token with 401 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 470 Level 3: tunnel unknown path returns 404 (auth passes, routing fails) # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 471 Level 3: tunnel POST with real token queues job and returns 202 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 547 Alertmanager amtool routes ACG sandbox criticals to email # skip amtool is not installed
ok 548 Alertmanager amtool routes HubKineCompactionStalled to email # skip amtool is not installed
ok 993 e2e staleness is fresh if any runner passed recently # skip promtool not installed
ok 994 E2EResultsMissing fires only when the hub has no e2e results # skip promtool not installed
ok 1249 PR checks distinguish current rows, retained history, empty ranges, and failed or stale reads # skip promtool not installed
ok 1511 _keycloak_reconcile_realm_client updates argocd redirect URIs # skip shopping-cart-infra realm fixture not reachable: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.14/agent-instruction-files-refresh/scripts/tests/plugins/../../../../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json
```

The non-external pytest gate exited 0:

```text
1764 passed, 4 skipped, 5 deselected in 111.71s (0:01:51)
```

Five tests marked external were deselected: four require promtool, unavailable here with Docker fallback blocked by the tripwire; one exercises the external-marker guard itself and passed separately (`1 passed, 13 deselected in 0.03s`). Full session logs are `/private/tmp/k3dm-agent-refresh-bats-independent.log`, `/private/tmp/k3dm-agent-refresh-bats-py313.log`, and `/private/tmp/k3dm-agent-refresh-pytest-independent.log`. The earlier worker's failed sandboxed gates are documented in `2026-11-01-dispatch-review-pending-verification.md`. Follow-up: run promtool-dependent tests in an environment with promtool; resolve the separate Python 3.15 bug; Claude should perform the plan's review and next-dispatch live evidence before marking the spec fully verified.
