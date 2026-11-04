# Bug: webhook post-provision check and cluster status hardcode Hostinger tunnel port 6443 and report other-provider ArgoCD apps as degraded

**Status:** OPEN
**Priority:** P2
**Severity:** medium — Slack post-provision check after `/k3dm acg-up` (`provider="k3s-aws"`) falsely reports `SSH tunnel (6443): DOWN ❌ — ACG cluster API unreachable` when the ACG tunnel on `:16443` is up, and flags/triages `ubuntu-hostinger-*` apps against `ubuntu-k3s` pods
**Filed:** 2026-11-03
**Detected by:** M5 live Slack verification (`job 4a9b212c` on `2026-11-03`)
**Branch:** `k3d-manager-v1.43.14`
**Approval:** Operator requested filing proper bug specs and dispatching to Luna on `2026-11-03`

## Evidence

On `2026-11-03`, after Slack job `4a9b212c` (`/k3dm acg-up`, `provider="k3s-aws"`) succeeded on `m5-air.local`, `_run_post_provision_check` in `bin/k3dm-webhook:1837-1910` posted:

```text
*SSH tunnel (6443):* DOWN ❌
⚠️ SSH tunnel down — ACG cluster API unreachable. Service endpoints may still be accessible via port-forwards.
*ArgoCD:* 43/46 apps healthy
⚠️ Degraded: `ubuntu-hostinger-data-layer`, `ubuntu-hostinger-shopping-cart-namespace`, `ubuntu-hostinger-shopping-cart-product-catalog`
```

1. **Wrong SSH tunnel port for `k3s-aws`:**
   - On `m5-air.local`, the ACG sandbox SSH tunnel (`com.k3d-manager.sandbox.ssh-tunnel`) listens on `localhost:16443` (`TUNNEL_SANDBOX_LOCAL_PORT`, default `16443`) and was `LISTEN`ing (`PID 49637`).
   - Port `6443` (`TUNNEL_LOCAL_PORT`, default `6443`) is the Hostinger tunnel (`com.k3d-manager.ssh-tunnel`).
   - While `_collect_cluster_state()` in `bin/k3dm-webhook:1463` uses `os.environ.get("TUNNEL_SANDBOX_LOCAL_PORT", "16443")`, both `_run_post_provision_check` (`bin/k3dm-webhook:1847-1851`) and `_run_cluster_status` (`scripts/lib/webhook/status.py:183-187`) still hardcode `("localhost", 6443)` and `*SSH tunnel (6443):*`.
2. **Unscoped ArgoCD `Application` health check across providers:**
   - On the Hub (`k3d-k3d-cluster`), `ApplicationSet`s generate per-cluster `Application` resources prefixed with `<cluster_context>-` (`ubuntu-k3s-*` for `k3s-aws`, `ubuntu-hostinger-*` for `k3s-hostinger`, `ubuntu-gcp-*` for `k3s-gcp`, `ubuntu-azure-*` for `k3s-az`).
   - All 23 `ubuntu-k3s-*` apps were `Synced` and `Healthy`, but `_run_post_provision_check` (`bin/k3dm-webhook:1867-1875`) and `_run_cluster_status` (`scripts/lib/webhook/status.py:267-272`) did not filter out `Application` names belonging to other app-cluster contexts (`ubuntu-hostinger-*`), and `_run_post_provision_check` (`bin/k3dm-webhook:1899-1904`) then queried `kubectl get pods -A --context ubuntu-k3s` while triaging `ubuntu-hostinger-*` apps.

## Files

- `bin/k3dm-webhook`
- `scripts/lib/webhook/status.py`
- `scripts/tests/bin/webhook_status.py`
- `CHANGELOG.md`

## Fix scope

1. **`bin/k3dm-webhook`:**
   - Add helper `_tunnel_port_for_provider(provider=None)`:
     - Resolve `app_context = _provider_context(provider)`.
     - If `app_context == "ubuntu-k3s"`, return `int(os.environ.get("TUNNEL_SANDBOX_LOCAL_PORT", "16443"))`.
     - Otherwise return `int(os.environ.get("TUNNEL_LOCAL_PORT", "6443"))`.
   - Add helper `_app_matches_provider_context(app_name, app_context)`:
     - Define `_APP_CLUSTER_PREFIXES = ("ubuntu-k3s-", "ubuntu-hostinger-", "ubuntu-gcp-", "ubuntu-azure-")`.
     - If `app_name` starts with any `prefix` in `_APP_CLUSTER_PREFIXES`, return `prefix == f"{app_context}-"`.
     - Otherwise return `True` (Hub/shared app).
   - In `_run_post_provision_check(job_id, provider)` (`bin/k3dm-webhook:1837-1910`):
     - Compute `app_context = _provider_context(provider)` and `tunnel_port = _tunnel_port_for_provider(provider)`.
     - Probe `("localhost", tunnel_port)` instead of hardcoded `("localhost", 6443)` and format the line as `f"*SSH tunnel ({tunnel_port}):* {'UP ✅' if tunnel_ok else 'DOWN ❌'}"`.
     - Filter `app_lines` with `_app_matches_provider_context(l.split()[0], app_context)` before computing `degraded` and `healthy_count`.
2. **`scripts/lib/webhook/status.py`:**
   - Add `_tunnel_port_for_context(app_context)` (`int(os.environ.get("TUNNEL_SANDBOX_LOCAL_PORT", "16443"))` when `app_context == "ubuntu-k3s"`, else `int(os.environ.get("TUNNEL_LOCAL_PORT", "6443"))`) and `_app_matches_provider_context(app_name, app_context)`.
   - In `_run_cluster_status` (`scripts/lib/webhook/status.py:180-188`), probe `("localhost", tunnel_port)` where `tunnel_port = _tunnel_port_for_context(app_context)` and log `f"*SSH tunnel ({tunnel_port}):* {'UP ✅' if tunnel_ok else 'DOWN ❌'}"`.
   - In `_run_cluster_status` (`scripts/lib/webhook/status.py:267-272`), filter `all_apps` using `_app_matches_provider_context(l.split()[0], app_context)` before computing `unhealthy`.
3. **`scripts/tests/bin/webhook_status.py`:**
   - Keep all existing tests intact and passing.
   - Add unit tests covering `M1`–`M3` and `N1`–`N2` below for both `bin/k3dm-webhook` (`_run_post_provision_check`, `_tunnel_port_for_provider`, `_app_matches_provider_context`) and `scripts/lib/webhook/status.py` (`_run_cluster_status`, `_tunnel_port_for_context`, `_app_matches_provider_context`).
4. **`CHANGELOG.md`:**
   - Add a `Fixed` bullet under `## [1.43.14] - Unreleased` for provider-scoped SSH tunnel port (`16443` for `k3s-aws`, `6443` for `k3s-hostinger`) and provider-scoped ArgoCD degraded-app filtering in webhook post-provision check and cluster status.

## Acceptance

```yaml
must:
  - id: M1
    req: when provider is k3s-aws (app_context ubuntu-k3s), _run_post_provision_check and _run_cluster_status probe localhost on TUNNEL_SANDBOX_LOCAL_PORT (default 16443) and report "*SSH tunnel (16443):* UP ✅" when that port accepts connections
  - id: M2
    req: when provider is k3s-hostinger (app_context ubuntu-hostinger), _run_post_provision_check and _run_cluster_status probe localhost on TUNNEL_LOCAL_PORT (default 6443) and report "*SSH tunnel (6443):* UP ✅" when that port accepts connections
  - id: M3
    req: when provider is k3s-aws and an ubuntu-k3s-* or hub-scoped ArgoCD application is Degraded, _run_post_provision_check reports that application in the Degraded list (paired positive control for N2)
must_not:
  - id: N1
    req: when provider is k3s-aws, port 16443 is UP, and port 6443 is DOWN, _run_post_provision_check and _run_cluster_status never probe port 6443 or emit "SSH tunnel down — ACG cluster API unreachable"
  - id: N2
    req: when provider is k3s-aws and all ubuntu-k3s-* apps are Healthy while ubuntu-hostinger-* apps are Degraded, _run_post_provision_check and _run_cluster_status never report ubuntu-hostinger-* apps as Degraded or invoke AI triage for them
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: >-
      Unit tests in scripts/tests/bin/webhook_status.py prove N1 and N2 fail (red) on pre-fix code and M1-M3 + N1-N2 pass (green) on fixed code.
    what: env -i HOME="$HOME" PATH="$PATH" pytest scripts/tests/bin/webhook_status.py
```

## Rules

- Touch only the 4 files listed under `## Files`. Do not create or modify any other files, and do not touch `memory-bank/`.
- Do not run `git add`, `git commit`, or `git push`. Leave changes in the working tree.
- Never weaken, skip, or delete any existing test in `scripts/tests/bin/webhook_status.py`.
- Run and paste the output of:
  - `pytest scripts/tests/bin/webhook_status.py`
  - `git --no-pager diff --check`
