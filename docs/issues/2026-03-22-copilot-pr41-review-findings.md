# Copilot PR #41 Review Findings

**Date:** 2026-03-22
**PR:** [#41 — chore(v0.9.7): lib sync, safety gate, bin/ consistency, tooling polish](https://github.com/wilddog64/k3d-manager/pull/41)
**Fix commit:** `8b8d218`

---

## Finding 1 — Stale docstring in `_run_command_resolve_sudo`

**File:** `scripts/lib/system.sh:46`

**Finding:**
The docstring said "Caller must initialize `_RCRS_RUNNER` before calling" but the function now
resets `_RCRS_RUNNER=()` internally. The caller no longer needs to pre-initialize it.

**Fix:**
Updated the comment to reflect actual behavior:
```bash
# it in the global _RCRS_RUNNER. Caller should read _RCRS_RUNNER after calling
# and unset it when done.
```

**Root cause:** Docstring was written for the original design where the caller owned
initialization. The function was later refactored to self-initialize but the comment wasn't
updated.

---

## Finding 2 — if-count scan misses unstaged files

**File:** `scripts/lib/agent_rigor.sh:117` (and `scripts/lib/foundation/scripts/lib/agent_rigor.sh:104`)

**Finding:**
`_agent_audit` scans if-count using `git show :"$file"` which reads from the git index
(staged content). For files that are modified but not staged, `git show :"$file"` returns
the pre-change HEAD content — missing any new if-count violations introduced in the working tree.

**Fix:**
Added `cat "$file"` fallback so unstaged files are read from disk:
```bash
done < <(git show :"$file" 2>/dev/null || cat "$file" 2>/dev/null || true)
```

**Note:** The fix was applied to `scripts/lib/agent_rigor.sh` (the local k3d-manager copy).
`scripts/lib/foundation/` is read-only in this repo — the same fix needs to be upstreamed
to lib-foundation on `feat/v0.3.4` before the next subtree pull.

**Root cause:** `git show :"$file"` is the standard way to read staged content, but it silently
falls back to returning nothing for unstaged-only files rather than erroring — so the scan
appeared to succeed while scanning stale content.

---

## Finding 3 — `deploy_cluster` no-args guard printed one-line hint instead of full help

**File:** `scripts/lib/core.sh:733`

**Finding:**
The no-args guard added by `51a40b0` printed only:
```
deploy_cluster: no arguments given — run with -h for usage.
```
This conflicts with the spec intent ("print help, not trigger deployment") — the guard should
emit the same full usage block as `--help`, not a terse redirect.

**Fix:**
Replaced the one-liner with the full usage heredoc emitted to stderr:
```bash
if [[ ${#positional[@]} -eq 0 && -z "${provider_cli}" && "${force_k3s}" -eq 0 ]]; then
   cat >&2 <<'EOF'
Usage: deploy_cluster [options] [cluster_name]

Options:
  -f, --force-k3s     Skip the provider prompt and deploy using k3s.
  --provider <name>   Explicitly set the provider (k3d or k3s).
  -h, --help          Show this help message.
EOF
   return 1
fi
```

**Root cause:** Codex implemented the guard as a minimal hint rather than reusing the existing
help heredoc. The spec said "print help" but the example message was too terse — spec should
have shown the full usage block explicitly.

**Process note:** Added to Codex spec template — "no-args guard must emit the full help text,
not a redirect hint."
