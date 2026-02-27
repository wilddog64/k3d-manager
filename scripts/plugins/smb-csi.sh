SMB_CSI_CONFIG_DIR="$SCRIPT_DIR/etc/smb-csi"
SMB_CSI_VARS_FILE="$SMB_CSI_CONFIG_DIR/vars.sh"

if [[ -r "$SMB_CSI_VARS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SMB_CSI_VARS_FILE"
fi

function deploy_smb_csi() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: deploy_smb_csi

Deploy the SMB CSI driver on supported platforms. On macOS (k3d/OrbStack) the
command logs a warning and exits successfully because SMB mounts require the
cifs kernel module, which is unavailable. Use a Linux/k3s cluster to validate
SMB CSI or implement the macOS NFS swap described in docs/plans/smb-csi-macos-workaround.md.
USAGE
    return 0
  fi

  if _is_mac ; then
    _warn "[smb-csi] SMB CSI is not supported on macOS; skipping deploy. Use Linux/k3s for validation or follow the NFS swap plan."
    return 0
  fi

  _info "[smb-csi] Deploying SMB CSI driver (release=${SMB_CSI_RELEASE:-smb-csi-driver}, namespace=${SMB_CSI_NAMESPACE:-kube-system})"
  _install_smb_csi_driver
}
