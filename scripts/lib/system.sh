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
  # Start and enable Docker
  _run_command -- sudo systemctl start docker
  _run_command -- sudo systemctl enable docker
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
  # Start and enable Docker
  _run_command  -- sudo systemctl start docker
  _run_command  -- sudo systemctl enable docker
  # Add current user to docker group
  _run_command  -- sudo usermod -aG docker "$USER"
  echo "Docker instsudo alled successfully. You may need to log out and back in for group changes to take effect."
}

function _k3d_cluster_exist() {
   local cluster_name=$1

   if _run_command --no-exit -- k3d cluster list "$cluster_name" >/dev/null 2>&1 ; then
      return 0
   else
      return 1
   fi
}

function __create_k3d_cluster() {
   cluster_yaml=$1

   if _is_mac ; then
     _run_command --quiet -- k3d cluster create --config "${cluster_yaml}"
   elif _is_linux ; then
     _run_command k3d cluster create --config "${cluster_yaml}"
   fi
}

function _list_k3d_cluster() {
   _run_command --quiet -- k3d cluster list
}

function _kubectl() {

  _install_kubernetes_cli

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
   _run_command "${pre[@]}" -- k3d "$@"
}

function _load_plugin_function() {
  local func="${1:?usage: _load_plugin_function <function> [args...]}"
  shift
  local plugin

  shopt -s nullglob
  trap 'shopt -u nullglob' RETURN

  for plugin in "$PLUGINS_DIR"/*.sh; do
    if command grep -Eq "^[[:space:]]*(function[[:space:]]+${func}[[:space:]]*\(\)|${func}[[:space:]]*\(\))[[:space:]]*\{" "$plugin"; then
      # shellcheck source=/dev/null
      source "$plugin"
      if [[ "$(type -t -- "$func")" == "function" ]]; then
        "$func" "$@"
        return $?
      fi
    fi
  done

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
   local s="$1" line hash

   if _command_exist shasum; then
      line=$(_run_command -- shasum -a 256 <<<"$s")
   elif _command_exist sha256sum; then
      line=$(_run_command <<<"$s")
   else
      echo "No SHA256 command found" >&2
      exit -1
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

function _ensure_bats() {
   if _command_exist bats ; then
      return 0
   fi

   if _command_exist brew ; then
      _run_command -- brew install bats-core
   elif _command_exist apt-get ; then
      _run_command -- sudo apt-get update
      _run_command -- sudo apt-get install -y bats
   elif _command_exist dnf ; then
      _run_command -- sudo dnf install -y bats
   elif _command_exist yum ; then
      _run_command -- sudo yum install -y bats
   elif _command_exist microdnf ; then
      _run_command -- sudo microdnf install -y bats
   else
      echo "Cannot install bats: no known package manager found" >&2
      exit 127
   fi

   command -v bats >/dev/null 2>&1
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

# ---------- tiny log helpers (no parentheses, no single-quote apostrophes) ----------
function _info() { printf 'INFO: %s\n' "$*" >&2; }
function _warn() { printf 'WARN: %s\n' "$*" >&2; }
function _err() { printf 'ERROR: %s\n' "$*" >&2; exit 127; }

function _no_trace() {
  local wasx=0
  case $- in *x*) wasx=1; set +x;; esac
  "$@"; local rc=$?
  (( wasx )) && set -x
  return $rc
}
