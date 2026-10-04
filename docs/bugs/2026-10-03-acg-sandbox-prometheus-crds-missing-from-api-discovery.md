# Bug: ACG sandbox Prometheus never starts; 4 operator CRDs missing from API discovery

**Filed:** 2026-10-03, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN. The fault persists on the same sandbox five hours later, and since `82fe2218` it makes `make up` exit 2 at Step 14 (see "Recurrence 2026-10-04")
**Severity:** medium. The hub's `federate-acg` target is down for the whole sandbox lifetime, so
`TargetDown` fires and no sandbox metrics reach the hub. `make up` exits 0 and does not notice.

## Observed (2026-10-03, sandbox `make up` at about 20:40 UTC, k3s `v1.32.0+k3s1`)

- Hub alert `TargetDown {job="federate-acg"}`. The scrape of `host.internal:19190/federate` is refused.
- `acg-prom-pf.log`: `Error from server (NotFound): services "prometheus-operated" not found`.
  Step 14b starts the port-forward with no check, so it dies straight away.
- Sandbox `monitoring` namespace: Grafana, Alertmanager, the operator, node-exporter and KSM are all
  Running. **There is no Prometheus StatefulSet and no `Prometheus` object**: a raw list of
  `prometheuses` returns `[]`.
- Hub ArgoCD `acg-kube-prometheus-stack` is `OutOfSync`, with sync id 00432 or more. Every attempt
  fails with:
  `resource mapping not found for name: "acg-kube-prometheus-stack-prometheus" ... no matches for kind
  "Prometheus" in version "monitoring.coreos.com/v1" — ensure CRDs are installed first (retried 5 times)`.
  Each attempt re-runs the `admission-create` PreSync hook, every 3 to 4 minutes.
- The CRD `prometheuses.monitoring.coreos.com` exists: created 20:42:29Z,
  `Established=True`, `v1 served=true`.
- **API discovery leaves it out:**
  - `GET /apis/monitoring.coreos.com/v1` lists probes, prometheusrules, podmonitors, alertmanagers
    and servicemonitors, but **not prometheuses or thanosrulers**.
  - `GET /apis/monitoring.coreos.com/v1alpha1` lists only alertmanagerconfigs. **prometheusagents
    and scrapeconfigs are missing.**
- The operator log at 20:42:39Z warns that exactly those four (`prometheuses`, `prometheusagents`,
  `scrapeconfigs`, `thanosrulers`) are "not installed in the cluster". It started 10 s after the
  CRDs were created and still disagrees with the API server 3 h later.

## Hypothesis (unconfirmed)

The sandbox kube-apiserver's discovery, or its CRD handler, never registered four CRDs that it
reports as Established. Those four are among the largest, at 300 to 460 KB each. The rest of
`monitoring.coreos.com` is served. ArgoCD and the operator both build their REST mappers from
discovery, so neither can apply or watch a `Prometheus` object, and neither retries discovery in a
way that recovers.

Ruled out: the CRDs missing outright (they exist and are Established), a CRD guard bug (see
`argocd-prometheus-operator-unguarded-crd-apply.md`, a different hub-side ordering defect), and an
admission webhook block (the hook Job completes in 3 s).

## Next live checks (Claude, read-only, on the next sandbox `make up`)

1. Run `kubectl --context ubuntu-k3s get --raw /apis/monitoring.coreos.com/v1`. Does
   `prometheuses` appear? If it does, this was a one-off and the doc closes as not reproduced.
2. If it is missing again: read the k3s server journal from 20:42 for the CRD and discovery
   errors (`sudo journalctl -u k3s` through the operator or SSM), and check whether a k3s server
   restart restores discovery. That decides the fix:
   - a `cluster-up` Step 14 discovery wait-and-restart, or
   - pinning `crds.enabled` and applying the CRDs out of band with `--server-side`.

## Separate small defect found on the way

Step 14b (`bin/cluster-up:1882`) starts the `svc/prometheus-operated` port-forward without
checking that the Service exists, and logs a PID as if it succeeded. A missing sandbox
Prometheus should show up as a `make up` WARN, not as a later hub `TargetDown`. Fold this into
whichever fix the checks above choose.

## Workaround

None is needed for the hub. The sandbox expires at 4 h. If sandbox metrics are needed during a
sandbox lifetime, ask the operator to restart k3s on the sandbox server node, then run a manual
sync of `acg-kube-prometheus-stack`.

## Recurrence 2026-10-04 (same sandbox, reused by `make up` at about 01:55 UTC)

- `make up` failed at Step 14 (exit 2):
  `ERROR: [observability] PrometheusRule CRD not established on ubuntu-k3s after waiting`.
- The CRD **is** `Established=True`. But on the sandbox,
  `kubectl wait --for=condition=Established crd/<any monitoring CRD>` **times out**: both
  `prometheusrules` and `servicemonitors` do. On the hub, the same command against
  `prometheusrules` returns immediately. `kubectl wait` on sandbox **nodes** works, and the sandbox
  apiserver is the same version as the hub's (v1.32.0+k3s1), with client v1.37.1.
- `kubectl get crd <name> -w` prints the initial row and then nothing.
- Discovery now lists `prometheusrules`, but `prometheuses`, `prometheusagents`, `scrapeconfigs` and
  `thanosrulers` are still missing.
- This sharpens the hypothesis. The sandbox apiserver's **CRD watch / apiextensions informer is
  stuck**, not just discovery. That would explain both the discovery gap and the `kubectl wait`
  hang, and it points at a k3s server restart as the recovery step.
- `_observability_wait_for_prometheusrule_crd` (added in `82fe2218`) relies on `kubectl wait`.
  A plain `get` of `.status.conditions` would not depend on the watch.

## Recurrence 2026-10-04 #2 (same sandbox, `make up` rerun ending about 02:30 UTC)

- `make up` failed at Step 14 with the same `PrometheusRule CRD not established on ubuntu-k3s after
  waiting` (`make: *** [up] Error 1`). Steps 1–13 were clean, including the live checks for
  `cc81df52` and `22cecd0e`.
- Shortly after the failure: `prometheusrules` is `Established=True` and present in discovery, so
  the Step 14 wait failed only because of the stuck watch. `prometheuses`, `prometheusagents`,
  `scrapeconfigs` and `thanosrulers` are still missing from `api-resources`. All 10 CRD objects
  exist, created 2026-10-03T20:42:29Z.
- Hub ArgoCD `acg-kube-prometheus-stack`: `Unknown/Missing`, operation `Running`, retry #5, with the
  same `no matches for kind "Prometheus"` error.
- The fault has now persisted for about 6 h on one sandbox, so it is not self-healing. The two
  open decisions still stand: a `.status.conditions` get in place of `kubectl wait`, and a k3s
  server restart (operator) as the recovery or automated step.

## k3s server restart confirms the recovery (2026-10-04 about 02:40 UTC)

- The operator ran `ssh ubuntu sudo systemctl restart k3s` on the server node (`ip-10-0-1-44`).
- Straight afterwards, `api-resources --api-group=monitoring.coreos.com` lists all 10 types,
  including `prometheuses`, `prometheusagents`, `scrapeconfigs` and `thanosrulers`.
  `kubectl wait --for=condition=Established crd/prometheusrules...` returns at once (rc 0).
- This confirms the hypothesis: the sandbox apiserver's CRD watch was stuck, and a k3s server
  restart clears it.
- It does not undo two side effects:
  - The hub ArgoCD app is left in `op=Error` (EOF during the restart window), and an Error phase
    blocks self-heal, so it needs a manual sync.
  - The Prometheus operator pod started while the four CRDs looked "not installed", so it needs
    a rollout restart before it reconciles `Prometheus` objects.
- This settles the fix direction. Replace `kubectl wait` with a `.status.conditions` get, then
  check discovery for `prometheuses`. When it is missing, WARN and print the restart command,
  rather than restarting k3s automatically.

## Fix spec (dispatched to Codex 2026-10-04)

There are three changes. None of them restarts k3s automatically: that stays an operator step.

### 1. `scripts/plugins/observability.sh`: read the condition, don't watch it

Replace the body of `_observability_wait_for_prometheusrule_crd` with a poll on
`.status.conditions`. A plain `get` does not depend on the apiserver's CRD watch:

```bash
function _observability_wait_for_prometheusrule_crd() {
  local _context="$1"
  local _attempts="${K3DM_ACG_RULES_CRD_ATTEMPTS:-36}"
  local _interval="${K3DM_ACG_RULES_CRD_INTERVAL:-5}"
  local _attempt _established

  for ((_attempt=1; _attempt<=_attempts; _attempt++)); do
    _established="$(_kubectl --no-exit get crd prometheusrules.monitoring.coreos.com \
        --context "${_context}" \
        -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || true)"
    [[ "${_established}" == "True" ]] && return 0
    (( _attempt < _attempts )) && sleep "${_interval}"
  done
  return 1
}
```

### 2. `scripts/plugins/observability.sh`: warn when kind `Prometheus` is not served

Add a new function directly below `_observability_wait_for_prometheusrule_crd`:

```bash
function _observability_warn_if_prometheus_kind_unserved() {
  local _context="$1"
  local _attempts="${K3DM_ACG_PROM_DISCOVERY_ATTEMPTS:-12}"
  local _interval="${K3DM_ACG_PROM_DISCOVERY_INTERVAL:-5}"
  local _attempt _resources

  for ((_attempt=1; _attempt<=_attempts; _attempt++)); do
    _resources="$(_kubectl --no-exit api-resources --api-group=monitoring.coreos.com \
        -o name --context "${_context}" 2>/dev/null || true)"
    if grep -qx 'prometheuses.monitoring.coreos.com' <<<"${_resources}"; then
      return 0
    fi
    (( _attempt < _attempts )) && sleep "${_interval}"
  done
  _warn "[observability] ${_context} apiserver does not serve kind Prometheus although its CRD is installed — the apiserver CRD watch is stuck; sandbox Prometheus will not start (docs/bugs/2026-10-03-acg-sandbox-prometheus-crds-missing-from-api-discovery.md)"
  _warn "[observability] recover: ssh ubuntu sudo systemctl restart k3s; kubectl --context ${_context} -n monitoring rollout restart deploy/acg-kube-prometheus-stack-operator; make fix-sync APP=acg-kube-prometheus-stack"
  return 1
}
```

In `deploy_observability_acg`, call it **only after** the rule CRD wait succeeds, and do not
let it fail the step. Replace

```bash
    elif _kubectl apply --context "${_app_context}" -f "${_acg_rules_dir}/" >/dev/null; then
      _info "[observability] app-cluster PrometheusRules applied from ${_acg_rules_dir}/"
```

with

```bash
    elif _kubectl apply --context "${_app_context}" -f "${_acg_rules_dir}/" >/dev/null; then
      _info "[observability] app-cluster PrometheusRules applied from ${_acg_rules_dir}/"
      _observability_warn_if_prometheus_kind_unserved "${_app_context}" || true
```

### 3. `bin/cluster-up` Step 14b: don't start a port-forward to a Service that doesn't exist

Wrap the existing Step 14b block, from `_acg_prom_pf_pid_file=...` through the
`_info "[acg-up] ACG Prometheus port-forward PID: ..."` line, in a bounded wait for
`svc/prometheus-operated`. Use 24 attempts × 5 s, overridable through
`K3DM_ACG_PROM_SVC_ATTEMPTS` and `K3DM_ACG_PROM_SVC_INTERVAL`:

```bash
_acg_prom_svc_ready=0
for ((_acg_prom_svc_try=1; _acg_prom_svc_try<=${K3DM_ACG_PROM_SVC_ATTEMPTS:-24}; _acg_prom_svc_try++)); do
  if kubectl get svc prometheus-operated -n monitoring --context "${_acg_observability_context}" >/dev/null 2>&1; then
    _acg_prom_svc_ready=1
    break
  fi
  sleep "${K3DM_ACG_PROM_SVC_INTERVAL:-5}"
done
if [[ "${_acg_prom_svc_ready}" -ne 1 ]]; then
  _warn "[acg-up] Step 14b/14 — svc/prometheus-operated not found on ${_acg_observability_context}; Prometheus port-forward NOT started, hub federate-acg will report TargetDown. After sandbox Prometheus is up run: nohup kubectl port-forward svc/prometheus-operated ${_acg_prom_local_port}:9090 -n monitoring --context ${_acg_observability_context} --address 0.0.0.0 >> ${_ACG_STATE_DIR}/logs/acg-prom-pf.log 2>&1 & echo \$! > ${_ACG_STATE_DIR}/run/acg-prom-pf.pid"
else
  <existing Step 14b block, unchanged apart from indentation>
fi
```

Keep the ownership line from
`docs/bugs/2026-10-04-cluster-up-exit-trap-kills-port-forwards-it-did-not-start.md`
(`_ACG_UP_OWNED_PIDS+=...` after `_acg_prom_pf_pid=$!`) inside the `else` branch.

### BATS

Put these in a new `scripts/tests/plugins/observability_acg_crd_discovery.bats`, stubbing
`_kubectl` and setting the attempts/interval envs to 2/0:

1. The CRD wait returns 0 when the jsonpath stub prints `True`, and 1 when it prints `False` or
   nothing.
2. **Mutation guard:** `kubectl wait` / `_kubectl ... wait` must no longer appear in the body of
   `_observability_wait_for_prometheusrule_crd` (a `sed` range plus `run !` grep).
3. The discovery check returns 0 when the `api-resources` stub lists
   `prometheuses.monitoring.coreos.com`. When it is absent, it returns 1 and the output contains
   `systemctl restart k3s`.
4. Static: in `deploy_observability_acg`, the discovery call comes after the rules `apply` and
   carries `|| true`.

In `scripts/tests/bin/cluster_up.bats`, add a static check that Step 14b's
`kubectl port-forward svc/prometheus-operated` sits inside the
`_acg_prom_svc_ready` else-branch: its line number falls between the `if` and the `fi`.

## Review follow-up (Claude, 2026-10-04, on `3b789adf`)

The fix landed in `3b789adf` (Codex). Claude verified it: on origin, scope matches, shellcheck
adds no warnings, 61/61 targeted BATS. Two defects remain.

**R1 — the Step 14b warning prints the wrong PID into its recovery command.** The `_warn` line in
`bin/cluster-up` Step 14b is double-quoted and ends with `& echo $! > .../acg-prom-pf.pid`. The `$!`
expands when the warning prints, to the last background job of *this* run (normally the Vault
port-forward). An operator who pastes the command writes the Vault port-forward's PID into
`acg-prom-pf.pid`, and the next Step 14b then kills the Vault port-forward. Fix: escape it as `\$!`
in that `_warn` string. Add a BATS static check that the line contains `echo \$! >`.

**R2 — `"su""do"` string split in `observability.sh`.** The second `_warn` in
`_observability_warn_if_prometheus_kind_unserved` splits the word so the pre-commit `_agent_audit`
bare-sudo check does not match. Do not defeat the audit. Replace that second `_warn` with:

```bash
  _warn "[observability] recover: restart k3s on the sandbox node, rollout-restart the prometheus operator, then make fix-sync APP=acg-kube-prometheus-stack (exact commands in the bug doc above)"
```

Update any BATS assertion that matched the old text to assert the tokens `restart k3s` and
`fix-sync`.
