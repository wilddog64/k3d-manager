# Fix: bin/acg-extend-test — re-validate AWS credentials after extend

**Branch (lib-acg):** `fix/next-improvements-5`
**File:** `bin/acg-extend-test`

---

## Problem

`bin/acg-extend-test` uses `exec node ...` which replaces the shell process with node.
Nothing can run after `exec`, so there is no credential re-validation step after the extend
action. `make all` and `make up` both call this script and have no signal that credentials
are still valid after extending the session.

**Root cause:** Line 15 uses `exec` — correct for a pure passthrough script, but prevents
any post-extend steps.

---

## Fix

Remove `exec`, run node normally, then re-validate AWS credentials after the extend
completes. Parse `--provider` from the remaining args to guard the AWS-only validation.

**Exact old file content:**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi

sandbox_url="${1:?Usage: $0 <sandbox-url>}"
shift

ACG_REQUIRE_CDP=1 exec node "$REPO_ROOT/playwright/acg_extend.js" "$sandbox_url" "$@"
```

**Exact new file content:**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi

sandbox_url="${1:?Usage: $0 <sandbox-url>}"
shift

ACG_REQUIRE_CDP=1 node "$REPO_ROOT/playwright/acg_extend.js" "$sandbox_url" "$@"

# Parse --provider from remaining args (default: aws)
_provider="aws"
_rest=("$@")
for (( _i=0; _i<${#_rest[@]}-1; _i++ )); do
  if [[ "${_rest[_i]}" == "--provider" ]]; then
    _provider="${_rest[$(( _i + 1 ))]}"
    break
  fi
done

if [[ "$_provider" == "aws" ]]; then
  if aws sts get-caller-identity --output text >/dev/null 2>&1; then
    printf 'INFO: AWS credentials re-validated after extend (sts:GetCallerIdentity OK)\n' >&2
  else
    printf 'ERROR: AWS credential re-validation failed after extend\n' >&2
    exit 1
  fi
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-extend-test` | Replace `exec node` with plain `node`; add provider-guarded AWS credential re-validation |

---

## Rules

- `shellcheck -S warning bin/acg-extend-test` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] `exec node` replaced with plain `node` on former line 15
- [ ] Provider-parse + AWS re-validation block added after the node call
- [ ] No other files modified
- [ ] `shellcheck -S warning bin/acg-extend-test` passes
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-extend-test): drop exec — add AWS credential re-validation after extend
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-extend-test`
- Do NOT commit to `main`
