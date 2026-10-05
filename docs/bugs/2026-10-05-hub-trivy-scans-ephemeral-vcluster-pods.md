# Bug: hub Trivy scans the e2e vCluster's short-lived pods, and the scan Job fails when they vanish

**Status:** OPEN
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Low. A `KubeJobFailed` (`trivy-system`) fires after an e2e run, with no
vulnerability signal lost.
**Files:** `scripts/etc/helm/observability/trivy-operator-values.yaml`,
`scripts/tests/plugins/trivy_operator_observability.bats`,
`docs/guides/security/01-trivy-and-cve-inventory.md`, `CHANGELOG.md`

Related: `docs/bugs/2026-10-05-sandbox-node-notready-trivy-cilium-scan-starves-kubelet.md` (the
sandbox scope change that added the test this spec amends).

## Symptom

On 2026-10-04 the operator received `[FIRING] KubeJobFailed on hub ... namespace=trivy-system`,
and it resolved about 40 minutes later. Hub Prometheus:

```
scan-vulnerabilityreport-759fbc56f9   10-04 20:25 -> 10-04 20:55
```

The scan pod's labels in Loki name its target:

```
trivy-operator.resource.kind:      Pod
trivy-operator.resource.namespace: vclusters
trivy-operator.resource.name:      payment-8b7d59d4f-wxlnf-x-shopping-cart-apps-x-e2e-1-78b9e52122
```

That is a pod the e2e vCluster synced to the hub. The e2e run that created it finished at 20:08
(`e2e_last_run_timestamp_seconds`), and the vCluster was torn down with it. The operator's own
log at 20:08 shows a `Reconciler error` for another synced pod of the same run
(`rabbitmq-…-x-shopping-cart-apps-x-e2e-…`).

## Root cause

The hub values set no namespace scope, so trivy-operator scans every pod in `vclusters`. Those
pods exist only for the length of an e2e run, about a minute. A scan Job created for one of them
fails once the pod and its vCluster are deleted mid-scan. That is a guaranteed failure,
repeatable with every e2e run that overlaps a scan.

Excluding the namespace loses nothing: the images under test are scanned where they are deployed
(the app clusters' trivy-operator), and by `app-cve-scan`.

## Fix spec

### File 1 — `scripts/etc/helm/observability/trivy-operator-values.yaml`

Add a top-level key directly above the existing `image:` block (the first line of the file):

```yaml
excludeNamespaces: "vclusters"

```

### File 2 — `scripts/tests/plugins/trivy_operator_observability.bats`

In `trivy observability: acg values skip kube-system and run one scan job at a time`, replace:

```bash
  run grep -E '^excludeNamespaces:|scanJobsConcurrentLimit:' "${SETTINGS}"
  [ "${status}" -ne 0 ]
}
```

with:

```bash
  run grep -E 'scanJobsConcurrentLimit:|kube-system' "${SETTINGS}"
  [ "${status}" -ne 0 ]
}

@test "trivy observability: hub values skip the ephemeral e2e vCluster namespace" {
  run grep -E '^excludeNamespaces: "vclusters"$' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -E '^excludeNamespaces:.*vclusters' "${ACG_SETTINGS}"
  [ "${status}" -ne 0 ]
}
```

### File 3 — docs

- `docs/guides/security/01-trivy-and-cve-inventory.md`: add a short paragraph where the guide
  describes what the operator scans. Say that the hub skips `vclusters`, because the e2e
  vCluster's synced pods live about a minute and a scan of them fails when they vanish. Say that
  their images are covered on the app clusters and by `app-cve-scan`. If the guide also lacks the
  sandbox scope from the related spec (`kube-system` excluded, one scan at a time), add one
  sentence for it in the same place. That paragraph was skipped earlier.
- `CHANGELOG.md` `[Unreleased]` → `### Fixed`: a prose entry.
- This file: flip **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: the new test is RED at `HEAD` (paste output).
- [ ] Mutation: change `"vclusters"` to `"vcluster"`; the new test goes red. Restore from a
      `$TMPDIR` snapshot and prove it with `cmp`.
- [ ] `bats scripts/tests/plugins/trivy_operator_observability.bats` is green; paste the counts.
- [ ] `python3 -c 'import yaml,sys;yaml.safe_load(open(sys.argv[1]))' scripts/etc/helm/observability/trivy-operator-values.yaml`
      exits 0.
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT change `trivy-operator-acg-values.yaml`.
- Do NOT add `kube-system` or a concurrency limit to the hub values.
- Do NOT change scanner resources, the TTL or the chart version.
- Do NOT apply anything to a cluster. ApplicationSet reapply is a release step.
- Do NOT touch files outside those listed. No commit, push, PR or `--no-verify`.
