# Bug: `cluster-up` restarts hub CoreDNS for no reason, and the ArgoCD controller restart right after it never becomes Ready

**Status:** OPEN
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** High. `make up` (sandbox) fails at Step 10 with exit 1, after the billable stack is
already up.
**Files:** `bin/cluster-up`, `scripts/tests/bin/cluster_up.bats`, `CHANGELOG.md`

Related: `docs/issues/2026-08-20-make-up-data-layer-argocd-host-dns.md` (why the alias exists),
`docs/bugs/2026-06-06-acg-refresh-coredns-restarts-instead-of-patching-configmap.md`.

## Symptom

Operator `make up` on 2026-10-05:

```
INFO: [acg-up] Step 10/12 — Registering app cluster with ArgoCD...
INFO: [acg-up] Ensuring Hub CoreDNS resolves host.k3d.internal...
INFO: [acg-up] CoreDNS host.k3d.internal alias restored
...
INFO: [acg-up] Restarting ArgoCD application controller to pick up new cluster secret...
Waiting for 1 pods to be ready...
error: timed out waiting for the condition
make: *** [up] Error 1
```

What the hub showed, read-only:

- `coredns-…-nzv4k` was 7m44s old, and `argocd-application-controller-0` was 7m26s old. The
  controller pod started 18 seconds after the single-replica CoreDNS was replaced.
- `argocd-application-controller-0` was `0/2`. Its `istio-proxy` startup probe failed 300+ times
  (`:15021 connection refused`), and its log repeated:
  `lookup istiod.istio-system.svc on 10.43.0.10:53: read: connection refused` and
  `failed to sign CSR`.
- The application container could reach nothing: `dial tcp 10.43.0.1:443: connect: connection
  refused`. With the sidecar never configured, every outbound connection is redirected into an
  Envoy that is not listening.
- At the same time, `argocd-server` and `argocd-image-updater` resolved
  `istiod.istio-system.svc` normally. Only the pod that started during the CoreDNS swap was
  stranded.
- At 22:51 the kubelet restarted the sidecar (startup probe 600×1s), and it did **not** recover.
  The new sidecar's DNS to `10.43.0.10:53` timed out (`i/o timeout`) while CoreDNS was healthy.
  The broken state lives in the pod's network namespace, which survives a container restart; only
  recreating the pod clears it.
- **Correction (23:28Z): recreating the pod did not help either.** The new pod (`10.42.0.7`) hit
  the same DNS timeout. The real fault was on node `agent-0`:
  - `iptables-save` there had **no `kube-dns` DNAT rules** and still sent the controller's metrics
    Service to the deleted pod `10.42.0.202`. agent-1, agent-2 and server-0 all had
    `kube-dns:dns -> 10.42.0.253:53`.
  - `kubeproxy_sync_proxy_rules_last_timestamp_seconds` on agent-0 was 35 minutes old, while its
    `last_queued` timestamp was current. Changes were queued, but the sync loop never ran them.
  - The `k3s agent` process (PID 86, which embeds kube-proxy) had **VmRSS 7.8 GB**, against 114 MB
    on agent-1 and agent-2. The Docker VM had 136 MB free, and agent-0's kubelet logged repeated
    1s `ExecSync` probe timeouts.

  So the CoreDNS restart did not break DNS. It moved the CoreDNS endpoint to a new IP, which a
  wedged kube-proxy on agent-0 never programmed, so every pod that started on agent-0 afterwards
  lost Service DNS. Pods on the other nodes were unaffected. The restart is still the trigger,
  and still unnecessary, so the fix below stands. The leak is recorded separately in
  `docs/issues/2026-10-05-hub-agent-0-k3s-agent-memory-wedges-kube-proxy.md`.

## Root cause

`_acg_repair_hub_host_alias` (about line 217) always runs, in this order:

1. it patches `NodeHosts`, even when the `host.k3d.internal` line is already correct
2. it runs `kubectl rollout restart deployment/coredns`
3. it runs `kubectl rollout status --timeout=30s`

There are two problems:

1. **The restart is unnecessary.** The hub Corefile already reloads the hosts file:

   ```
   hosts /etc/coredns/NodeHosts {
     ttl 60
     reload 15s
     fallthrough
   }
   ```

   A `NodeHosts` patch takes effect without a restart, once the kubelet syncs the ConfigMap volume
   and the plugin reloads. That takes about a minute at most.
2. **The restart opens a DNS gap on a single-replica CoreDNS**, and Step 10 restarts the ArgoCD
   controller into that gap. A sidecar that starts while service DNS is unavailable cannot reach
   istiod. In this run it never recovered within the controller's rollout timeout.

## Fix spec

### File 1 — `bin/cluster-up`

In `_acg_repair_hub_host_alias`:

**1a.** Read the current `NodeHosts` once, and return early when the alias is already correct.
Replace:

```bash
  _existing_nodes=$(kubectl get configmap coredns -n kube-system \
    --context k3d-k3d-cluster -o jsonpath='{.data.NodeHosts}' 2>/dev/null \
    | grep -v "host\.k3d\.internal" || true)
```

with:

```bash
  local _current_node_hosts
  _current_node_hosts=$(kubectl get configmap coredns -n kube-system \
    --context k3d-k3d-cluster -o jsonpath='{.data.NodeHosts}' 2>/dev/null || true)
  if printf '%s\n' "${_current_node_hosts}" | grep -qxF "${_host_ip} host.k3d.internal"; then
    _info "[acg-up] CoreDNS host.k3d.internal alias already present — no change"
    return 0
  fi
  _existing_nodes=$(printf '%s\n' "${_current_node_hosts}" | grep -v "host\.k3d\.internal" || true)
```

**1b.** Remove the restart. CoreDNS reloads the hosts file on its own. Replace:

```bash
  if kubectl rollout restart deployment/coredns -n kube-system \
      --context k3d-k3d-cluster >/dev/null 2>&1; then
    kubectl rollout status deployment/coredns -n kube-system \
      --context k3d-k3d-cluster --timeout=30s >/dev/null 2>&1 \
      || _warn "[acg-up] CoreDNS rollout status timed out — DNS may still be recovering"
    _info "[acg-up] CoreDNS host.k3d.internal alias restored"
  else
    _warn "[acg-up] CoreDNS restart failed — ArgoCD may not reach ubuntu-k3s"
  fi
```

with:

```bash
  _info "[acg-up] CoreDNS host.k3d.internal alias patched — the hosts plugin reloads it within ~1m (no restart)"
```

Do **not** change the other `rollout restart deployment/coredns` calls (about lines 1419 and
1547). They are separate paths, outside this spec.

### File 2 — `scripts/tests/bin/cluster_up.bats`

Extract `_acg_repair_hub_host_alias` with the file's existing `sed -n '/^function …()/,/^}$/p'`
pattern. Stub `_hub_docker_host_ip` to print `0.250.250.254`, stub `_info`/`_warn`/`_err`, and stub
`kubectl` so that it logs every call's arguments to a file and returns the `NodeHosts` text from
`${STUB_NODE_HOSTS}` for `get configmap`.

1. **Alias already present:** with `STUB_NODE_HOSTS=$'0.250.250.254 host.k3d.internal\n192.168.97.2 k3d-k3d-cluster-server-0'`,
   status is 0, the output contains `already present`, and the kubectl log has **no** `patch` and
   **no** `rollout`.
2. **Alias wrong:** with `STUB_NODE_HOSTS=$'10.0.0.9 host.k3d.internal\n192.168.97.2 k3d-k3d-cluster-server-0'`,
   status is 0, the kubectl log has one `patch configmap coredns`, and it has **no** `rollout`.
3. **Alias missing:** with `STUB_NODE_HOSTS='192.168.97.2 k3d-k3d-cluster-server-0'`, there is one
   `patch` and no `rollout`.

### File 3 — docs

- `CHANGELOG.md` `[Unreleased]` → `### Fixed`: a prose entry. Explain that the hosts plugin's
  `reload` makes the restart unnecessary. Explain that the restart opened a DNS gap on a
  single-replica CoreDNS, and that the controller restart landed inside it: the sidecar could not
  reach istiod, so every outbound connection from the pod was refused.
- This file: flip **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: tests 1 and 2 are RED at `HEAD` (paste output).
- [ ] Mutation: put the `rollout restart` call back after the patch; tests 2 and 3 go red.
      Restore from a `$TMPDIR` snapshot and prove it with `cmp`.
- [ ] `bats scripts/tests/bin/cluster_up.bats` is green; paste the counts.
- [ ] `shellcheck bin/cluster-up` shows no new findings vs `HEAD`.
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT change the ArgoCD controller restart, its timeout, or any other CoreDNS restart call.
- Do NOT scale CoreDNS or change its Deployment.
- Do NOT run `make up`, `kubectl` against a cluster, or anything that reaches AWS.
- Do NOT touch files outside those listed. No commit, push, PR or `--no-verify`.
