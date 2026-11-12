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
