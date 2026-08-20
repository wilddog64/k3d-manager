# make status does not self-diagnose the hostinger edge-down pattern

**Filed:** 2026-08-16
**Provider:** k3s-hostinger
**Severity:** low (ergonomics — follow-up to
`docs/bugs/2026-08-16-hostinger-edge-recovery-no-narrow-entrypoint.md`)

## Problem

The narrow recovery entrypoint now exists (`make refresh-edge CLUSTER_PROVIDER=k3s-hostinger`,
commit `f28b6cda`). But nothing *tells* the operator to use it. When the laptop edge for
`k3s-hostinger` is down (cloudflared tunnel + port-forward launchd agents stopped by a
`make up/down` or provider-switch cycle), `make status CLUSTER_PROVIDER=k3s-hostinger` prints a
wall of `HTTP 530` failures (Cloudflare Argo Tunnel error 1033 — origin unreachable) and reads as
a full cluster outage. The cluster is healthy; only the edge is down. The operator has to *know*
that "all-530" means "run refresh-edge" — that knowledge lives only in memory
(`reference_hostinger_edge_recovery_lever`), not in the tool.

## Goal

Make `make status` (summary mode) self-diagnose the edge-down signature for `k3s-hostinger` and
point the operator straight at `make refresh-edge`. One extra hint line — no behavior/exit-code
change.

## Signal (why this is reliable, not a guess)

- Cloudflare returns **HTTP 530** when the tunnel origin is unreachable — that is *exactly* the
  edge-down case. It is distinct from `502`/`503` (a live-but-unhealthy backend or a single zombie
  port-forward — see `reference_single_service_502_zombie_port_forward`, which is a per-service
  issue, NOT an edge outage).
- **≥2** Cloudflare-fronted services returning `530` at once = the whole edge is down, not one
  service. A single `530`/`502` must NOT trip the hint (that's per-service).
- In `bin/cluster-status-summary` the per-service failure detail already carries the code as the
  substring `HTTP 530` (same string the json path greps via `HTTP (\d+)`), so detection needs no
  new probe — just count it while rendering.

## Scope note — KeepAlive is already done

The spec that filed the parent bug listed an *optional* "launchd `KeepAlive` on the tunnel plist"
follow-up. **That is already in place** — `scripts/lib/providers/k3s-hostinger.sh:269` sets
`<key>KeepAlive</key><true/>` on `com.k3d-manager.cloudflare-tunnel` (and on the port-forward
plists). KeepAlive self-heals a *crash* while the job is loaded; it does not (and should not)
fight a deliberate `launchctl bootout` from `make down`/provider-switch — which is the case
`make refresh-edge` covers. **Do NOT touch the plists.** This bug is the status hint only.

## Change — one file: `bin/cluster-status-summary`

Summary (human) mode only. Do **NOT** change the json branch (lines 31–44) or any exit code.

1. Before the render loop (currently `_errors=0; _warnings=0` at line 45), add an edge-530 counter:
   ```bash
   _errors=0; _warnings=0; _edge530=0
   ```
2. In the render loop (line 47), in the `error)` arm, increment the counter when the failure detail
   is a Cloudflare 530:
   ```bash
   error) _errors=$((_errors+1)); [[ "${_message}" == *"HTTP 530"* ]] && _edge530=$((_edge530+1)); printf '  %s %s: %s\n' "$(_color 31 '✗')" "${_name}" "${_message}";;
   ```
   (Leave the `warning)` and `healthy)` arms unchanged.)
3. After the `Overall:` line (line 49) and before the `Details:` line (line 50), emit the hint when
   the provider is hostinger and the edge-down signature is present:
   ```bash
   if [[ "${_provider}" == k3s-hostinger ]] && (( _edge530 >= 2 )); then
     printf '%s\n' "  hint: edge down (Cloudflare 530 x${_edge530}) — cluster likely healthy; run: make refresh-edge CLUSTER_PROVIDER=k3s-hostinger"
   fi
   ```
   Keep the hint plain (no `_color`), matching the existing `  hint: make restart-webhook` /
   `  hint: make refresh-edge` style already in the file (line 15). Do not gate it on `_mode` — this
   block is already inside the summary-only path (json returns earlier at line 43).

## Verification

1. `bash -n bin/cluster-status-summary` — syntax clean.
2. `shellcheck bin/cluster-status-summary` — **no new findings** vs. the parent commit (diff the
   count; the file may carry pre-existing ones).
3. **New BATS** in `scripts/tests/bin/cluster_status_summary.bats` (extend — do not rewrite),
   mirroring the existing curl-mock pattern (canned webhook JSON via a PATH `curl` stub):
   - **edge-down → hint:** provider `k3s-hostinger` (set via `active-provider` file, as the existing
     provider test does) + a mocked health payload with **≥2** services `"detail":"HTTP 530"` →
     output contains `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger` and still `Overall: FAIL`,
     exit 1.
   - **single 530 → no hint:** exactly one `HTTP 530` service → output does **NOT** contain
     `refresh-edge`.
   - **wrong provider → no hint:** ≥2 `HTTP 530` but provider is `k3d` (or default) → no
     `refresh-edge` hint.
4. Existing 5 tests in that BATS file still pass unchanged.

## Commit message

```
feat(status): hint make refresh-edge when k3s-hostinger edge is down (all-530)
```

## What NOT to Do

- Do NOT change the json branch, exit codes, or the `warning`/`healthy` arms.
- Do NOT touch any launchd plist — KeepAlive is already set; this is a status-only change.
- Do NOT trip the hint on a single 530/502 (that's a per-service zombie port-forward, not the edge).
- Do NOT add the hint for non-hostinger providers (their edge has no launchd layer).
- Do NOT create a PR. Do NOT commit to `main`. Do NOT use `--no-verify` / `ALLOW_MAIN_PUSH=1`.
  Commit to `k3d-manager-v1.25.0` only, then **push the branch** and report the `origin` SHA.
- Do NOT touch shopping-cart-* repos or `scripts/lib/acg/`.
- Update `memory-bank/activeContext.md` + `progress.md` after the code commit (separate commit ok).

## Prevention (out of scope — note only)

A future pass could teach the webhook health endpoint itself to distinguish "edge down" from
"cluster down" (it can see both the k8s API and the Cloudflare-fronted probe) and surface a
first-class `edge` state, rather than inferring it from an all-530 pattern in the CLI. Keep out
of this change.
