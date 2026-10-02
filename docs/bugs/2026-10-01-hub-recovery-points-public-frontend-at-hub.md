# Hub recovery points the public frontend at the hub, which serves no frontend

**Filed:** 2026-10-01
**Branch:** `k3d-manager-v1.40.0`
**Severity:** medium. The public shop (`frontend.3ai-talk.org`) returns 404, and `/cluster-status`
reports `Frontend` and `Product images` as FAIL on a healthy Hostinger cluster.
**Status:** OPEN
**Related:** `2026-09-13-hub-recovery-manual-fixes-not-declarative.md` (Defect 3, which added
`origins.tsv`)

## Observed (2026-10-01)

- `/cluster-status`: `Frontend: HTTP Error 404`, `Product images: HTTP Error 404`.
- `~/.cloudflared/config.yml` (mtime 2026-09-11) routes `frontend.3ai-talk.org` to
  `http://127.0.0.1:8000`, the k3d hub serverlb.
  - The hub has no frontend pod, so it answers 404.
- Hostinger is healthy:
  - `shopping-cart-apps/frontend` is Running on `ubuntu-hostinger`.
  - `curl -H 'Host: frontend.3ai-talk.org' http://127.0.0.2:80/` → 200. That is the
    `k3s-hostinger` origin in `origins.tsv`.

## Cause

`_hub_recovery_install_cloudflared_config` (`scripts/plugins/hub_recovery.sh`) always renders
`_hub_recovery_render_cloudflared_config k3d …`. Hub recovery therefore points the public frontend
at the hub, whichever cluster actually runs the shop. Defect 3 assumed the hub serves the frontend;
it no longer does. Hostinger is the permanent app cluster. `bin/cluster-up` already renders with
`${CLUSTER_PROVIDER}`, so only hub recovery is wrong.

## Fix

Only `scripts/plugins/hub_recovery.sh` changes. Do not change `origins.tsv`, the render function,
`bin/cluster-up`, or `scripts/etc/cloudflared/config.yml`.

1. Add `_hub_recovery_frontend_origin_provider <hub_context> <app_context>`. It prints one provider
   key and always returns 0:
   1. If `HUB_RECOVERY_FRONTEND_PROVIDER` is set and non-empty, print it. This is the explicit
      operator override.
   2. Else, if `_kubectl -- --context "$app_context" -n shopping-cart-apps get deployment frontend`
      succeeds, print `k3s-hostinger`.
   3. Else, if the same check against `$hub_context` succeeds, print `k3d`.
   4. Else print `k3s-hostinger` and `_warn` that no frontend deployment was found, so the
      origin is left on the permanent app cluster.
   - Use `>/dev/null 2>&1` on the probes. The checks never fail the reconcile.
2. `_hub_recovery_install_cloudflared_config` takes `<hub_context> <app_context>`. It resolves the
   provider with step 1 instead of the literal `k3d`.
   - It `_info`s the chosen provider and origin, e.g.
     `[hub-recovery] cloudflared frontend origin: k3s-hostinger`.
   - The call site in `hub_recovery_reconcile` passes `"$hub_context" "$app_context"`.
   - Backup-on-change, `cmp`, and the "reload with: launchctl kickstart …" hint stay as they are.
   - Keep printing the hint. Do **not** kickstart the tunnel automatically.
3. Dry-run output (the reconcile without `--confirm`) names this step the same way as today. It
   must not call `_kubectl`, so the existing dry-run test stays green.

## Tests

Add to `scripts/tests/plugins/hub_recovery.bats`. Stub `_kubectl`, and point `HOME` at
`$BATS_TEST_TMPDIR` so the real `~/.cloudflared` is never touched.

- The app context has a frontend → the provider is `k3s-hostinger`. The installed `config.yml`
  routes `frontend.3ai-talk.org` to `http://127.0.0.2:80`.
- Only the hub has a frontend → `k3d` → `http://127.0.0.1:8000`.
- Neither has one → `k3s-hostinger`, a warning is printed, and the return code is 0.
- `HUB_RECOVERY_FRONTEND_PROVIDER=k3d` wins even when the app context has a frontend.
- The existing render tests and the dry-run test are unchanged and still green.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) hardcode `k3d` again → the app-context test is red;
(b) drop the override branch → the override test is red;
(c) swap the app/hub probe order → the app-context test is red.

## Rules

- Linux-portable shell (CI is Ubuntu). No `sed -i ''`. Quote every expansion.
- `shellcheck scripts/plugins/hub_recovery.sh` adds no new warnings. The hub_recovery bats file
  is green.
- Touch only: `scripts/plugins/hub_recovery.sh`, `scripts/tests/plugins/hub_recovery.bats`,
  `CHANGELOG.md` (Fixed bullet), and this doc (Resolution section, Status FIXED).
- Do not run anything against a live cluster or touch the real `~/.cloudflared`.

## Operator step after the fix

Re-render, or hand-edit the frontend line in `~/.cloudflared/config.yml` to `http://127.0.0.2:80`.
Then run `launchctl kickstart -k "gui/$(id -u)/com.k3d-manager.cloudflare-tunnel"` and rerun
`/cluster-status`.
