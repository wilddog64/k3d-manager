# Catching up the hub checkout

The hub receives changes through three routes, with different delays:

| Change | Route | Typical delay |
|---|---|---|
| Bug and plan docs | Hermes reads `origin/<release-branch>` | About five minutes |
| Host tools in `bin/` and `scripts/` | M5 checkout auto-sync; `make hub-sync` nudges and reports it | About five minutes |
| Dashboards and CronJobs | ArgoCD's ApplicationSet branch or `make platform-ops` | Until synced |

The **Hub code behind** tile shows code commits promoted to `deploy/hub` that
the hub checkout has not pulled. Documentation commits are excluded because
Hermes can read them from the release ref without moving the checkout.

The hub checkout follows `deploy/hub`, the promoted ref. Use `make hub-sync`
to nudge the hub's checkout sync and print its current commit and pending
deployment steps. See [checkout auto-sync](checkout-auto-sync.md) for how sync
works and how to read its state. To move the hub to another commit, use
`make hub-promote REF=<commit-ish>`.

## When a CI-green commit is waiting to promote

The hub sync on the M5 (every five minutes) also tells you when there is something to promote. Nothing promotes
automatically; the operator stays the gate.

1. It lists up to 10 commits on the release branch that `deploy/hub` lacks, newest first, and asks
   `bin/k3dm-hub-promote is-green <sha>` about each, the same check-run rule `hub-promote` enforces
   (exit 0 green, 3 not green, 2 check-run lookup failed). It stops at the first green commit.
2. It publishes, with the other `k3dm_repo_sync_*` series:

   | Series | Meaning |
   |---|---|
   | `k3dm_repo_sync_promotable{sha,branch}` = 1 | the newest green commit `deploy/hub` lacks; absent when there is none |
   | `k3dm_repo_sync_promote_backlog_commits` | how many commits `deploy/hub` is behind the release branch |
   | `k3dm_repo_sync_promote_lookup_failed` = 1 | a check-run lookup failed, so the answer is unknown |

3. The `hub-sync` summary line ends with `promote backlog: <n>; promotable: <sha7>|none|unknown`.
   `unknown` means a lookup failed, or none of the 10 newest commits is green while more than 10 are waiting.

Alerts (`scripts/etc/prometheus/rules/repo-sync.yaml`, `severity: warning`, `cluster: hub`):

- **`K3dmPromoteWaiting`** — a green commit has waited 15 minutes. It names the SHA and a command to run. A newer green
  commit replaces the series, so the alert always names the newest one. The everyday command is
  `make hub-deploy REF=<sha>` ([hub promote](hub-promote.md)); the alert text still says `make hub-promote`, which only
  moves the ref (tracked in `docs/bugs/2026-11-15-promote-waiting-alert-names-hub-promote-not-hub-deploy.md`).
- **`K3dmPromoteLookupFailed`** — the check-run lookup has failed for 30 minutes (GitHub outage, token). To promote during an outage, use the
  outage path in [hub promote](hub-promote.md).

On the **k3dm Release Tracking** dashboard (uid `k3dm-bugs`), the **deploy/hub behind** stat shows the backlog count and
the promotable SHA, next to the older **Hub code behind** tile (which counts the opposite gap: promoted commits the hub
checkout has not pulled).
