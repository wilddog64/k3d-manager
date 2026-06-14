# Bugfix: v1.7.0 — k3s-hostinger: load `_ensure_k3sup`; resolve hostname → IP for k3sup

**Branch:** `k3d-manager-v1.7.0`
**Files:** `scripts/lib/providers/k3s-hostinger.sh`

---

## Problem

Live smoke test of the `k3s-hostinger` provider (`deploy_cluster --confirm` against the real
VPS) surfaced two defects that `shellcheck` and `make -n` cannot catch:

**Bug A — `_ensure_k3sup: command not found` (`k3s-hostinger.sh:39`).**
The provider calls `_ensure_k3sup`, but that function lives in `scripts/plugins/shopping_cart.sh`.
The sibling `k3s-az.sh` (line 11) and `k3s-gcp.sh` source `shopping_cart.sh` at the top; when
`k3s-hostinger.sh` was built as "mirror `k3s-az.sh` minus VM lifecycle," the `shopping_cart.sh`
source line was dropped along with the Azure-specific source. It is non-fatal **only** because
k3sup happens to be pre-installed on the operator Mac; on a clean machine the provider cannot
bootstrap k3sup and the install step would run unguarded.

**Bug B — `failed to parse IP: "srv1754834.hstgr.cloud"` (FATAL).**
`_hostinger_k3sup_install` passes `HOSTINGER_HOST` straight to k3sup's `--ip` flag, which accepts
only a numeric IPv4 address. A hostname (which is what the operator naturally has for a Hostinger
box — `srv1754834.hstgr.cloud`) is rejected and the deploy aborts. az/gcp never hit this because
they pass actual IPs returned by their cloud APIs.

**Root cause (both):** parity gaps introduced when the provider was trimmed from the `k3s-az.sh`
template — one dropped source line, plus a hostinger-only need to resolve the user-supplied host
to an IP before k3sup. Using k3sup `--ip <resolved-ip>` (rather than `--host <hostname>`) keeps the
kubeconfig server address inside the k3s server-cert SAN (the node IP is auto-added; an arbitrary
hostname is not), so kubectl TLS verification keeps working — confirmed by the smoke test, which
succeeded end-to-end once an IP was supplied.

---

## Reproduction

```bash
HOSTINGER_HOST=srv1754834.hstgr.cloud CLUSTER_PROVIDER=k3s-hostinger \
  ./scripts/k3d-manager deploy_cluster --confirm
# actual:   line 39: _ensure_k3sup: command not found
#           Error: invalid argument "srv1754834.hstgr.cloud" for "--ip" flag: failed to parse IP
# expected: SSH wait → k3sup install → node Ready  (works today only if HOSTINGER_HOST is an IP)
```

---

## Fix

### Change 1 — Bug A: source `shopping_cart.sh` so `_ensure_k3sup` is defined

Mirror `k3s-az.sh:11`. Add the source line immediately after the header comment block,
before the variable assignments.

**Exact old block (lines 1–10):**

```bash
#!/usr/bin/env bash
# scripts/lib/providers/k3s-hostinger.sh
# Single-node k3s app cluster on a pre-existing, permanent Hostinger VPS (SSH target).
# The VPS is provisioned out-of-band (Hostinger panel); this provider never creates or
# deletes the VM — it only installs/uninstalls k3s over SSH and registers the context.

_HOSTINGER_SSH_USER="${HOSTINGER_SSH_USER:-ubuntu}"
_HOSTINGER_SSH_KEY="${HOSTINGER_SSH_KEY:-${HOME}/.ssh/hostinger}"
_HOSTINGER_KUBE_CONTEXT="ubuntu-hostinger"
_HOSTINGER_KUBECONFIG="${HOME}/.kube/hostinger.config"
```

**Exact new block:**

```bash
#!/usr/bin/env bash
# scripts/lib/providers/k3s-hostinger.sh
# Single-node k3s app cluster on a pre-existing, permanent Hostinger VPS (SSH target).
# The VPS is provisioned out-of-band (Hostinger panel); this provider never creates or
# deletes the VM — it only installs/uninstalls k3s over SSH and registers the context.

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"

_HOSTINGER_SSH_USER="${HOSTINGER_SSH_USER:-ubuntu}"
_HOSTINGER_SSH_KEY="${HOSTINGER_SSH_KEY:-${HOME}/.ssh/hostinger}"
_HOSTINGER_KUBE_CONTEXT="ubuntu-hostinger"
_HOSTINGER_KUBECONFIG="${HOME}/.kube/hostinger.config"
```

### Change 2 — Bug B: add `_hostinger_resolve_ip` and use it for k3sup `--ip`

Add the resolver helper immediately before `_hostinger_k3sup_install` (i.e. between the closing
`}` of `_hostinger_wait_for_ssh` and `function _hostinger_k3sup_install()`).

**Exact new helper to insert:**

```bash
function _hostinger_resolve_ip() {
  local host="$1" ip=""
  if [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "${host}"
    return 0
  fi
  if command -v dig >/dev/null 2>&1; then
    ip="$(dig +short "${host}" 2>/dev/null | grep -Em1 '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')"
  fi
  if [[ -z "${ip}" ]] && command -v getent >/dev/null 2>&1; then
    ip="$(getent ahostsv4 "${host}" 2>/dev/null | awk '{print $1; exit}')"
  fi
  if [[ -z "${ip}" ]] && command -v python3 >/dev/null 2>&1; then
    ip="$(python3 -c 'import socket,sys; print(socket.gethostbyname(sys.argv[1]))' "${host}" 2>/dev/null)"
  fi
  if [[ -z "${ip}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] could not resolve ${host} to an IPv4 address" >&2
    return 1
  fi
  printf '%s' "${ip}"
}
```

Then resolve the host inside `_hostinger_k3sup_install` and pass the IP to `--ip`.

**Exact old block:**

```bash
function _hostinger_k3sup_install() {
  local host="$1" ssh_user="$2" ssh_key="$3"
  _ensure_k3sup
  mkdir -p "$(dirname "${_HOSTINGER_KUBECONFIG}")" "${HOME}/.kube"
  _info "[k3s-hostinger] Installing k3s on ${ssh_user}@${host} via k3sup..."
  _run_command -- k3sup install \
    --ip "${host}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${_HOSTINGER_KUBECONFIG}" \
    --context "${_HOSTINGER_KUBE_CONTEXT}" \
    --k3s-extra-args '--disable traefik --disable servicelb'
}
```

**Exact new block:**

```bash
function _hostinger_k3sup_install() {
  local host="$1" ssh_user="$2" ssh_key="$3" ip
  ip="$(_hostinger_resolve_ip "${host}")" || return 1
  _ensure_k3sup
  mkdir -p "$(dirname "${_HOSTINGER_KUBECONFIG}")" "${HOME}/.kube"
  _info "[k3s-hostinger] Installing k3s on ${ssh_user}@${host} (${ip}) via k3sup..."
  _run_command -- k3sup install \
    --ip "${ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${_HOSTINGER_KUBECONFIG}" \
    --context "${_HOSTINGER_KUBE_CONTEXT}" \
    --k3s-extra-args '--disable traefik --disable servicelb'
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-hostinger.sh` | source `shopping_cart.sh` for `_ensure_k3sup`; add `_hostinger_resolve_ip`; pass resolved IP to k3sup `--ip` |

---

## Rules

- `shellcheck -S warning scripts/lib/providers/k3s-hostinger.sh` — zero warnings
- `./scripts/k3d-manager _agent_audit` — passes (no new findings)
- `bash -n scripts/lib/providers/k3s-hostinger.sh` — parses clean
- No other files touched

---

## Definition of Done

- [ ] `shopping_cart.sh` sourced near the top (matches `k3s-az.sh:11`)
- [ ] `_hostinger_resolve_ip` added; passes through a literal IPv4, resolves a hostname, errors if neither
- [ ] `_hostinger_k3sup_install` passes the resolved IP to `--ip`
- [ ] `shellcheck -S warning` clean; `_agent_audit` clean; `bash -n` clean
- [ ] Committed and pushed to `k3d-manager-v1.7.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(k3s-hostinger): source shopping_cart for _ensure_k3sup; resolve host to IP for k3sup
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT switch k3sup to `--host` (breaks kubeconfig TLS SAN) — resolve to an IP and keep `--ip`
- Do NOT modify any file other than `scripts/lib/providers/k3s-hostinger.sh`
- Do NOT commit to `main` — work on `k3d-manager-v1.7.0`
