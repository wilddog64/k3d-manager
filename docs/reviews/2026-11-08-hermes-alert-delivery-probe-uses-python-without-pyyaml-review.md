# Review brief: alert_delivery probe PyYAML fix (Luna) — cross-vendor diff review

**Role:** review child of `2026-11-08-hermes-alert-delivery-probe-uses-python-without-pyyaml`.
**Intent approved:** operator, 2026-11-08
**Spec under review:** `docs/bugs/2026-11-08-hermes-alert-delivery-probe-uses-python-without-pyyaml.md` (read it in full first).

## Files

Read-only: review these, change none of them.
- `bin/k3dm-alert-delivery-status`
- `scripts/tests/bin/alert_delivery_status_python.bats`

## Task

Review the worker's diff below against the spec: its Fix, its Do-not list and its Acceptance block. Report findings
only. Do not edit, commit or keep any file. You may `git apply` the diff in your own worktree to run
`bats scripts/tests/bin/alert_delivery_status_python.bats` and to try mutations, but leave the worktree clean at exit
(`git checkout -- . && git clean -fd`).

For each finding give:
- severity: blocker / should-fix / nit;
- file:line in the diff;
- a concrete input or state that breaks it;
- the spec line (Fix, Do-not item, or M/N id) it violates.

Check in particular:
1. Each `must_not` (N1, N2) has a test that fails when its guard is removed (try it).
2. The block sits after `ROOT=` and before the first `python3` or `mapfile`, so every Python call in the script gets it.
3. The script runs under `set -u` from launchd: can `$HOME` be unset there, and what happens if it is?
4. M1 has no test named for it: does the test named N1 really prove M1?
5. The fixture stubs `yaml` through `PYTHONPATH` and asserts a fixed count of 8 Python calls. Can either make a test
   pass when the fix is wrong, or fail when the script legitimately changes?
6. Nothing in the Do-not list changed: the plist template, lib-foundation, machine-setup, `sensors.py`, and `mapfile`.

End with a one-line verdict: `land`, `land after fixes`, or `rework`. Under 400 words.

## Worker diff (uncommitted, against `k3d-manager-v1.43.15` at the worker's base `5fa30f70`)

```diff
diff --git a/bin/k3dm-alert-delivery-status b/bin/k3dm-alert-delivery-status
index d28185a4..125568e2 100755
--- a/bin/k3dm-alert-delivery-status
+++ b/bin/k3dm-alert-delivery-status
@@ -2,6 +2,10 @@
 set -euo pipefail
 
 ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
+venv_bin="${XDG_DATA_HOME:-$HOME/.local/share}/k3d-manager/venv/bin"
+if [[ -x "${venv_bin}/python3" ]]; then
+  PATH="${venv_bin}:${PATH}"
+fi
 results_file="$(mktemp)"
 trap 'rm -f "${results_file}"' EXIT
 
diff --git a/scripts/tests/bin/alert_delivery_status_python.bats b/scripts/tests/bin/alert_delivery_status_python.bats
new file mode 100644
index 00000000..b11957c4
--- /dev/null
+++ b/scripts/tests/bin/alert_delivery_status_python.bats
@@ -0,0 +1,91 @@
+#!/usr/bin/env bats
+
+setup() {
+  ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
+  REAL_PYTHON="$(command -v python3)"
+  FIXHOME="${BATS_TEST_TMPDIR}/home"
+  STUBS="${BATS_TEST_TMPDIR}/stubs"
+  XDG_FIX="${BATS_TEST_TMPDIR}/data"
+  VENV="${XDG_FIX}/k3d-manager/venv/bin"
+  mkdir -p "${FIXHOME}" "${STUBS}" "${VENV}"
+  export REAL_PYTHON FIXHOME STUBS XDG_FIX VENV
+  # The fixture YAML module parses only the synthetic generated configuration.
+  cat > "${STUBS}/yaml.py" <<'PYMODULE'
+def safe_load(raw):
+    assert b"synthetic@example.invalid" in raw
+    return {"route": {"receiver": "test"}, "receivers": [{"name": "test", "email_configs": [{}]}]}
+PYMODULE
+  export PYTHONPATH="${STUBS}"
+  export CALLS="${BATS_TEST_TMPDIR}/calls"
+  : > "${CALLS}"
+  # Context and Alertmanager name from m5-air.local read-only capture, 2026-11-08.
+  cat > "${STUBS}/kubectl" <<'STUB'
+#!/bin/bash
+case " $* " in
+  *' config get-contexts '*) printf '%s\n' "${K3DM_HUB_CONTEXT:-k3d-k3d-cluster}" ;;
+  *' get alertmanager '*) printf '%s\n' '{"items":[{"metadata":{"name":"kube-prometheus-stack-alertmanager"},"spec":{"configSecret":"alertmanager-smtp-secret"}}]}' ;;
+  *' get secret alertmanager-smtp-secret '*) exit 0 ;;
+  *' get secret alertmanager-kube-prometheus-stack-alertmanager-generated '*) cat "${FIXHOME}/generated.json" ;;
+  *) exit 1 ;;
+esac
+STUB
+  cat > "${STUBS}/python3" <<'STUB'
+#!/bin/bash
+printf 'path\n' >> "${CALLS}"
+case "${PATH}" in "${VENV}:"*) : > "${BATS_TEST_TMPDIR}/unexpected-path" ;; esac
+exec "${REAL_PYTHON}" "$@"
+STUB
+  cat > "${VENV}/python3" <<'STUB'
+#!/bin/bash
+printf 'venv\n' >> "${CALLS}"
+exec "${REAL_PYTHON}" "$@"
+STUB
+  chmod +x "${STUBS}/kubectl" "${STUBS}/python3" "${VENV}/python3"
+  "${REAL_PYTHON}" - "${FIXHOME}/generated.json" <<'PY'
+import base64, gzip, json, sys
+payload = b'route:\n  receiver: test\nreceivers:\n  - name: test\n    email_configs:\n      - to: synthetic@example.invalid\n'
+with open(sys.argv[1], 'w') as f:
+    json.dump({'data': {'alertmanager.yaml.gz': base64.b64encode(gzip.compress(payload)).decode()}}, f)
+PY
+}
+
+run_probe() {
+  [[ "${FIXHOME}" == "${BATS_TEST_TMPDIR}/home" && "${FIXHOME}" != "${HOME}" ]]
+  [[ "${STUBS}" == "${BATS_TEST_TMPDIR}/stubs" ]]
+  run env HOME="${FIXHOME}" XDG_DATA_HOME="${XDG_FIX}" PATH="${STUBS}:${PATH}" "${ROOT}/bin/k3dm-alert-delivery-status" --json
+  [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
+  [[ "${output}" == *'"available": true'* && "${output}" == *'"child_routes": 0'* ]]
+}
+
+@test "N1: executable XDG venv handles every Python call" {
+  run_probe
+  [ "$(grep -c '^venv$' "${CALLS}")" -eq 8 ]
+  [ "$(grep -c '^path$' "${CALLS}" || true)" -eq 0 ]
+}
+
+@test "M2: absent venv uses PATH Python" {
+  rm "${VENV}/python3"
+  run_probe
+  [ "$(grep -c '^path$' "${CALLS}")" -eq 8 ]
+  [ "$(grep -c '^venv$' "${CALLS}" || true)" -eq 0 ]
+}
+
+@test "N2: non-executable venv leaves PATH unchanged and uses PATH Python" {
+  chmod -x "${VENV}/python3"
+  run_probe
+  [ "$(grep -c '^path$' "${CALLS}")" -eq 8 ]
+  [ "$(grep -c '^venv$' "${CALLS}" || true)" -eq 0 ]
+  # A PATH recording stub sees whether the unusable venv was prepended.
+  [ ! -e "${BATS_TEST_TMPDIR}/unexpected-path" ]
+}
+
+@test "M3: unset XDG uses the HOME venv" {
+  mkdir -p "${FIXHOME}/.local/share/k3d-manager/venv/bin"
+  cp "${VENV}/python3" "${FIXHOME}/.local/share/k3d-manager/venv/bin/python3"
+  [[ "${FIXHOME}" == "${BATS_TEST_TMPDIR}/home" && "${FIXHOME}" != "${HOME}" ]]
+  run env -u XDG_DATA_HOME HOME="${FIXHOME}" PATH="${STUBS}:${PATH}" "${ROOT}/bin/k3dm-alert-delivery-status" --json
+  [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
+  [[ "${output}" == *'"available": true'* && "${output}" == *'"child_routes": 0'* ]]
+  [ "$(grep -c '^venv$' "${CALLS}")" -eq 8 ]
+  [ "$(grep -c '^path$' "${CALLS}" || true)" -eq 0 ]
+}
```
