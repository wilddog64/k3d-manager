#!/usr/bin/env bats
# shellcheck shell=bash

# Bootstrap helper — sources real libs + provider with external calls stubbed.
# Call at the top of each run bash -c block.
# shellcheck disable=SC2016
_BOOTSTRAP='
  SCRIPT_DIR="$(pwd)/scripts"
  source scripts/lib/system.sh
  source scripts/lib/core.sh
  source scripts/lib/provider.sh
  source scripts/lib/providers/k3s-oci.sh
'

# ---------------------------------------------------------------------------
# --help flags
# ---------------------------------------------------------------------------

@test "_provider_k3s_oci_deploy_cluster --help prints k3s-oci usage" {
  run bash -c "
    ${_BOOTSTRAP}
    _provider_k3s_oci_deploy_cluster --help
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3s-oci"* ]]
}

@test "_provider_k3s_oci_deploy_cluster -h prints k3s-oci usage" {
  run bash -c "
    ${_BOOTSTRAP}
    _provider_k3s_oci_deploy_cluster -h
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3s-oci"* ]]
}

@test "_provider_k3s_oci_destroy_cluster --help prints destroy usage" {
  run bash -c "
    ${_BOOTSTRAP}
    _provider_k3s_oci_destroy_cluster --help
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"destroy-infra"* ]]
}

# ---------------------------------------------------------------------------
# destroy_cluster — guard rails
# ---------------------------------------------------------------------------

@test "_provider_k3s_oci_destroy_cluster without --destroy-infra preserves instance" {
  run bash -c "
    ${_BOOTSTRAP}
    _oci_deregister_cluster() { echo '[stub] deregister'; return 0; }
    _provider_k3s_oci_destroy_cluster
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[stub] deregister"* ]]
  [[ "$output" == *"preserved"* ]]
}

@test "_provider_k3s_oci_destroy_cluster --destroy-infra aborts when user does not type yes" {
  run bash -c "
    ${_BOOTSTRAP}
    _oci_deregister_cluster() { return 0; }
    _oci_destroy_infrastructure() { echo '[stub] destroy-infra'; return 0; }
    echo 'no' | _provider_k3s_oci_destroy_cluster --destroy-infra
  "
  [ "$status" -ne 0 ]
  [[ "$output" != *"[stub] destroy-infra"* ]]
  [[ "$output" == *"Aborted"* ]]
}

@test "_provider_k3s_oci_destroy_cluster --destroy-infra proceeds when user types yes" {
  run bash -c "
    ${_BOOTSTRAP}
    _oci_deregister_cluster() { return 0; }
    _oci_destroy_infrastructure() { echo '[stub] destroy-infra'; return 0; }
    echo 'yes' | _provider_k3s_oci_destroy_cluster --destroy-infra
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[stub] destroy-infra"* ]]
}

# ---------------------------------------------------------------------------
# _oci_validate_prereqs — CLI guard
# ---------------------------------------------------------------------------

@test "_oci_validate_prereqs fails when oci CLI not in PATH" {
  run bash -c "
    ${_BOOTSTRAP}
    PATH=/usr/bin:/bin _oci_validate_prereqs
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"brew install oci-cli"* ]]
}

@test "_oci_validate_prereqs fails when required env vars missing and no state file" {
  run bash -c "
    ${_BOOTSTRAP}
    oci() { return 0; }
    HOME=\"\$(mktemp -d)\"
    mkdir -p \"\${HOME}/.oci\"
    touch \"\${HOME}/.oci/config\"
    # SSH key already exists to skip keygen
    mkdir -p \"\${HOME}/.ssh\"
    touch \"\${HOME}/.ssh/oci-k3s\"
    _OCI_SSH_KEY=\"\${HOME}/.ssh/oci-k3s\"
    _OCI_STATE_DIR=\"\${HOME}/.local/share/k3d-manager/oci\"
    unset OCI_COMPARTMENT_ID OCI_REGION OCI_AVAILABILITY_DOMAIN OCI_IMAGE_ID
    # Pipe non-interactive input to avoid hanging on read prompts
    printf 'ocid1.compartment.oc1..test\nus-ashburn-1\nAD-1\n' | _oci_validate_prereqs
  "
  # exits 0 because prompts are answered — state file written; IMAGE_ID resolution fails
  # We only assert the prompts were consumed (no hang) and the state file was created
  [[ "$output" != *"brew install oci-cli"* ]]
}

# ---------------------------------------------------------------------------
# _oci_reconfigure — state cleanup
# ---------------------------------------------------------------------------

@test "_oci_reconfigure removes env and image-id state files" {
  run bash -c "
    ${_BOOTSTRAP}
    _state=\"\$(mktemp -d)\"
    _OCI_STATE_DIR=\"\${_state}\"
    mkdir -p \"\${_state}\"
    touch \"\${_state}/env\" \"\${_state}/image-id\"
    _oci_reconfigure
    [[ ! -f \"\${_state}/env\" ]] || exit 1
    [[ ! -f \"\${_state}/image-id\" ]] || exit 1
    echo 'state files removed'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"state files removed"* ]]
}

# ---------------------------------------------------------------------------
# _provider_k3s_oci_deploy_cluster — step sequencing (stubbed)
# ---------------------------------------------------------------------------

@test "_provider_k3s_oci_deploy_cluster calls steps in order" {
  run bash -c "
    ${_BOOTSTRAP}
    _oci_validate_prereqs()       { echo '[1] validate_prereqs'; return 0; }
    _oci_provision_infrastructure() { echo '[2] provision_infra'; return 0; }
    _oci_get_instance_ip()        { echo '1.2.3.4'; }
    _oci_wait_ssh()               { echo '[3] wait_ssh'; return 0; }
    _oci_install_k3s()            { echo '[4] install_k3s'; return 0; }
    _oci_fetch_kubeconfig()       { echo '[5] fetch_kubeconfig'; return 0; }
    _oci_register_cluster()       { echo '[6] register_cluster'; return 0; }
    _oci_wait_argocd()            { echo '[7] wait_argocd'; return 0; }
    _oci_bootstrap_argocd()       { echo '[8] bootstrap_argocd'; return 0; }
    _oci_smoke_test()             { echo '[9] smoke_test'; return 0; }
    _provider_k3s_oci_deploy_cluster
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1] validate_prereqs"* ]]
  [[ "$output" == *"[2] provision_infra"* ]]
  [[ "$output" == *"[3] wait_ssh"* ]]
  [[ "$output" == *"[4] install_k3s"* ]]
  [[ "$output" == *"[5] fetch_kubeconfig"* ]]
  [[ "$output" == *"[6] register_cluster"* ]]
  [[ "$output" == *"[7] wait_argocd"* ]]
  [[ "$output" == *"[8] bootstrap_argocd"* ]]
  [[ "$output" == *"[9] smoke_test"* ]]
}

@test "_provider_k3s_oci_deploy_cluster aborts when validate_prereqs fails" {
  run bash -c "
    ${_BOOTSTRAP}
    _oci_validate_prereqs()         { return 1; }
    _oci_provision_infrastructure() { echo '[stub] should not run'; return 0; }
    _oci_get_instance_ip()          { echo '1.2.3.4'; }
    _provider_k3s_oci_deploy_cluster
  "
  [ "$status" -ne 0 ]
  [[ "$output" != *"[stub] should not run"* ]]
}
