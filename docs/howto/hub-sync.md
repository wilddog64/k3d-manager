# Catching up the hub checkout

The hub receives changes through three routes, with different delays:

| Change | Route | Typical delay |
|---|---|---|
| Bug and plan docs | Hermes reads `origin/<release-branch>` | About five minutes |
| Host tools in `bin/` and `scripts/` | The M5 checkout, advanced by an operator | Until `make hub-sync` |
| Dashboards and CronJobs | ArgoCD's ApplicationSet branch or `make platform-ops` | Until synced |

The **Hub code behind** tile shows code commits on the hub's checked-out branch
that have not been pulled. Documentation commits are excluded because Hermes
can read them from the release ref without moving the checkout. The second
value says whether the hub is reading the newest release branch. `unknown`
means the metric check is stale or unavailable.
The count stays accurate while a newer release exists, at the cost of a second fetch on those cycles.

Run `make hub-sync` from a shell on the hub when the tile shows code behind or
a fix is missing. `make platform-ops` reads the login Keychain, so run this as
the hub operator in their normal shell. To move to a newer release, use the
branch named by the tile: `make hub-sync BRANCH=k3d-manager-vX.Y.Z`.
The command refuses dirty checkouts and recent queued or running webhook jobs,
and only advances branches by fast-forward. It restarts the webhook and Hermes
for code changes, applies platform-ops changes when needed, and always checks
the ApplicationSets. It prints staged follow-up commands for machine setup,
ApplicationSet reapply, or a still newer release; those are not run for you.

The first run after this change lands needs a manual `git pull --ff-only` on
the M5, because `bin/k3dm-hub-sync` is not present there until that pull.
