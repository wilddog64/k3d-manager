# Bug: `cluster-up` failure cleanup kills port-forwards started by someone else

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** FIXED in `f61d3b3b` (Codex, Claude-verified: scope = spec, 61/61 BATS). Status line updated 2026-10-04.
**Severity:** low. It needs an orphaned run plus a manual restart to trigger, but when it does
it silently takes down the hub's `federate-acg` scrape.

## Observed (2026-10-04, about 02:55 UTC)

- A `make up` started at 12:58 PDT lost its terminal. Its `bin/cluster-up` (PID 1927) stayed
  alive as an orphan, sitting in a `sleep 12600` child.
- During recovery the operator started a fresh Prometheus port-forward by hand (PID 93911) and
  wrote it to `${_ACG_STATE_DIR}/run/acg-prom-pf.pid`, the same way Step 14b does.
- The operator then ran `kill 1927 85324`. A killed `cluster-up` exits non-zero, so the `EXIT`
  trap `_acg_up_cleanup` runs. It kills **whatever PID is in** `vault-pf.pid`, `frontend-pf.pid`
  and `acg-prom-pf.pid`.
- This time 93911 survived, apparently because the trap did not fire on that signal path. Nothing
  in the code protects it, though: the cleanup does not check who started the PID it kills.

## Root cause

`_acg_up_cleanup` (`bin/cluster-up:160`) treats each pid file as "the port-forward this run
started". The files are shared state, and a later run or the operator can overwrite them. A
failing or killed **older** run then kills the **newer** process.

## Fix

Kill only the PIDs this run started:

- Keep them in a list such as `_ACG_UP_OWNED_PIDS`.
- Add to the list at each `$!` capture: the Vault port-forward in Step 4 and the Prometheus
  port-forward in Step 14b.
- In the cleanup, kill a pid file's PID, and remove the file, only when that PID is in the list.
  Otherwise leave both alone.

## Fix spec

`bin/cluster-up`. Directly above `trap _acg_up_cleanup EXIT`, add:

```bash
_ACG_UP_OWNED_PIDS=""
```

In `_acg_up_cleanup`, replace

```bash
    if [[ -f "${_f}" ]]; then
      kill "$(cat "${_f}")" 2>/dev/null || true
      rm -f "${_f}"
    fi
```

with

```bash
    if [[ -f "${_f}" ]]; then
      local _pf_pid
      _pf_pid="$(cat "${_f}" 2>/dev/null || true)"
      if [[ -n "${_pf_pid}" && " ${_ACG_UP_OWNED_PIDS:-} " == *" ${_pf_pid} "* ]]; then
        kill "${_pf_pid}" 2>/dev/null || true
        rm -f "${_f}"
      fi
    fi
```

Directly after `_vault_pf_pid=$!`, add `_ACG_UP_OWNED_PIDS+=" ${_vault_pf_pid}"`. Directly after
`_acg_prom_pf_pid=$!`, add `_ACG_UP_OWNED_PIDS+=" ${_acg_prom_pf_pid}"`.

BATS (`scripts/tests/bin/cluster_up.bats`) uses the existing `_load_acg_up_cleanup` pattern and
stubs `kill` to record its argument:

1. When `acg-prom-pf.pid` holds a PID that is **not** in `_ACG_UP_OWNED_PIDS`, `kill` is not
   called and the file still exists.
2. When it holds a PID that **is** in the list, `kill` gets that PID and the file is removed.
3. A static check that the line after `_vault_pf_pid=$!`, and the line after
   `_acg_prom_pf_pid=$!`, each add to `_ACG_UP_OWNED_PIDS`.
