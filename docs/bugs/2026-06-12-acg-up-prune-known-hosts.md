# SSH host-key hygiene — non-interactive provisioning + automated known_hosts prune

**Date:** 2026-06-12
**Branch:** `k3d-manager-v1.6.5`
**Files:** `scripts/plugins/shopping_cart.sh`, `bin/acg-up`

---

## Problem

Two related symptoms on the AWS multi-node path:

1. **Interactive prompt hangs provisioning.** `shopping_cart.sh` connects SSH/k3sup to fresh
   EC2 hosts by raw IP with no host-key bypass (unlike `k3s-az.sh`/`k3s-gcp.sh`, which pass
   `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`). On a brand-new host OpenSSH's
   default `ask` policy fires:
   ```
   The authenticity of host '54.184.31.89' can't be established.
   Are you sure you want to continue connecting (yes/no/[fingerprint])?
   ```
   Four call sites are affected: `k3sup install` (~872), `k3sup join` (~771), and two bare
   `ssh` heredocs (~785, ~882).

2. **known_hosts rots.** Each provision leaves ephemeral cloud host keys behind (a manual sweep
   just purged 733). ACG recycles public IPs across sandboxes, so a stale entry for a recycled
   IP later triggers the hard `REMOTE HOST IDENTIFICATION HAS CHANGED` / `Host key verification
   failed` error.

**Decision (user, 2026-06-12):** fix both together — (Part 1) make the four call sites
non-interactive, and (Part 2) automate a **preflight broad sweep** at the start of every
`acg-up` that drops every globally-routable IPv4 entry.

The two parts are self-consistent: Step 0 removes all stale public IPs at the start of a run, so
during provisioning every live host is "new"; Part 1 trusts those hosts non-interactively; the
next run's Step 0 sweeps them again.

---

## Part 1 — non-interactive host keys in `scripts/plugins/shopping_cart.sh`

### 1A — add a host-trust helper (insert ABOVE `function _k3sup_join_agent() {`)

`k3sup` connects to the raw IP and has no `StrictHostKeyChecking` flag, so pre-seed the host key
into `known_hosts` (works whether k3sup uses the system ssh client or its own known_hosts
reader). The bounded loop doubles as a wait-for-SSH.

**Anchor (exact existing line):**
```bash
function _k3sup_join_agent() {
```

**Insert this block directly ABOVE that anchor:**
```bash
function _ubuntu_k3s_trust_host() {
  local host="$1" attempts=0 key
  [[ -z "${host}" ]] && return 0
  mkdir -p "${HOME}/.ssh"
  touch "${HOME}/.ssh/known_hosts"
  until key=$(ssh-keyscan -T 5 "${host}" 2>/dev/null) && [[ -n "${key}" ]]; do
    (( ++attempts ))
    if (( attempts >= 24 )); then
      _warn "[shopping_cart] ssh-keyscan ${host} not ready after 120s — k3sup may prompt"
      return 0
    fi
    sleep 5
  done
  ssh-keygen -R "${host}" >/dev/null 2>&1 || true
  printf '%s\n' "${key}" >> "${HOME}/.ssh/known_hosts"
  _info "[shopping_cart] Trusted host key for ${host}"
}

```

### 1B — trust before `k3sup join`

**Old:**
```bash
  _info "[shopping_cart] Joining agent ${agent_host} (${agent_ip}) to server ${server_ip}..."
  _run_command -- k3sup join \
```
**New:**
```bash
  _info "[shopping_cart] Joining agent ${agent_host} (${agent_ip}) to server ${server_ip}..."
  _ubuntu_k3s_trust_host "${agent_ip}"
  _run_command -- k3sup join \
```

### 1C — relax the vault-bridge bare ssh

**Old:**
```bash
_run_command -- ssh -i "${ssh_key}" "${ssh_host}" bash <<'REMOTE'
```
**New:**
```bash
_run_command -- ssh -i "${ssh_key}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${ssh_host}" bash <<'REMOTE'
```

### 1D — trust before `k3sup install`

**Old:**
```bash
  _info "[shopping_cart] Installing k3s on ${ssh_user}@${external_ip} via k3sup..."
  _run_command -- k3sup install \
```
**New:**
```bash
  _info "[shopping_cart] Installing k3s on ${ssh_user}@${external_ip} via k3sup..."
  _ubuntu_k3s_trust_host "${external_ip}"
  _run_command -- k3sup install \
```

### 1E — relax the kubeconfig-copy bare ssh

**Old:**
```bash
  _run_command -- ssh -i "${ssh_key}" "${ssh_user}@${external_ip}" bash <<'REMOTE'
```
**New:**
```bash
  _run_command -- ssh -i "${ssh_key}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${ssh_user}@${external_ip}" bash <<'REMOTE'
```

---

## Part 2 — preflight known_hosts sweep in `bin/acg-up`

Insert a self-contained "Step 0/12" block **immediately ABOVE** the existing Step 1 line
(logging helpers are already sourced by this point).

**Anchor (exact existing line — insert ABOVE it):**
```bash
_info "[acg-up] Step 1/12 — Getting ${_cluster_provider} credentials..."
```

**Exact block to insert directly above that anchor:**
```bash
_info "[acg-up] Step 0/12 — Pruning stale public IPs from ~/.ssh/known_hosts..."
_kh="${HOME}/.ssh/known_hosts"
if [[ -f "${_kh}" ]]; then
  cp -p "${_kh}" "${_kh}.bak"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${_kh}" <<'PY'
import sys, ipaddress, re
path = sys.argv[1]
kept, removed = [], 0
for line in open(path):
    s = line.strip()
    if not s or s.startswith('#') or s.startswith('|1|'):
        kept.append(line); continue
    host = s.split()[0].split(',')[0]
    m = re.match(r'^\[(.+)\](?::\d+)?$', host)
    h = m.group(1) if m else host
    try:
        ip = ipaddress.ip_address(h)
        if ip.version == 4 and ip.is_global:
            removed += 1; continue
    except ValueError:
        pass
    kept.append(line)
open(path, 'w').writelines(kept)
print(f"INFO: [acg-up] known_hosts pruned {removed} public-IP entries, kept {len(kept)}")
PY
  else
    _warn "[acg-up] python3 not found — skipping known_hosts prune"
  fi
fi

```

Filter notes (do NOT change the logic):
- `is_global` is the keep/drop test: public IPv4 → dropped; private (`10/8`, `172.16/12`,
  `192.168/16`), loopback (`127/8`), CGNAT (`100.64/10`), link-local → kept.
- Hostnames (`github.com`, `m2-air.local`, …) don't parse as an IP → kept.
- Bracketed `[host]:port` forwards (e.g. `[127.0.0.1]:2201`) → host parsed, loopback kept.
- Comment (`#`) and hashed (`|1|`) lines → kept verbatim.
- Single rolling backup `known_hosts.bak`, overwritten each run.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/shopping_cart.sh` | add `_ubuntu_k3s_trust_host`; trust before both k3sup calls; `StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null` on both bare ssh calls |
| `bin/acg-up` | add Step 0/12 known_hosts prune block before Step 1 |

---

## Rules

- `shellcheck -S warning scripts/plugins/shopping_cart.sh bin/acg-up` — zero new warnings
- `./scripts/k3d-manager _agent_audit` — passes
- Part 1: exactly the 5 edits above (1 helper + 2 trust calls + 2 ssh option additions); no
  other line in `shopping_cart.sh` changed
- Part 2: Step 0 block inserted exactly once, directly above the `Step 1/12` line
- No other file touched; do NOT modify `scripts/lib/foundation/`, the providers, or other plugins

---

## Definition of Done

- [ ] Part 1: helper added + 4 call sites updated in `scripts/plugins/shopping_cart.sh`
- [ ] Part 2: Step 0 block inserted above the Step 1 anchor in `bin/acg-up`
- [ ] `shellcheck -S warning scripts/plugins/shopping_cart.sh bin/acg-up` passes
- [ ] `./scripts/k3d-manager _agent_audit` passes
- [ ] Dry verify the filter: pipe 4 sample lines (a hostname, `127.0.0.1`, `192.168.1.2`,
      `54.184.31.89`) through the Part 2 python logic — first three kept, last dropped
- [ ] Committed and pushed to `k3d-manager-v1.6.5`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(ssh): non-interactive host keys in shopping_cart + prune known_hosts on acg-up preflight
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/plugins/shopping_cart.sh` and `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.5`
- Do NOT change the `is_global` filter logic or remove the backup/trust steps
