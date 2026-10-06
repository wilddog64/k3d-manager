# shellcheck shell=bash
# k3d-manager's system library is the lib-foundation subtree copy. This file loads it so that
# bin/* scripts, the Makefile and tests that source scripts/lib/system.sh get the same
# _run_command as the dispatcher. Only k3d-manager-specific helpers are defined here; change
# shared helpers upstream in lib-foundation.
_k3dm_system_lib_dir="${BASH_SOURCE[0]%/*}"
if [[ "$_k3dm_system_lib_dir" == "${BASH_SOURCE[0]}" ]]; then
    _k3dm_system_lib_dir="."
fi
_k3dm_system_lib_dir="$(cd -P "$_k3dm_system_lib_dir" >/dev/null 2>&1 && pwd)"

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="${_k3dm_system_lib_dir%/*}"
fi

# shellcheck source=scripts/lib/foundation/scripts/lib/system.sh
source "${_k3dm_system_lib_dir}/foundation/scripts/lib/system.sh"
unset _k3dm_system_lib_dir

KUBECONFORM_VERSION="0.7.0"

# Print the pinned SHA-256 of the kubeconform v0.7.0 release asset for "<os>-<arch>".
function _kubeconform_sha256() {
   case "$1" in
      darwin-amd64) echo "c6771cc894d82e1b12f35ee797dcda1f7da6a3787aa30902a15c264056dd40d4" ;;
      darwin-arm64) echo "b5d32b2cb77f9c781c976b20a85e2d0bc8f9184d5d1cfe665a2f31a19f99eeb9" ;;
      linux-amd64) echo "c31518ddd122663b3f3aa874cfe8178cb0988de944f29c74a0b9260920d115d3" ;;
      linux-arm64) echo "cc907ccf9e3c34523f0f32b69745265e0a6908ca85b92f41931d4537860eb83c" ;;
      *) return 1 ;;
   esac
}

# Download the pinned kubeconform release, verify its SHA-256, and install it into ~/.local/bin.
function _install_kubeconform_from_release() {
   local os arch expected asset tmp_dir actual

   case "$(uname -s)" in
      Darwin) os=darwin ;;
      Linux) os=linux ;;
      *) echo "Cannot install kubeconform: unsupported OS $(uname -s)" >&2; return 1 ;;
   esac
   case "$(uname -m)" in
      x86_64|amd64) arch=amd64 ;;
      arm64|aarch64) arch=arm64 ;;
      *) echo "Cannot install kubeconform: unsupported architecture $(uname -m)" >&2; return 1 ;;
   esac

   if ! expected="$(_kubeconform_sha256 "${os}-${arch}")"; then
      echo "Cannot install kubeconform: no pinned checksum for ${os}-${arch}" >&2
      return 1
   fi
   if ! _command_exist curl || ! _command_exist tar; then
      echo "Cannot install kubeconform: curl and tar are required" >&2
      return 1
   fi

   tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t kubeconform)"
   if [[ -z "$tmp_dir" || ! -d "$tmp_dir" ]]; then
      echo "Failed to create temporary directory for kubeconform install" >&2
      return 1
   fi

   asset="kubeconform-${os}-${arch}.tar.gz"
   echo "Installing kubeconform ${KUBECONFORM_VERSION} (${os}-${arch}) from release..." >&2
   if ! _run_command -- curl -fsSL \
         "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/${asset}" \
         -o "${tmp_dir}/${asset}"; then
      rm -rf "$tmp_dir"
      return 1
   fi

   if _command_exist shasum; then
      actual="$(shasum -a 256 "${tmp_dir}/${asset}")"
   elif _command_exist sha256sum; then
      actual="$(sha256sum "${tmp_dir}/${asset}")"
   else
      echo "Cannot verify kubeconform: no SHA-256 command found" >&2
      rm -rf "$tmp_dir"
      return 1
   fi
   actual="${actual%% *}"
   if [[ "$actual" != "$expected" ]]; then
      echo "kubeconform checksum mismatch for ${asset}: expected ${expected}, got ${actual}" >&2
      rm -rf "$tmp_dir"
      return 1
   fi

   if ! tar -xzf "${tmp_dir}/${asset}" -C "$tmp_dir" kubeconform; then
      rm -rf "$tmp_dir"
      return 1
   fi
   mkdir -p "${HOME}/.local/bin"
   if ! install -m 0755 "${tmp_dir}/kubeconform" "${HOME}/.local/bin/kubeconform"; then
      rm -rf "$tmp_dir"
      return 1
   fi
   rm -rf "$tmp_dir"

   _ensure_local_bin_on_path
   hash -r 2>/dev/null || true
   _command_exist kubeconform
}

# Make kubeconform available: already installed, then Homebrew, then the pinned release.
function _ensure_kubeconform() {
   if _command_exist kubeconform; then
      return 0
   fi

   if _command_exist brew; then
      _run_command -- brew install kubeconform
      if _command_exist kubeconform; then
         return 0
      fi
   fi

   if _install_kubeconform_from_release; then
      return 0
   fi

   echo "Cannot install kubeconform; install it manually: https://github.com/yannh/kubeconform" >&2
   return 1
}
