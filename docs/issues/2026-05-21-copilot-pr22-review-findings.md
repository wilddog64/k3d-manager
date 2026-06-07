# Copilot PR #22 Review Findings

**PR:** #22 — feat(acg): make CFn template path configurable via ACG_CLUSTER_TEMPLATE
**Date:** 2026-05-21

---

## Finding 1 — No preflight check on `ACG_CLUSTER_TEMPLATE` path

**Location:** `scripts/plugins/acg.sh` line 136
**Copilot:** `ACG_CLUSTER_TEMPLATE` can be overridden by callers; a non-existent path produces an opaque `aws cloudformation deploy` failure. Recommend a preflight `-f` check with an actionable error.

**Fix:**
```bash
# Before
  _info "[acg] Deploying CloudFormation stack ..."
  _run_command -- aws cloudformation deploy \
    --template-file "${ACG_CLUSTER_TEMPLATE:-${_LIB_ACG_ROOT}/scripts/etc/acg-cluster.yaml}" \

# After
  local _cfn_template="${ACG_CLUSTER_TEMPLATE:-${_LIB_ACG_ROOT}/scripts/etc/acg-cluster.yaml}"
  if [[ ! -f "${_cfn_template}" ]]; then
    _err "[acg] CloudFormation template not found: ${_cfn_template}" \
         "(set ACG_CLUSTER_TEMPLATE to a valid path)"
    return 1
  fi

  _info "[acg] Deploying CloudFormation stack ..."
  _run_command -- aws cloudformation deploy \
    --template-file "${_cfn_template}" \
```

**Root cause:** The env-var override was added without a corresponding existence check, leaving callers with a confusing AWS CLI error if they set a wrong path.

**Process note:** Any configurable file path accepted from an env var must be validated with `-f` before use, with an error message that names the variable.

---

## Finding 2 — README "Upstream Push to Main" row links to wrong file

**Location:** `README.md` line 57
**Copilot:** The Issue Logs row for "Upstream Push to Main" links to `docs/issues/2026-05-20-copilot-pr18-review-findings.md` (a Copilot review doc) instead of the actual upstream-push incident doc.

**Fix:**
```markdown
# Before
| 2026-05-19 | [Upstream Push to Main](docs/issues/2026-05-20-copilot-pr18-review-findings.md) | ...

# After
| 2026-05-19 | [Upstream Push to Main](docs/issues/2026-05-19-lib-acg-upstream-push-targeted-main.md) | ...
```

**Root cause:** When the Haiku subagent populated the Issue Logs table, it reused a nearby filename from the same date cluster instead of looking up the correct doc for the incident description.

**Process note:** When populating README Issue Logs from `docs/issues/`, always match the link target to the actual file name — do not infer from adjacent entries.

---

## Finding 3 — Spec references non-existent `scripts/lib/vars.sh`

**Location:** `docs/bugs/v0.3.0-feat-cfn-template-path-configurable.md` lines 5, 83, 93
**Copilot:** The spec references `scripts/lib/vars.sh` but the repo uses `scripts/vars.sh` (no `lib/` subdirectory). This would confuse anyone following the spec.

**Fix:** `replace_all` — `scripts/lib/vars.sh` → `scripts/vars.sh` throughout the file.

**Root cause:** The spec was written from memory of a `scripts/lib/` layout that doesn't exist in lib-acg; the actual vars file is `scripts/vars.sh`.

**Process note:** Before naming a file path in a spec doc, verify it exists with `find` or `ls`.
