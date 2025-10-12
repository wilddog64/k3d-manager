
function _k3s_set_defaults() {
   if [[ -n "${K3S_DEFAULTS_INITIALIZED:-}" ]]; then
      return 0
   fi

   _ensure_cluster_provider

   if [[ "${CLUSTER_PROVIDER:-}" != "k3s" ]]; then
      # Another provider is active; nothing to seed.
      K3S_DEFAULTS_INITIALIZED=1
      return 0
   fi

   local vars_file="${SCRIPT_DIR}/etc/k3s/vars.sh"

   if [[ ! -r "$vars_file" ]]; then
      _err "k3s vars file not found: $vars_file"
   fi

   # shellcheck disable=SC1090
   source "$vars_file"

   K3S_DEFAULTS_INITIALIZED=1
}

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

   if _run_command --quiet --soft --prefer-sudo -- mkdir -p "$dir"; then
      return 0
   fi

   if command -v sudo >/dev/null 2>&1; then
      local sudo_checked=0

      if declare -f _sudo_available >/dev/null 2>&1; then
         sudo_checked=1
         if _sudo_available; then
            if sudo mkdir -p "$dir"; then
               return 0
            fi
            _err "Failed to create directory '$dir' using sudo"
         fi
      fi

      if sudo mkdir -p "$dir"; then
         return 0
      fi
   fi

   _err "Cannot create directory '$dir'. Create it manually, configure sudo, or set K3S_CONFIG_DIR to a writable path."
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

function _k3s_template_path() {
   local name="${1:-}"
   printf '%s/%s' "$(_k3s_asset_dir)" "$name"
}

function _k3s_detect_ip() {
   local override="${K3S_NODE_IP:-${NODE_IP:-}}"
   if [[ -n "$override" ]]; then
      printf '%s\n' "$override"
      return 0
   fi

   if declare -f _ip >/dev/null 2>&1; then
      local detected
      detected=$(_ip 2>/dev/null || true)
      detected="${detected//$'\r'/}"
      detected="${detected//$'\n'/}"
      detected="${detected## }"
      detected="${detected%% }"
      if [[ -n "$detected" ]]; then
         printf '%s\n' "$detected"
         return 0
      fi
   fi

   printf '127.0.0.1\n'
}

function _k3s_stage_file() {
   local src="$1"
   local dest="$2"
   local mode="${3:-0644}"

   if [[ -z "$src" || -z "$dest" ]]; then
      [[ -n "$src" ]] && rm -f "$src"
      return 1
   fi

   local dir
   dir="$(dirname "$dest")"
   _ensure_path_exists "$dir"

   if [[ -f "$dest" ]] && cmp -s "$src" "$dest" 2>/dev/null; then
      rm -f "$src"
      return 0
   fi

   if command -v install >/dev/null 2>&1; then
      if install -m "$mode" "$src" "$dest" 2>/dev/null; then
         rm -f "$src"
         return 0
      fi
      _run_command --prefer-sudo -- install -m "$mode" "$src" "$dest"
      rm -f "$src"
      return 0
   fi

   if cp "$src" "$dest" 2>/dev/null; then
      chmod "$mode" "$dest" 2>/dev/null || _run_command --prefer-sudo -- chmod "$mode" "$dest"
      rm -f "$src"
      return 0
   fi

   _run_command --prefer-sudo -- cp "$src" "$dest"
   _run_command --prefer-sudo -- chmod "$mode" "$dest"
   rm -f "$src"
}

function _k3s_render_template() {
   local template="$1"
   local destination="$2"
   local mode="${3:-0644}"

   _ensure_envsubst

   if [[ ! -r "$template" ]]; then
      return 0
   fi

   local tmp
   tmp="$(mktemp -t k3s-istio-template.XXXXXX)"
   envsubst <"$template" >"$tmp"
   _k3s_stage_file "$tmp" "$destination" "$mode"
}

function _k3s_prepare_assets() {
   _ensure_path_exists "$K3S_CONFIG_DIR"
   _ensure_path_exists "$K3S_MANIFEST_DIR"
   _ensure_path_exists "$K3S_LOCAL_STORAGE"

   local ip saved_ip
   ip="$(_k3s_detect_ip)"
   saved_ip="${IP:-}"
   export IP="$ip"

   _k3s_render_template "$(_k3s_template_path config.yaml.tmpl)" "$K3S_CONFIG_FILE"
   _k3s_render_template "$(_k3s_template_path local-path-storage.yaml.tmpl)" \
      "${K3S_MANIFEST_DIR}/local-path-storage.yaml"

   if [[ -n "$saved_ip" ]]; then
      export IP="$saved_ip"
   else
      unset IP
   fi
}

function _k3s_cluster_exists() {
   [[ -f "$K3S_SERVICE_FILE" ]] && return 0 || return 1
}

function _install_k3s() {
   local cluster_name="${1:-${CLUSTER_NAME:-k3s-cluster}}"

   export CLUSTER_NAME="$cluster_name"

   if _is_mac ; then
      if _command_exist k3s ; then
         _info "k3s already installed, skipping"
         return 0
      fi

      local arch asset tmpfile dest
      arch="$(uname -m)"
      case "$arch" in
         arm64|aarch64)
            asset="k3s-darwin-arm64"
            ;;
         x86_64|amd64)
            asset="k3s-darwin-amd64"
            ;;
         *)
            _err "Unsupported macOS architecture for k3s: $arch"
            ;;
      esac

      tmpfile="$(mktemp -t k3s-download.XXXXXX)"
      dest="${K3S_INSTALL_DIR}/k3s"

      _info "Downloading k3s binary for macOS ($arch)"
      _curl -fsSL "https://github.com/k3s-io/k3s/releases/latest/download/${asset}" -o "$tmpfile"

      _ensure_path_exists "$K3S_INSTALL_DIR"

      if [[ -w "$K3S_INSTALL_DIR" ]]; then
         mv "$tmpfile" "$dest"
      else
         _run_command --prefer-sudo -- mv "$tmpfile" "$dest"
      fi

      if [[ -w "$dest" ]]; then
         chmod 0755 "$dest"
      else
         _run_command --prefer-sudo -- chmod 0755 "$dest"
      fi

      _info "Installed k3s binary at $dest"
      return 0
   fi

   if ! _is_debian_family && ! _is_redhat_family && ! _is_wsl ; then
      if _command_exist k3s ; then
         _info "k3s already installed, skipping installer"
         return 0
      fi

      _err "Unsupported platform for k3s installation"
   fi

   _k3s_prepare_assets

   if _command_exist k3s ; then
      _info "k3s already installed, skipping installer"
      return 0
   fi

   local installer
   installer="$(mktemp -t k3s-installer.XXXXXX)"
   _info "Fetching k3s installer script"
   _curl -fsSL https://get.k3s.io -o "$installer"

   local install_exec
   if [[ -n "${INSTALL_K3S_EXEC:-}" ]]; then
      install_exec="${INSTALL_K3S_EXEC}"
   else
      install_exec="server --write-kubeconfig-mode 0644"
      if [[ -f "$K3S_CONFIG_FILE" ]]; then
         install_exec+=" --config ${K3S_CONFIG_FILE}"
      fi
      export INSTALL_K3S_EXEC="$install_exec"
   fi

   _info "Running k3s installer"
   _run_command --prefer-sudo -- env INSTALL_K3S_EXEC="$install_exec" \
      sh "$installer"

   rm -f "$installer"

   if _systemd_available ; then
      _run_command --prefer-sudo -- systemctl enable "$K3S_SERVICE_NAME"
   else
      _warn "systemd not available; skipping enable for $K3S_SERVICE_NAME"
   fi
}

function _teardown_k3s_cluster() {
   if _is_mac ; then
      local dest="${K3S_INSTALL_DIR}/k3s"
      if [[ -f "$dest" ]]; then
         if [[ -w "$dest" ]]; then
            rm -f "$dest"
         else
            _run_command --prefer-sudo -- rm -f "$dest"
         fi
         _info "Removed k3s binary at $dest"
      fi
      return 0
   fi

   if [[ -x "/usr/local/bin/k3s-uninstall.sh" ]]; then
      _run_command --prefer-sudo -- /usr/local/bin/k3s-uninstall.sh
      return 0
   fi

   if [[ -x "/usr/local/bin/k3s-killall.sh" ]]; then
      _run_command --prefer-sudo -- /usr/local/bin/k3s-killall.sh
      return 0
   fi

   if _k3s_cluster_exists; then
      if _systemd_available ; then
         _run_command --prefer-sudo -- systemctl stop "$K3S_SERVICE_NAME"
         _run_command --prefer-sudo -- systemctl disable "$K3S_SERVICE_NAME"
      else
         _warn "systemd not available; skipping service shutdown for $K3S_SERVICE_NAME"
      fi
   fi
}

function _start_k3s_service() {
   local -a server_args

   if [[ -n "${INSTALL_K3S_EXEC:-}" ]]; then
      read -r -a server_args <<<"${INSTALL_K3S_EXEC}"
   else
      server_args=(server --write-kubeconfig-mode 0644)
      if [[ -f "$K3S_CONFIG_FILE" ]]; then
         server_args+=(--config "$K3S_CONFIG_FILE")
      fi
   fi

   if _systemd_available ; then
      _run_command --prefer-sudo -- systemctl start "$K3S_SERVICE_NAME"
      return 0
   fi

   _warn "systemd not available; starting k3s server in background"

   if command -v pgrep >/dev/null 2>&1; then
      if pgrep -x k3s >/dev/null 2>&1; then
         _info "k3s already running; skipping manual start"
         return 0
      fi
   fi

   local manual_cmd
   manual_cmd="$(printf '%q ' k3s "${server_args[@]}")"
   manual_cmd="${manual_cmd% }"

   local log_file="${K3S_DATA_DIR}/k3s-no-systemd.log"
   export K3S_NO_SYSTEMD_LOG="$log_file"

   _ensure_path_exists "$(dirname "$log_file")"

   local log_escaped
   log_escaped="$(printf '%q' "$log_file")"

   local start_cmd
   start_cmd="nohup ${manual_cmd} >> ${log_escaped} 2>&1 &"

   if (( EUID == 0 )); then
      _run_command -- sh -c "$start_cmd"
      return 0
   fi

   local tried_non_interactive=0
   if declare -f _sudo_available >/dev/null 2>&1 && _sudo_available; then
      tried_non_interactive=1
      if _run_command --prefer-sudo -- sh -c "$start_cmd"; then
         return 0
      fi
   fi

   if command -v sudo >/dev/null 2>&1; then
      if sudo sh -c "$start_cmd"; then
         return 0
      fi
   fi

   if (( ! tried_non_interactive )); then
      local instruction
      instruction="nohup ${manual_cmd} >> ${log_file} 2>&1 &"
      _err "systemd not available and sudo access is required to start k3s automatically. Run manually as root: ${instruction}"
   fi

   if _run_command --soft -- sh -c "$start_cmd"; then
      return 0
   fi

   local instruction
   instruction="nohup ${manual_cmd} >> ${log_file} 2>&1 &"
   _err "systemd not available and automatic elevation failed. Run manually as root: ${instruction}"
}

function _deploy_k3s_cluster() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: deploy_k3s_cluster [cluster_name=k3s-cluster]"
      return 0
   fi

   local cluster_name="${1:-k3s-cluster}"
   export CLUSTER_NAME="$cluster_name"

   if _is_mac ; then
      _warn "k3s server deployment is not supported natively on macOS. Installed binaries only."
      return 0
   fi

   _install_k3s "$cluster_name"

   _start_k3s_service

   local kubeconfig_src="$K3S_KUBECONFIG_PATH"
   local timeout=60
   local kubeconfig_ready=1
   while (( timeout > 0 )); do
      if [[ -r "$kubeconfig_src" ]]; then
         kubeconfig_ready=0
         break
      fi

      if _run_command --soft --quiet --prefer-sudo -- test -r "$kubeconfig_src"; then
         kubeconfig_ready=0
         break
      fi

      sleep 2
      timeout=$((timeout - 2))
   done

   if (( kubeconfig_ready != 0 )); then
      if [[ -n "${K3S_NO_SYSTEMD_LOG:-}" ]]; then
         local log_output=""
         if [[ -r "$K3S_NO_SYSTEMD_LOG" ]]; then
            log_output="$(tail -n 20 "$K3S_NO_SYSTEMD_LOG" 2>/dev/null || true)"
         else
            log_output="$(_run_command --soft --quiet --prefer-sudo -- tail -n 20 "$K3S_NO_SYSTEMD_LOG" 2>/dev/null || true)"
         fi

         if [[ -n "$log_output" ]]; then
            _warn "Recent k3s log output:"
            while IFS= read -r line; do
               [[ -n "$line" ]] && _warn "  $line"
            done <<< "$log_output"
         fi
      fi

      _err "Timed out waiting for k3s kubeconfig at $kubeconfig_src"
   fi

   unset K3S_NO_SYSTEMD_LOG

   local dest_kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
   _ensure_path_exists "$(dirname "$dest_kubeconfig")"

   if [[ -w "$dest_kubeconfig" || ! -e "$dest_kubeconfig" ]]; then
      cp "$kubeconfig_src" "$dest_kubeconfig"
   else
      _run_command --prefer-sudo -- cp "$kubeconfig_src" "$dest_kubeconfig"
   fi

   if ! _is_wsl; then
      _run_command --prefer-sudo -- chown "$(id -u):$(id -g)" "$dest_kubeconfig" 2>/dev/null || true
   fi
   chmod 0600 "$dest_kubeconfig" 2>/dev/null || true

   export KUBECONFIG="$dest_kubeconfig"

   _info "k3s cluster '$CLUSTER_NAME' is ready"
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
      tmp_script=$(mktemp -t istioctl-fetch.XXXXXX)
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
   local logger="_info"
   if ! declare -f _info >/dev/null 2>&1; then
      logger=""
   fi

   if [[ -n "$file_to_cleanup" ]]; then
      if [[ -n "$logger" ]]; then
         "$logger" "Cleaning up temporary files... : $file_to_cleanup :"
      else
         printf 'INFO: Cleaning up temporary files... : %s :\n' "$file_to_cleanup" >&2
      fi
      rm -rf "$file_to_cleanup"
   fi
   local path
   for path in "$@"; do
      [[ -n "$path" ]] || continue
      if [[ -n "$logger" ]]; then
         "$logger" "Cleaning up temporary files... : $path :"
      else
         printf 'INFO: Cleaning up temporary files... : %s :\n' "$path" >&2
      fi
      rm -rf -- "$path"
   done
}

function _cleanup_trap_command() {
   local cmd="_cleanup_on_success" path

   for path in "$@"; do
      [[ -n "$path" ]] || continue
      printf -v cmd '%s %q' "$cmd" "$path"
   done

   printf '%s' "$cmd"
}
function _install_smb_csi_driver() {
   if _is_mac ; then
      _warn "SMB CSI driver is not supported on macOS"
      return 0
   fi
   _ensure_helm
   if ! _ensure_cifs_utils; then
      return 1
   fi
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

function destroy_k3s_cluster() {
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

function _create_k3s_cluster() {
   _create_cluster "$@"
}

function create_k3s_cluster() {
   create_cluster "$@"
}

function deploy_cluster() {
   local force_k3s=0 provider_cli="" show_help=0
   local -a positional=()

   while [[ $# -gt 0 ]]; do
      case "$1" in
         -f|--force-k3s)
            force_k3s=1
            shift
            ;;
         --provider)
            provider_cli="${2:-}"
            shift 2
            ;;
         --provider=*)
            provider_cli="${1#*=}"
            shift
            ;;
         -h|--help)
            show_help=1
            shift
            ;;
         --)
            shift
            while [[ $# -gt 0 ]]; do
               positional+=("$1")
               shift
            done
            break
            ;;
         *)
            positional+=("$1")
            shift
            ;;
      esac
   done

   if (( show_help )); then
      cat <<'EOF'
Usage: deploy_cluster [options] [cluster_name]

Options:
  -f, --force-k3s     Skip the provider prompt and deploy using k3s.
  --provider <name>   Explicitly set the provider (k3d or k3s).
  -h, --help          Show this help message.
EOF
      return 0
   fi

   local platform="" platform_msg=""
   if _is_mac; then
      platform="mac"
      platform_msg="Detected macOS environment."
   elif _is_wsl; then
      platform="wsl"
      platform_msg="Detected Windows Subsystem for Linux environment."
   elif _is_debian_family; then
      platform="debian"
      platform_msg="Detected Debian-based Linux environment."
   elif _is_redhat_family; then
      platform="redhat"
      platform_msg="Detected Red Hat-based Linux environment."
   elif _is_linux; then
      platform="linux"
      platform_msg="Detected generic Linux environment."
   else
      _err "Unsupported platform: $(uname -s)."
   fi

   if [[ -n "$platform_msg" ]]; then
      _info "$platform_msg"
   fi

   local provider=""
   if [[ -n "$provider_cli" ]]; then
      provider="$provider_cli"
   elif (( force_k3s )); then
      provider="k3s"
   else
      local env_override="${CLUSTER_PROVIDER:-${K3D_MANAGER_PROVIDER:-${K3DMGR_PROVIDER:-${K3D_MANAGER_CLUSTER_PROVIDER:-}}}}"
      if [[ -n "$env_override" ]]; then
         provider="$env_override"
      fi
   fi

   provider="$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')"

   if [[ "$platform" == "mac" && "$provider" == "k3s" ]]; then
      _err "k3s is not supported on macOS; please use k3d instead."
   fi

   if [[ -z "$provider" ]]; then
      if [[ "$platform" == "mac" ]]; then
         provider="k3d"
      else
         local has_tty=0
         if [[ -t 0 && -t 1 ]]; then
            has_tty=1
         fi

         if (( has_tty )); then
            local choice=""
            while true; do
               printf 'Select cluster provider [k3d/k3s] (default: k3d): '
               IFS= read -r choice || choice=""
               choice="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')"
               if [[ -z "$choice" ]]; then
                  provider="k3d"
                  break
               fi
               case "$choice" in
                  k3d|k3s)
                     provider="$choice"
                     break
                     ;;
                  *)
                     _warn "Unsupported selection '$choice'. Please choose k3d or k3s."
                     ;;
               esac
            done
         else
            provider="k3d"
            _info "Non-interactive session detected; defaulting to k3d provider."
         fi
      fi
   fi

   if [[ "$platform" == "mac" && "$provider" == "k3s" ]]; then
      _err "k3s is not supported on macOS; please use k3d instead."
   fi

   case "$provider" in
      k3d|k3s)
         ;;
      "")
         _err "Failed to determine cluster provider."
         ;;
      *)
         _err "Unsupported cluster provider: $provider"
         ;;
   esac

   export CLUSTER_PROVIDER="$provider"
   export K3D_MANAGER_PROVIDER="$provider"
   export K3D_MANAGER_CLUSTER_PROVIDER="$provider"
   if declare -f _cluster_provider_set_active >/dev/null 2>&1; then
      _cluster_provider_set_active "$provider"
   fi

   _info "Using cluster provider: $provider"
   _cluster_provider_call deploy_cluster "${positional[@]}"
   test_istio
}

function deploy_k3d_cluster() {
   deploy_cluster "$@"
}

function deploy_k3s_cluster() {
   deploy_cluster "$@"
}
