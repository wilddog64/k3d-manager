# Bug: a sandbox node goes NotReady during bring-up — the Trivy scan of `cilium` starves the kubelet

**Status:** FIXED
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** High — `make up` (sandbox, `k3s-aws`) fails at Step 10b with exit 1
**Files:** `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`,
`scripts/plugins/shopping_cart.sh`, `scripts/tests/plugins/trivy_operator_observability.bats`,
`scripts/tests/plugins/shopping_cart.bats`, `docs/guides/trivy-operator.md` (if present — see File 5)

## Symptom

Operator `make up` 2026-10-05, fresh sandbox, three t3.medium nodes (4 GiB, no swap):

```
INFO: [acg-up] data-layer not yet Synced — waiting...          (x48, about 8 minutes)
WARN: [acg-up] data-layer did not reach Synced within 300s — force-syncing and retrying (one attempt)...
ERROR: [acg-up] data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry
make: *** [up] Error 1
```

## Evidence (collected live, read-only)

- Node `ip-10-0-1-161` joined at about 12:11Z. Its kubelet **stopped posting status at 12:20:37Z**
  (`Ready=Unknown`, `NodeStatusUnknown`). The EC2 instance `i-0f569c560ad077afd` stayed `running`,
  and both AWS status checks (instance and system) were `ok`. The VM was alive and only the
  kubelet had gone silent.
- The sandbox's own Prometheus showed, for that node over the 15 minutes before it went dark:
  - `min_over_time(node_memory_MemAvailable_bytes[15m])` was **398 Mi** (the other nodes: 682 Mi
    and 2580 Mi).
  - The top working set was `trivy-system/scan-vulnerabilityreport-c84ff9879-g9m55` at
    **1265 Mi**, the last sample before the scrape stopped. Next came Grafana (373 Mi), cilium
    (183 Mi) and Loki (113 Mi).
- That scan pod was scanning **`kube-system/DaemonSet cilium`**. The operator creates one scanner
  container per image in the workload. Cilium has **7 containers** (`cilium-agent`, `config`,
  `mount-cgroup`, `apply-sysctl-overwrites`, `mount-bpf-fs`, `clean-cilium-state`,
  `install-cni-binaries`). Each scanner container requests 256 Mi and is limited to 1 Gi, so
  that one pod is scheduled on 1.75 Gi of requests but may grow to 7 Gi.
- `trivy-operator-config` has `OPERATOR_CONCURRENT_SCAN_JOBS_LIMIT=10` (the chart default), and
  8 scan jobs were created within 15 seconds of the operator starting.
- Knock-on effect: `external-secrets-webhook` was on the dead node, so its Service had no
  endpoints. Every ExternalSecret patch in `ubuntu-k3s-data-layer` failed with
  `no endpoints available for service "external-secrets-webhook"`, and the Application stayed
  OutOfSync. Kubernetes evicted the pods at about 12:25:45Z, by which time the 300s budget was
  nearly spent.

## Root cause

There are two defects, and either one alone would not have taken the node down:

1. **The sandbox scans `kube-system` with the operator's default concurrency.** The `cilium`
   DaemonSet scan alone can grow far beyond what the scheduler accounted for, and with up to 10
   scans running at once on fresh nodes they all land during the busiest minutes of bring-up.
   The sandbox is transient, and the hub already scans the same upstream system images, so this
   scan buys little coverage at a high cost.
2. **The k3s nodes reserve no memory for the system or the kubelet.** Without
   `system-reserved`/`kube-reserved`, the `kubepods` cgroup is sized to the whole node. When pods
   burst past their requests, the kernel thrashes the whole VM instead of OOM-killing inside the
   pod cgroup, so the kubelet itself stops responding. With a reservation, the misbehaving pod is
   OOM-killed and the node stays Ready.

## Fix spec

### File 1 — `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`

Add a top-level key directly above the existing `image:` block (the first line of the file):

```yaml
excludeNamespaces: "kube-system"

```

In the `operator:` block, replace:

```yaml
operator:
  scanJobTTL: 1h
```

with:

```yaml
operator:
  scanJobTTL: 1h
  scanJobsConcurrentLimit: 1
```

Do **not** change `scripts/etc/helm/observability/trivy-operator-values.yaml` (the hub/Hostinger
values).

### File 2 — `scripts/plugins/shopping_cart.sh`

**2a — agents (`_k3sup_join_agent`).** Replace:

```bash
  _run_command -- k3sup join \
    --ip "${agent_ip}" \
    --server-ip "${server_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --k3s-version "${K3S_VERSION:-v1.32.0+k3s1}"
```

with:

```bash
  local _agent_extra_args="${K3S_KUBELET_RESERVED_ARGS:-}"
  [[ -n "${_agent_extra_args}" ]] || _agent_extra_args='--kubelet-arg=system-reserved=memory=256Mi --kubelet-arg=kube-reserved=memory=256Mi'
  _run_command -- k3sup join \
    --ip "${agent_ip}" \
    --server-ip "${server_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --k3s-version "${K3S_VERSION:-v1.32.0+k3s1}" \
    --k3s-extra-args "${_agent_extra_args}"
```

**2b — server (the `k3sup install` function, about line 1420).** Replace:

```bash
  local _k3s_extra_args='--disable traefik --disable servicelb'
  if [[ "${K3S_AMBIENT_MESH:-false}" == "true" ]]; then
    _k3s_extra_args="${_k3s_extra_args} --flannel-backend=none --disable-network-policy"
```

with:

```bash
  local _k3s_extra_args='--disable traefik --disable servicelb'
  local _kubelet_reserved="${K3S_KUBELET_RESERVED_ARGS:-}"
  [[ -n "${_kubelet_reserved}" ]] || _kubelet_reserved='--kubelet-arg=system-reserved=memory=256Mi --kubelet-arg=kube-reserved=memory=256Mi'
  _k3s_extra_args="${_k3s_extra_args} ${_kubelet_reserved}"
  if [[ "${K3S_AMBIENT_MESH:-false}" == "true" ]]; then
    _k3s_extra_args="${_k3s_extra_args} --flannel-backend=none --disable-network-policy"
```

Only edit the `k3sup install` occurrence of `local _k3s_extra_args=`. The SSM server path
(`_ssm_bootstrap_k3s`, `local _k3s_exec=`) and the SSM agent path (`_ssm_join_agent_worker`) are
**out of scope**: SSM is opt-in, and the default sandbox profile forces SSH because of the Vault
reverse bridge.

### File 3 — `scripts/tests/plugins/trivy_operator_observability.bats`

Add:

```bash
@test "trivy observability: acg values skip kube-system and run one scan job at a time" {
  run grep -E '^excludeNamespaces: "kube-system"$' "${ACG_SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -E '^  scanJobsConcurrentLimit: 1$' "${ACG_SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -E '^excludeNamespaces:|scanJobsConcurrentLimit:' "${SETTINGS}"
  [ "${status}" -ne 0 ]
}
```

### File 4 — `scripts/tests/plugins/shopping_cart.bats`

Add behavioural tests that drive the real `_k3sup_join_agent`, not a grep on the source:

```bash
@test "_k3sup_join_agent reserves kubelet memory by default" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    export HOME="${BATS_TEST_TMPDIR}"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/plugins/shopping_cart.sh
    _ubuntu_k3s_trust_host() { :; }
    _info() { :; }
    _run_command() { printf "%s\n" "$@"; }
    _k3sup_join_agent ubuntu-1 10.0.1.130
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"--k3s-extra-args"* ]]
  [[ "$output" == *"--kubelet-arg=system-reserved=memory=256Mi --kubelet-arg=kube-reserved=memory=256Mi"* ]]
}

@test "_k3sup_join_agent honours K3S_KUBELET_RESERVED_ARGS" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    export HOME="${BATS_TEST_TMPDIR}"
    export K3S_KUBELET_RESERVED_ARGS="--kubelet-arg=system-reserved=memory=128Mi"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/plugins/shopping_cart.sh
    _ubuntu_k3s_trust_host() { :; }
    _info() { :; }
    _run_command() { printf "%s\n" "$@"; }
    _k3sup_join_agent ubuntu-1 10.0.1.130
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"--kubelet-arg=system-reserved=memory=128Mi"* ]]
  [[ "$output" != *"kube-reserved=memory=256Mi"* ]]
}
```

For the server path, add one test that drives the real `k3sup install` caller with `_run_command`
stubbed. Read the function first, and stub only what it needs to reach the `k3sup install` call
(SSH readiness, trust-host, the kubeconfig copy). Assert that the captured
`--k3s-extra-args` value contains both `--disable traefik --disable servicelb` and
`--kubelet-arg=system-reserved=memory=256Mi`. If the function cannot reach `k3sup install`
without a real host after reasonable stubbing, say so in your report rather than replacing the
test with a source grep.

### File 5 — docs

- `CHANGELOG.md` `[Unreleased]` → `### Fixed`: a prose entry covering both defects. Explain why
  a single 7-container scan pod can grow past what the scheduler accounted for, and why a
  reservation turns node death into a pod OOM-kill.
- If `docs/guides/trivy-operator.md` exists, add a short "Sandbox scan scope" paragraph saying the
  sandbox skips `kube-system` and runs one scan at a time, and why. If it does not exist, find the
  Trivy guide under `docs/guides/` with `ls docs/guides | grep -i trivy` and use that. If there is
  none, report it and skip this item.
- Document `K3S_KUBELET_RESERVED_ARGS` wherever the README or `docs/` lists the other `K3S_*`
  env vars (`git grep -n "K3S_VERSION" -- README.md docs/` to find the place). If there is no
  such list, report it and skip.
- This file: flip **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: the new tests are RED against `HEAD` before the change (paste output).
- [ ] Mutation: delete the `--k3s-extra-args "${_agent_extra_args}"` line, and the default test
      goes red. Restore from a `$TMPDIR` snapshot and prove it with `cmp`.
- [ ] `bats scripts/tests/plugins/trivy_operator_observability.bats scripts/tests/plugins/shopping_cart.bats`
      green; paste the counts.
- [ ] `shellcheck scripts/plugins/shopping_cart.sh` shows no new findings vs `HEAD`.
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT change the hub/Hostinger `trivy-operator-values.yaml`.
- Do NOT raise or lower the scanner `resources` in either values file.
- Do NOT touch the SSM install/join paths.
- Do NOT edit `scripts/lib/foundation/` (it is a subtree).
- Do NOT touch files outside those listed. No commit, push, PR or `--no-verify`.
- Do NOT run `make up`, `kubectl` against any cluster, or anything that reaches AWS.
