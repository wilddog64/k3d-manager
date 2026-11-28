# Operator Acceptance Guide

Automated acceptance scenarios and live profile verification for `k3d-manager` observability, metrics publication, cloud session requests, and cleanup isolation.

## 1. What it checks

The offline harness executes nine registered acceptance scenarios covering the `k3dm-tests` dashboard, webhook job status, and cleanup isolation. Each scenario asserts product contracts against isolated stubs and local fixtures:

| Scenario ID | What it proves | Status |
|---|---|---|
| `metrics-totals` | Real `bin/k3dm-test-metrics` exporter publishes case totals (`k3dm_test_cases_total`, `k3dm_test_cases_failed`) matching fixture logs to a replace-semantics fake Pushgateway. | `passed` |
| `metrics-pass-fail-fail-pass` | Replays a pass-fail-fail-pass sequence; last run timestamp advances on each run, last success timestamp holds across failures and advances at recovery, and failure groups clear on recovery. | `passed` |
| `metrics-publication-failure` | Exporter reports skipped publication when Pushgateway PUT fails; currently exits 0 instead of non-zero. | `known_failing` |
| `panels-promql` | Evaluates every Prometheus expression in the `k3dm-tests` dashboard ConfigMap using `promtool test rules` across test series, verifying panel queries and empty states. | `passed` |
| `panels-multi-target` | Verifies whether summary panels differentiate target series; currently takes `max()` across targets and hides stale test runs. | `known_failing` |
| `job-output` | Webhook job output reader and status API report exit code 7, failed classification, retain failing assertions and tails, and scrub canary credentials. | `passed` |
| `cleanup-preview` | Stale sandbox cleanup preview avoids destructive commands (`bootout`, `delete-context`) and leaves scratch state empty. | `passed` |
| `cleanup-ambient-confirm` | Stale sandbox cleanup script inherits ambient `CONFIRM=1` environment variables unless scrubbed by an isolation guard. | `known_failing` |
| `cleanup-vocabulary` | Webhook thread command parser rejects `cleanup-stale-sandbox apply` while the Slack relay accepts it. | `known_failing` |

### Known failing scenarios

Four scenarios are registered as `known_failing`. These represent captured product contract gaps that are tracked in dedicated bug documents rather than weakened in test assertions:

- `metrics-publication-failure`: [`docs/bugs/2026-11-26-test-metrics-exporter-exits-zero-when-push-fails.md`](../bugs/2026-11-26-test-metrics-exporter-exits-zero-when-push-fails.md) — Exporter exits 0 when Pushgateway PUT fails.
- `panels-multi-target`: [`docs/bugs/2026-11-26-k3dm-tests-summary-panels-max-across-targets-hide-stale-test-all.md`](../bugs/2026-11-26-k3dm-tests-summary-panels-max-across-targets-hide-stale-test-all.md) — Summary panels 1-2 aggregate `max()` across targets, hiding stale `test-all` runs behind fresh `test` runs.
- `cleanup-ambient-confirm`: [`docs/bugs/2026-11-26-stale-sandbox-cleanup-inherits-ambient-confirm.md`](../bugs/2026-11-26-stale-sandbox-cleanup-inherits-ambient-confirm.md) — Cleanup script inherits ambient `CONFIRM` from parent shells (also serves as positive control for the isolation guard).
- `cleanup-vocabulary`: [`docs/bugs/2026-11-26-cleanup-stale-sandbox-apply-accepted-by-slash-command-refused-in-thread.md`](../bugs/2026-11-26-cleanup-stale-sandbox-apply-accepted-by-slash-command-refused-in-thread.md) — Relay accepts `apply` but thread parser expects `cleanup-stale-sandbox confirm`.

## 2. Run it

To run the offline acceptance scenarios:

```bash
make test-operator-acceptance
```

Or run the CLI binary directly:

```bash
bin/k3dm-operator-acceptance [--scenario <id>]... [--run-root <path>] [--with-prior-art]
```

The CLI supports the following options:

- `-h`, `--help`: Show usage and options.
- `--scenario`: Run specific scenarios by ID (can be repeated). Cannot be combined with `--live`.
- `--run-root`: Set a custom run directory root.
- `--live`: Run the opt-in live profile instead of offline scenarios.
- `--with-test-all`: Include the ~70-minute `make-test-all` leg and Grafana dashboard verification (requires `--live`).
- `--with-prior-art`: Query `prior_art.search` for advisory candidate bug docs on contract failures.

### Run root and retention

Each run writes to a timestamped directory `$K3DM_ACCEPTANCE_RUN_ROOT/<UTC timestamp>-<8 hex>/` with directory permissions `0700` and file permissions `0600`. The default root is:

```
~/.local/state/k3d-manager/acceptance
```

Retention is evaluated automatically on each run using two environment variables:

- `K3DM_ACCEPTANCE_RUN_ROOT`: Custom path to the acceptance run root.
- `K3DM_ACCEPTANCE_RETENTION_DAYS`: Delete runs older than this many days (default: `14`).
- `K3DM_ACCEPTANCE_MAX_MB`: Delete oldest runs until total root size is under this limit (default: `500`).

Only directories matching `<timestamp>-<hex>` directly under the root are pruned; other files or subdirectories are never touched.

### Running in pytest

The offline scenarios also run inside `make test-pytest` via `scripts/tests/bin/test_operator_acceptance.py`. This ensures acceptance scenarios execute during `make test-all` and CI within a 30-second budget on macOS.

### Inconclusive results

If `promtool` is not installed on the system, scenarios requiring it (`panels-promql` and `panels-multi-target`) report an `inconclusive` outcome with cause `environment_dependency`. To install `promtool`, run:

```bash
make machine-setup
```

Or install Prometheus via Homebrew (`brew install prometheus`).

## 3. Reading the report

Each run creates three report files in the run directory:

1. `report.json`: Machine-readable report conforming to schema version 1.
2. `junit.xml`: Standard JUnit test suite XML for CI parsers.
3. `report.md`: Human-readable Markdown summary table.

### Schema 1 fields

`report.json` contains:

- `schema`: Integer version (`1`).
- `source_sha`: Source commit SHA or `"unknown"`.
- `started`: ISO-8601 UTC start timestamp.
- `finished`: ISO-8601 UTC finish timestamp.
- `scenarios`: Array of scenario results. Each entry contains:
  - `id`: Scenario identifier string.
  - `outcome`: One of `passed`, `failed`, `known_failing`, `inconclusive`, or `skipped`.
  - `cause`: One of `product_contract`, `environment_dependency`, `harness_error`, or `unknown`.
  - `assertions`: List of individual assertions (`name`, `passed`, `detail`).
  - `linked_bug`: Path to the tracking bug document for `known_failing` scenarios, or `null`.
- `drafts`: Array of generated bug draft records (when failures occur).
- `prior_art`: Advisory prior-art candidates (when `--with-prior-art` is enabled).

### Outcome and cause values

- `passed`: All assertions succeeded (`cause: unknown`).
- `failed`: An assertion failed on an unlinked product contract (`cause: product_contract`). Causes the run to exit 1.
- `known_failing`: An assertion failed on a known gap linked to an existing bug document (`cause: product_contract`). Does not fail the run.
- `inconclusive`: Missing environment tool (`cause: environment_dependency`) or internal harness error (`cause: harness_error`). Causes the run to exit 1.

## 4. Isolation guarantees

The offline harness enforces strict sandbox boundaries before executing child processes:

- **Refused ports and hosts:** Network calls are restricted to loopback (`127.0.0.1` and `::1`) on dynamic ephemeral ports bound by the harness. Ports `9091` (Pushgateway), `19094`, and `7443` (webhook) are refused. Non-loopback addresses and non-HTTP schemes are blocked.
- **Allowlisted environment:** Child processes receive only `LANG`, `TMPDIR`, stubbed `PATH`, scratch `HOME`, and `K3DM_STUB_LOG`, plus scenario-specific explicit variables. Parent environment variables such as `CONFIRM`, `CLUSTER_PROVIDER`, `ACG_KUBE_CONTEXT`, `SLACK_*`, `K3DM_SLACK_*`, `VAULT_*`, `GITHUB_*`, and `K3DM_PUSHGATEWAY_URL` never pass through.
- **Stub PATH:** A dedicated stub directory prepends `PATH`, intercepting `launchctl`, `kubectl`, `security`, `docker`, `git`, and `curl`. All stubs log invocations to `stub.log` and exit 0 (except `git push`, which exits 1).
- **Scratch HOME:** Each run executes with `HOME` pointed at `<run_dir>/home` (mode `0700`), verified not to match the user's real home directory.
- **What it never does:** The offline harness never sends Slack messages, never runs `git push`, never connects to the live hub webhook, and never starts or touches containers.
- **Redaction:** All output written to report files is sanitized with `scrub_credentials` and scrubbed of Slack webhook URLs and user tokens.

## 5. Live profile

The live acceptance profile checks the end-to-end cloud session request pipeline and verifies the live `k3dm-tests` Grafana dashboard on the hub.

To run the live profile:

```bash
K3DM_ACCEPTANCE_LIVE=1 make test-operator-acceptance-live PROFILE=k3dm-tests
```

Or via CLI:

```bash
K3DM_ACCEPTANCE_LIVE=1 bin/k3dm-operator-acceptance --live [--with-test-all] [--with-prior-art]
```

### Safety requirements and closed action list

The live profile enforces strict safety constraints:

1. **Explicit opt-in and TTY:** Refuses to run unless `K3DM_ACCEPTANCE_LIVE=1` is exported in the shell and the process is connected to an interactive terminal (TTY).
2. **Single-instance serialization:** Uses `live.lock` in the run root via non-blocking `fcntl.flock`. If another live run is in progress, the command refuses immediately.
3. **Closed action list:** The profile can only submit four allowed actions through `bin/k3dm-cloud-request`:
   - `cluster-status` (waits for terminal status, deadline 120s)
   - `job-status` (reads status for submitted jobs)
   - `make-test-python-unit` (waits for final response, deadline 600s)
   - `make-test-all` (only with `--with-test-all`, deadline 6000s)
   Before submitting any action, the profile verifies that the action is in this closed list and that `gated(action)` is false. Gated actions (`make-e2e`, `sandbox-up`, `sandbox-down`) are never submitted by acceptance.

### Grafana Viewer token

When `--with-test-all` is passed, the live profile queries the live Grafana instance on the hub to verify panel freshness (panels 1, 3, and 9) following the `make-test-all` run.

- **Creating the Service Account:** In Grafana (`https://grafana.3ai-talk.org` or hub loopback), the operator creates a Service Account with the **Viewer** role (e.g. `k3dm-acceptance-viewer`) and generates a Viewer token. Never use the admin password or a Vault read.
- **Keychain storage:** Save the token to macOS Keychain under service item `k3dm-grafana-viewer-token`:
  ```bash
  security add-generic-password -a k3dm -s k3dm-grafana-viewer-token -w
  ```
- **Token expiration and rotation:** The Viewer token expires (the initial token expires 2027-01-26). When expired, the Grafana leg fails with HTTP 401. To rotate: generate a new token on the same service account in Grafana and update the Keychain item:
  ```bash
  security add-generic-password -U -a k3dm -s k3dm-grafana-viewer-token -w
  ```
- **Security:** The token is read into memory by item name only. It is never printed, logged, stored in reports, or passed on command lines. Requests include an explicit `User-Agent: k3dm-operator-acceptance/1` to satisfy tunnel access policies.

### Local-only bug drafts

When a live or offline scenario fails with cause `product_contract`, the harness writes a local bug draft under `<run_dir>/drafts/<fingerprint>.md` (mode `0600`):

- **Fingerprint:** A 12-character hex hash calculated from scenario ID, assertion ID, and normalized expected/actual output.
- **Header format:** Standard canonical bug template (`Status: OPEN — captured, not triaged`, `Priority: P3 (proposed)`, `Introduced by: unknown`, `Should have been caught by: live check`, etc.).
- **Deduplication:** The harness checks if the fingerprint matches existing bug docs in `docs/bugs/*.md` or drafts in previous acceptance runs. If already seen, no new draft is written and the report notes `seen before: <path>`.
- **Local isolation:** Drafts remain strictly inside the run directory. They are never committed, never pushed to git, never copied into `docs/bugs/`, and never posted to Slack.
- **Prior art:** When `--with-prior-art` is enabled, the harness queries `hermes.prior_art.search` for the top 3 advisory matches. If retrieval is unavailable, the error is recorded in the report without failing the run.

## 6. Known limits

1. **Pushgateway restart:** The hub Pushgateway does not persist metrics to disk. If the Pushgateway restarts, the `-last-success` group is lost until the next successful test run.
2. **Summary panels across targets:** Panels 1 and 2 on the `k3dm-tests` dashboard evaluate `max(k3dm_test_last_timestamp_seconds)` across all targets. A fast test target can mask a stale `test-all` run. See [`docs/bugs/2026-11-26-k3dm-tests-summary-panels-max-across-targets-hide-stale-test-all.md`](../bugs/2026-11-26-k3dm-tests-summary-panels-max-across-targets-hide-stale-test-all.md).
3. **Out of scope checks:** Rendered Grafana visual checks using browser automation (Playwright) and document index canary monitoring are not included in this harness; these proposals are tracked in `docs/ideas.md`.
