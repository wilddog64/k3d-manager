# Checkout auto-sync

`bin/k3dm-repo-sync` runs every five minutes when installed. It fetches and fast-forwards configured checkouts for the machine role. The hub's k3d-manager root checkout follows its configured remote's `deploy/hub` branch so it does not run unpromoted release code. A clean non-fast-forward hub checkout is reset to that branch after a create-only backup ref is recorded. `--check` reports `would-reset-to-deploy-hub` without moving it. Worker checkouts and other repositories are never reset.

The sync never switches branches, rebases, stashes, cleans, deploys, or restarts the webhook. Non-hub checkouts with local commits are left alone: ahead-only is `skipped:ahead`, and ahead plus behind is `skipped:diverged`. A dirty hub checkout or a path collision with a file being added is `skipped:dirty`; unrelated untracked files do not prevent a reset. If local edits conflict with a fast-forward, it records `blocked`; unrelated edits are kept. A missing or empty machine-role file prints an error and exits 1 before syncing or writing state. Webhook changes set `webhook_restart_pending`; restart it manually with the normal operator procedure.

State is written to `~/.local/share/k3d-manager/repo-sync/state.json`. Each repository has its path, branch, result, before/after behind counts, old/new commit and run time. Hub state also reports pending deployment steps and steps it could not determine. `deployed-platform-ops` records the commit last applied by `make platform-ops`.

Pause automatic sync with `make uninstall-repo-sync`; install again with `make install-repo-sync`. `bin/k3dm-repo-sync --check` reports intended actions without fetching or merging.
