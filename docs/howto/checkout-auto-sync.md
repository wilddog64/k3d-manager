# Checkout auto-sync

`bin/k3dm-repo-sync` runs every five minutes when installed. It fetches and fast-forwards configured checkouts for the machine role. The hub's k3d-manager checkout follows `origin/deploy/hub` so it does not run unpromoted release code.

The sync never switches branches, resets, rebases, stashes, cleans, deploys, or restarts the webhook. It leaves local commits alone and records a checkout as skipped. If local edits conflict with a fast-forward, it records `blocked`; unrelated edits are kept. Webhook changes set `webhook_restart_pending`; restart it manually with the normal operator procedure.

State is written to `~/.local/share/k3d-manager/repo-sync/state.json`. Each repository has its path, branch, result, before/after behind counts, old/new commit and run time. Hub state also reports pending deployment steps and steps it could not determine. `deployed-platform-ops` records the commit last applied by `make platform-ops`.

Pause automatic sync with `make uninstall-repo-sync`; install again with `make install-repo-sync`. `bin/k3dm-repo-sync --check` reports intended actions without fetching or merging.
