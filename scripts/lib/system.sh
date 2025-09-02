function command_exist() {
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
_run_command() {
  local quiet=0 prefer_sudo=0 require_sudo=0 probe= soft=0

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
    if [[ -n "$probe" ]]; then
      # Try user first; if probe fails, try sudo -n
      if "$prog" "$probe" >/dev/null 2>&1; then
        runner=("$prog")
      elif sudo -n "$prog" "$probe" >/dev/null 2>&1; then
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
  command_exist secret-tool && return 0
  is_linux || return 1

  if command_exist apt-get ; then
    _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update
    _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y libsecret-tools
  elif command_exist dnf ; then
    _run_command --prefer-sudo -- dnf -y install libsecret
  elif command_exist -v yum >/dev/null 2>&1; then
    _run_command --prefer-sudo -- yum -y install libsecret
  elif command_exist microdnf ; then
    _run_command --prefer-sudo -- microdnf -y install libsecret
  else
    echo "Cannot install secret-tool: no known package manager found" >&2
    exit 127
  fi

  command -v secret-tool >/dev/null 2>&1
}

function _install_redhat_kubernetes_client() {
  if ! command_exist kubectl; then
     _run_command --prefer-sudo -- dnf install -y kubernetes-client
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
   if command_exist kubectl ; then
      echo "kubectl already installed, skipping"
      return 0
   fi

   echo "Installing kubectl on Debian/Ubuntu system..."

   # Create the keyrings directory if it doesn't exist
   _run_command --require-sudo -- mkdir -p /etc/apt/keyrings

   # Download the Kubernetes signing key
   if [[ ! -e "/etc/apt/keyrings/kubernetes-apt-keyring.gpg" ]]; then
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key \
         | _run_command --require-sudo -- gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
   fi

   # Add the Kubernetes apt repository
   echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | _run_command --require-sudo - tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

   # Update apt package index
   _run_command --require-sudo -- apt-get update -y

   # Install kubectl
   _run_command --require-sudo -- apt-get install -y kubectl

}

function install_kubernetes_cli() {
   if is_redhat_family ; then
      _install_redhat_kubernetes_client
   elif is_debian_family ; then
      _install_debian_kubernetes_client
   elif is_wsl ; then
      if grep "debian" /etc/os-release &> /dev/null; then
        _install_debian_kubernetes_client
      elif grep "redhat" /etc/os-release &> /dev/null; then
         _install_redhat_kubernetes_client
      fi
   fi
}

function is_mac() {
   if [[ "$(uname -s)" == "Darwin" ]]; then
      return 0
   else
      return 1
   fi
}

function install_mac_helm() {
  _run_command --quiet -- brew install helm
}

function install_redhat_helm() {
  _run_command --require-sudo -- dnf install -y helm
}

function _install_helm() {
  if command_exist helm; then
    echo helm already installed, skip
    return 0
  fi

  if is_mac; then
    install_mac_helm
  elif is_redhat_family ; then
    install_redhat_helm
  fi
}

function is_linux() {
   if [[ "$(uname -s)" == "Linux" ]]; then
      return 0
   else
      return 1
   fi
}

function is_redhat_family() {
   [[ -f /etc/redhat-release ]] && return 0 || return 1
}

function is_debian_family() {
   [[ -f /etc/debian_version ]] && return 0 || return 1
}

function is_wsl() {
   if [[ -n "$WSL_DISTRO_NAME" ]]; then
      return 0
   elif grep -Eqi "(Microsoft|WSL)" /proc/version &> /dev/null; then
      return 0
   else
      return 1
   fi
}

function install_colima() {
   if ! command_exist colima ; then
      echo colima does not exist, install it
      _run_command --quiet -- brew install colima
   else
      echo colima installed already
   fi
}

function _install_mac_docker() {

   if  ! command_exist docker && is_mac ; then
      echo docker does not exist, install it
      brew install docker
   else
      echo docker installed already
   fi

   if is_mac; then
      docker context use colima
      export DOCKER_HOST=unix:///Users/$USER/.colima/docker.sock
      colima start
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
  _run_command --require-sudo -- apt-get update
  # Install dependencies
  _run_command --require-sudo -- apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  # Add Docker's GPG key
  if [[ ! -e "/usr/share/keyrings/docker-archive-keyring.gpg" ]]; then
     _curl -fsSL https://download.docker.com/linux/$(lsb_release -is \
        | tr '[:upper:]' '[:lower:]')/gpg \
        | sudo gpg --dearmor \
        -o /usr/share/keyrings/docker-archive-keyring.gpg
  fi
  # Add Docker repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) stable" | _run_command --require-sudo -- tee /etc/apt/sources.list.d/docker.list > /dev/null
  # Update package list
  _run_command --require-sudo -- apt-get update
  # Install Docker
  _run_command --require-sudo -- apt-get install -y docker-ce docker-ce-cli containerd.io
  # Start and enable Docker
  _run_command --require-sudo -- systemctl start docker
  _run_command --require-sudo -- systemctl enable docker
  # Add current user to docker group
  _run_command --require-sudo -- usermod -aG docker $USER
  echo "Docker installed successfully. You may need to log out and back in for group changes to take effect."
}

function _install_redhat_docker() {
  echo "Installing Docker on RHEL/Fedora/CentOS system..."
  # Install required packages
  _run_command --require-sudo -- dnf install -y dnf-plugins-core
  # Add Docker repository
  _run_command --require-sudo -- dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  # Install Docker
  _run_command --require-sudo -- dnf install -y docker-ce docker-ce-cli containerd.io
  # Start and enable Docker
  _run_command --require-sudo -- systemctl start docker
  _run_command --require-sudo -- systemctl enable docker
  # Add current user to docker group
  _run_command --require-sudo -- usermod -aG docker $USER
  echo "Docker installed successfully. You may need to log out and back in for group changes to take effect."
}

function _create_k3d_cluster() {
   cluster_yaml=$1

   if is_mac ; then
     _run_command --quiet -- k3d cluster create --config "${cluster_yaml}"
   elif is_linux ; then
     _run_command --require-sudo k3d cluster create --config "${cluster_yaml}"
   fi
}

function _list_k3d_cluster() {
   _run_command --quiet -- k3d cluster list
}

function _kubectl() {

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
   if ! command_exist istioctl ; then
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
   if ! command_exist curl ; then
      echo "curl is not installed. Please install it first."
      exit 1
   fi

   _run_command --quiet -- curl "$@"
}

function _kill() {
   _run_command --quiet -- kill "$@"
}

function _ip() {
   if is_mac ; then
      ifconfig en0 | grep inet | awk '$1=="inet" {print $2}'
   else
      ip -4 route get 8.8.8.8 | perl -nle 'print $1 if /src (.*) uid/'
   fi
}

function _k3d() {
   if ! command_exist k3d ; then
      echo "k3d is not installed. Please install it first."
      exit 1
   fi

   _run_command --quiet --probe $HOME/.kube/config -- k3d cluster list >/dev/null 2>&1
}

function _try_load_plugin() {
  local func="${1:?usage: _try_load_plugin <function> [args...]}"
  shift
  local plugin

  if [[ "$func" == _* ]]; then
    echo "Error: '$func' is private (names starting with '_' cannot be invoked)." >&2
    return 1
  fi
  if [[ ! "$func" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
    echo "Error: invalid function name: '$func'" >&2
    return 1
  fi

  shopt -s nullglob
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
  shopt -u nullglob

  echo "Error: Function '$func' not found in plugins" >&2
  return 1
}

function _try_load_function() {
  local func="${1:?usage: _try_load_function <function> [args...]}"
  shift
  local plugin

  if [[ "$func" == _* ]]; then
    echo "Error: '$func' is private (names starting with '_' cannot be invoked)." >&2
    return 1
  fi
  if [[ ! "$func" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
    echo "Error: invalid function name: '$func'" >&2
    return 1
  fi

  shopt -s nullglob
  for plugin in "$PLUGINS_DIR"/*.sh; do
    if command grep -Eq "^[[:space:]]*(function[[:space:]]+${func}[[:space:]]*\(\)|${func}[[:space:]]*\(\))[[:space:]]*\{" "$plugin"; then
      # shellcheck source=/dev/null
      source "$plugin"
      if [[ "$(type -t -- "$func")" == "function" ]]; then
        shopt -u nullglob
        "$func" "$@"
        return $?
      fi
    fi
  done
  shopt -u nullglob

  echo "Error: Function '$func' not found in plugins" >&2
  return 1
}

function _sha256_12() {
   local s="$1" line hash

   if command_exist shasum; then
      line=$(_run_command -- shasum -a 256 <<<"$s")
   elif command_exist sha256sum; then
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
      echo "✅ Bitwarden token in k3d matches local token."
      return 1
   else
      return 0
   fi
}

function _ensure_cargo() {
   if command_exist cargo ; then
      return 0
   fi

   if is_mac && command_exist brew ; then
      brew install rust
      return 0
   fi

   if is_debian_family ; then
      _run_command --require-sudo -- apt-get update
      _run_command --require-sudo -- apt-get install -y cargo
   elif is_redhat_family ; then
      _run_command --require-sudo -- dnf install -y cargo
   elif is_wsl && grep -qi "debian" /etc/os-release &> /dev/null; then
      _run_command --require-sudo -- apt-get update
      _run_command --require-sudo -- apt-get install -y cargo
   elif is_wsl && grep -qi "redhat" /etc/os-release &> /dev/null; then
      _run_command --require-sudo -- apt-get update
      _run_command --require-sudo -- apt-get install -y cargo
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
function _info() { printf 'INFO: %s\n' "$*"; }
function _warn() { printf 'WARN: %s\n' "$*" >&2; }
function _err() { printf 'ERROR: %s\n' "$*" >&2; exit 127; }
