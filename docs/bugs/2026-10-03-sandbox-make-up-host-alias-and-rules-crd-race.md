# Bug: sandbox `make up` — hub host alias repair is a silent no-op, and ACG rules apply before their CRD

**Branch:** `k3d-manager-v1.41.0`
**Filed:** 2026-10-03, Claude
**Status:** SPEC — ready for Codex
**Files:**
- `scripts/lib/hub_host_ip.sh` (new);
- `bin/cluster-up`;
- `bin/cluster-refresh`;
- `scripts/plugins/observability.sh`;
- BATS: `scripts/tests/lib/hub_host_ip.bats` (new), `scripts/tests/bin/cluster_up.bats`, `scripts/tests/plugins/observability_k3dm_tests_rules.bats`.

Two independent defects, both hit on the operator's `make up CLUSTER_PROVIDER=k3s-aws`, 2026-10-03.

## Defect 1 — the hub host alias repair never runs

### Symptom

```
ERROR: data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry
```

The ArgoCD Application `ubuntu-k3s-data-layer` reported:

```
dial tcp: lookup host.k3d.internal on 10.43.0.10:53: no such host
```

### Root cause

`_acg_repair_hub_host_alias` (`bin/cluster-up:170`) finds the Mac's address like this:

```bash
_host_ip=$(docker exec k3d-k3d-cluster-server-0 sh -c \
  "getent hosts host.docker.internal 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "")
```

The hub image `rancher/k3s:v1.32.0-k3s1` has **no `getent`**. The pipeline prints nothing, `_host_ip`
is empty, and the function warns and returns 0:

```
[acg-up] Could not detect host IP from host.docker.internal — CoreDNS host alias repair skipped
```

The hub CoreDNS `NodeHosts` was last written by k3s at the 2026-09-27 hub rebuild and held only the 4
node entries. Since then, every `make up` has skipped the repair with a warning nobody reads. The run
then fails 3+ minutes later at the data-layer sync, which names neither DNS nor the skipped repair.

`bin/cluster-refresh:249-251` (step 2b-pre) has a copy of the same code with the same defect.

`nslookup` exists in the image and resolves the name. Its output on OrbStack, captured live:

```
Server:		192.168.97.1
Address:	192.168.97.1:53

Non-authoritative answer:

Non-authoritative answer:
Name:	host.docker.internal
Address: 0.250.250.254
```

Only the `Address:` line under `Name:` is the answer. The first `Address:` line is the DNS server and
carries a `:53` suffix. `0.250.250.254` is the correct address: `docs/bugs/2026-06-06-acg-refresh-coredns-restarts-instead-of-patching-configmap.md`
records that the bridge gateway `192.168.97.1` is **not** the Mac and is not reachable on 6443.

Live proof of the fix, 2026-10-03: the operator added `0.250.250.254 host.k3d.internal` to
`NodeHosts` by hand. Then:
- a busybox pod on the hub resolved the name;
- `nc -z host.k3d.internal 6443` returned `TCP_OK`;
- on the rerun, `ubuntu-k3s-data-layer` went Synced / Healthy.

## Defect 2 — the ACG PrometheusRules are applied before their CRD exists

### Symptom

On the rerun, after data-layer synced:

```
ERROR: failed to execute kubectl apply --context ubuntu-k3s -f .../scripts/etc/prometheus/rules-acg/: 1
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
```

### Root cause

`_deploy_pushgateway_acg` (`scripts/plugins/observability.sh:703`) runs these steps in order:
1. it installs Pushgateway with Helm, `--create-namespace monitoring`;
2. it applies two dashboard ConfigMaps;
3. it runs `kubectl apply -f rules-acg/` immediately after that.

`rules-acg/k3dm-tests.yaml` is a `PrometheusRule`. Its CRD comes from kube-prometheus-stack, which the
`observability-acg` ApplicationSet installs asynchronously, so on a fresh sandbox nothing guarantees
it exists yet. Timing, live:
- the log's last write was 15:07:18Z;
- `crd/prometheusrules.monitoring.coreos.com` has `creationTimestamp` 15:07:44Z, 26 s later;
- a server-side dry run of the same apply succeeded shortly afterwards.

This is the same class as `docs/bugs/argocd-prometheus-operator-unguarded-crd-apply.md`, at a
different site. The fix pattern is already in the repo: `_eso_wait_for_crds`
(`scripts/plugins/eso.sh:97`) polls for the CRD, then `kubectl wait --for=condition=Established`.

## Fix

### M1 — shared host-IP resolver: `scripts/lib/hub_host_ip.sh` (new)

```bash
#!/usr/bin/env bash
# scripts/lib/hub_host_ip.sh — the Mac's address as seen from the hub's k3d server container.

function _hub_docker_host_ip() {
  local _container="${1:-k3d-k3d-cluster-server-0}"
  local _out
  _out=$(docker exec "${_container}" sh -c 'nslookup host.docker.internal 2>/dev/null' 2>/dev/null || true)
  printf '%s\n' "${_out}" \
    | awk '/^Name:/{seen=1; next} seen && /^Address/ {sub(/^Address:[[:space:]]*/, ""); if ($0 ~ /^[0-9]+(\.[0-9]+)+$/) {print; exit}}'
}
```

- It prints the first IPv4 answer, or nothing at all. It always returns 0, so the caller decides
  what to do with an empty result.
- Only the `Address` lines **after** `Name:` count. The server line `192.168.97.1:53` must never come
  back, even from output that has no `Name:` line (an NXDOMAIN reply).
- It does not use `getent`.

### M2 — `bin/cluster-up`: use the resolver, fail loud

- Source the new lib next to the other `scripts/lib/*` sources (after `core.sh`, line ~59):
  `source "${REPO_ROOT}/scripts/lib/hub_host_ip.sh"`.
- In `_acg_repair_hub_host_alias`, change two things:
  - replace the `docker exec … getent …` assignment with `_host_ip=$(_hub_docker_host_ip)`;
  - make the empty branch fatal, so the run stops at the real cause instead of failing later at the data-layer:

  ```bash
  if [[ -z "${_host_ip}" ]]; then
    _err "[acg-up] Could not resolve host.docker.internal inside k3d-k3d-cluster-server-0 — hub CoreDNS cannot be given host.k3d.internal and ArgoCD will not reach ubuntu-k3s"
    return 1
  fi
  ```

  Check how `_err` behaves in this file first. If `_err` already exits, drop the `return 1`. The rest
  of the function is unchanged. Leave the patch-failure and restart-failure branches as warnings.

### M3 — `bin/cluster-refresh`: use the resolver

- Source `scripts/lib/hub_host_ip.sh` next to its other lib sources (line ~24).
- Replace the `_coredns_host_ip=$(docker exec … getent …)` assignment (lines 249-251) with
  `_coredns_host_ip=$(_hub_docker_host_ip)`.
- Leave the empty branch as a `_warn`. Refresh is a recovery tool and must keep going.

### M4 — `scripts/plugins/observability.sh`: wait for the CRD before the rules apply

In `_deploy_pushgateway_acg`, inside the existing `if [[ -d "${_acg_rules_dir}" ]]` block and before
the `_kubectl apply`, wait for `prometheusrules.monitoring.coreos.com` on `${_app_context}`:

- Add a helper `_observability_wait_for_prometheusrule_crd <context>`, modelled on `_eso_wait_for_crds`.
  It works in two steps:
  - It polls `_kubectl --no-exit get crd prometheusrules.monitoring.coreos.com --context <ctx>` up to
    `${K3DM_ACG_RULES_CRD_ATTEMPTS:-36}` times, sleeping `${K3DM_ACG_RULES_CRD_INTERVAL:-5}` s
    between tries (default 180 s).
  - Once the CRD is present, it runs `_kubectl --no-exit wait --context <ctx> --for=condition=Established --timeout=120s crd/prometheusrules.monitoring.coreos.com`.
  - It returns 0 when the CRD is established, 1 otherwise.
- If the wait fails, run `_err "[observability] PrometheusRule CRD not established on ${_app_context} after waiting — kube-prometheus-stack (observability-acg) has not installed it"`,
  set `_acg_rules_failed=1`, and **skip** the apply.
- Keep the apply line byte-identical, because the existing BATS asserts it:
  `_kubectl apply --context "${_app_context}" -f "${_acg_rules_dir}/"`.

## Gates (offline; paste actual output)

1. **New `scripts/tests/lib/hub_host_ip.bats`.** Stub `docker` as a bash function that prints fixture
   output, then assert:
   - (a) the OrbStack output above → `0.250.250.254`, not `192.168.97.1`;
   - (b) an NXDOMAIN reply (`** server can't find host.docker.internal: NXDOMAIN` plus the server
     lines) → empty output, rc 0;
   - (c) `docker` failing (rc 1, no output) → empty output, rc 0;
   - (d) a reply with an IPv6 `Address:` before the IPv4 one → the IPv4 address;
   - (e) the source contains no `getent` (`run grep -c getent` → 0; mind `grep -c` exiting 1 on zero).
2. **`cluster_up.bats`:**
   - `bin/cluster-up` and `bin/cluster-refresh` contain no `getent hosts host.docker.internal` (a
     disappearance gate);
   - both source `hub_host_ip.sh`;
   - in `_acg_repair_hub_host_alias`, the empty-IP branch returns non-zero. Assert on meaningful
     tokens such as `return 1` inside the function body, not on a whole source line.
3. **`observability_k3dm_tests_rules.bats`.** Source the plugin and stub `_kubectl`, `_info`, `_err`,
   `_warn`, `helm` and `sleep`. Set `K3DM_ACG_RULES_CRD_ATTEMPTS=3` and `K3DM_ACG_RULES_CRD_INTERVAL=0`.
   Cover three cases:
   - (a) `get crd` fails twice, then succeeds → the wait runs, the apply runs once, and rc is 0;
   - (b) `get crd` always fails → the apply **never** runs, the error names the CRD, and
     `_deploy_pushgateway_acg` returns non-zero;
   - (c) the existing line-53 assertion still passes.
4. **Mutations.** Snapshot with `cp`, mutate, show red, restore from the snapshot, and show `cmp`
   byte-equality. Never use `git checkout`.
   - (a) the resolver drops the `seen` guard, so it takes the first `Address` → gate 1a red, because
     the `:53` server line is no longer skipped;
   - (b) the empty branch goes back to `return 0` → gate 2 red;
   - (c) delete the CRD-wait call → gate 3a or 3b red.
5. Run `shellcheck` on every touched shell file: zero new warnings.
6. Run the BATS files above, then `make test` (it takes ~15 min, so let it finish and read the
   per-suite counts), then `python3 scripts/check-doc-links.py`.
7. `git diff --stat`: only the files listed at the top.

## Definition of Done

- [ ] M1–M4 complete; gates 1–7 pass, output pasted.
- [ ] Commit message, exactly (trailers on consecutive lines):

  ```
  fix(cluster-up): resolve the hub host alias without getent; wait for the PrometheusRule CRD

  Co-Authored-By: Codex <noreply@openai.com>
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] `git push origin k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`.
- [ ] `CHANGELOG.md` `[Unreleased]` → `### Fixed`: one prose bullet covering both defects.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, or use `--no-verify`.
- Do NOT edit `memory-bank/` (Claude records it).
- Do NOT edit `scripts/plugins/acg.sh` (a stub) or anything under `scripts/lib/foundation/`.
- Do NOT hard-code `0.250.250.254`, and do NOT fall back to the bridge gateway (`192.168.97.1`). It is
  not the Mac.
- Do NOT change the CoreDNS patch/restart logic, the `register_app_cluster` ordering, or the
  data-layer wait.
- Do NOT turn `bin/cluster-refresh`'s empty branch into a failure.
- Do NOT run `make up`, `make down`, `bin/cluster-up`, `bin/cluster-refresh` or `kubectl` against any
  live cluster, and do NOT touch the hub CoreDNS. Every test is offline, with stubs.
- Do NOT read, echo or log any token or credential.
