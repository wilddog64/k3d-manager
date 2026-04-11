# Copilot PR #64 Review Findings

**Date:** 2026-04-11
**PR:** #64 — feat(ssm): AWS SSM support for k3s-aws provider
**Fix commit:** `6fb423e5`

## Finding 1 — `Makefile`: bare `sudo dpkg -i` for Linux session-manager-plugin install

**File:** `Makefile:85`
**What Copilot flagged:** The `make ssm` target called `sudo dpkg -i` directly for Linux installs, bypassing the `_run_command` pattern used everywhere else. Makefile targets cannot route through `_run_command`.

**Fix:** Drop the Linux auto-install branch entirely; print manual install URL instead:
```makefile
# Before
elif command -v curl >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then \
  curl -sf "..." -o /tmp/session-manager-plugin.deb && sudo dpkg -i /tmp/session-manager-plugin.deb; \

# After
else \
  echo "[make] ERROR: cannot auto-install session-manager-plugin in this environment"; \
  echo "[make] Install it manually from:"; \
  echo "[make]   https://docs.aws.amazon.com/systems-manager/..."; \
  exit 1; \
```

**Root cause:** Makefile targets are shell snippets — `_run_command` is not available there. The correct pattern for non-brew platforms is print-and-exit.

**Process note:** Makefile targets that install software must not call `sudo` directly. macOS via `brew` only; all other platforms print the manual URL.

---

## Finding 2 — `shopping_cart.sh:deploy_app_cluster`: lost indentation

**File:** `scripts/plugins/shopping_cart.sh:285`
**What Copilot flagged:** The post-join block (`_setup_vault_bridge` + `_info` next-steps messages) was at column 0 instead of indented inside the function body.

**Fix:** Re-indented the entire block with 2-space indent to match surrounding code.

**Root cause:** Spec had the block added at the end of a conditional (`if [[ -n "${UBUNTU_K3S_AGENT_HOSTS:-}" ]]; then … fi`) and the `fi` closing moved the visual baseline — the block was pasted at the wrong indent level.

**Process note:** When adding code after a closing `fi` inside a function, verify the indent level relative to the `function` keyword, not the `fi`.

---

## Finding 3 — `shopping_cart.sh:_ssm_bootstrap_k3s`: missing `mkdir -p ~/.kube`

**File:** `scripts/plugins/shopping_cart.sh:357`
**What Copilot flagged:** `_ssm_bootstrap_k3s` writes `${HOME}/.kube/ubuntu-k3s.tmp` without ensuring `~/.kube/` exists. On a clean machine with no prior kubectl usage this would fail silently.

**Fix:**
```bash
# Before
local tmp_kube tmp_merged
tmp_kube="${HOME}/.kube/ubuntu-k3s.tmp"

# After
local tmp_kube tmp_merged
mkdir -p "${HOME}/.kube"
tmp_kube="${HOME}/.kube/ubuntu-k3s.tmp"
```

**Root cause:** `deploy_app_cluster` (SSH path) also writes `~/.kube/` but creates `kubeconfig_dir` earlier via `k3sup`; the SSM path writes directly without that guard.

**Process note:** Any function writing to `~/.kube/` must `mkdir -p "${HOME}/.kube"` first.

---

## Finding 4 — `ssm.sh:_ssm_get_instance_id`: `None`/`null` sentinel not normalized

**File:** `scripts/plugins/ssm.sh:47`
**What Copilot flagged:** `aws ec2 describe-instances ... --output text` returns the string `"None"` (not empty) when no instance is found. The function returned that string with exit code 0, so callers treated it as a valid instance ID.

**Fix:**
```bash
# Before
aws ec2 describe-instances \
  --filters ... \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text

# After
local instance_id
instance_id=$(aws ec2 describe-instances \
  --filters ... \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)
if [[ -z "${instance_id}" || "${instance_id}" == "None" || "${instance_id}" == "null" ]]; then
  _err "[ssm] No running instance found with tag Name=${tag_value}"
  return 1
fi
echo "${instance_id}"
```

**Root cause:** AWS CLI `--output text` returns `"None"` for null JMESPath results; `--output json` returns `null`. Both must be handled. Consistent with the existing pattern in `_acg_get_instance_id` (acg.sh:54-63).

**Process note:** All AWS CLI `--output text` calls that return an ID must guard against `"None"` and `"null"`.

---

## Finding 5 — `docs/api/functions.md:ssm_exec`: inaccurate doc claims

**File:** `docs/api/functions.md:77`
**What Copilot flagged:** The `ssm_exec` table entry claimed it "streams stdout/stderr" and "requires `K3S_AWS_SSM_ENABLED=true`". The code polls `get-command-invocation` and prints output after completion (not streaming), and has no env guard.

**Fix:**
```
# Before
Run a shell command ... ; streams stdout/stderr; requires `K3S_AWS_SSM_ENABLED=true`

# After
Run a shell command ... ; prints command output/results after execution
```

**Root cause:** Doc was written from the spec intent rather than the actual implementation.

**Process note:** Doc entries for new functions must be written after reading the implementation, not from the spec.

---

## Finding 6 — `CHANGE.md:make ssm`: description says "open SSM shell"

**File:** `CHANGE.md:8`
**What Copilot flagged:** The CHANGE.md entry described `make ssm` as "open SSM shell" but the target only ensures `session-manager-plugin` is installed; it does not open a shell.

**Fix:**
```
# Before
`ssm` target (open SSM shell) and `provision` target ...

# After
`ssm` target (ensures `session-manager-plugin` is installed) and `provision` target ...
```

**Root cause:** Description was written at spec time when the intent was broader; final implementation was scoped to plugin install only and the description wasn't updated.

**Process note:** CHANGE.md entries must be written (or re-verified) after final implementation, not carried over from spec intent.
