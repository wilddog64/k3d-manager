# Makefile Reference — k3d-manager

All targets operate on the **current `CLUSTER_PROVIDER`** set in your environment
(default: `k3s-aws`). Override the sandbox URL with `URL=https://...`.

```bash
make up                      # provision full stack (default URL)
make up URL=https://...      # provision with explicit sandbox URL
```

---

## Core Lifecycle

| Target | Command | When to use |
|---|---|---|
| `make up` | `bin/cluster-up` | Start from scratch — credentials → Hub cluster → ESO → ArgoCD → app cluster |
| `make down` | `bin/cluster-down --confirm` | Tear down the app cluster and Vault port-forward while preserving the local Hub; add `DELETE_HUB=1` to delete it only with a fresh snapshot |
| `make down CLEANUP_STALE=1` | `cleanup-stale-clusters` (+ AWS local cleanup) | Explicitly remove expired managed registrations and stale AWS sandbox state after teardown |
| `make cleanup-stale-sandbox` | `bin/cleanup-stale-sandbox` | Preview stale AWS sandbox local state; add `CONFIRM=1` to remove it |
| `make cleanup-stale-clusters` | `bin/cleanup-stale-clusters` | Preview expired managed ArgoCD registrations; add `CONFIRM=1` to remove them |
| `make cleanup-stale-resources` | Both cleanup scripts | Run both guarded cleanup paths; the local sandbox path runs only for `CLUSTER_PROVIDER=k3s-aws` |
| `make refresh` | `bin/cluster-refresh` | Creds expired or tunnel dropped — re-extracts credentials and restarts tunnel |
| `make status` | `bin/cluster-status` | Read-only health check — Hub nodes, pods, tunnel, ArgoCD |
| `make smoke` | `scripts/k3d-manager smoke_run` | Run the offline webhook check and the cluster health check when the configured context is reachable |

`make smoke SMOKE_ONLY=offline` runs only the webhook check. Use
`SMOKE_ONLY=cluster` to run only the cluster check. An unreachable cluster is
reported as `SKIP`, while a failed check makes the target exit non-zero. Each
check writes its output under `${TMPDIR:-/tmp}/k3dm-smoke/<UTC-run>/`.

## Hub snapshots

`make snapshot` captures the cold hub state and transfers it to
`${K3DM_SNAPSHOT_HOST:-m2jump}:${K3DM_SNAPSHOT_DIR:-k3dm-snapshots}`, where a
relative default resolves against the remote login home. Do not set
`K3DM_SNAPSHOT_DIR` to a `~`-prefixed path: it is passed single-quoted to the
remote shell, which would create a directory literally named `~`.
The capture includes the k3s server database and token, the PV/PVC metadata,
Vault's file-backed data tree, Prometheus, Loki, Keycloak Postgres, OpenLDAP,
and Trivy local-path trees. Use `make snapshot-list` to show each timestamp,
size, and verification state. `make snapshot-prune` removes incomplete
snapshots first and keeps the newest three verified snapshots by default; set
`K3DM_SNAPSHOT_KEEP` to change that ceiling.

`make hub-retain-pvs` patches the mapped Hub PVs to `Retain`; rerun it after
each rebuild. `DISCARD_HUB_DATA=1` explicitly bypasses the `make down`
snapshot guard and permanently loses Hub claims, so use it only when that
consequence is intended.

Prometheus retains only three days (`--storage.tsdb.retention.time=3d`), so an
older snapshot restores blocks that Prometheus immediately prunes on startup.
Snapshots preserve history across a down/up cycle inside that window; they are
not long-term history storage. Long-term retention requires a higher Prometheus
retention setting or remote write.

After a rebuild, generate the new target map and restore with:

```bash
./scripts/k3d-manager hub_recovery_restore <captured-directory> <targets.tsv> --confirm
```

---

## ArgoCD

| Target | When to use |
|---|---|
| `make sync-apps` | Sync `rollout-demo-default` in ArgoCD and show remote pod status |
| `make argocd-registration` | Re-register the app cluster with ArgoCD after sandbox recreation or IP change |
| `make appsets-reapply` | **Every release:** reapply every ApplicationSet (hub and ACG) so its `$values` source tracks the release branch (`BRANCH=`, default: current branch; refuses anything that is not `k3d-manager-vX.Y.Z`) |
| `make appsets-check` | Read-only: list Applications whose k3d-manager values source is not on `BRANCH`; run after `appsets-reapply` |
| `make codex-dispatch SPEC=...` | Start Codex in an isolated worktree for a spec |
| `make codex-status` | Show Codex task state, changes, and scope |
| `make codex-land SLUG=...` | Land a verified, in-scope task |
| `make codex-abandon SLUG=... [YES=1]` | Preview or remove an abandoned task |

`sync-apps` delegates to `bin/cluster-sync-apps` which manages the argocd-server port-forward
automatically (reuses an existing one, starts a new one if needed).

Slack admin commands also support `cluster-up [provider] [dry-run]` and
`cluster-down [provider] [dry-run]`. Dry-run tokens (`dry`, `dry-run`, `--dry-run`,
or `dryrun`) may appear in any order and preview the lifecycle operation without
changing the sandbox.

ApplicationSets freeze their `$values` ref to the branch checked out when they were last applied, so
config committed to a newer release branch is inert until `make appsets-reapply` runs. It is a required
release step (see `CLAUDE.md`).

`argocd-registration` reads the `ubuntu-k3s` kubeconfig, switches to `k3d-k3d-cluster`
context, calls `register_app_cluster`, and restarts the ArgoCD application controller.

---

## Credential Extraction

| Target | When to use |
|---|---|
| `make creds` | Extract AWS/GCP credentials only — no cluster changes |
| `make chrome-cdp` | Install macOS Chrome CDP launchd agent (persistent CDP session on boot) |
| `make chrome-cdp-stop` | Uninstall the launchd agent |
| `make acg-watch` | Install the sandbox TTL watcher launchd agent (checks every 30 minutes) |
| `make acg-watch-stop` | Uninstall the sandbox TTL watcher |
| `make acg-watch-check` | Print the sandbox's remaining minutes without extending it (read-only) |
| `make acg-restart` | Recover an expired ACG sandbox: delete it, recreate it, re-extract credentials |
| `make acg-recover` | End-to-end recovery: `chrome-cdp` + `acg-restart` + a clean `make up` |

`make creds` calls `acg_get_credentials` directly — useful for refreshing short-lived
credentials without touching the cluster.

`make chrome-cdp` installs a `launchd` plist so Chrome starts with CDP flags on login,
enabling headless credential automation without a manual browser launch.

`make acg-watch` wraps `acg_watch_start`: it installs the `com.k3d-manager.acg-watch` launchd agent,
which checks the sandbox every 30 minutes and clicks Extend once 65 minutes or less remain. `make up`
installs it too (Step 12); run `make acg-watch` on its own to pick up a newer lib-foundation without
a full `make up`. `make acg-watch-check` is read-only: it prints `REMAINING_MINS:<n>` and never
clicks Extend — a zero or negative value means the sandbox has already expired. Both accept
`URL=<sandbox-url>` (default: the sandbox list page). See
`scripts/lib/foundation/docs/api/acg.md` ("Sandbox TTL watcher and extend") for how a pass works.

`make acg-restart` wraps `acg_restart` — the recovery path for a sandbox that has already expired
(`acg_extend` only works while one is still alive). It deletes the dead sandbox, provisions a
replacement via Playwright/CDP, then re-extracts and checks the credentials. Accepts
`URL=<sandbox-url>` (default: the sandbox list page) and `PROVIDER=aws|gcp|azure` (default: `aws`).
Needs `make chrome-cdp` in place and a real TTY for the first Pluralsight login. See
[ACG sandbox how-to](acg.md) for the full lifecycle.

`make acg-recover` is the one-shot form: `chrome-cdp` and `acg-restart` as prerequisites, then a
recursive `make up`. Because a replaced sandbox has no EC2 instance and no k3s, `make up` is what
provisions the cluster (Step 2) and re-registers it with ArgoCD (Step 10) — `make
argocd-registration` alone would have nothing to register. The recursive call passes `K3DM_RESUME=`
so an exported `K3DM_RESUME=1` cannot make `cluster-up` reuse checkpoints from the dead sandbox and
skip provisioning.

---

## AWS SSM

| Target | When to use |
|---|---|
| `make ssm` | Ensure `session-manager-plugin` is installed (required for SSM-based workflows) |
| `make provision` | Provision the ACG CloudFormation stack with SSM support (depends on `ssm`) |

`make provision` is equivalent to `K3S_AWS_SSM_ENABLED=true scripts/k3d-manager acg_provision --confirm`.
It installs the SSM plugin first via `make ssm` then provisions the full CloudFormation stack.

## Host Setup

| Target | When to use |
|---|---|
| `make sudoers` | One-time setup: install `/etc/sudoers.d/k3d-manager` so `make up/down/refresh` run without sudo password prompts |

`make sudoers` delegates to `bin/install-sudoers.sh`. It validates the rules with
`visudo -c` before installing. To remove: `bin/install-sudoers.sh --uninstall`.

---

## Docs & Prior Art

| Target | Command | When to use |
|---|---|---|
| `make index-docs` | `python3 scripts/index-docs.py` | Embed the tracked `docs/bugs`, `docs/issues`, `docs/plans` and `docs/retro` trees into the pgvector store. Add `DRY_RUN=1` to report what would be embedded without calling the API, or `LIMIT=<n>` to cap the document count |
| `make find-similar-docs` | `python3 scripts/find-similar-docs.py` | Dedup pass 2 before filing a bug or issue — `Q="<the symptom in prose>"` is required, `K=<n>` sets how many results to rank (default 5) |

Both targets are **advisory and always exit 0**. A missing credential, an
unreachable store or an empty index reports on stderr and succeeds, because a
dedup aid must never become a new way for filing a bug to fail. A high
similarity score means *read that file before filing*, not *do not file*.

Only each document's title, leading paragraph and `##` headings are embedded —
roughly 3% of a typical file — and rows are keyed by a content hash of exactly
that text, so re-running with no doc changes makes zero API calls. The v1.40.0
live eval measured a modest recall gain over a TF-IDF control on bugs only, with
more intrusion — results stay advisory; see
[Vector Store](../guides/vector-store.md).

A cold index on the free Gemini tier spans **two sittings**, not one: the
per-day allowance is spent before the corpus finishes. A partial run is durable
— each batch of 100 commits in its own transaction — so a resumed run adds to
the store rather than truncating it. See
[Vector Store](../guides/vector-store.md) and
[Find Prior Art](find-prior-art.md).

---

## Test Suites

| Target | Command | When to use |
|---|---|---|
| `make test` | `scripts/k3d-manager test all` | The dispatcher BATS suites — `scripts/tests/lib`, `core`, `plugins` and `etc`, one level deep each. Takes **~15 minutes**; a quiet terminal is not a hang |
| `make test-bin` | `bats scripts/tests/bin` | The BATS suites for `bin/` scripts and `Makefile` behaviour, which `make test` does **not** reach |
| `make test-python-unit` | `python3 scripts/tests/bin/<suite>.py` | The stdlib-`unittest` suites — every `scripts/tests/bin/*.py` whose name is not `test_*.py` |
| `make test-pytest` | `pytest scripts/tests/hermes scripts/tests/bin/test_*.py` | The pytest suites — Hermes plus the `test_*.py` files under `scripts/tests/bin` |
| `make test-python` | `test-python-unit` + `test-pytest` | Both Python halves in one call |
| `make test-all` | `test` + `test-bin` + `test-python` + metrics publication | Everything that runs offline, with the result sent to the `k3dm Tests` dashboard |
| `make lint-python` | `ruff check -- <tracked Python files>` | Run Ruff's pyflakes rules over `.py` files and Python-shebang scripts |
| `make validate-manifests` | `kubeconform -strict -summary` | Validate Kubernetes manifests, custom resources included, against the Datree CRD catalog pinned to a commit. Defaults to platform-ops, Prometheus rules, Grafana dashboards and ApplicationSets; `FILES="a.yaml b.yaml"` overrides the set. Installs kubeconform if missing (Homebrew, else the pinned release into `~/.local/bin`, SHA-256 checked) and needs network for the schemas |

**A new BATS suite must live in one of those directories or nothing runs it.**
Discovery is by directory glob, not by file pattern: the dispatcher globs
`scripts/tests/{lib,core,plugins,etc}` at `-maxdepth 1`, and `make test-bin`
globs `scripts/tests/bin`. A `.bats` file at the `scripts/tests/` root, or
nested a level deeper inside one of those directories, is collected by nothing
and reported by nothing — it passes when run by hand and never runs again.
Three suites sat at the root this way until v1.40.0. Put plugin tests in
`plugins/`, `bin/` and `Makefile` tests in `bin/`.

`make test` alone is **not the CI gate.** CI runs `make test`, `make test-bin`,
`make test-python-unit` and `make test-pytest` as four separate steps, so a
branch that is green under `make test` can still be red on a Python suite.

**The two Python targets split on filename, and the split is enforced.**
`test-python-unit` runs each file as a script, so a file that defines bare
`def test_` functions with no `unittest.main()` or `pytest.main()` hook would
execute nothing and still exit 0. Rather than pass silently, the target fails
with exit 2 and tells you to rename the file to `test_*.py` so
`make test-pytest` collects it. It also exits 2 when it finds no suites at all —
an empty glob is a broken checkout, not a pass.

**`make test-pytest` resolves an interpreter in four steps** and exits 2 with
the list if none works: `$PYTEST` (word-split, so
`PYTEST="python3 -m pytest"` works), `pytest` on `PATH`, `python3 -m pytest`,
then `~/.pyenv/shims/python3 -m pytest`. The last fallback exists because this
target also runs from the webhook, whose `PATH` excludes the pyenv shims. Exit 2
from this target means *no pytest was found*, never *a test failed*.

Missing `bats` is the same shape — `make test-bin` exits 2 with
`brew install bats-core` rather than reporting a pass.

**Read per-suite counts, not just the exit code.** A non-zero status from any of
these can mean the tooling was absent (exit 2) or that assertions failed, and
the two want opposite responses.

---

## Test Metrics

| Target | Command | When to use |
|---|---|---|
| `make test-metrics` | `make test-all` | Compatibility reporting wrapper; `test-all` now performs the single metrics publication |

The `test-metrics` wrapper **always exits 0** — it is a reporter, not a gate. The
suite's real exit code travels in the `k3dm_test_exit_code` metric rather than the
wrapper's status. `make test-all` itself remains a gate and returns the original
suite status after publishing, so use it when the caller must fail on a test failure.

The raw log path is echoed by `test-all`; the log itself is kept under
`${TMPDIR:-/tmp}/k3dm-test-all-<epoch>.log`.

---

## Help

```bash
make help    # print all targets with one-line descriptions
make         # same as make help (DEFAULT_GOAL)
```

---

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `URL` | `https://app.pluralsight.com/hands-on/playground/cloud-sandboxes` | Sandbox URL passed to `bin/cluster-up` and `bin/cluster-refresh` |
| `GHCR_PAT` | `$(gh auth token)` | GitHub Container Registry token — used by `cluster-up` to create the `ghcr-pull-secret` |
| `KEEP_LOCAL` | `1` | Set to `0` to delete the local Hub cluster when running `make down` (equivalent to `DELETE_HUB=1`) |
| `DELETE_HUB` | `0` | Set to `1` to delete the local Hub cluster when running `make down` |
| `DISCARD_HUB_DATA` | `0` | Set to `1` to bypass the fresh-snapshot guard when deleting the local Hub |
| `CLEANUP_STALE` | `0` | Set to `1` to run guarded stale-resource cleanup after `make down` |

Set `GHCR_PAT` before running `make up`:

```bash
export GHCR_PAT=$(gh auth token)
make up
```
