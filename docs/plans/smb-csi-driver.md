# SMB CSI Driver Enablement Plan (k3s single-node focus)

1. **Baseline the current host and cluster**
   - Verify the WSL2/k3s node has the `cifs` kernel module available and record how to install `cifs-utils` (`sudo apt-get install cifs-utils`) so `mount.cifs` works.
   - Capture the present behaviour of `_install_smb_csi_driver` in `scripts/lib/core.sh` (currently a stub) and list gaps blocking a working driver install in this environment.
   - Confirm Helm access to the upstream `smb.csi.k8s.io` chart and note any air-gapped concerns.

2. **Implement prerequisite helpers**
   - Add `_ensure_cifs_utils` to `scripts/lib/system.sh`; make it install the package on Debian/Ubuntu (`apt-get install cifs-utils`) and RHEL/Fedora (`dnf install cifs-utils`), while emitting actionable guidance for platforms we cannot automate (e.g., macOS Homebrew, SUSE).
   - Ensure `_install_smb_csi_driver` invokes `_ensure_helm` and `_ensure_cifs_utils` before touching the cluster, failing fast when prerequisites cannot be met.

3. **Complete the driver installer**
   - Extend `_install_smb_csi_driver` to add the upstream Helm repo idempotently, install/upgrade the chart into a dedicated namespace (e.g., `kube-system`), and apply k3s-friendly settings (disable Windows daemonset, tolerate/control-plane scheduling).
   - Make the helper create or update the CSI `CSIDriver` object when Helm skips it, and surface clear status messages.
   - Add `deploy_cluster` switches (default `--enable-cifs`, opt-out `--no-cifs`) so the installer runs automatically on new clusters unless explicitly disabled.

4. **Provision secrets and storage classes**
   - Introduce a helper or template for creating the SMB credentials `Secret` (username, password, optional domain/workgroup) sourced from env vars or flags without logging secrets.
   - Add a `StorageClass` manifest geared for the single-node k3s lab (e.g., `csi.storage.k8s.io/provisioner: smb.csi.k8s.io`, default reclaim policy) and wire it through the helper.
   - Document how to override share/endpoint parameters for future multi-node clusters without changing code.
   - Support multiple credential sources: environment variables exported via smartcd, LastPass, and (once available) Vault; add helpers that can read from these providers without persisting secrets to disk.

5. **Testing and validation**
   - Add BATS coverage for `_ensure_cifs_utils`, the new secret/storage-class helpers, and success/failure paths of `_install_smb_csi_driver` (mocking `helm`/`kubectl`).
   - Provide manual smoke test steps for (a) the k3s pod-based mount and (b) mounting directly from WSL2 to a Windows-hosted SMB share. Include guidance for validating both a successful mount (share exists) and a failure case (share absent/credentials wrong) so operators know how the system behaves in each scenario.

6. **Documentation refresh**
   - Update README and `docs/` deployment guides with SMB CSI instructions tailored to the single-node k3s environment, including prerequisite commands for Debian/Ubuntu and RHEL/Fedora, plus cleanup steps.
   - Note future work for k3d/multi-node support so this plan remains the base for broader adoption.
