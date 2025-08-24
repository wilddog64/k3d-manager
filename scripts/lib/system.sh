function command_exist() {
    command -v "$1" &> /dev/null
}

function _install_redhat_kubernetes_client() {
  if ! command_exist kubectl; then
     sudo dnf install -y kubernetes-client
  fi
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
  local quiet=0 prefer_sudo=0 require_sudo=0 probe=

  while [[ $# -gt 0 ]]; do
    case "$1" in
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
    return 127
  fi

  # Decide runner: user vs sudo -n
  local runner
  if (( require_sudo )); then
    if sudo -n true >/dev/null 2>&1; then
      runner=(sudo -n "$prog")
    else
      (( quiet )) || echo "sudo non-interactive not available" >&2
      return 1
    fi
  else
    if [[ -n "$probe" ]]; then
      # Try user first; if probe fails, try sudo -n
      if "$prog" $probe >/dev/null 2>&1; then
        runner=("$prog")
      elif sudo -n "$prog" $probe >/dev/null 2>&1; then
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

  if (( rc != 0 && quiet == 0 )); then
    printf '%s command failed (%d): ' "$prog" "$rc" >&2
    printf '%q ' "${runner[@]}" "$@" >&2
    printf '\n' >&2
  fi
  return "$rc"
}

function _install_debian_kubernetes_client() {
   if command_exist kubectl ; then
      echo "kubectl already installed, skipping"
      return 0
   fi

   echo "Installing kubectl on Debian/Ubuntu system..."

   # Create the keyrings directory if it doesn't exist
   sudo mkdir -p /etc/apt/keyrings

   # Download the Kubernetes signing key
   if [[ ! -e "/etc/apt/keyrings/kubernetes-apt-keyring.gpg" ]]; then
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key \
         | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
   fi

   # Add the Kubernetes apt repository
   echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

   # Update apt package index
   sudo apt-get update -y

   # Install kubectl
   sudo apt-get install -y kubectl

   if [[ $? == 0 ]]; then
      echo "kubectl installed successfully"
   else
      echo "Failed to install kubectl"
      exit 1
   fi
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
  brew install helm
  if [[ $? != 0 ]]; then
    echo problem install helm
    exit -1
  fi
}

function install_redhat_helm() {
  sudo dnf install -y helm
  if [[ $? != 0 ]]; then
    echo problem install helm
    exit -1
  fi
}

function install_helm() {
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
   elif egrep -qi "(Microsoft|WSL)" /proc/version &> /dev/null; then
      return 0
   else
      return 1
   fi
}

function install_colima() {
   if ! command_exist colima ; then
      echo colima does not exist, install it
      brew install colima
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
  sudo apt-get update
  # Install dependencies
  sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  # Add Docker's GPG key
  if [[ ! -e "/usr/share/keyrings/docker-archive-keyring.gpg" ]]; then
     curl -fsSL https://download.docker.com/linux/$(lsb_release -is \
        | tr '[:upper:]' '[:lower:]')/gpg \
        | sudo gpg --dearmor \
        -o /usr/share/keyrings/docker-archive-keyring.gpg
  fi
  # Add Docker repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  # Update package list
  sudo apt-get update
  # Install Docker
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  # Start and enable Docker
  sudo systemctl start docker
  sudo systemctl enable docker
  # Add current user to docker group
  sudo usermod -aG docker $USER
  echo "Docker installed successfully. You may need to log out and back in for group changes to take effect."
}

function _install_redhat_docker() {
  echo "Installing Docker on RHEL/Fedora/CentOS system..."
  # Install required packages
  sudo dnf install -y dnf-plugins-core
  # Add Docker repository
  sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  # Install Docker
  sudo dnf install -y docker-ce docker-ce-cli containerd.io
  # Start and enable Docker
  sudo systemctl start docker
  sudo systemctl enable docker
  # Add current user to docker group
  sudo usermod -aG docker $USER
  echo "Docker installed successfully. You may need to log out and back in for group changes to take effect."
}

function install_docker() {
   if is_mac; then
      _install_mac_docker
   elif is_debian_family; then
      _install_debian_docker
   elif is_redhat_family ; then
      _install_redhat_docker
   else
      echo "Unsupported Linux distribution. Please install Docker manually."
      exit 1
   fi
}

function install_k3d() {
   install_docker
   install_helm
   install_istioctl

   if ! command_exist k3d ; then
      echo k3d does not exist, install it
      curl -f -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
   else
      echo k3d installed already
   fi
}

function install_istioctl() {
   install_dir="${1:-/usr/local/bin}"

   if command_exist istioctl ; then
      echo "istioctl already exists, skip installation"
      return 0
   fi

   echo "install dir: ${install_dir}"
   if [[ ! -e "$install_dir" && ! -d "$install_dir" ]]; then
      mkdir -p "${install_dir}"
   fi

   if  ! command_exist istioctl ; then
      echo installing istioctl
      tmp_script=$(mktemp)
      pushd /tmp
      curl -f -s https://raw.githubusercontent.com/istio/istio/master/release/downloadIstioCandidate.sh -o "$tmp_script"
      istio_bin=$(bash "$tmp_script" | perl -nle 'print $1 if /add the (.*) directory/')
      if [[ -z "$istio_bin" ]]; then
         echo "Failed to download istioctl"
         exit 1
      fi
      sudo cp -v "$istio_bin/istioctl" "${install_dir}/"
      popd
   fi

   trap 'rm -rf /tmp/istio-*' EXIT TERM
}

function _create_k3d_cluster() {
   cluster_yaml=$1

   if is_mac ; then
     k3d cluster create --config "${cluster_yaml}"
   elif is_linux ; then
     sudo k3d cluster create --config "${cluster_yaml}"
   fi
}

function _list_k3d_cluster() {
   if is_mac ; then
      k3d cluster list
   elif is_linux ; then
      sudo k3d cluster list
   fi
}

function _kubectl() {
   _run_command --probe 'config current-context' -- kubectl "$@"
}

function _istioctl() {
   if ! command_exist istioctl ; then
      echo "istioctl is not installed. Please install it first."
      exit 1
   fi

   if is_mac ; then
      istioctl "$@"
   else
      sudo istioctl "$@"
   fi

   if [[ $? != 0 ]]; then
      echo "Istioctl command failed: $@"
      exit 1
   fi
}

# Optional: global default flags you want on every helm call
# export HELM_GLOBAL_ARGS="--debug"   # example

_helm() {
  # Pass-through mini-parser so you can do: _helm --quiet ...  (like _run_command)
  local pre=() ; while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet|--prefer-sudo|--require-sudo) pre+=("$1"); shift;;
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

   if [[ -f $HOME/.kube/config ]] && kubectl get nodes 2>&1 > /dev/null ; then
      curl "$@"
   else
      sudo curl "$@"
   fi

   if [[ $? != 0 ]]; then
      echo "Curl command failed: $@"
      exit 1
   fi
}

function _kill() {

   if [[ -f "$HOME/.kube/config" ]] && kubectl get nodes 2>&1 > /dev/null ; then
      kill "$@"
   else
      sudo kill "$@"
   fi

   if [[ $? != 0 ]]; then
      echo "Kill command failed: $@"
      exit 1
   fi
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

   if [[ -f $HOME/.kube/config ]] && kubectl get nodes 2>&1 > /dev/null ; then
      k3d "$@"
   else
      sudo k3d "$@"
   fi

   if [[ $? != 0 ]]; then
      echo "k3d command failed: $@"
      exit 1
   fi
}

function try_load_plugin() {
   PLUGIN_DIR="${SCRIPT_DIR}/plugins"
   local func="$1"
   for plugin in "$PLUGIN_DIR"/*.sh; do
     if grep -q "function $func" "$plugin"; then
       source "$plugin"
       # Check again if function is now available
       if [[ "$(type -t $func)" == "function" ]]; then
         $func "${@:2}"
         exit 0
       fi
     fi
   done
   echo "Error: Function '$func' not found in plugins"
   exit 1
}

