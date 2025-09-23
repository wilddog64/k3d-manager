
function _cluster_provider() {
   local provider="${K3D_MANAGER_PROVIDER:-${K3DMGR_PROVIDER:-${CLUSTER_PROVIDER:-k3d}}}"
   provider="$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')"

   case "$provider" in
      k3d|k3s)
         printf '%s' "$provider"
         ;;
      *)
         _err "Unsupported cluster provider: $provider"
         ;;
   esac
}

function _ensure_path_exists() {
   local dir="$1"
   [[ -z "$dir" ]] && return 0

   if [[ -d "$dir" ]]; then
      return 0
   fi

   if mkdir -p "$dir" 2>/dev/null; then
      return 0
   fi

   _run_command --prefer-sudo -- mkdir -p "$dir"
}

function _ensure_port_available() {
   local port="$1"
   [[ -z "$port" ]] && return 0

   if ! _command_exist python3; then
      _warn "python3 is not available; skipping port availability check for $port"
      return 0
   fi

   local script
   script=$(cat <<'PY'
import socket
import sys

port = int(sys.argv[1])
s = socket.socket()
try:
    s.bind(("0.0.0.0", port))
except OSError as exc:
    print(f"Port {port} unavailable: {exc}", file=sys.stderr)
    sys.exit(1)
finally:
    try:
        s.close()
    except Exception:
        pass
PY
)

   if ! _run_command --prefer-sudo -- python3 - "$port" <<<"$script"; then
      _err "Port $port is already in use"
   fi
}

function _k3s_asset_dir() {
   printf '%s/etc/k3s' "$(dirname "$SOURCE")"
}

function _k3s_set_defaults() {
   export K3S_INSTALL_DIR="${K3S_INSTALL_DIR:-/usr/local/bin}"
   export K3S_DATA_DIR="${K3S_DATA_DIR:-/var/lib/rancher/k3s}"
   export K3S_CONFIG_DIR="${K3S_CONFIG_DIR:-/etc/rancher/k3s}"
   export K3S_CONFIG_FILE="${K3S_CONFIG_FILE:-${K3S_CONFIG_DIR}/config.yaml}"
   export K3S_KUBECONFIG_PATH="${K3S_KUBECONFIG_PATH:-${K3S_CONFIG_DIR}/k3s.yaml}"
   export K3S_SERVICE_NAME="${K3S_SERVICE_NAME:-k3s}"
   export K3S_SERVICE_FILE="${K3S_SERVICE_FILE:-/etc/systemd/system/${K3S_SERVICE_NAME}.service}"
   export K3S_MANIFEST_DIR="${K3S_MANIFEST_DIR:-${K3S_DATA_DIR}/server/manifests}"
   export K3S_LOCAL_STORAGE="${K3S_LOCAL_STORAGE:-${JENKINS_HOME_PATH:-${SCRIPT_DIR}/storage/jenkins_home}}"
}

function _k3s_cluster_exists() {
   _k3s_set_defaults
   [[ -f "$K3S_SERVICE_FILE" ]] && return 0 || return 1
}
function _install_docker() {
   if _is_mac; then
      _install_mac_docker
   elif _is_debian_family; then
      _install_debian_docker
   elif _is_redhat_family ; then
      _install_redhat_docker
   else
      echo "Unsupported Linux distribution. Please install Docker manually."
      exit 1
   fi
}

function _install_istioctl() {
   install_dir="${1:-/usr/local/bin}"

   if _command_exist istioctl ; then
      echo "istioctl already exists, skip installation"
      return 0
   fi

   echo "install dir: ${install_dir}"
   if [[ ! -e "$install_dir" && ! -d "$install_dir" ]]; then
      if mkdir -p "${install_dir}" 2>/dev/null; then
         :
      else
         _run_command --prefer-sudo -- mkdir -p "${install_dir}"
      fi
   fi

   if  ! _command_exist istioctl ; then
      echo installing istioctl
      tmp_script=$(mktemp)
      trap 'rm -rf /tmp/istio-*' EXIT TERM
      pushd /tmp
      curl -f -s https://raw.githubusercontent.com/istio/istio/master/release/downloadIstioCandidate.sh -o "$tmp_script"
      istio_bin=$(bash "$tmp_script" | perl -nle 'print $1 if /add the (.*) directory/')
      if [[ -z "$istio_bin" ]]; then
         echo "Failed to download istioctl"
         exit 1
      fi
      if [[ -w "${install_dir}" ]]; then
         _run_command -- cp -v "$istio_bin/istioctl" "${install_dir}/"
      else
         _run_command --prefer-sudo -- cp -v "$istio_bin/istioctl" "${install_dir}/"
      fi
      popd
   fi

}

function _cleanup_on_success() {
   local file_to_cleanup=$1
   echo "Cleaning up temporary files... : $file_to_cleanup :"
   rm -rf "$file_to_cleanup"
}

function _install_smb_csi_driver() {
   if _is_mac ; then
      echo "warning: SMB CSI driver is not supported on macOS"
      exit 0
   fi
   _install_helm
   _helm repo add smb-csi-driver https://kubernetes-sigs.github.io/smb-csi-driver
   _helm repo update
   _helm upgrade --install smb-csi-driver smb-csi-driver/smb-csi-driver \
      --namespace kube-system
}

function _create_nfs_share() {

   if grep -q "k3d-nfs" /etc/exports ; then
      echo "NFS share already exists, skip"
      return 0
   fi

   if _is_mac ; then
      echo "Creating NFS share on macOS"
      mkdir -p $HOME/k3d-nfs
      if ! grep "$HOME/k3d-nfs" /etc/exports 2>&1 > /dev/null; then
         ip=$(ipconfig getifaddr en0)
         mask=$(ipconfig getoption en0 subnet_mask)
         prefix=$(python3 -c "import ipaddress; print(ipaddress.IPv4Network('0.0.0.0/$mask').prefixlen)")
         network=$(python3 -c "import ipaddress; print(ipaddress.IPv4Network('$ip/$prefix', strict=False).network_address)")
         export_line="/Users/$USER/k3d-nfs -alldirs -rw -insecure -mapall=$(id -u):$(id -g) -network $network -mask $mask"
         echo "$export_line" | \
            sudo tee -a /etc/exports
         sudo nfsd enable
         sudo nfsd restart  # Full restart instead of update
         showmount -e localhost
      fi
   fi
}

function _install_k3d() {
   _cluster_provider_call install "$@"
}

function destroy_cluster() {
   _cluster_provider_call destroy_cluster "$@"
}

function destroy_k3d_cluster() {
   destroy_cluster "$@"
}

function _create_cluster() {
   _cluster_provider_call create_cluster "$@"
}

function create_cluster() {
   _create_cluster "$@"
}

function _create_k3d_cluster() {
   _create_cluster "$@"
}

function create_k3d_cluster() {
   create_cluster "$@"
}

function deploy_cluster() {
   _cluster_provider_call deploy_cluster "$@"
}

function deploy_k3d_cluster() {
   deploy_cluster "$@"
}
