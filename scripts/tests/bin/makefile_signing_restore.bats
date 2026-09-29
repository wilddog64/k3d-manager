#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  STUB="${BATS_TEST_TMPDIR}/stub"
  LOG="${BATS_TEST_TMPDIR}/calls.log"
  mkdir -p "${WORK}/scripts" "${STUB}"
  cp "${MAKEFILE}" "${WORK}/Makefile"
  : > "${LOG}"
  cat > "${WORK}/scripts/k3d-manager" <<EOF
#!/usr/bin/env bash
printf 'k3d-manager %s KUBECONFIG_CONTEXT=%s\n' "\$*" "\$(sed -n 's/^current-context: //p' "\${KUBECONFIG}")" >> "${LOG}"
exit "\${STUB_RESTORE_RC:-0}"
EOF
  cat > "${STUB}/kubectl" <<EOF
#!/usr/bin/env bash
printf 'kubectl %s\n' "\$*" >> "${LOG}"
if [[ "\$*" == "config view --minify --flatten --context "* ]]; then
  ctx="\${*: -1}"
  [[ "\${ctx}" == "missing-ctx" ]] && exit 1
  printf 'apiVersion: v1\ncurrent-context: %s\n' "\${ctx}"
  exit 0
fi
if [[ "\$*" == *" get externalsecret cosign-public-key"* ]]; then
  exit "\${STUB_ES_RC:-0}"
fi
exit 0
EOF
  chmod +x "${WORK}/scripts/k3d-manager" "${STUB}/kubectl"
}

_run_target() {
  run env PATH="${STUB}:${PATH}" make --no-print-directory -C "${WORK}" signing-restore "$@"
}

@test "signing-restore is declared phony" {
  run awk '/^\.PHONY:/,/^$/' "${MAKEFILE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *" signing-restore "* ]]
}

@test "defaults to the hub and pins it through a temporary kubeconfig" {
  _run_target
  [ "${status}" -eq 0 ]
  grep -q 'k3d-manager signing_restore KUBECONFIG_CONTEXT=k3d-k3d-cluster' "${LOG}"
  grep -q 'kubectl --context k3d-k3d-cluster -n platform-ops annotate externalsecret cosign-public-key force-sync=' "${LOG}"
  grep -q 'kubectl --context k3d-k3d-cluster -n platform-ops wait externalsecret cosign-public-key --for=condition=Ready' "${LOG}"
}

@test "CONTEXT and SIGNING_ES_NAMESPACE retarget the restore and the resync" {
  SIGNING_ES_NAMESPACE=kyverno _run_target CONTEXT=ubuntu-hostinger
  [ "${status}" -eq 0 ]
  grep -q 'KUBECONFIG_CONTEXT=ubuntu-hostinger' "${LOG}"
  grep -q 'kubectl --context ubuntu-hostinger -n kyverno annotate externalsecret cosign-public-key' "${LOG}"
}

@test "the global current-context is never changed" {
  _run_target
  [ "${status}" -eq 0 ]
  run grep -E 'kubectl config (use-context|set-context)' "${LOG}"
  [ "${status}" -ne 0 ]
}

@test "an unknown context fails before anything runs" {
  _run_target CONTEXT=missing-ctx
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"kube context 'missing-ctx' not found"* ]]
  run grep -q 'k3d-manager' "${LOG}"
  [ "${status}" -ne 0 ]
}

@test "a failed restore stops before the resync" {
  STUB_RESTORE_RC=1 _run_target
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"signing_restore failed on k3d-k3d-cluster"* ]]
  run grep -q 'annotate externalsecret' "${LOG}"
  [ "${status}" -ne 0 ]
}

@test "a cluster without the ExternalSecret skips the resync cleanly" {
  STUB_ES_RC=1 _run_target
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"nothing to resync"* ]]
  run grep -q 'annotate externalsecret' "${LOG}"
  [ "${status}" -ne 0 ]
}

@test "the target never generates a new signing key" {
  run awk '/^signing-restore:/,/^$/' "${MAKEFILE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"signing_init"* ]]
  [[ "${output}" != *"signing_rotate_key"* ]]
}
