# Bug: `make test` fails 7 tests on a fresh Linux control-node clone (three test-hermeticity causes)

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-10 (intent approval; then dispatch as children when WIP allows)
**Introduced by:** A `82c1d9c8` (v1.43.14 release squash); B pre-existing (`945018ee`, v1.36.0); C `76446d6e` (v1.43.15, helm skip guard)
**Should have been caught by:** A review (the 2026-08-03 lesson: fixtures must not depend on branch-only commits); B offline test (host tool not stubbed); C offline test (skip guard never run on a host without helm)
**Prior art:** `docs/issues/2026-08-03-stale-test-refs-fixture-orphaned-by-branch-cleanup.md` — read, same class as A (recurrence; that doc recommended a self-contained fixture); `docs/bugs/2026-10-24-ci-promql-tests-blocked-by-tripwire-docker.md` — read, related to C (tripwire vs tool fallback), different mechanism; `make find-similar-docs` not run (vector store unreachable from the M4)
**Severity:** test-only. Blocks M3 of `docs/plans/v1.43.15-control-node-linux.md` (make test on Ubuntu 24.04 with only labelled skips), so control-node E3 cannot pass and Hostinger E4 stays held. Workaround: install helm and apache2-utils on the node and clone with all branches.
**Approval:** Claude, 2026-11-10 (found in control-node E3); dispatch needs the operator's intent approval
**Filed:** 2026-11-10
**Detected by:** Claude, live E3 probe, Vagrant `bento/ubuntu-24.04` aarch64 on the M4, k3dm-control's clone at `dfb29052` (scratchpad `control-e3/make-test2.log`: 2033 ok, 21 skip, 7 not ok)
**Branch:** `k3d-manager-v1.43.15`

## Root causes (each reproduced by Claude in the VM, 2026-11-10)

**A. Test 526 `agent dispatch dashboard: verification ladder contract`** (`scripts/tests/plugins/agent_dispatch_dashboard.bats:61`)
runs `git show 028b898f:<dashboard>` as its baseline. `028b898f` is reachable only from `origin/k3d-manager-v1.43.14`
(v1.43.14 was squash-merged as `82c1d9c8`, so main does not contain it). `bin/k3dm-machine-setup:119` clones
`--single-branch`, so the control clone has only main: `fatal: Not a valid object name 028b898f`. CI passes only because
`fetch-depth: 0` still finds the v1.43.14 branch on origin; deleting that branch (or a tag-less cleanup) turns CI red.

**B. Test 272 `deploy_observability calls envsubst ...`** (`scripts/tests/lib/observability.bats:82`) reaches the real
`htpasswd` through `scripts/plugins/observability.sh` (`htpasswd -niBC 12 admin`). macOS ships `/usr/sbin/htpasswd`;
Ubuntu does not without `apache2-utils`: `ERROR: [observability] htpasswd required to generate Prometheus basic-auth`.

**C. Tests 800-804 `loki: rendered config ...`** (`scripts/tests/plugins/argocd_loki.bats:17-19`) guard with
`command -v helm || skip "helm is missing"`. Run directly, they skip correctly on a host without helm. Under
`scripts/tests/tripwire.sh` (how `make test` runs), the tripwire installs a `helm` shim in its own bin dir for every
listed tool whether or not the real tool exists, so `command -v helm` succeeds, the skip never fires, and the shim's
passthrough fails: `/tmp/k3dm-tripwire.D6c0KK/bin/helm: line 4: exec: helm: not found`.

## Fix (three children, independent files)

| Child | File | Change |
|---|---|---|
| A | `scripts/tests/plugins/agent_dispatch_dashboard.bats` (+ a fixture under `scripts/tests/fixtures/`) | Replace the `git show 028b898f:` baseline with a committed fixture copy of that file version (byte-identical to `git show 028b898f:scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`). No git history lookup. |
| B | `scripts/tests/lib/observability.bats` | Stub `htpasswd` on PATH in this test (records argv, prints a fixed `admin:$2y$12$...` line); assertions unchanged. |
| C | `scripts/tests/tripwire.sh` | Create a shim only for tools that resolve on the real PATH before the shim dir is prepended; an absent tool stays absent, so `command -v` guards keep working. |

Integration verify (Claude): rerun `make test` in a fresh single-branch Linux clone (Vagrant), expect 0 not ok and the
Loki tests reported as `skip helm is missing`.

## Contract readers

- C changes `scripts/tests/tripwire.sh`'s shim set. Readers: every `make test`/`make test-pytest`/land `--test` run
  wrapped by it (Makefile `test` target, `bin/k3dm-codex-dispatch land`); behaviour changes only when a listed tool is
  absent on the host. Writers: none. The blocked-call report (`kubectl ... get --raw=/readyz` counts) is unchanged for
  tools that exist.
- A and B change only their own test files.

## Acceptance

```yaml
must:
  M1: test 526 passes in a clone that has no commit 028b898f (single-branch clone of main), comparing against the committed fixture
  M2: test 272 passes on a host with no htpasswd, and on macOS still passes with the same assertions
  M3: on a host without helm, the five Loki render tests report skip "helm is missing" under scripts/tests/tripwire.sh
  M4: on a host with helm, the Loki render tests still run and pass under the tripwire (paired with M3)
must_not:
  N1: the tripwire never lets a blocked (mutating) call to a tool that exists reach the real binary; the block report still lists it
  N2: no test in these files reads git history for its baseline
evidence:
  - {id: E1, proves: [M1, N2], kind: offline, intent: "You will see test 526 pass in a scratch single-branch clone where `git cat-file -t 028b898f` fails, and fail on today's test."}
  - {id: E2, proves: [M2], kind: offline, intent: "You will see test 272 pass with PATH stripped of htpasswd, and fail on today's test."}
  - {id: E3, proves: [M3, M4, N1], kind: offline, intent: "You will see the tripwire run the Loki tests as skips with helm hidden from PATH and as passes with helm present, and a stubbed `kubectl apply` still blocked and reported."}
  - {id: E4, proves: [M1, M2, M3], kind: live, intent: "Claude reruns make test as k3dm-control in a fresh Vagrant VM clone and sees 0 not ok."}
interface:
  - "make test (scripts/tests/tripwire.sh ./scripts/k3d-manager test all)"
  - "bats scripts/tests/plugins/agent_dispatch_dashboard.bats scripts/tests/lib/observability.bats scripts/tests/plugins/argocd_loki.bats"
```

## Worker definition of done (per child)

- Change only the child's files. Show the child's test red on today's code (for A, in a scratch `--single-branch`
  clone under the scratchpad; for B, PATH without htpasswd; for C, PATH without helm), then green. For C also show
  N1: a `kubectl apply` through the tripwire is still blocked. Paste command, rc and proving lines. Leave changes
  uncommitted; Claude reviews and lands.

## Recurrence (Claude, 2026-11-11)

Control-node E3 rerun after the Vagrant P3 and the missing-formula P2 landed: fresh M4 Vagrant VM, k3dm-control's
clone at `ad383619`, `make test` rc 2: 2040 tests, 2033 ok, 21 skip, the same 7 not ok (272, 526, 800-804). Rerun
of those three files with `bats --print-output-on-failure` outside the tripwire: 272 `htpasswd required` (B), 526
`git show 028b898f` CalledProcessError (A), Loki M1 `skip helm is missing` (C: skips outside the tripwire, fails
inside). Same three causes; no new failure. E3 stays FAILED on this bug alone; Hostinger E4 stays held.

