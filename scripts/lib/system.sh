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

function _ensure_jq() {
   _command_exist jq && return 0

   if _is_mac; then
      _run_command --quiet -- brew install jq
      return
   fi

   if _is_debian_family; then
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update -y
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y jq
      return
   fi

   if _is_redhat_family; then
      if _command_exist dnf; then
         _run_command --prefer-sudo -- dnf install -y jq
      else
         _run_command --prefer-sudo -- yum install -y jq
      fi
      return
   fi

   if _is_wsl && _command_exist apt-get; then
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update -y
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y jq
      return
   fi

   _err "Package manager not found to install jq"
}

function _ensure_curl() {
   if _command_exist curl; then
      return 0
   fi

   if _is_mac; then
      if _command_exist brew; then
         _run_command --quiet -- brew install curl
      else
         _warn "Homebrew not available; install curl from https://curl.se/download.html"
         return 1
      fi
   elif _is_debian_family; then
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update -y
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y curl
   elif _is_redhat_family; then
      local pkg_manager=
      if _command_exist dnf; then
         pkg_manager="dnf"
      elif _command_exist yum; then
         pkg_manager="yum"
      else
         _warn "Cannot determine package manager to install curl on this Red Hat based system."
         return 1
      fi
      _run_command --prefer-sudo -- "$pkg_manager" install -y curl
   elif _is_wsl; then
      if _command_exist apt-get; then
         _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update -y
         _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y curl
      else
         local wsl_pkg=
         if _command_exist dnf; then
            wsl_pkg="dnf"
         elif _command_exist yum; then
            wsl_pkg="yum"
         fi
         if [[ -n "$wsl_pkg" ]]; then
            _run_command --prefer-sudo -- "$wsl_pkg" install -y curl
         else
            _warn "Unable to determine package manager for curl installation under WSL."
            return 1
         fi
      fi
   else
      _warn "Unsupported platform for automatic curl installation."
      return 1
   fi

   if _command_exist curl; then
      return 0
   fi

   _warn "curl installation attempted but curl binary still missing."
   return 1
}

function _ensure_lpass() {
   local lpass_cmd="${1:-lpass}"

    if _command_exist "$lpass_cmd"; then
       return 0
    fi

    local installed_cmd="lpass"
    if [[ "$lpass_cmd" != "$installed_cmd" ]] && _command_exist "$installed_cmd"; then
       return 0
    fi

    if _is_mac; then
       if _command_exist brew; then
          _run_command --quiet -- brew install lastpass-cli
       else
          _warn "Homebrew not available; install LastPass CLI from https://github.com/lastpass/lastpass-cli"
          return 1
       fi
    elif _is_debian_family; then
       _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update -y
       _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y lastpass-cli
    elif _is_redhat_family; then
       local pkg_manager=
       if _command_exist dnf; then
          pkg_manager="dnf"
       elif _command_exist yum; then
          pkg_manager="yum"
       else
          _warn "Cannot determine package manager to install LastPass CLI on this Red Hat based system."
          return 1
       fi
       if ! _run_command --prefer-sudo -- "$pkg_manager" install -y lastpass-cli; then
          _warn "LastPass CLI not available via $pkg_manager; install manually from https://github.com/lastpass/lastpass-cli"
          return 1
       fi
    elif _is_wsl; then
       if _command_exist apt-get; then
          _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update -y
          _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y lastpass-cli
       else
          local wsl_pkg=
          if _command_exist dnf; then
             wsl_pkg="dnf"
          elif _command_exist yum; then
             wsl_pkg="yum"
          fi
          if [[ -n "$wsl_pkg" ]]; then
             if ! _run_command --prefer-sudo -- "$wsl_pkg" install -y lastpass-cli; then
                _warn "LastPass CLI not available via $wsl_pkg; install manually from https://github.com/lastpass/lastpass-cli"
                return 1
             fi
          else
             _warn "Unable to determine package manager for LastPass CLI installation under WSL."
             return 1
          fi
       fi
    else
       _warn "Unsupported platform for automatic LastPass CLI installation."
       return 1
    fi

    if _command_exist "$lpass_cmd" || _command_exist "$installed_cmd"; then
       return 0
    fi

   _warn "LastPass CLI installation attempted but binary still missing."
   return 1
}

function _ensure_cifs_utils() {
   if _command_exist mount.cifs; then
      return 0
   fi

   if _is_mac; then
      _warn "Automatic cifs-utils install not supported on macOS; install via Homebrew or macports."
      return 1
   fi

   if _is_debian_family || (_is_wsl && _command_exist apt-get); then
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update -y
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y cifs-utils
   elif _is_redhat_family || (_is_wsl && (_command_exist dnf || _command_exist yum)); then
      local pkg_manager=
      if _command_exist dnf; then
         pkg_manager="dnf"
      elif _command_exist yum; then
         pkg_manager="yum"
      fi

      if [[ -n "$pkg_manager" ]]; then
         _run_command --prefer-sudo -- "$pkg_manager" install -y cifs-utils
      else
         _warn "Cannot determine package manager to install cifs-utils on this system."
         return 1
      fi
   else
      _warn "Unsupported platform for automatic cifs-utils installation."
      return 1
   fi

   if _command_exist mount.cifs; then
      return 0
   fi

   _warn "cifs-utils installation attempted but mount.cifs still missing."
   return 1
}

function _ensure_docker() {
   if _command_exist docker; then
      return 0
   fi

   if declare -f _install_docker >/dev/null 2>&1; then
      if ! _install_docker; then
         _warn "Docker installation helper failed; install manually from https://docs.docker.com/engine/install/."
         return 1
      fi
   else
      _warn "Docker install helper not available; install manually from https://docs.docker.com/engine/install/."
      return 1
   fi

   if _command_exist docker; then
      return 0
   fi

   _warn "Docker installation attempted but docker binary still missing."
   return 1
}

function _ensure_k3d() {
   if _command_exist k3d; then
      return 0
   fi

   local install_dir="${1:-}"
   if declare -f _install_k3d >/dev/null 2>&1; then
      if [[ -n "$install_dir" ]]; then
         _install_k3d "$install_dir"
      else
         _install_k3d
      fi
   else
      _warn "k3d install helper not available; install manually from https://k3d.io/#installation."
      return 1
   fi

   if _command_exist k3d; then
      return 0
   fi

   _warn "k3d installation attempted but binary still missing."
   return 1
}

function _ensure_envsubst() {
   if command -v envsubst >/dev/null 2>&1; then
      return 0
   fi

   if _is_mac; then
      _run_command --quiet -- brew install gettext
      return
   fi

   if _is_debian_family; then
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update -y
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y gettext-base
      return
   fi

   if _is_redhat_family; then
      if _command_exist dnf; then
         _run_command --prefer-sudo -- dnf install -y gettext
      else
         _run_command --prefer-sudo -- yum install -y gettext
      fi
      return
   fi

   if _is_wsl && _command_exist apt-get; then
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get update -y
      _run_command --prefer-sudo -- env DEBIAN_FRONTEND=noninteractive apt-get install -y gettext-base
      return
   fi

   _err "Package manager not found to install envsubst"
}

function _sync_lastpass_ad() {
   local lpass_cmd="${LPASS_CMD:-lpass}"
   if ! _ensure_lpass "$lpass_cmd"; then
      printf 'ERROR: LastPass CLI not found (looked for %s); run bin/sync-lastpass-ad.sh to validate manual workflow.\n' "$lpass_cmd" >&2
      return 1
   fi
   if ! command -v "$lpass_cmd" >/dev/null 2>&1 && ! command -v lpass >/dev/null 2>&1; then
      printf 'ERROR: LastPass CLI still missing after attempted install (looked for %s)\n' "$lpass_cmd" >&2
      return 1
   fi

   _ensure_jq

   local entry_listing entry_line entry_id lp_pass
   if ! entry_listing=$("$lpass_cmd" ls 2>/dev/null); then
      printf 'ERROR: lpass ls failed; ensure LastPass CLI is logged in.\n' >&2
      return 1
   fi

   entry_line=$(printf '%s\n' "$entry_listing" | grep -i svcADReader | grep PACIFIC | head -n1 || true)
   if [[ -z "$entry_line" ]]; then
      printf 'ERROR: Unable to locate LastPass entry for svcADReader in PACIFIC vault.\n' >&2
      return 1
   fi

   if [[ "$entry_line" =~ id:[[:space:]]*([0-9]+) ]]; then
      entry_id="${BASH_REMATCH[1]}"
   else
      printf 'ERROR: Failed to parse LastPass entry id from: %s\n' "$entry_line" >&2
      return 1
   fi

   if ! lp_pass=$("$lpass_cmd" show --id "$entry_id" --pass 2>/dev/null); then
      printf 'ERROR: Failed to retrieve LastPass password for entry id %s.\n' "$entry_id" >&2
      return 1
   fi

   local username="CN=svcADReader,OU=Service Accounts,OU=UsersOU,DC=pacific,DC=costcotravel,DC=com"
   local payload payload_file
   if ! payload=$(jq -n --arg username "$username" --arg password "$lp_pass" '{username:$username,password:$password}'); then
      printf 'ERROR: Failed to build Vault payload for Jenkins AD secret.\n' >&2
      return 1
   fi

   if ! payload_file=$(mktemp "${TMPDIR:-/tmp}/jenkins-ad-payload.XXXXXX"); then
      printf 'ERROR: Failed to create temporary file for Jenkins AD payload.\n' >&2
      return 1
   fi
   _cleanup_register "$payload_file"

   if ! printf '%s' "$payload" >"$payload_file"; then
      rm -f "$payload_file"
      printf 'ERROR: Failed to write Jenkins AD payload to temporary file.\n' >&2
      return 1
   fi

   if ! _kubectl --quiet -n vault exec vault-0 -i -- sh -c 'cat >/tmp/jenkins-ad.json && vault kv put secret/jenkins/ad-ldap @/tmp/jenkins-ad.json && rm -f /tmp/jenkins-ad.json' <"$payload_file"; then
      rm -f "$payload_file"
      printf 'ERROR: Failed to write Jenkins AD credentials to Vault.\n' >&2
      return 1
   fi
   rm -f "$payload_file"

   local vault_json vault_pass
   if ! vault_json=$(_kubectl --quiet -n vault exec vault-0 -i -- vault kv get -format=json secret/jenkins/ad-ldap); then
      printf 'ERROR: Failed to read Jenkins AD credentials from Vault for verification.\n' >&2
      return 1
   fi

   vault_pass=$(printf '%s' "$vault_json" | jq -r '.data.data.password')
   if [[ -z "$vault_pass" || "$vault_pass" == "null" ]]; then
      printf 'ERROR: Vault returned an empty password for secret/jenkins/ad-ldap.\n' >&2
      return 1
   fi

   if [[ "$lp_pass" != "$vault_pass" ]]; then
      local lp_sha vault_sha
      lp_sha=$(printf '%s' "$lp_pass" | sha256sum | awk '{print $1}')
      vault_sha=$(printf '%s' "$vault_pass" | sha256sum | awk '{print $1}')
      printf 'Vault credential mismatch\n' >&2
      printf 'LastPass SHA256: %s\n' "$lp_sha" >&2
      printf 'Vault    SHA256: %s\n' "$vault_sha" >&2
      return 1
   fi

   local lp_sha
   lp_sha=$(printf '%s' "$lp_pass" | sha256sum | awk '{print $1}')
   printf 'Vault credential matches LastPass (SHA256 %s)\n' "$lp_sha"
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

   return 0
}

function _install_helm() {
  if _command_exist helm; then
    return 0
  fi

  if _is_mac; then
    if _command_exist brew; then
      _install_mac_helm
    else
      _warn "Homebrew not available; install Helm manually from https://helm.sh/docs/intro/install/"
      return 1
    fi
  elif _is_redhat_family; then
    if _command_exist dnf; then
      _install_redhat_helm
    elif _command_exist yum; then
      _run_command -- sudo yum install -y helm
    else
      _warn "No supported package manager found to install Helm on this system."
      return 1
    fi
  elif _is_debian_family; then
    _install_debian_helm
  elif _is_wsl; then
    if _command_exist apt-get; then
      _install_debian_helm
    elif _command_exist dnf || _command_exist yum; then
      _install_redhat_helm
    else
      _warn "Unable to determine package manager for Helm installation under WSL."
      return 1
    fi
  else
    _warn "Unsupported platform for automatic Helm installation."
    return 1
  fi

  if _command_exist helm; then
    return 0
  fi

  _warn "Helm installation attempted but helm binary still missing."
  return 1
}

function _ensure_helm() {
  if _command_exist helm; then
    return 0
  fi

  if _install_helm; then
    return 0
  fi

  _err "Unable to install helm automatically; visit https://helm.sh/docs/intro/install/ for manual steps."
}

function _ensure_istioctl() {
  if _command_exist istioctl; then
    return 0
  fi

  if declare -f _install_istioctl >/dev/null 2>&1; then
    if _install_istioctl; then
      :
    fi
  fi

  if _command_exist istioctl; then
    return 0
  fi

  _warn "istioctl not available; install manually via https://istio.io/latest/docs/setup/getting-started/#download."
  return 1
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
   if ! _ensure_istioctl; then
      _err "istioctl is not installed. Please install it first."
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

  _ensure_helm

  # If you keep global flags, splice them in *before* user args:
  if [[ -n "${HELM_GLOBAL_ARGS:-}" ]]; then
    _run_command "${pre[@]}" --probe 'version --short' -- helm ${HELM_GLOBAL_ARGS} "$@"
  else
    _run_command "${pre[@]}" --probe 'version --short' -- helm "$@"
  fi
}

function _curl() {
   if ! _ensure_curl; then
      _err "curl is required but could not be installed automatically."
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
function _err() { printf 'ERROR: %s\n' "$*" >&2; exit 127; }

function _no_trace() {
  local wasx=0
  case $- in *x*) wasx=1; set +x;; esac
  "$@"; local rc=$?
  (( wasx )) && set -x
  return $rc
}

# Validate that all variables referenced in templates are set & non-empty,
# using values/defaults from a given vars file. Avoid double-sourcing by
# marking each env file as loaded via a unique path-based marker variable.
#
# Usage:
#   validate_variables /path/to/vars.sh /path/to/template1 [template2 ...] [--allow-empty VAR]...
#
# In vars.sh you may also define:
#   export ALLOW_EMPTY_VARS=(VAR1 VAR2)
#
function validate_variables() {
  local vars_file templates=() extra_allow=()

  # --- parse args ---
  if (($# == 0)); then
    echo "ERROR: _validate_variables requires at least a vars file" >&2
    return 1
  fi
  vars_file=$1; shift
  while (($#)); do
    case "$1" in
      --allow-empty)
        shift
        [[ $# -gt 0 ]] || { echo "ERROR: --allow-empty needs a var name" >&2; return 1; }
        extra_allow+=("$1"); shift
        ;;
      *)
        templates+=("$1"); shift
        ;;
    esac
  done

  [[ -r "$vars_file" ]] || { echo "ERROR: vars file not readable: $vars_file" >&2; return 1; }
  ((${#templates[@]})) || { echo "ERROR: no templates provided to validate" >&2; return 1; }

  # --- compute absolute path + a unique marker var for this env file ---
  local abs_dir abs_vars_file marker
  abs_dir="$(cd "$(dirname "$vars_file")" && pwd)"
  abs_vars_file="$abs_dir/$(basename "$vars_file")"
  marker="_ENV_LOADED_${abs_vars_file//[^A-Za-z0-9_]/_}"
  marker="${marker^^}"  # uppercase

  # --- source vars.sh only once per env file ---
  if [[ -z "${!marker-}" ]]; then
    # shellcheck disable=SC1090
    source "$abs_vars_file"
    printf -v "$marker" '1'
    export "$marker"
  fi

  # --- collect allow-empty list: from env file + extra arguments ---
  local -a allow_empty=()
  if declare -p ALLOW_EMPTY_VARS >/dev/null 2>&1; then
    # shellcheck disable=SC2154
    allow_empty+=("${ALLOW_EMPTY_VARS[@]}")
  fi
  if ((${#extra_allow[@]})); then
    allow_empty+=("${extra_allow[@]}")
  fi

  _is_allowed_empty() {
    local v=$1 x
    for x in "${allow_empty[@]}"; do [[ "$v" == "$x" ]] && return 0; done
    return 1
  }

  # --- extract vars from templates: $VAR, ${VAR}, ${VAR:-...} ---
  local -a template_vars=() tmp out t
  for t in "${templates[@]}"; do
    [[ -r "$t" ]] || { echo "ERROR: template not readable: $t" >&2; return 1; }
    while IFS= read -r out; do
      template_vars+=("$out")
    done < <(
      grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*(?::-[^}]*)?\}|\$[A-Za-z_][A-Za-z0-9_]*' "$t" |
      sed -E 's/^\$\{([A-Za-z_][A-Za-z0-9_]*)[:}].*/\1/; s/^\$([A-Za-z_][A-Za-z0-9_]*).*/\1/' |
      sort -u
    )
  done

  # --- validate: must be set & non-empty unless allowed empty ---
  local -a missing=() v
  for v in "${template_vars[@]}"; do
    _is_allowed_empty "$v" && continue
    # use ${!v-} so unset → empty, safe with `set -u`
    [[ -n "${!v-}" ]] || missing+=("$v")
  done

  if ((${#missing[@]})); then
    echo "ERROR: missing required variables: ${missing[*]}" >&2
    echo "Hint: define them in $abs_vars_file or add to ALLOW_EMPTY_VARS/--allow-empty." >&2
    return 1
  fi
  return 0
}
