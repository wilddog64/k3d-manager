# Automate ~/.ssh/known_hosts hygiene — preflight prune in acg-up

**Date:** 2026-06-12
**Branch:** `k3d-manager-v1.6.5`
**Files:** `bin/acg-up`

---

## Problem

Every ACG provision connects SSH/k3sup to fresh, ephemeral cloud VMs (AWS/Azure/GCP public
IPs). Those host keys pile up in `~/.ssh/known_hosts` and never get removed — a one-time manual
sweep just purged **733** stale public-IP entries. Worse, ACG recycles public IPs across
sandboxes, so a stale entry for a recycled IP later triggers the hard
`REMOTE HOST IDENTIFICATION HAS CHANGED` / `Host key verification failed` error.

**Decision (user, 2026-06-12):** automate this as a **preflight broad sweep** — at the start of
every `acg-up`, back up `known_hosts` and drop every globally-routable IPv4 entry, keeping
hostnames, private/loopback/CGNAT addresses, hashed entries, and comments.

---

## Fix — add a Step 0 prune block to `bin/acg-up`

Insert a self-contained "Step 0/12" block **immediately before** the existing Step 1 line.
Logging helpers (`_info`, `_warn`) are already sourced by this point.

### Anchor (exact existing line — insert ABOVE it)

```bash
_info "[acg-up] Step 1/12 — Getting ${_cluster_provider} credentials..."
```

### Exact block to insert (directly above that anchor)

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

Notes on the filter (do NOT change the logic):
- `is_global` is the keep/drop test: public IPv4 → dropped; private (`10/8`, `172.16/12`,
  `192.168/16`), loopback (`127/8`), CGNAT (`100.64/10`), link-local → kept.
- Hostnames (`github.com`, `m2-air.local`, …) don't parse as an IP → kept.
- Bracketed `[host]:port` forwards (e.g. `[127.0.0.1]:2201`) → host parsed, loopback kept.
- Comment (`#`) and hashed (`|1|`) lines → kept verbatim.
- A single rolling backup `known_hosts.bak` is overwritten each run (no backup spam).

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | add Step 0/12 known_hosts prune block before Step 1 |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- `./scripts/k3d-manager _agent_audit` — passes (repo lint gate used by other acg-up fixes)
- Block must be inserted exactly once, directly above the `Step 1/12` line
- No other file touched; do NOT modify `scripts/lib/foundation/`, providers, or plugins

---

## Definition of Done

- [ ] Step 0 block inserted above the Step 1 anchor in `bin/acg-up`
- [ ] `shellcheck -S warning bin/acg-up` passes
- [ ] `./scripts/k3d-manager _agent_audit` passes
- [ ] Dry verify: `python3 - <<'PY'` filter keeps a hostname + `127.0.0.1` + `192.168.1.2`,
      drops `54.184.31.89` (paste 4 sample lines through the same logic and confirm)
- [ ] Committed and pushed to `k3d-manager-v1.6.5`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
feat(acg-up): prune stale public IPs from known_hosts on preflight (Step 0)
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.5`
- Do NOT change the `is_global` filter logic or remove the backup step
