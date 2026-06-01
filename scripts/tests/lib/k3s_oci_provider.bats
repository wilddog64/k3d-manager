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
    mkdir -p \"\${HOME}/.ssh\"
    touch \"\${HOME}/.ssh/oci-k3s\"
    _OCI_SSH_KEY=\"\${HOME}/.ssh/oci-k3s\"
    _OCI_STATE_DIR=\"\${HOME}/.local/share/k3d-manager/oci\"
    unset OCI_COMPARTMENT_ID OCI_REGION OCI_AVAILABILITY_DOMAIN OCI_IMAGE_ID
    printf 'ocid1.compartment.oc1..test\nus-ashburn-1\nAD-1\n' | _oci_validate_prereqs
  "
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
# _provider_k3s_oci_deploy_cluster — step sequencing (two-node, stubbed)
# ---------------------------------------------------------------------------

@test "_provider_k3s_oci_deploy_cluster calls all twelve steps in order" {
  run bash -c "
    ${_BOOTSTRAP}
    _oci_validate_prereqs()          { echo '[1] validate_prereqs'; return 0; }
    _oci_provision_infrastructure()  { echo '[2] provision_infra'; return 0; }
    _oci_get_server_ip()             { echo '1.2.3.4'; }
    _oci_get_agent_ip()              { echo '1.2.3.5'; }
    _oci_wait_ssh()                  { echo \"[wait_ssh] \$1\"; return 0; }
    _oci_install_k3s_server()        { echo '[3] install_k3s_server'; return 0; }
    _oci_install_cilium()            { echo '[4] install_cilium'; return 0; }
    _oci_install_k3s_agent()         { echo '[5] install_k3s_agent'; return 0; }
    _oci_fetch_kubeconfig()          { echo '[6] fetch_kubeconfig'; return 0; }
    _oci_register_cluster()          { echo '[7] register_cluster'; return 0; }
    _oci_wait_argocd()               { echo '[8] wait_argocd'; return 0; }
    _oci_bootstrap_argocd()          { echo '[9] bootstrap_argocd'; return 0; }
    _oci_smoke_test()                { echo '[10] smoke_test'; return 0; }
    _oci_storage_ensure_bucket()     { echo '[11] ensure_bucket'; return 0; }
    oci_backup()                     { echo '[12] backup'; return 0; }
    _provider_k3s_oci_deploy_cluster
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1] validate_prereqs"* ]]
  [[ "$output" == *"[2] provision_infra"* ]]
  [[ "$output" == *"[3] install_k3s_server"* ]]
  [[ "$output" == *"[4] install_cilium"* ]]
  [[ "$output" == *"[5] install_k3s_agent"* ]]
  [[ "$output" == *"[6] fetch_kubeconfig"* ]]
  [[ "$output" == *"[7] register_cluster"* ]]
  [[ "$output" == *"[8] wait_argocd"* ]]
  [[ "$output" == *"[9] bootstrap_argocd"* ]]
  [[ "$output" == *"[10] smoke_test"* ]]
  [[ "$output" == *"[11] ensure_bucket"* ]]
  [[ "$output" == *"[12] backup"* ]]
}

@test "_provider_k3s_oci_deploy_cluster aborts when validate_prereqs fails" {
  run bash -c "
    ${_BOOTSTRAP}
    _oci_validate_prereqs()          { return 1; }
    _oci_provision_infrastructure()  { echo '[stub] should not run'; return 0; }
    _oci_get_server_ip()             { echo '1.2.3.4'; }
    _provider_k3s_oci_deploy_cluster
  "
  [ "$status" -ne 0 ]
  [[ "$output" != *"[stub] should not run"* ]]
}

@test "_provider_k3s_oci_deploy_cluster aborts when install_cilium fails" {
  run bash -c "
    ${_BOOTSTRAP}
    _oci_validate_prereqs()          { return 0; }
    _oci_provision_infrastructure()  { return 0; }
    _oci_get_server_ip()             { echo '1.2.3.4'; }
    _oci_get_agent_ip()              { echo '1.2.3.5'; }
    _oci_wait_ssh()                  { return 0; }
    _oci_install_k3s_server()        { return 0; }
    _oci_install_cilium()            { return 1; }
    _oci_install_k3s_agent()         { echo '[stub] should not run'; return 0; }
    _provider_k3s_oci_deploy_cluster
  "
  [ "$status" -ne 0 ]
  [[ "$output" != *"[stub] should not run"* ]]
}

# ---------------------------------------------------------------------------
# _oci_provision_instance — idempotent skip + first launch
# ---------------------------------------------------------------------------

@test "_oci_provision_instance skips launch when instance already running" {
  run bash -c "
    ${_BOOTSTRAP}
    OCI_COMPARTMENT_ID='ocid1.compartment.test'
    OCI_AVAILABILITY_DOMAIN='AD-1'
    oci() {
      if [[ \"\$*\" == *'lifecycle-state RUNNING'* ]]; then
        echo 'ocid1.instance.existing'
        return 0
      fi
      echo 'null'
      return 0
    }
    result=\$(_oci_provision_instance 'k3s-oci-server' 'ocid1.subnet.test')
    [[ \"\${result}\" == 'ocid1.instance.existing' ]] || exit 1
    echo 'idempotent-ok'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"idempotent-ok"* ]]
  [[ "$output" == *"already running"* ]]
}

@test "_oci_provision_instance launches instance when not running" {
  run bash -c "
    ${_BOOTSTRAP}
    OCI_COMPARTMENT_ID='ocid1.compartment.test'
    OCI_AVAILABILITY_DOMAIN='AD-1'
    OCI_IMAGE_ID='ocid1.image.test'
    _OCI_INSTANCE_SHAPE='VM.Standard.A1.Flex'
    _OCI_OCPUS=2
    _OCI_MEMORY_GB=12
    _OCI_SSH_KEY=\"\$(mktemp)\"
    touch \"\${_OCI_SSH_KEY}.pub\"
    _launch_count=0
    oci() {
      # list call — not running
      if [[ \"\$*\" == *'lifecycle-state RUNNING'* ]]; then echo 'null'; return 0; fi
      # launch call — return new ID
      if [[ \"\$*\" == *'instance launch'* ]]; then
        echo 'ocid1.instance.new'
        return 0
      fi
      # wait for RUNNING state
      if [[ \"\$*\" == *'instance get'* ]]; then return 0; fi
      return 0
    }
    result=\$(_oci_provision_instance 'k3s-oci-server' 'ocid1.subnet.test')
    [[ \"\${result}\" == 'ocid1.instance.new' ]] || exit 1
    echo 'launch-ok'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"launch-ok"* ]]
}

# ---------------------------------------------------------------------------
# _oci_provision_infrastructure — writes both state files
# ---------------------------------------------------------------------------

@test "_oci_provision_infrastructure writes server-instance-id and agent-instance-id" {
  run bash -c "
    ${_BOOTSTRAP}
    _state=\"\$(mktemp -d)\"
    _OCI_STATE_DIR=\"\${_state}\"
    OCI_COMPARTMENT_ID='ocid1.compartment.test'
    OCI_AVAILABILITY_DOMAIN='AD-1'
    OCI_IMAGE_ID='ocid1.image.test'
    OCI_REGION='us-ashburn-1'
    oci() {
      # All oci network/vcn/subnet/seclist calls
      if [[ \"\$*\" == *'vcn list'* || \"\$*\" == *'internet-gateway list'* || \"\$*\" == *'security-list list'* || \"\$*\" == *'subnet list'* ]]; then
        echo 'ocid1.existing.test'; return 0
      fi
      if [[ \"\$*\" == *'route-table list'* ]]; then echo 'ocid1.rt.test'; return 0; fi
      if [[ \"\$*\" == *'route-table update'* ]]; then return 0; fi
      echo 'null'; return 0
    }
    _oci_provision_instance() {
      local _name=\"\$1\"
      if [[ \"\${_name}\" == *'server'* ]]; then echo 'ocid1.instance.server'; return 0; fi
      if [[ \"\${_name}\" == *'agent'* ]];  then echo 'ocid1.instance.agent';  return 0; fi
    }
    _oci_provision_infrastructure
    [[ \"\$(cat \"\${_state}/server-instance-id\")\" == 'ocid1.instance.server' ]] || exit 1
    [[ \"\$(cat \"\${_state}/agent-instance-id\")\"  == 'ocid1.instance.agent'  ]] || exit 1
    echo 'both-state-files-written'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"both-state-files-written"* ]]
}

# ---------------------------------------------------------------------------
# _oci_install_k3s_server — idempotent skip + flannel flags
# ---------------------------------------------------------------------------

@test "_oci_install_k3s_server skips when k3s already installed" {
  run bash -c "
    ${_BOOTSTRAP}
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    ssh() {
      if [[ \"\$*\" == *'command -v k3s'* ]]; then return 0; fi
      return 1
    }
    _oci_install_k3s_server '1.2.3.4'
    echo 'skip-ok'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip-ok"* ]]
  [[ "$output" == *"already installed"* ]]
}

@test "_oci_install_k3s_server sends --flannel-backend=none and --disable-network-policy" {
  run bash -c "
    ${_BOOTSTRAP}
    _CMD_LOG=\"\$(mktemp)\"
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    OCI_REGION='us-ashburn-1'
    _OCI_K3S_VERSION='v1.32.0+k3s1'
    ssh() {
      local _args=\"\$*\"
      echo \"\${_args}\" >> \"\${_CMD_LOG}\"
      if [[ \"\${_args}\" == *'command -v k3s'* ]]; then return 1; fi
      if [[ \"\${_args}\" == *'kubectl get nodes'* ]]; then return 0; fi
      return 0
    }
    _oci_install_k3s_server '1.2.3.4'
    grep -q -- '--flannel-backend=none' \"\${_CMD_LOG}\" || exit 1
    grep -q -- '--disable-network-policy' \"\${_CMD_LOG}\" || exit 1
    echo 'flannel-flags-ok'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"flannel-flags-ok"* ]]
}

# ---------------------------------------------------------------------------
# _oci_install_cilium — idempotent skip + cni.exclusive=false
# ---------------------------------------------------------------------------

@test "_oci_install_cilium skips when Cilium already installed" {
  run bash -c "
    ${_BOOTSTRAP}
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    _OCI_STATE_DIR=\"\$(mktemp -d)\"
    echo 'ocid1.instance.server' > \"\${_OCI_STATE_DIR}/server-instance-id\"
    ssh() {
      if [[ \"\$*\" == *'helm status cilium'* ]]; then return 0; fi
      return 1
    }
    OCI_COMPARTMENT_ID='test'
    oci() { echo '10.0.0.5'; return 0; }
    _oci_install_cilium '1.2.3.4'
    echo 'skip-ok'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip-ok"* ]]
  [[ "$output" == *"already installed"* ]]
}

@test "_oci_install_cilium includes cni.exclusive=false and kubeProxyReplacement=true" {
  run bash -c "
    ${_BOOTSTRAP}
    _CMD_LOG=\"\$(mktemp)\"
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    _OCI_CILIUM_VERSION='1.16.5'
    _oci_get_server_private_ip() { echo '10.0.0.5'; }
    ssh() {
      local _args=\"\$*\"
      echo \"\${_args}\" >> \"\${_CMD_LOG}\"
      if [[ \"\${_args}\" == *'helm status cilium'* ]]; then return 1; fi
      if [[ \"\${_args}\" == *'rollout status daemonset/cilium'* ]]; then return 0; fi
      return 0
    }
    _oci_install_cilium '1.2.3.4'
    grep -q 'cni.exclusive=false' \"\${_CMD_LOG}\" || exit 1
    grep -q 'kubeProxyReplacement=true' \"\${_CMD_LOG}\" || exit 1
    echo 'cilium-flags-ok'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"cilium-flags-ok"* ]]
}

# ---------------------------------------------------------------------------
# _oci_install_k3s_agent — idempotent skip + private IP + 2-node wait
# ---------------------------------------------------------------------------

@test "_oci_install_k3s_agent skips when k3s-agent already active" {
  run bash -c "
    ${_BOOTSTRAP}
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    ssh() {
      if [[ \"\$*\" == *'systemctl is-active k3s-agent'* ]]; then return 0; fi
      return 1
    }
    _oci_install_k3s_agent '1.2.3.99' '1.2.3.4'
    echo 'skip-ok'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip-ok"* ]]
  [[ "$output" == *"already running"* ]]
}

@test "_oci_install_k3s_agent joins via server private IP, not public IP" {
  run bash -c "
    ${_BOOTSTRAP}
    _CMD_LOG=\"\$(mktemp)\"
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    OCI_REGION='us-ashburn-1'
    _OCI_K3S_VERSION='v1.32.0+k3s1'
    _oci_get_server_private_ip() { echo '10.0.0.5'; }
    ssh() {
      local _args=\"\$*\"
      echo \"\${_args}\" >> \"\${_CMD_LOG}\"
      if [[ \"\${_args}\" == *'systemctl is-active k3s-agent'* ]]; then return 1; fi
      if [[ \"\${_args}\" == *'node-token'* ]]; then echo 'K1030abc::server:secret'; return 0; fi
      if [[ \"\${_args}\" == *'grep -c'* ]]; then echo '2'; return 0; fi
      return 0
    }
    _oci_install_k3s_agent '1.2.3.99' '1.2.3.4'
    grep -q \"K3S_URL='https://10.0.0.5:6443'\" \"\${_CMD_LOG}\" || exit 1
    grep -q \"K3S_URL='https://1.2.3.4:6443'\" \"\${_CMD_LOG}\" && exit 1 || true
    echo 'private-ip-ok'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"private-ip-ok"* ]]
}

@test "_oci_install_k3s_agent wait loop counts Ready nodes (not grep -v master)" {
  run bash -c "
    ${_BOOTSTRAP}
    _CMD_LOG=\"\$(mktemp)\"
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    OCI_REGION='us-ashburn-1'
    _OCI_K3S_VERSION='v1.32.0+k3s1'
    _oci_get_server_private_ip() { echo '10.0.0.5'; }
    ssh() {
      local _args=\"\$*\"
      echo \"\${_args}\" >> \"\${_CMD_LOG}\"
      if [[ \"\${_args}\" == *'systemctl is-active k3s-agent'* ]]; then return 1; fi
      if [[ \"\${_args}\" == *'node-token'* ]]; then echo 'K1030abc::server:secret'; return 0; fi
      if [[ \"\${_args}\" == *'grep -c'* ]]; then echo '2'; return 0; fi
      return 0
    }
    _oci_install_k3s_agent '1.2.3.99' '1.2.3.4'
    grep -q 'grep -v master' \"\${_CMD_LOG}\" && exit 1 || true
    grep -q 'grep -c' \"\${_CMD_LOG}\" || exit 1
    echo 'wait-loop-ok'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"wait-loop-ok"* ]]
}

# ---------------------------------------------------------------------------
# _oci_smoke_test — node count + Cilium DaemonSet
# ---------------------------------------------------------------------------

@test "_oci_smoke_test fails when fewer than 2 nodes are Ready" {
  run bash -c "
    ${_BOOTSTRAP}
    _OCI_KUBECONFIG='/dev/null'
    kubectl() {
      local _cmd=\"\$*\"
      if [[ \"\${_cmd}\" == *'get namespace'* ]]; then echo 'Active'; return 0; fi
      if [[ \"\${_cmd}\" == *'get pods'* ]]; then echo 'argocd-server Running'; return 0; fi
      if [[ \"\${_cmd}\" == *'get nodes'* ]]; then
        printf 'k3s-oci-server   Ready\n'
        return 0
      fi
      if [[ \"\${_cmd}\" == *'rollout status'* ]]; then return 0; fi
      return 0
    }
    _oci_smoke_test
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected 2 nodes Ready"* ]]
}

@test "_oci_smoke_test fails when Cilium DaemonSet is not ready" {
  run bash -c "
    ${_BOOTSTRAP}
    _OCI_KUBECONFIG='/dev/null'
    kubectl() {
      local _cmd=\"\$*\"
      if [[ \"\${_cmd}\" == *'get namespace'* ]]; then echo 'Active'; return 0; fi
      if [[ \"\${_cmd}\" == *'get pods'* ]]; then echo 'argocd-server Running'; return 0; fi
      if [[ \"\${_cmd}\" == *'get nodes'* ]]; then
        printf 'k3s-oci-server   Ready\nk3s-oci-agent   Ready\n'
        return 0
      fi
      if [[ \"\${_cmd}\" == *'rollout status'*'cilium'* ]]; then return 1; fi
      return 0
    }
    _oci_smoke_test
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"cilium"* ]]
}

# ---------------------------------------------------------------------------
# _oci_destroy_infrastructure — terminates both instances
# ---------------------------------------------------------------------------

@test "_oci_destroy_infrastructure terminates both server and agent instances" {
  run bash -c "
    ${_BOOTSTRAP}
    _state=\"\$(mktemp -d)\"
    _OCI_STATE_DIR=\"\${_state}\"
    printf '%s' 'ocid1.instance.server' > \"\${_state}/server-instance-id\"
    printf '%s' 'ocid1.instance.agent'  > \"\${_state}/agent-instance-id\"
    _OCI_LOG=\"\$(mktemp)\"
    OCI_COMPARTMENT_ID='ocid1.compartment.test'
    oci() { echo \"\$*\" >> \"\${_OCI_LOG}\"; return 0; }
    _oci_destroy_infrastructure
    grep -q 'ocid1.instance.server' \"\${_OCI_LOG}\" || exit 1
    grep -q 'ocid1.instance.agent'  \"\${_OCI_LOG}\" || exit 1
    echo 'both-terminated'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"both-terminated"* ]]
}

# ---------------------------------------------------------------------------
# oci_backup / oci_restore — error paths
# ---------------------------------------------------------------------------

@test "oci_backup fails when etcd-snapshot SSH command fails" {
  run bash -c "
    ${_BOOTSTRAP}
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    _OCI_KUBECONFIG=\"\$(mktemp)\"
    OCI_REGION='us-ashburn-1'
    _oci_storage_ensure_bucket() { return 0; }
    _oci_get_server_ip() { echo '1.2.3.4'; }
    _oci_storage_namespace() { echo 'testns'; }
    ssh() {
      if [[ \"\$*\" == *'etcd-snapshot save'* ]]; then return 1; fi
      return 0
    }
    oci_backup
  "
  [ "$status" -ne 0 ]
}

@test "oci_backup fails when snapshot download produces empty file" {
  run bash -c "
    ${_BOOTSTRAP}
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    _OCI_KUBECONFIG=\"\$(mktemp)\"
    OCI_REGION='us-ashburn-1'
    _oci_storage_ensure_bucket() { return 0; }
    _oci_get_server_ip() { echo '1.2.3.4'; }
    _oci_storage_namespace() { echo 'testns'; }
    ssh() {
      if [[ \"\$*\" == *'etcd-snapshot save'* ]]; then return 0; fi
      # cat produces no output — simulates missing remote file
      return 0
    }
    oci_backup
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "oci_restore fails when snapshot name has invalid format" {
  run bash -c "
    ${_BOOTSTRAP}
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    _OCI_KUBECONFIG=\"\$(mktemp)\"
    OCI_REGION='us-ashburn-1'
    _oci_storage_ensure_bucket() { return 0; }
    _oci_get_server_ip() { echo '1.2.3.4'; }
    _oci_storage_namespace() { echo 'testns'; }
    _oci_storage_list() { echo 'k3s-oci/etcd/k3s-etcd-20260101-120000.db'; }
    oci_restore --snapshot '../etc/passwd'
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid snapshot name"* ]]
}

@test "oci_restore fails when scp upload to server fails" {
  run bash -c "
    ${_BOOTSTRAP}
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    _OCI_KUBECONFIG=\"\$(mktemp)\"
    OCI_REGION='us-ashburn-1'
    _tmp_snap=\"\$(mktemp)\"
    printf 'data' > \"\${_tmp_snap}\"
    _oci_storage_ensure_bucket() { return 0; }
    _oci_get_server_ip() { echo '1.2.3.4'; }
    _oci_storage_namespace() { echo 'testns'; }
    _oci_storage_list() { echo 'k3s-oci/etcd/k3s-etcd-20260101-120000.db'; }
    _oci_storage_download() { cp \"\${_tmp_snap}\" \"\${2}\"; }
    _oci_wait_ssh() { return 0; }
    _oci_storage_download() { printf 'data' > \"\${2}\"; }
    scp() { return 1; }
    oci_restore
  "
  [ "$status" -ne 0 ]
}

@test "oci_restore fails when remote restore SSH command fails" {
  run bash -c "
    ${_BOOTSTRAP}
    _OCI_SSH_KEY=\"\$(mktemp)\"
    _OCI_SSH_USER='ubuntu'
    _OCI_KUBECONFIG=\"\$(mktemp)\"
    OCI_REGION='us-ashburn-1'
    _oci_storage_ensure_bucket() { return 0; }
    _oci_get_server_ip() { echo '1.2.3.4'; }
    _oci_storage_namespace() { echo 'testns'; }
    _oci_storage_list() { echo 'k3s-oci/etcd/k3s-etcd-20260101-120000.db'; }
    _oci_storage_download() { printf 'data' > \"\${2}\"; }
    _oci_wait_ssh() { return 0; }
    scp() { return 0; }
    ssh() { return 1; }
    oci_restore
  "
  [ "$status" -ne 0 ]
}
