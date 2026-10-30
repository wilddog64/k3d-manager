# M5 hub migration

This guide moves the single-instance services from the M4 hub to a freshly built M5 hub. Run commands from a local terminal on the M5. The cut-over requires a recent passing `hub-new` report and typed confirmation.

## Build and prepare the M5

1. Complete [one-command machine setup](machine-setup.md), enable Remote Login on the M4, and confirm the M5 has its copied Keychain records and authenticated GitHub CLI. You do not need to copy the Cloudflare tunnel files or install `k3d` yourself: `hub-new` copies the files listed in `scripts/etc/machine/files.hub.list` from the M4 during its machine-setup stage, and its `hub-up` stage installs `k3d`.
2. Open OrbStack on the M5 and wait until it is running. Confirm sleep prevention is enabled: `pmset -g` must show a `SleepDisabled 1` line (set it with `sudo pmset -a disablesleep 1`).
3. Pull the release branch, then run `make hub-new HUB_OLD_HOST=m4-air.local`. It copies the Cloudflare tunnel credentials and origin cert from the M4 if missing (you may be asked for the M4 login), takes the Hostinger tunnel target from `scripts/etc/hostinger/vars.sh` (an exported `HOSTINGER_HOST` overrides it), builds the fresh local cluster, restores credentials without starting the Cloudflare tunnel, prepares the single-instance plists without loading them, recovers the newest export (type the approval at its prompt), applies platform state, and waits for the read-only verification checks. Review `~/.local/share/k3d-manager/hub-new/hub-new-report.json`; it must report `status: pass` and be less than 24 hours old before cut-over.

If a stage stops, resolve its stated cause and rerun `make hub-new`. Passed stages are retained; use `HUB_NEW_FROM=<stage>` only when intentionally restarting from a named stage. Never run bare `make up` for this process.

## Agent classifications

The manifests under `scripts/etc/machine/` define ownership:

- `hub-local.list` contains agents that only reach their own Mac's cluster. These may run on both hubs during migration.
- `hub-singletons.list` contains agents that must run on exactly one Mac. Cut-over stops loaded entries on the M4 in reverse list order and loads the M5 entries in list order. `cloudflare-tunnel` remains last.
- `not-installed.list` records agents that this flow does not install, including sandbox lifecycle agents managed by the ACG sandbox and the uninstalled webhook token rotator.

Do not manually start a `hub-singletons.list` agent on either host during the move. The cut-over command checks the M4 is quiet before loading any singleton on the M5.

## Cut over

1. Review the printed agent plan with `make hub-cutover DRY_RUN=1`.
2. Run `make hub-cutover` and type `cutover` when prompted. It stops the loaded singleton agents on the M4 over SSH, confirms that none remain loaded there, loads them on the M5, and performs read-only checks for webhook health, public hostnames, the Cloudflare connector, Hostinger SSH tunnels and Hermes status.
3. Confirm a Hermes message arrives in Slack. Hermes delivery is an operator check because the command does not send a test message.
4. Review `~/.local/share/k3d-manager/hub-cutover/stopped-on-old` and `hub-cutover-report.json`. Verification retries for about three minutes while the webhook starts and Cloudflare drops the M4 connector. If it still fails it prints the rollback command; run `make hub-cutover-rollback` and type `rollback` to unload the M5 agents and restore exactly the recorded agents on the M4.
5. Once the cut-over has passed, stop the M4 cluster on the M4 with `k3d cluster stop k3d-cluster`. The cut-over moves only the singleton agents; a running M4 cluster would keep its ArgoCD syncing and its alerts firing next to the M5's. The M4's `hub-local.list` port-forward agents will then fail to connect, which is expected.

To roll back after step 5, start the M4 cluster first with `k3d cluster start k3d-cluster` on the M4, wait for its pods to be ready, then run `make hub-cutover-rollback` on the M5.

The command does not delete plists, clusters or data. Keep the M4 cluster stopped and intact for **7 days** as the rollback path. Do not run hub singletons on both Macs.

## After the 7-day rollback window

After the new hub has remained healthy for seven days:

1. Run `make machine-setup ROLE=worker` on the M4.
2. Remove the M4's hub LaunchAgent plists as a separate, deliberate operator step.
3. Update remaining `HUB_*` defaults, SSH aliases and `docs/howto` pages that still name the M4 as the hub.

These retirement steps are not automated by `hub-cutover` or its rollback command.
