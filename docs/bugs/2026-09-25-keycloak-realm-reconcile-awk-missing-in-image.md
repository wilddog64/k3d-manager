# Bug: `keycloak-realm-reconcile` has failed for 4 days — `awk` does not exist in `quay.io/keycloak/keycloak:24.0`

**Filed:** 2026-09-25
**Work repo:** `shopping-cart-infra` (NOT k3d-manager)
**Branch (work repo):** `fix/keycloak-reconcile-awk-free` — create from `origin/main`
**Target file:** `identity/keycloak/keycloak-reconcile-hook-job.yaml` (517 lines) — and nothing else
**Severity:** the ArgoCD PostSync hook fails on every sync; `shopping-cart-identity` is stuck `OutOfSync`

---

## Symptom

```
$ kubectl --context k3d-k3d-cluster get job keycloak-realm-reconcile -n identity
NAME                       STATUS   COMPLETIONS   DURATION   AGE
keycloak-realm-reconcile   Failed   0/1           4d16h      4d16h
```

Two pods, both `Error`, `backoffLimit: 1` exhausted. The log ends after three lines:

```
Logging into http://keycloak.identity.svc.cluster.local as user admin of realm master
Realm shopping-cart exists; applying partial import
browser-with-conditional-otp flow already exists; reconciling it
environment: line 104: awk: command not found
```

`shopping-cart-identity` is `OutOfSync` on the hub as a direct result — the PostSync hook never
completes.

## Root cause

The Job runs in `quay.io/keycloak/keycloak:24.0` (manifest line 31). That image is built on
**ubi9-micro**, which ships `bash`, `grep`, `sed`, `head`, `date`, `sleep`, `mktemp` and `printf` —
but **no `awk`**.

This is why the failure looks selective: the `grep -q '"browser-with-conditional-otp"'` on the line
immediately above succeeds, so the script gets far enough to print "reconciling it" before dying on
the first `awk`. Reported "line 104" is the offset inside the embedded script; it corresponds to the
`awk` in `csv_value` at manifest line 106.

The script depends on `awk` in **11 places**:

| manifest line | context |
|---|---|
| 106 | `csv_value()` |
| 127 | `csv_match_count()` |
| 141 | `level0_rows()` |
| 153 | `urlencode_path()` |
| 186 | inline — stray `otp-conditional-subflow` ids |
| 207 | inline — count level-0 executions |
| 208 | inline — unexpected level-0 display names |
| 268, 279, 310 | inline — resolve execution id by `providerId` |
| 326 | inline — re-count level-0 executions |

**The image cannot be changed.** The script calls `/opt/keycloak/bin/kcadm.sh`, which only exists in
the Keycloak image, so this must be fixed by removing the `awk` dependency — not by swapping the base
image and not by installing a package (the container runs as non-root with no package manager, and an
ArgoCD hook must not reach the network for tooling).

## Fix — rewrite the CSV helpers in pure bash

`kcadm.sh --format csv` output is one record per line with each field wrapped in double quotes. The
existing `awk -F','` splits naively on commas, so `IFS=','` in bash is **equivalent fidelity** — this
is not a behavioural regression. Set `LC_ALL=C` for the character loop.

### Before You Start

1. Read `memory-bank/activeContext.md` in k3d-manager for the 2026-09-25 entries.
2. `git -C <shopping-cart-infra> fetch origin`
3. `git -C <shopping-cart-infra> checkout -b fix/keycloak-reconcile-awk-free origin/main`
4. Read `identity/keycloak/keycloak-reconcile-hook-job.yaml` **in full** before editing. The script is
   a YAML block scalar under `command:` — every line you add must keep the block's existing
   indentation exactly, or the manifest silently changes meaning.

### C1 — add a quote-stripping helper and replace the four named helpers

Replace `csv_value`, `csv_match_count`, `level0_rows` and `urlencode_path` with:

```bash
_strip_quotes() {
  local s="$1"
  s="${s#\"}"
  s="${s%\"}"
  printf '%s' "${s}"
}

csv_value() {
  local csv="$1" match_column="$2" match_value="$3" value_column="$4"
  local line
  local -a fields
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    IFS=',' read -r -a fields <<< "${line}"
    if [[ "$(_strip_quotes "${fields[$((match_column - 1))]:-}")" == "${match_value}" ]]; then
      printf '%s\n' "$(_strip_quotes "${fields[$((value_column - 1))]:-}")"
      return 0
    fi
  done <<< "${csv}"
}

csv_all_values() {
  local csv="$1" match_column="$2" match_value="$3" value_column="$4"
  local line
  local -a fields
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    IFS=',' read -r -a fields <<< "${line}"
    if [[ "$(_strip_quotes "${fields[$((match_column - 1))]:-}")" == "${match_value}" ]]; then
      printf '%s\n' "$(_strip_quotes "${fields[$((value_column - 1))]:-}")"
    fi
  done <<< "${csv}"
}

csv_match_count() {
  local csv="$1" match_column="$2" match_value="$3"
  local line count=0
  local -a fields
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    IFS=',' read -r -a fields <<< "${line}"
    if [[ "$(_strip_quotes "${fields[$((match_column - 1))]:-}")" == "${match_value}" ]]; then
      count=$((count + 1))
    fi
  done <<< "${csv}"
  printf '%s\n' "${count}"
}

csv_row_count() {
  local line count=0
  while IFS= read -r line; do
    [[ -n "${line}" ]] && count=$((count + 1))
  done <<< "$1"
  printf '%s\n' "${count}"
}

level0_rows() {
  local line
  local -a fields
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    IFS=',' read -r -a fields <<< "${line}"
    if [[ "$(_strip_quotes "${fields[5]:-}")" == "0" ]]; then
      printf '%s\n' "${line}"
    fi
  done <<< "$1"
}

csv_unexpected_top_names() {
  local csv="$1" forms_display_name="$2" line name
  local -a fields
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    IFS=',' read -r -a fields <<< "${line}"
    name="$(_strip_quotes "${fields[1]:-}")"
    case "${name}" in
      Cookie|Kerberos|"Identity Provider Redirector"|"${forms_display_name}") ;;
      *) printf '%s\n' "${name}" ;;
    esac
  done <<< "${csv}"
}

urlencode_path() {
  local s="$1" i c out=""
  local LC_ALL=C
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "${c}" in
      [A-Za-z0-9._~-]) out+="${c}" ;;
      *) out+="$(printf '%%%02X' "'${c}")" ;;
    esac
  done
  printf '%s' "${out}"
}
```

`level0_rows` uses `fields[5]` because the `--fields` list puts `level` sixth
(`id,displayName,requirement,authenticationFlow,flowId,level`) and bash arrays are 0-indexed. Keep
that coupling in mind if the `--fields` list ever changes.

### C2 — replace the seven inline `awk` pipelines with helper calls

| manifest line | old | new |
|---|---|---|
| 186 | `stray_ids="$(printf … \| awk … $2 == "otp-conditional-subflow" print $1)"` | `stray_ids="$(csv_all_values "${top_executions}" 2 "otp-conditional-subflow" 1)"` |
| 207 | `top_execution_count="$(printf … \| awk 'NF {count++} END {print count+0}')"` | `top_execution_count="$(csv_row_count "${top_executions}")"` |
| 208 | `unexpected_top_execution="$(printf … \| awk -v forms_display_name=…)"` | `unexpected_top_execution="$(csv_unexpected_top_names "${top_executions}" "${forms_display_name}")"` |
| 268 | `… --fields id,providerId --format csv \| awk … $2 == "conditional-user-role"` | assign the `kcadm.sh get` output to a local first, then `csv_value "${_csv}" 2 "conditional-user-role" 1` |
| 279 | same as 268 (the retry after create) | same treatment |
| 310 | `… \| awk … $2 == "auth-otp-form"` | `csv_value "${_csv}" 2 "auth-otp-form" 1` |
| 326 | `top_execution_count="$(printf … \| awk 'NF {count++} …')"` | `csv_row_count "${top_executions}"` |

For 268, 279 and 310 the `kcadm.sh get … | awk` pipeline must become two statements, because
`csv_value` takes the CSV as an argument, not on stdin:

```bash
_exec_csv="$(/opt/keycloak/bin/kcadm.sh get \
  "authentication/flows/${conditional_otp_flow_alias}/executions" \
  -r "${KC_REALM}" --fields id,providerId --format csv)"
role_condition_id="$(csv_value "${_exec_csv}" 2 "conditional-user-role" 1)"
```

Declare `_exec_csv` in the enclosing function's existing `local` list. Do not change any
`kcadm.sh` argument, `--fields` list, URL, or the surrounding control flow.

## Rules

- Only `identity/keycloak/keycloak-reconcile-hook-job.yaml` may change (plus `CHANGELOG.md` and the
  bug doc named below). No other manifest, no reformatting, no comment churn.
- LF endings. Preserve the YAML block-scalar indentation exactly — verify with
  `python3 -c "import yaml;yaml.safe_load(open('identity/keycloak/keycloak-reconcile-hook-job.yaml'))"`.
- Extract the script body and shellcheck it:
  `python3 -c "import yaml;print(yaml.safe_load(open('identity/keycloak/keycloak-reconcile-hook-job.yaml'))['spec']['template']['spec']['containers'][0]['command'][3])" > /tmp/reconcile.sh`
  then `shellcheck -s bash /tmp/reconcile.sh` — no new warnings versus the same extraction from
  `origin/main`. Paste the before/after counts.
- `grep -c awk` on the manifest must output `0`.
- Do NOT run the job, and do NOT touch a live cluster.

## Definition of Done

- [ ] Branch `fix/keycloak-reconcile-awk-free` created from `origin/main`
- [ ] C1 and C2 applied; `git diff --stat` shows only the one manifest (plus CHANGELOG + bug doc)
- [ ] `grep -c awk identity/keycloak/keycloak-reconcile-hook-job.yaml` outputs `0`
- [ ] YAML parses; shellcheck before/after counts pasted
- [ ] A shell-level unit check of the helpers, run locally with `bash`: feed each helper the real
      quoted-CSV shapes above and assert `csv_value`, `csv_all_values`, `csv_match_count`,
      `csv_row_count`, `level0_rows`, `csv_unexpected_top_names` and `urlencode_path` return exactly
      what the `awk` versions returned for the same input. Paste the comparison. **Prove each check
      can fail** by feeding one deliberately wrong input.
- [ ] `urlencode_path "browser-with-conditional-otp forms"` outputs
      `browser-with-conditional-otp%20forms` — paste it
- [ ] `CHANGELOG.md` gains an `### Fixed` entry naming the missing `awk` in the Keycloak image
- [ ] A bug doc at `docs/bugs/2026-09-25-keycloak-realm-reconcile-awk-missing.md` in
      `shopping-cart-infra` recording the log evidence and the ubi9-micro cause
- [ ] Commit message exactly:
      `fix(identity): remove the awk dependency the Keycloak image does not provide`
- [ ] `git push origin fix/keycloak-reconcile-awk-free`; verify with
      `git rev-parse origin/fix/keycloak-reconcile-awk-free`; report the SHA and `git show --stat`

## What NOT to Do

- Do NOT create a pull request, merge, commit to `main`, force-push, or use `--no-verify`
- Do NOT change the container image, add an initContainer, or install any package
- Do NOT change `kcadm.sh` arguments, `--fields` lists, URLs, requirement values or control flow
- Do NOT switch `--format csv` to `--format json` (there is no `jq` in the image either)
- Do NOT modify `identity/keycloak/realm-shopping-cart.json`, the secrets, or any other manifest
- Do NOT apply anything to a live cluster, and do NOT delete or re-run the failed Job — ArgoCD will
  re-run the hook on the next sync

## Operator follow-up

The existing `keycloak-realm-reconcile` Job is `Failed` with `backoffLimit` exhausted. ArgoCD's
`hook-delete-policy` should replace it on the next sync once this lands, but if it does not, the
failed Job must be deleted by the operator so the hook can re-run. That is a live mutation and needs
the owner's go — it is not part of this task.
