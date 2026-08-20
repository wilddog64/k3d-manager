# Bug: lib-acg — `bin/acg-credential-test` validates in isolated env; credentials not written to shell; `aws s3 ls` fails after "validated OK"

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `bin/acg-credential-test` — write extracted credentials to `~/.aws/credentials [default]`; validate using the written file (not isolated env)

---

## Before You Start

```
git -C ~/src/gitrepo/personal/lib-acg fetch origin
git -C ~/src/gitrepo/personal/lib-acg checkout fix/acg-credentials-extend-dialog
git -C ~/src/gitrepo/personal/lib-acg pull origin fix/acg-credentials-extend-dialog
```

Read this spec in full before touching any file.

---

## Problem

`bin/acg-credential-test` prints `INFO: AWS credentials validated (sts:GetCallerIdentity OK)`
but subsequent `aws s3 ls` (or any `aws` command in the same shell) fails with
`InvalidAccessKeyId`.

**Root cause:** `_validate_aws` runs `aws sts get-caller-identity` inside an isolated `env`
subshell with the extracted key/secret/token. This validates that the credential *values* are
structurally valid, but nothing writes those values to `~/.aws/credentials` or to the shell
environment. Any subsequent `aws` command in the same terminal uses whatever credentials were
already configured — not the extracted ones. The "validated OK" message is misleading because
it does not reflect what the shell will experience.

**Fix:** Write the extracted credentials to `~/.aws/credentials` under `[default]` immediately
after extraction, then run `aws sts get-caller-identity` without an isolated env (using the
default profile). If `sts:GetCallerIdentity` passes using the file, subsequent `aws` commands
in the same shell will also pass — because they use the same credential source.

---

## Fix

### Change 1 — `bin/acg-credential-test`: write to ~/.aws/credentials; validate via default profile

**Exact old block (entire file):**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi

sandbox_url="${1:?Usage: $0 <sandbox-url> [--provider aws|gcp]}"
shift

_tmpout=$(mktemp)
trap 'rm -f "$_tmpout"' EXIT

node "$REPO_ROOT/playwright/acg_credentials.js" "$sandbox_url" "$@" | tee "$_tmpout"

if grep -q '^AWS_ACCESS_KEY_ID=' "$_tmpout"; then
  _key_id=$(grep '^AWS_ACCESS_KEY_ID=' "$_tmpout" | cut -d= -f2-)
  _secret=$(grep '^AWS_SECRET_ACCESS_KEY=' "$_tmpout" | cut -d= -f2-)
  _token=$(grep '^AWS_SESSION_TOKEN=' "$_tmpout" | cut -d= -f2- || true)

  _validate_aws() {
    local -a _env=(
      AWS_ACCESS_KEY_ID="$1"
      AWS_SECRET_ACCESS_KEY="$2"
    )
    [[ -n "${3:-}" ]] && _env+=(AWS_SESSION_TOKEN="$3")
    env "${_env[@]}" aws sts get-caller-identity >/dev/null 2>&1
  }

  if _validate_aws "$_key_id" "$_secret" "$_token"; then
    printf 'INFO: AWS credentials validated (sts:GetCallerIdentity OK)\n' >&2
  else
    printf 'ERROR: AWS credentials are invalid — sts:GetCallerIdentity failed\n' >&2
    exit 1
  fi
fi
```

**Exact new block (entire file):**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi

sandbox_url="${1:?Usage: $0 <sandbox-url> [--provider aws|gcp]}"
shift

_tmpout=$(mktemp)
trap 'rm -f "$_tmpout"' EXIT

node "$REPO_ROOT/playwright/acg_credentials.js" "$sandbox_url" "$@" | tee "$_tmpout"

if grep -q '^AWS_ACCESS_KEY_ID=' "$_tmpout"; then
  _key_id=$(grep '^AWS_ACCESS_KEY_ID=' "$_tmpout" | cut -d= -f2-)
  _secret=$(grep '^AWS_SECRET_ACCESS_KEY=' "$_tmpout" | cut -d= -f2-)
  _token=$(grep '^AWS_SESSION_TOKEN=' "$_tmpout" | cut -d= -f2- || true)

  mkdir -p "${HOME}/.aws"
  {
    printf '[default]\n'
    printf 'aws_access_key_id=%s\n' "$_key_id"
    printf 'aws_secret_access_key=%s\n' "$_secret"
    [[ -n "$_token" ]] && printf 'aws_session_token=%s\n' "$_token"
  } > "${HOME}/.aws/credentials"
  printf 'INFO: AWS credentials written to ~/.aws/credentials [default]\n' >&2

  if AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity >/dev/null 2>&1; then
    printf 'INFO: AWS credentials validated via ~/.aws/credentials (sts:GetCallerIdentity OK)\n' >&2
  else
    printf 'ERROR: AWS credentials written to ~/.aws/credentials but sts:GetCallerIdentity failed\n' >&2
    exit 1
  fi
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-credential-test` | Write credentials to `~/.aws/credentials [default]`; validate via default profile (not isolated env) |

---

## Rules

- `shellcheck -S warning bin/acg-credential-test` — zero warnings
- GCP flow (no `AWS_ACCESS_KEY_ID` in output) must pass through without touching `~/.aws/credentials`
- No other files modified

---

## Definition of Done

- [ ] `_validate_aws` function removed entirely
- [ ] `mkdir -p "${HOME}/.aws"` present before write
- [ ] `~/.aws/credentials` written with `[default]` header, `aws_access_key_id`, `aws_secret_access_key`, and conditional `aws_session_token`
- [ ] File write uses `printf` with `>` redirect (not `cat <<EOF` heredoc) to avoid quoting issues with credential values
- [ ] `printf 'INFO: AWS credentials written to ~/.aws/credentials [default]\n'` logged before validation
- [ ] Validation uses `AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity` (no isolated env; uses `~/.aws/credentials [default]`)
- [ ] ERROR message on validation failure references `~/.aws/credentials`
- [ ] GCP-only output (no `AWS_ACCESS_KEY_ID=`) skips the entire block — `~/.aws/credentials` not touched
- [ ] `shellcheck -S warning bin/acg-credential-test` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat` output

**Commit message (exact):**
```
fix(bin): write AWS credentials to ~/.aws/credentials; validate via default profile
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-credential-test`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT use `eval` to expand credential variables
- Do NOT touch `bin/acg-extend-test`
- Do NOT use a named profile (e.g. `[acg]`) — write to `[default]` so `aws` commands work without `--profile`
- Do NOT use `cat <<EOF` heredoc for the credentials file — use `printf` to avoid whitespace and quoting issues
