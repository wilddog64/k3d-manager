function _command_exist() {
    command -v "$1" &> /dev/null
}

# _run_command [--quiet] [--prefer-sudo|--require-sudo] [--probe '<subcmd>'] -- <prog> [args...]
# - --quiet         : suppress wrapper error message (still returns real exit code)
# - --prefer-sudo   : use sudo -n if available, otherwise run as user
# - --require-sudo  : fail if sudo -n not available
# - --probe '...'   : subcommand to test env/permissions (e.g., for kubectl: 'config current-context')
# - --              : end of options; after this comes <prog> and its args
#
# Returns the command's real exit code; prints a helpful error unless --quiet.
function _run_command() {
  local quiet=0 prefer_sudo=0 require_sudo=0 probe= soft=0
  local -a probe_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-exit|--soft) soft=1; shift;;
      --quiet)        quiet=1; shift;;
      --prefer-sudo)  prefer_sudo=1; shift;;
      --require-sudo) require_sudo=1; shift;;
      --probe)        probe="$2"; shift 2;;
      --)             shift; break;;
      *)              break;;
    esac
  done

  local prog="${1:?usage: _run_command [opts] -- <prog> [args...]}"
  shift

  if ! command -v "$prog" >/dev/null 2>&1; then
    (( quiet )) || echo "$prog: not found in PATH" >&2
    if (( soft )); then
      return 127
    else
      exit 127
    fi
  fi

  if [[ -n "$probe" ]]; then
    read -r -a probe_args <<< "$probe"
  fi

  # Decide runner: user vs sudo -n
  local runner
  if (( require_sudo )); then
    if sudo -n true >/dev/null 2>&1; then
      runner=(sudo -n "$prog")
    else
      (( quiet )) || echo "sudo non-interactive not available" >&2
      exit 127
    fi
  else
    if (( ${#probe_args[@]} )); then
      # Try user first; if probe fails, try sudo -n
      if "$prog" "${probe_args[@]}" >/dev/null 2>&1; then
        runner=("$prog")
      elif sudo -n "$prog" "${probe_args[@]}" >/dev/null 2>&1; then
        runner=(sudo -n "$prog")
      elif (( prefer_sudo )) && sudo -n true >/dev/null 2>&1; then
        runner=(sudo -n "$prog")
      else
        runner=("$prog")
      fi
    else
      if (( prefer_sudo )) && sudo -n true >/dev/null 2>&1; then
        runner=(sudo -n "$prog")
      else
        runner=("$prog")
      fi
    fi
  fi

  # Execute and preserve exit code
  "${runner[@]}" "$@"
  local rc=$?

  if (( rc != 0 )); then
     if (( quiet == 0 )); then
       printf '%s command failed (%d): ' "$prog" "$rc" >&2
       printf '%q ' "${runner[@]}" "$@" >&2
       printf '\n' >&2
     fi

     if (( soft )); then
         return "$rc"
     else
         _err "failed to execute ${runner[@]} $@: $rc"
     fi
  fi

  return 0
}

function _args_have_sensitive_flag() {
  local arg
  local expect_secret=0

  for arg in "$@"; do
    if (( expect_secret )); then
      return 0
    fi
    case "$arg" in
      --password|--token|--username)
        expect_secret=1
        ;;
      --password=*|--token=*|--username=*)
        return 0
        ;;
    esac
  done

  return 1
}

_ensure_secret_tool() {
  _command_exist secret-tool && return 0
  _is_linux || return 1

  if _command_exist apt-get ; then
    _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update
    _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y libsecret-tools
  elif _command_exist dnf ; then
    _run_command --prefer-sudo -- dnf -y install libsecret
  elif _command_exist -v yum >/dev/null 2>&1; then
    _run_command --prefer-sudo -- yum -y install libsecret
  elif _command_exist microdnf ; then
    _run_command --prefer-sudo -- microdnf -y install libsecret
  else
    echo "Cannot install secret-tool: no known package manager found" >&2
    exit 127
  fi

  command -v secret-tool >/dev/null 2>&1
}

function _install_redhat_kubernetes_client() {
  if ! _command_exist kubectl; then
     _run_command -- sudo dnf install -y kubernetes-client
  fi
}

function _secret_tool() {
   _ensure_secret_tool >/dev/null 2>&1
   _run_command --quiet -- secret-tool "$@"
}

# macOS only
function _security() {
   _run_command --quiet -- security "$@"
}

function _set_sensitive_var() {
   local name="${1:?variable name required}"
   local value="${2:-}"
   local wasx=0
   case $- in *x*) wasx=1; set +x;; esac
   printf -v "$name" '%s' "$value"
   (( wasx )) && set -x
}

function _write_sensitive_file() {
   local path="${1:?path required}"
   local data="${2:-}"
   local wasx=0
   local old_umask
   case $- in *x*) wasx=1; set +x;; esac
   old_umask=$(umask)
   umask 077
   printf '%s' "$data" > "$path"
   local rc=$?
   if (( rc == 0 )); then
      chmod 600 "$path" 2>/dev/null || true
   fi
   umask "$old_umask"
   (( wasx )) && set -x
   return "$rc"
}

function _remove_sensitive_file() {
   local path="${1:-}"
   local wasx=0
   if [[ -z "$path" ]]; then
      return 0
   fi
   case $- in *x*) wasx=1; set +x;; esac
   rm -f -- "$path"
   (( wasx )) && set -x
}

function _decode_hex_blob() {
   local blob="${1:-}"
   local wasx=0
   case $- in *x*) wasx=1; set +x;; esac
   if [[ -n "$blob" && "$blob" =~ ^[0-9a-fA-F]+$ && $(( ${#blob} % 2 )) -eq 0 ]]; then
      local decoded=""
      decoded=$(python3 - "$blob" <<'PY'
import binascii
import sys
try:
    sys.stdout.write(binascii.unhexlify(sys.argv[1]).decode("utf-8"))
except Exception:
    sys.stdout.write(sys.argv[1])
PY
      )
      (( wasx )) && set -x
      printf '%s' "$decoded"
      return 0
   fi
   (( wasx )) && set -x
   printf '%s' "$blob"
}

function _json_escape() {
   local value="${1:-}"
   value="${value//\\/\\\\}"
   value="${value//\"/\\\"}"
   printf '%s' "$value"
}

function _write_registry_config() {
   local host="${1:?registry host required}"
   local username="${2:?username required}"
   local password="${3:?password required}"
   local destination="${4:?destination required}"

   local auth=""
   auth=$(printf '%s:%s' "$username" "$password" | base64 | tr -d $'\r\n')

   local esc_user esc_pass
   esc_user=$(_json_escape "$username")
   esc_pass=$(_json_escape "$password")

   local config=""
   config=$'{\n  "auths": {\n'
   printf -v config '%s    "%s": {\n      "username": "%s",\n      "password": "%s",\n      "auth": "%s"\n    }' \
      "$config" "$host" "$esc_user" "$esc_pass" "$auth"

   if [[ "$host" == "registry-1.docker.io" ]]; then
      printf -v config '%s,\n    "%s": {\n      "username": "%s",\n      "password": "%s",\n      "auth": "%s"\n    }\n' \
         "$config" "https://index.docker.io/v1/" "$esc_user" "$esc_pass" "$auth"
   else
      config+=$'\n'
   fi

   config+=$'  }\n}\n'

   _write_sensitive_file "$destination" "$config"
}

function _build_credential_blob() {
   local username="${1:?username required}"
   local password="${2:?password required}"
   local blob=""
   local wasx=0
   case $- in *x*) wasx=1; set +x;; esac
   printf -v blob 'username=%s\npassword=%s\n' "$username" "$password"
   (( wasx )) && set -x
   printf '%s' "$blob"
}

function _parse_credential_blob() {
   local blob="${1:-}"
   local username_var="${2:?username variable required}"
   local password_var="${3:?password variable required}"
   local username=""
   local password=""
   local line key value

   if [[ -z "$blob" ]]; then
      return 1
   fi

   while IFS='=' read -r key value; do
      case "$key" in
         username) username="$value" ;;
         password) password="$value" ;;
      esac
   done <<<"$blob"

   if [[ -z "$username" || -z "$password" ]]; then
      return 1
   fi

   _set_sensitive_var "$username_var" "$username"
   _set_sensitive_var "$password_var" "$password"
   return 0
}

function _oci_registry_host() {
   local ref="${1:-}"
   if [[ "$ref" == oci://* ]]; then
      ref="${ref#oci://}"
      printf '%s\n' "${ref%%/*}"
      return 0
   fi
   return 1
}

function _secret_tool_ready() {
   if _command_exist secret-tool; then
      return 0
   fi

   if _is_linux; then
      if _ensure_secret_tool >/dev/null 2>&1; then
         return 0
      fi
   fi

   return 1
}

function _store_registry_credentials() {
   local context="${1:?context required}"
   local host="${2:?registry host required}"
   local username="${3:?username required}"
   local password="${4:?password required}"
   local blob=""
   local blob_file=""

   blob=$(_build_credential_blob "$username" "$password") || return 1
   blob_file=$(mktemp -t registry-cred.XXXXXX) || return 1
   _write_sensitive_file "$blob_file" "$blob"

   if _is_mac; then
      local service="${context}:${host}"
      local account="${context}"
      local rc=0
      _no_trace bash -c 'security delete-generic-password -s "$1" >/dev/null 2>&1 || true' _ "$service" >/dev/null 2>&1
      if ! _no_trace bash -c 'security add-generic-password -s "$1" -a "$2" -w "$3" >/dev/null' _ "$service" "$account" "$blob"; then
         rc=$?
      fi
      _remove_sensitive_file "$blob_file"
      return $rc
   fi

   if _secret_tool_ready; then
      local label="${context} registry ${host}"
      local rc=0
      _no_trace bash -c 'secret-tool clear service "$1" registry "$2" type "$3" >/dev/null 2>&1 || true' _ "$context" "$host" "helm-oci" >/dev/null 2>&1
      local store_output=""
      store_output=$(_no_trace bash -c 'secret-tool store --label "$1" service "$2" registry "$3" type "$4" < "$5"' _ "$label" "$context" "$host" "helm-oci" "$blob_file" 2>&1)
      local store_rc=$?
      if (( store_rc != 0 )) || [[ -n "$store_output" ]]; then
         rc=${store_rc:-1}
         if [[ -z "$store_output" ]]; then
            store_output="unable to persist credentials via secret-tool"
         fi
         _warn "[${context}] secret-tool store failed for ${host}: ${store_output}"
      fi
      _remove_sensitive_file "$blob_file"
      if (( rc == 0 )); then
         return 0
      fi
   fi

   _remove_sensitive_file "$blob_file"
   _warn "[${context}] unable to persist OCI credentials securely; re-supply --username/--password on next run"
   return 1
}

function _registry_login() {
   local host="${1:?registry host required}"
   local username="${2:-}"
   local password="${3:-}"
   local registry_config="${4:-}"
   local pass_file=""

   if [[ -z "$username" || -z "$password" ]]; then
      return 1
   fi

   pass_file=$(mktemp -t helm-pass.XXXXXX) || return 1
   if ! _write_sensitive_file "$pass_file" "$password"; then
      _remove_sensitive_file "$pass_file"
      return 1
   fi

   local login_output=""
   local login_rc=0
   if [[ -n "$registry_config" ]]; then
      login_output=$(_no_trace bash -c 'HELM_REGISTRY_CONFIG="$4" helm registry login "$1" --username "$2" --password-stdin < "$3"' _ "$host" "$username" "$pass_file" "$registry_config" 2>&1) || login_rc=$?
   else
      login_output=$(_no_trace bash -c 'helm registry login "$1" --username "$2" --password-stdin < "$3"' _ "$host" "$username" "$pass_file" 2>&1) || login_rc=$?
   fi
   _remove_sensitive_file "$pass_file"

   if (( login_rc != 0 )); then
      if [[ -n "$login_output" ]]; then
         _warn "[helm] registry login failed for ${host}: ${login_output}"
      else
         _warn "[helm] registry login failed for ${host}; ensure credentials are valid."
      fi
      return 1
   fi

   _info "[helm] authenticated OCI registry ${host}"
   return 0
}

function _load_registry_credentials() {
   local context="${1:?context required}"
   local host="${2:?registry host required}"
   local username_var="${3:?username variable required}"
   local password_var="${4:?password variable required}"
   local blob=""

   if _is_mac; then
      local service="${context}:${host}"
      blob=$(_no_trace bash -c 'security find-generic-password -s "$1" -w' _ "$service" 2>/dev/null || true)
   elif _command_exist secret-tool; then
      blob=$(_no_trace bash -c 'secret-tool lookup service "$1" registry "$2" type "$3"' _ "$context" "$host" "helm-oci" 2>/dev/null || true)
   fi

   if [[ -z "$blob" ]]; then
      return 1
   fi

   blob=$(_decode_hex_blob "$blob")

   _parse_credential_blob "$blob" "$username_var" "$password_var" || return 1
   return 0
}

function _secret_store_data() {
   local service="${1:?service name required}"
   local key="${2:?entry key required}"
   local data="${3:-}"
   local label="${4:-${service} ${key}}"
   local type="${5:-note}"

   if _is_mac; then
      local rc=0
      _no_trace bash -c 'security delete-generic-password -s "$1" -a "$2" >/dev/null 2>&1 || true' _ "$service" "$key"
      if ! _no_trace bash -c 'security add-generic-password -s "$1" -a "$2" -w "$3" >/dev/null' _ "$service" "$key" "$data"; then
         rc=$?
      fi
      return "$rc"
   fi

   if _secret_tool_ready; then
      local tmp rc=0 store_output=""
      tmp=$(mktemp -t secret-data.XXXXXX) || return 1
      if ! _write_sensitive_file "$tmp" "$data"; then
         _remove_sensitive_file "$tmp"
         return 1
      fi
      _no_trace bash -c 'secret-tool clear service "$1" name "$2" type "$3" >/dev/null 2>&1 || true' _ "$service" "$key" "$type"
      store_output=$(_no_trace bash -c 'secret-tool store --label "$1" service "$2" name "$3" type "$4" < "$5"' _ "$label" "$service" "$key" "$type" "$tmp" 2>&1)
      rc=$?
      _remove_sensitive_file "$tmp"
      if (( rc != 0 )) || [[ -n "$store_output" ]]; then
         _warn "[secret] unable to store data for ${service}/${key}: ${store_output:-unknown error}"
         return ${rc:-1}
      fi
      return 0
   fi

   _warn "[secret] secure storage unavailable; install secret-tool or run on macOS"
   return 1
}

function _secret_load_data() {
   local service="${1:?service name required}"
   local key="${2:?entry key required}"
   local type="${3:-note}"
   local value=""

   if _is_mac; then
      value=$(_no_trace bash -c 'security find-generic-password -s "$1" -a "$2" -w' _ "$service" "$key" 2>/dev/null || true)
   elif _command_exist secret-tool; then
      value=$(_no_trace bash -c 'secret-tool lookup service "$1" name "$2" type "$3"' _ "$service" "$key" "$type" 2>/dev/null || true)
   fi

   if [[ -z "$value" ]]; then
      return 1
   fi

   printf '%s' "$value"
   return 0
}

function _secret_clear_data() {
   local service="${1:?service name required}"
   local key="${2:?entry key required}"
   local type="${3:-note}"

   if _is_mac; then
      _no_trace bash -c 'security delete-generic-password -s "$1" -a "$2" >/dev/null 2>&1 || true' _ "$service" "$key"
      return 0
   fi

   if _command_exist secret-tool; then
      _no_trace bash -c 'secret-tool clear service "$1" name "$2" type "$3" >/dev/null 2>&1 || true' _ "$service" "$key" "$type"
      return 0
   fi

   return 1
}

function _install_debian_kubernetes_client() {
   if _command_exist kubectl ; then
      echo "kubectl already installed, skipping"
      return 0
   fi

   echo "Installing kubectl on Debian/Ubuntu system..."

   # Create the keyrings directory if it doesn't exist
   _run_command -- sudo mkdir -p /etc/apt/keyrings

   # Download the Kubernetes signing key
   if [[ ! -e "/etc/apt/keyrings/kubernetes-apt-keyring.gpg" ]]; then
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key \
         | _run_command -- sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
   fi

   # Add the Kubernetes apt repository
   echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | \
      _run_command -- sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

   # Update apt package index
   _run_command -- sudo apt-get update -y

   # Install kubectl
   _run_command -- sudo apt-get install -y kubectl

}

function _install_kubernetes_cli() {
   if _is_redhat_family ; then
      _install_redhat_kubernetes_client
   elif _is_debian_family ; then
      _install_debian_kubernetes_client
   elif _is_mac ; then
      if ! _command_exist kubectl ; then
         _run_command --quiet -- brew install kubectl
      fi
   elif _is_wsl ; then
      if grep "debian" /etc/os-release &> /dev/null; then
        _install_debian_kubernetes_client
      elif grep "redhat" /etc/os-release &> /dev/null; then
         _install_redhat_kubernetes_client
      fi
   fi
}

function _is_mac() {
   if [[ "$(uname -s)" == "Darwin" ]]; then
      return 0
   else
      return 1
   fi
}

function _install_mac_helm() {
  _run_command --quiet -- brew install helm
}

function _install_redhat_helm() {
  _run_command -- sudo dnf install -y helm
}

function _install_debian_helm() {
  # 1) Prereqs
  _run_command -- sudo apt-get update
  _run_command -- sudo apt-get install -y curl gpg apt-transport-https

   # 2) Add Helm’s signing key (to /usr/share/keyrings)
   _run_command -- curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | \
      _run_command -- gpg --dearmor | \
      _run_command -- sudo tee /usr/share/keyrings/helm.gpg >/dev/null

   # 3) Add the Helm repo (with signed-by, required on 24.04)
   echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | \
   sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

   # 4) Install
   _run_command sudo apt-get update
   _run_command sudo apt-get install -y helm

}

function _install_helm() {
  if _command_exist helm; then
    echo helm already installed, skip
    return 0
  fi

  if _is_mac; then
    _install_mac_helm
  elif _is_redhat_family ; then
    _install_redhat_helm
  elif _is_debian_family ; then
    _install_debian_helm
  elif _is_wsl ; then
    if grep "debian" /etc/os-release &> /dev/null; then
      _install_debian_helm
    elif grep "redhat" /etc/os-release &> /dev/null; then
       _install_redhat_helm
    fi
  fi
}

function _is_linux() {
   if [[ "$(uname -s)" == "Linux" ]]; then
      return 0
   else
      return 1
   fi
}

function _is_redhat_family() {
   [[ -f /etc/redhat-release ]] && return 0 || return 1
}

function _is_debian_family() {
   [[ -f /etc/debian_version ]] && return 0 || return 1
}

function _is_wsl() {
   if [[ -n "$WSL_DISTRO_NAME" ]]; then
      return 0
   elif grep -Eqi "(Microsoft|WSL)" /proc/version &> /dev/null; then
      return 0
   else
      return 1
   fi
}

function _install_colima() {
   if ! _command_exist colima ; then
      echo colima does not exist, install it
      _run_command --quiet -- brew install colima
   else
      echo colima installed already
   fi
}

function _install_mac_docker() {
   local cpu="${1:-${COLIMA_CPU:-4}}"
   local memory="${2:-${COLIMA_MEMORY:-8}}"
   local disk="${3:-${COLIMA_DISK:-20}}"

   if  ! _command_exist docker && _is_mac ; then
      echo docker does not exist, install it
      brew install docker
   else
      echo docker installed already
   fi

   if _is_mac; then
      _install_colima
      docker context use colima
      export DOCKER_HOST=unix:///Users/$USER/.colima/docker.sock
      colima start --cpu "$cpu" --memory "$memory" --disk "$disk"
   fi


   # grep DOKER_HOST $HOME/.zsh/zshrc | wc -l 2>&1 > /dev/null
   # if $? == 0 ; then
   #    echo "export DOCKER_HOST=unix:///Users/$USER/.colima/docker.sock" >> $HOME/.zsh/zshrc
   #    echo "export DOCKER_CONTEXT=colima" >> $HOME/.zsh/zshrc
   #    echo "restart your shell to apply the changes"
   # fi
}

function _install_debian_docker() {
  echo "Installing Docker on Debian/Ubuntu system..."
  # Update apt
  _run_command -- sudo apt-get update
  # Install dependencies
  _run_command -- sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  # Add Docker's GPG key
  if [[ ! -e "/usr/share/keyrings/docker-archive-keyring.gpg" ]]; then
     _curl -fsSL https://download.docker.com/linux/$(lsb_release -is \
        | tr '[:upper:]' '[:lower:]')/gpg \
        | sudo gpg --dearmor \
        -o /usr/share/keyrings/docker-archive-keyring.gpg
  fi
  # Add Docker repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) stable" | \
     _run_command -- sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  # Update package list
  _run_command -- sudo apt-get update
  # Install Docker
  _run_command -- sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  # Start and enable Docker when systemd is available
  if _systemd_available ; then
     _run_command -- sudo systemctl start docker
     _run_command -- sudo systemctl enable docker
  else
     _warn "systemd not available; skipping docker service activation"
  fi
  # Add current user to docker group
  _run_command -- sudo usermod -aG docker $USER
  echo "Docker installed successfully. You may need to log out and back in for group changes to take effect."
}

function _install_redhat_docker() {
  echo "Installing Docker on RHEL/Fedora/CentOS system..."
  # Install required packages
  _run_command -- sudo dnf install -y dnf-plugins-core
  # Add Docker repository
  _run_command -- sudo dnf config-manager addrepo --overwrite \
     --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
  # Install Docker
  _run_command -- sudo dnf install -y docker-ce docker-ce-cli containerd.io
  # Start and enable Docker when systemd is available
  if _systemd_available ; then
     _run_command  -- sudo systemctl start docker
     _run_command  -- sudo systemctl enable docker
  else
     _warn "systemd not available; skipping docker service activation"
  fi
  # Add current user to docker group
  _run_command  -- sudo usermod -aG docker "$USER"
  echo "Docker instsudo alled successfully. You may need to log out and back in for group changes to take effect."
}

function _k3d_cluster_exist() {
   _cluster_provider_call cluster_exists "$@"
}

function __create_cluster() {
   _cluster_provider_call apply_cluster_config "$@"
}

function __create_k3d_cluster() {
   __create_cluster "$@"
}

function _list_k3d_cluster() {
   _cluster_provider_call list_clusters "$@"
}

function _kubectl() {

  if ! _command_exist kubectl; then
     _install_kubernetes_cli
  fi

  # Pass-through mini-parser so you can do: _helm --quiet ...  (like _run_command)
  local pre=()
  while [[ $# -gt 0 ]]; do
     case "$1" in
         --quiet|--prefer-sudo|--require-sudo|--no-exit) pre+=("$1");
            shift;;
         --) shift;
            break;;
         *)  break;;
     esac
  done
   _run_command "${pre[@]}" -- kubectl "$@"
}

function _istioctl() {
   if ! _command_exist istioctl ; then
      echo "istioctl is not installed. Please install it first."
      exit 1
   fi

   _run_command --quiet -- istioctl "$@"

}

# Optional: global default flags you want on every helm call
# export HELM_GLOBAL_ARGS="--debug"   # example

function _helm() {
  # Pass-through mini-parser so you can do: _helm --quiet ...  (like _run_command)
  local pre=() ;
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet|--prefer-sudo|--require-sudo|--no-exit) pre+=("$1"); shift;;
      --) shift; break;;
      *)  break;;
    esac
  done

  # If you keep global flags, splice them in *before* user args:
  if [[ -n "${HELM_GLOBAL_ARGS:-}" ]]; then
    _run_command "${pre[@]}" --probe 'version --short' -- helm ${HELM_GLOBAL_ARGS} "$@"
  else
    _run_command "${pre[@]}" --probe 'version --short' -- helm "$@"
  fi
}

function _curl() {
   if ! _command_exist curl ; then
      echo "curl is not installed. Please install it first."
      exit 1
   fi

   local curl_max_time="${CURL_MAX_TIME:-30}"
   local has_max_time=0
   local arg
   for arg in "$@"; do
      case "$arg" in
         --max-time|-m|--max-time=*|-m*)
            has_max_time=1
            break
            ;;
      esac
   done

   local -a curl_args=("$@")
   if (( ! has_max_time )) && [[ -n "$curl_max_time" ]]; then
      curl_args=(--max-time "$curl_max_time" "${curl_args[@]}")
   fi

   _run_command --quiet -- curl "${curl_args[@]}"
}

function _kill() {
   _run_command --quiet -- kill "$@"
}

function _ip() {
   if _is_mac ; then
      ifconfig en0 | grep inet | awk '$1=="inet" {print $2}'
   else
      ip -4 route get 8.8.8.8 | perl -nle 'print $1 if /src (.*) uid/'
   fi
}

function _k3d() {
   _cluster_provider_call exec "$@"
}

function _load_plugin_function() {
  local func="${1:?usage: _load_plugin_function <function> [args...]}"
  shift
  local plugin
  local restore_trace=0

  if [[ $- == *x* ]]; then
    set +x
    if _args_have_sensitive_flag "$@"; then
      restore_trace=1
    else
      set -x
    fi
  fi

  shopt -s nullglob
  trap 'shopt -u nullglob' RETURN

  for plugin in "$PLUGINS_DIR"/*.sh; do
    if command grep -Eq "^[[:space:]]*(function[[:space:]]+${func}[[:space:]]*\(\)|${func}[[:space:]]*\(\))[[:space:]]*\{" "$plugin"; then
      # shellcheck source=/dev/null
      source "$plugin"
      if [[ "$(type -t -- "$func")" == "function" ]]; then
        local rc=0
        "$func" "$@" || rc=$?
        if (( restore_trace )); then
          set -x
        fi
        return "$rc"
      fi
    fi
  done

  if (( restore_trace )); then
    set -x
  fi

  echo "Error: Function '$func' not found in plugins" >&2
  return 1
}

function _try_load_plugin() {
  local func="${1:?usage: _try_load_plugin <function> [args...]}"
  shift

  if [[ "$func" == _* ]]; then
    echo "Error: '$func' is private (names starting with '_' cannot be invoked)." >&2
    return 1
  fi
  if [[ ! "$func" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
    echo "Error: invalid function name: '$func'" >&2
    return 1
  fi

  _load_plugin_function "$func" "$@"
}

function _sha256_12() {
   local line hash payload
   local -a cmd

   if _command_exist shasum; then
      cmd=(shasum -a 256)
   elif _command_exist sha256sum; then
      cmd=(sha256sum)
   else
      echo "No SHA256 command found" >&2
      exit -1
   fi

   if [[ $# -gt 0 ]]; then
      payload="$1"
      line=$(printf %s "$payload" | _run_command -- "${cmd[@]}")
   else
      line=$(_run_command -- "${cmd[@]}")
   fi

   hash="${line%% *}"
   printf %s "${hash:0:12}"
}

function _is_same_token() {
   local token1="$1"
   local token2="$2"

   if [[ -z "$token1" ]] && [[ -z "$token2" ]]; then
      echo "One or both tokens are empty" >&2
      exit -1
   fi

   if [[ "$token1" == "$token2" ]]; then
      echo "Bitwarden token in k3d matches local token."
      return 1
   else
      return 0
   fi
}

function _version_ge() {
   local lhs_str="$1"
   local rhs_str="$2"
   local IFS=.
   local -a lhs rhs

   read -r -a lhs <<< "$lhs_str"
   read -r -a rhs <<< "$rhs_str"

   local len=${#lhs[@]}
   if (( ${#rhs[@]} > len )); then
      len=${#rhs[@]}
   fi

   for ((i=0; i<len; ++i)); do
      local l=${lhs[i]:-0}
      local r=${rhs[i]:-0}
      if ((10#$l > 10#$r)); then
         return 0
      elif ((10#$l < 10#$r)); then
         return 1
      fi
   done

   return 0
}

function _bats_version() {
   if ! _command_exist bats ; then
      return 1
   fi

   local version
   version="$(bats --version 2>/dev/null | awk '{print $2}')"
   if [[ -n "$version" ]]; then
      printf '%s\n' "$version"
      return 0
   fi

   return 1
}

function _bats_meets_requirement() {
   local required="$1"
   local current

   current="$(_bats_version 2>/dev/null)" || return 1
   if [[ -z "$current" ]]; then
      return 1
   fi

   _version_ge "$current" "$required"
}

function _sudo_available() {
   if ! command -v sudo >/dev/null 2>&1; then
      return 1
   fi

   sudo -n true >/dev/null 2>&1
}

function _systemd_available() {
   if ! command -v systemctl >/dev/null 2>&1; then
      return 1
   fi

   if [[ -d /run/systemd/system ]]; then
      return 0
   fi

   local init_comm
   init_comm="$(ps -p 1 -o comm= 2>/dev/null || true)"
   init_comm="${init_comm//[[:space:]]/}"
   [[ "$init_comm" == systemd ]]
}

function _install_bats_from_source() {
   local version="${1:-1.10.0}"
   local url="https://github.com/bats-core/bats-core/releases/download/v${version}/bats-core-${version}.tar.gz"
   local tmp_dir

   tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t bats-core)"
   if [[ -z "$tmp_dir" ]]; then
      echo "Failed to create temporary directory for bats install" >&2
      return 1
   fi

   if ! _command_exist curl || ! _command_exist tar ; then
      echo "Cannot install bats from source: curl and tar are required" >&2
      rm -rf "$tmp_dir"
      return 1
   fi

   echo "Installing bats ${version} from source..." >&2
   if ! _run_command -- curl -fsSL "$url" -o "${tmp_dir}/bats-core.tar.gz"; then
      rm -rf "$tmp_dir"
      return 1
   fi

   if ! tar -xzf "${tmp_dir}/bats-core.tar.gz" -C "$tmp_dir"; then
      rm -rf "$tmp_dir"
      return 1
   fi

   local src_dir="${tmp_dir}/bats-core-${version}"
   if [[ ! -d "$src_dir" ]]; then
      rm -rf "$tmp_dir"
      return 1
   fi

   local prefix="${HOME}/.local"
   mkdir -p "$prefix"

   if _run_command -- bash "$src_dir/install.sh" "$prefix"; then
      rm -rf "$tmp_dir"
      return 0
   fi

   if _sudo_available; then
      if _run_command --prefer-sudo -- bash "$src_dir/install.sh" /usr/local; then
         rm -rf "$tmp_dir"
         return 0
      fi
   fi

   echo "Cannot install bats: write access to ${prefix} or sudo is required" >&2
   rm -rf "$tmp_dir"
   return 1
}

function _ensure_bats() {
   local required="1.5.0"

   if _bats_meets_requirement "$required"; then
      return 0
   fi

   local pkg_attempted=0

   if _command_exist brew ; then
      _run_command -- brew install bats-core
      pkg_attempted=1
   elif _command_exist apt-get && _sudo_available; then
      _run_command --prefer-sudo -- apt-get update
      _run_command --prefer-sudo -- apt-get install -y bats
      pkg_attempted=1
   elif _command_exist dnf && _sudo_available; then
      _run_command --prefer-sudo -- dnf install -y bats
      pkg_attempted=1
   elif _command_exist yum && _sudo_available; then
      _run_command --prefer-sudo -- yum install -y bats
      pkg_attempted=1
   elif _command_exist microdnf && _sudo_available; then
      _run_command --prefer-sudo -- microdnf install -y bats
      pkg_attempted=1
   fi

   if _bats_meets_requirement "$required"; then
      return 0
   fi

   local target_version="${BATS_PREFERRED_VERSION:-1.10.0}"
   if _install_bats_from_source "$target_version" && _bats_meets_requirement "$required"; then
      return 0
   fi

   if (( pkg_attempted == 0 )); then
      echo "Cannot install bats >= ${required}: no suitable package manager or sudo access available." >&2
   else
      echo "Cannot install bats >= ${required}. Please install it manually." >&2
   fi

   exit 127
}


function _ensure_cargo() {
   if _command_exist cargo ; then
      return 0
   fi

   if _is_mac && _command_exist brew ; then
      brew install rust
      return 0
   fi

   if _is_debian_family ; then
      _run_command -- sudo apt-get update
      _run_command -- sudo apt-get install -y cargo
   elif _is_redhat_family ; then
      _run_command -- sudo dnf install -y cargo
   elif _is_wsl && grep -qi "debian" /etc/os-release &> /dev/null; then
      _run_command -- sudo apt-get update
      _run_command -- sudo apt-get install -y cargo
   elif _is_wsl && grep -qi "redhat" /etc/os-release &> /dev/null; then
      _run_command -- sudo apt-get update
      _run_command -- sudo apt-get install -y cargo
   else
      echo "Cannot install cargo: unsupported OS or missing package manager" >&2
      exit 127
   fi
}

function _add_exit_trap() {
   local handler="$1"
   local cur="$(trap -p EXIT | sed -E "s/.*'(.+)'/\1/")"

   if [[ -n "$cur" ]]; then
      trap '"$cur"; "$handler"' EXIT
   else
      trap '"$handler"' EXIT
   fi
}

function _cleanup_register() {
   if [[ -z "$__CLEANUP_TRAP_INSTALLED" ]]; then
      _add_exit_trap [[ -n "$__CLEANUP_PATHS" ]] && rm -rf "$__CLEANUP_PATHS"
   fi
   __CLEANUP_PATHS+=" $*"
}

function _failfast_on() {
  set -Eeuo pipefail
  set -o errtrace
  trap '_err "[fatal] rc=$? at $BASH_SOURCE:$LINENO: ${BASH_COMMAND}"' ERR
}

function _failfast_off() {
  trap - ERR
  set +Eeuo pipefail
}

function _detect_cluster_name() {
   # shellcheck disable=SC2155
   local cluster_info="$(_kubectl --quiet -- get nodes | tail -1)"

   if [[ -z "$cluster_info" ]]; then
      _err "Cannot detect cluster name: no nodes found"
   fi
   local cluster_ready=$(echo "$cluster_info" | awk '{print $2}')
   local cluster_name=$(echo "$cluster_info" | awk '{print $1}')

   if [[ "$cluster_ready" != "Ready" ]]; then
      _err "Cluster node is not ready: $cluster_info"
   fi
   _info "Detected cluster name: $cluster_name"

   printf '%s' "$cluster_name"
}

# ---------- tiny log helpers (no parentheses, no single-quote apostrophes) ----------
function _info() { printf 'INFO: %s\n' "$*" >&2; }
function _warn() { printf 'WARN: %s\n' "$*" >&2; }
function _err() {
   printf 'ERROR: %s\n' "$*" >&2
   exit 1
}

function _no_trace() {
  local wasx=0
  case $- in *x*) wasx=1; set +x;; esac
  "$@"; local rc=$?
  (( wasx )) && set -x
  return $rc
}
