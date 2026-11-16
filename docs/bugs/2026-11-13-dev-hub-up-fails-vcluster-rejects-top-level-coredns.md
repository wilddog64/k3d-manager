# dev-hub-up fails: vCluster 0.32.1 rejects the top-level `coredns` key in values-dev-hub.yaml

**Status:** LIVE-VERIFIED — 8c2bfc5f live on m5-air (2026-11-13)
**Priority:** P1 (Claude proposal: `make dev-hub-up` cannot create the dev hub, no workaround short of editing the file; blocks dev-hub plan E2 in the open v1.44.0 release)
**Classified:** pending (Argon, from this doc alone)
**Introduced by:** b2067ad3 (dev-hub Part A, `scripts/etc/vcluster/values-dev-hub.yaml`)
**Should have been caught by:** offline test (no test validates the values file against the pinned chart schema; the plan's source table cites `coredns` values ~521–530, which sit under `controlPlane`)
**Fix commit:** `8c2bfc5f`
**Prior art:** exact-slug glob, no match; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing)
**Approval:** operator, 2026-11-13: "go ahead to fix coredns"
**Dispatch go:** operator, 2026-11-13: "go ahead to fix coredns"
**Intent approved:** operator, 2026-11-13

## Symptom

On m5-air, 2026-11-13 09:44 PST, after the promote of 9a579a05, `make dev-hub-up` created the PriorityClass, namespace, ResourceQuota and LimitRange, then:

    fatal merge values: invalid config: error unmarshaling JSON: while decoding JSON: json: unknown field "coredns"
    ERROR: failed to execute .../vcluster/0.32.1/vcluster create dev-hub -n dev-hub --chart-version 0.32.1 --connect=false -f .../scripts/etc/vcluster/values-dev-hub.yaml: 1

## Proof of external behaviour

vCluster v0.32.1 (tag commit `9d2cec3`), `chart/values.schema.json` fetched with `gh api repos/loft-sh/vcluster/contents/chart/values.schema.json?ref=v0.32.1` by Claude on m4-air, 2026-11-13:
- the root has `additionalProperties: false`; its properties are `controlPlane deletion deploy experimental exportKubeConfig global integrations logging networking platform plugin plugins policies privateNodes pro rbac serviceCIDR sleep snapshots sync telemetry` (no `coredns`);
- `controlPlane.coredns.deployment.resources` exists.
- Walking all three files in `scripts/etc/vcluster/` against the schema: `values-dev-hub.yaml` has one unknown key, `.coredns`; `values.yaml` and `values-preflight.yaml` are clean.

## Fix

Move the `coredns:` block under `controlPlane:` unchanged (same `deployment.resources` values: requests 20m/32Mi, limits 100m/128Mi). No other key changes.

Retry is safe: `dev_hub_up` applies host objects with `apply` and creates the vCluster only when `_dev_hub_cluster_exists` is false, so the objects left by the failed run need no cleanup.

## Acceptance

```yaml
must:
  - id: M1
    text: values-dev-hub.yaml sets controlPlane.coredns.deployment.resources to requests cpu 20m memory 32Mi, limits cpu 100m memory 128Mi
  - id: M2
    text: every top-level key of each vCluster values file, scripts/etc/vcluster/values*.yaml (values.yaml, values-dev-hub.yaml, values-preflight.yaml; not the argocd-manager-rbac.yaml manifest), is in the v0.32.1 root property list (captured above; the test names host, date and tag commit in a comment)
must_not:
  - id: N1
    text: values-dev-hub.yaml has a top-level coredns key (red on pre-fix)
  - id: N2
    text: any other value in values-dev-hub.yaml changes (compare the parsed file with the pre-fix parse after moving coredns back)
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: The dev hub values file uses only keys vCluster 0.32.1 accepts, with the same CoreDNS limits as before, and a test fails if a top-level key outside the chart's list comes back.
    command: bats scripts/tests/plugins/dev_hub.bats (new tests red on b2067ad3..9a579a05 values file)
  - id: E2
    proves: [M1]
    kind: live
    intent: After a promote, make dev-hub-up on the M5 creates the dev hub and the coredns pod in host namespace dev-hub has a 128Mi memory limit; this is the start of dev-hub plan E2.
interface: scripts/etc/vcluster/values-dev-hub.yaml
```

## Contract readers

- `scripts/plugins/dev_hub.sh:9` (`DEV_HUB_VALUES`), passed as `VCLUSTER_VALUES_FILE` to `vcluster_create` (`scripts/plugins/vcluster.sh`) — reads the file; unchanged.
- `scripts/tests/plugins/dev_hub.bats:432-460` — scanner tests read the file by path; unchanged.
- writers: none besides this fix.

## Files

- `scripts/etc/vcluster/values-dev-hub.yaml`
- `scripts/tests/plugins/dev_hub.bats`

## Definition of done (worker)

- Edit text only (do not re-serialise the YAML): move the `coredns:` block under `controlPlane:` with two extra spaces of indent; nothing else in the file changes.
- In `dev_hub.bats`, add tests for M1, M2/N1 and N2. The M2 test holds the 21 root keys above as a literal list with a comment naming the source (`chart/values.schema.json` at v0.32.1, tag commit 9d2cec3, captured on m4-air 2026-11-13), parses each `scripts/etc/vcluster/values*.yaml` (asserting the glob found exactly `values-dev-hub.yaml`, `values-preflight.yaml` and `values.yaml`) with the repo's existing YAML approach, and fails naming the file and key. Do not remove or weaken any existing test or assert.
- Run and paste command, exit code and summary line: `bats scripts/tests/plugins/dev_hub.bats` (0 not ok); then with `values-dev-hub.yaml` temporarily restored from `git show HEAD:scripts/etc/vcluster/values-dev-hub.yaml` (keep your test edits) the new N1 test is not ok; restore your fix.
- Do not commit; leave changes in the worktree.

**Spec correction 2026-11-13 (Claude):** M2 said `scripts/etc/vcluster/*.yaml`, which also matches the multi-document Kubernetes manifest `argocd-manager-rbac.yaml`; Luna stopped and flagged it. M2 now names `values*.yaml`.

## Review log (Fable side-by-side, 2026-11-13)

- H1 CONFIRMED by Claude: `setup()` overrides HOME, hiding user-site PyYAML, so the three new tests are red in a plain local run (and likely in CI's bats job, where PyYAML comes from `pip install --user`). Claude had misread the same symptom as "no PyYAML on this host". Fix sent as correction 2 (`PYTHONUSERBASE` exported before the HOME override).
- M1 (CI exposure): same cause, same fix; not probed separately.
- L1 (glob narrowed to `values*.yaml`): overlap with Claude and Luna; spec already corrected.
- L2 (root keys only): accepted as spec scope; N2's frozen comparison covers nested keys in `values-dev-hub.yaml`; the vCluster upgrade idea should consider a full schema walk.

## Landed (2026-11-13)

`8c2bfc5f` (Luna, 3 correction runs). E1 offline PASS outside the sandbox with no Python overrides: `bats scripts/tests/plugins/dev_hub.bats` 55/55; M1, M2/N1 and N2 red on the pre-fix values file for the coredns reason; no-interpreter control red with the helper message. Correction 2's `setup()` PYTHONUSERBASE line (Claude's) broke all 55 tests (venv `python3 -m site --user-base` exits 1 under errexit); correction 3 resolves the interpreter in `setup_file()` and uses that interpreter's own user base. E2 live: after promote, operator runs `make dev-hub-up` on the M5.

## Live verification (2026-11-13)

m5-air, operator, after `make hub-promote REF=5c253d1b`, `git pull --ff-only`, `make dev-hub-down`, `make dev-hub-up` (which reached the Grafana `--wait` install): `kubectl --context k3d-k3d-cluster get priorityclass k3dm-dev-preemptible -o jsonpath='{.preemptionPolicy}'` gave `PreemptLowerPriority`. Host namespace `dev-hub` lists 8 pods. Seven were copied from the vCluster (Argo CD x5, Grafana, and `coredns-7c7ccd6944-xfgqv-x-kube-system-x-dev-hub` at a `128Mi` memory limit), plus `dev-hub-0` at 768Mi. Mark live_verified recorded at 8c2bfc5f. Errors seen: none.

**Live evidence:** 2026-11-13 · run operator-m5-dev-hub-up · env hub · scenario dev-hub-up-past-coredns-schema · commit 5c253d1b · proves E2
