# SMB CSI configuration defaults.
# These values are primarily consumed by deploy_smb_csi and any future SMB helpers.

# SMB server connection details (used by storage templates once implemented)
export SMB_SERVER="${SMB_SERVER:-192.168.1.100}"
export SMB_SHARE="${SMB_SHARE:-jenkins}"
export SMB_USERNAME="${SMB_USERNAME:-jenkins}"
export SMB_PASSWORD="${SMB_PASSWORD:-}"

# CSI driver release/namespace
export SMB_CSI_NAMESPACE="${SMB_CSI_NAMESPACE:-kube-system}"
export SMB_CSI_RELEASE="${SMB_CSI_RELEASE:-smb-csi-driver}"

# StorageClass defaults (placeholder for future templates)
export SMB_STORAGE_CLASS_NAME="${SMB_STORAGE_CLASS_NAME:-smb}"
