# Offline test sweep: the `test*` targets now run behind a PATH tripwire

**Date:** 2026-10-01
**Branch:** `k3d-manager-v1.40.0`
**Spec:** `docs/plans/v1.40.0-cloud-bridge-test-targets.md` (M1 evidence, M2 control)
**Closes the sweep asked for in:** `docs/bugs/2026-09-25-deploy-app-cluster-confirm-bats-mutates-live-cluster.md`

## Why

The cloud bridge now exposes `make test`, `test-bin`, `test-python` and `test-all` at reader tier.
"The suites are offline" was a repo convention plus an unfinished sweep. On the operator's host a
cluster, the AWS credentials and the login keychain are always reachable, so a test that falls
through to a real binary is not a theoretical risk there.

## Method: run the suites, don't read them

Reading 149 BATS files and 35 Python files for "stubbed only when unreachable" paths is exactly
the review that missed the 2026-09-25 bug. Instead, every suite was run with a directory of shims
first on `PATH` for 31 cluster, cloud, credential and AI tools (`kubectl`, `helm`, `k3d`, `docker`,
`aws`, `gcloud`, `az`, `vault`, `argocd`, `security`, `launchctl`, `ssh`, `gh`, …). Each shim logs
its argv and exits 97. A test's own stubs still win because tests prepend their stub directory.
Anything in the log is a call that would have reached the real binary on the operator's host.

## Findings (first full run, before any fix)

| tool | call | from | verdict | action |
|---|---|---|---|---|
| `k3d` | `cluster delete k3d-test-orbstack-exists` | `provider_contract.bats` `teardown_file` | **mutation** on the host; dead code (nothing creates that cluster) | removed |
| `kubectl` | `-n vectordb get pod` / `get externalsecret` / `exec … psql` ×14 each | `test_hermes.py` — two sensor-stub lists predate the `vectordb` sensor | live DB access, `exec` | `vectordb` added to both lists |
| `kubectl` | `-n secrets get secret vault-root` ×7 | `test_e2e_bugs.py`, `test_app_health.py` — new docs call `search()` (v1.40.0 WS4) | **reads the Vault root token** | `scripts/tests/hermes/conftest.py` stubs `search` by default |
| `security` | `find-generic-password` (embeddings / gemini keys) ×7 each | same `search()` path | keychain credential read | same fix |
| `gh` | `auth token` ×7 | BATS (`scripts/tests/`) | reads the real GitHub token | blocked; read-classified |
| `kubectl` | `--context ubuntu-{k3s,hostinger,gcp,azure} get --raw=/readyz` ×38 each | BATS | read, network | blocked |
| `aws` | `cloudformation describe-stacks` ×5 | BATS | read, real AWS credentials | blocked |
| `helm` | `list`, `version` | BATS | read | blocked / passed through |
| `security` | `find-generic-password` for slack, webhook, alertmanager items | `webhook/auth.py` at **module import**; several suites | keychain read | blocked; see Residuals |

Every suite also passed under the tripwire except one legitimate case: `e2e.bats` "payment
substrate renders offline" runs `kubectl kustomize`, a pure offline render. The tripwire passes a
short list of offline subcommands (`kubectl kustomize`, `helm template`/`lint`, `* version`)
through to the real binary.

## The control (M2)

`scripts/tests/tripwire.sh` is now part of the targets: `test`, `test-bin`, `test-python-unit` and
`test-pytest` run their suite command through it, and `test-python` / `test-all` only compose
those. So the offline property comes from the targets, not from each test author.

- Blocked calls are summarized on stderr after every run.
- A blocked call that is not a known **read** fails the run, even when every test passed. Reading a
  Kubernetes Secret counts as a credential read and fails; so does any `gh`, `security` or
  `launchctl` verb outside a short read list.
- `scripts/tests/bin/test_test_tripwire.py` keeps it true: every recipe routes through the
  tripwire, the tool list covers the required set, a mutating call fails the run without the real
  binary ever executing, Secret reads and `gh pr merge` are not reads, offline subcommands pass
  through, and the command's own exit code is preserved. Each assertion was mutation-tested
  (unwrapped recipe, strict mode off, Secret reads allowed, `gh` dropped — all red).

Result with the fixes in place: every target green under the strict tripwire; the only blocked
calls left are reads.

## Residuals (stated, not hidden)

- **Keychain reads at import.** `scripts/lib/webhook/auth.py` reads the Slack signing secret and
  role map from the keychain when the module is imported. Under the tripwire those reads never
  reach the keychain, but removing them means changing production code; left as a follow-up.
- **The tripwire is PATH-based.** A test that sets `PATH` from scratch, or calls a tool by absolute
  path, steps around it. Searched 2026-10-01: four tests replace `PATH`
  (`shopping_cart.bats` ×2 with `/dev/null`, `k3s_oci_provider.bats`, `safe_path.bats`); none
  calls a tripwired tool. No test calls one by absolute path.
- **Coverage is the tool list.** A new cluster or cloud CLI must be added to `TRIPWIRE_TOOLS`.
