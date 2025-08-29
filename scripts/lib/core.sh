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
      _curl -f -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
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
      trap 'rm -rf /tmp/istio-*' EXIT TERM
      pushd /tmp
      curl -f -s https://raw.githubusercontent.com/istio/istio/master/release/downloadIstioCandidate.sh -o "$tmp_script"
      istio_bin=$(bash "$tmp_script" | perl -nle 'print $1 if /add the (.*) directory/')
      if [[ -z "$istio_bin" ]]; then
         echo "Failed to download istioctl"
         exit 1
      fi
      _run_command --require-sudo cp -v "$istio_bin/istioctl" "${install_dir}/"
      popd
   fi

}

function create_k3d_cluster() {
   cluster_name=$1

   export CLUSTER_NAME="$cluster_name"

   if [[ -z "$cluster_name" ]]; then
      echo "Cluster name is required"
      exit 1
   fi

   cluster_template="$(dirname $SOURCE)/etc/cluster.yaml.tmpl"
   cluster_var="$(dirname $SOURCE)/etc/cluster_var.sh"

   if [[ ! -r "$cluster_template" ]]; then
      echo "Cluster template file not found: $cluster_template"
      exit 1
   fi

   if [[ ! -r "$cluster_var" ]]; then
      echo "Cluster variable file not found: $cluster_var"
      exit 1
   fi

   source "$cluster_var"

   yamlfile=$(mktemp -t)
   envsubst < "$cluster_template" > "$yamlfile"


   if _list_k3d_cluster | grep -q "$cluster_name"; then
      echo "Cluster $cluster_name already exists, skip"
   fi

   _create_k3d_cluster "$yamlfile"

   trap 'cleanup_on_success "$yamlfile"' EXIT
}

function cleanup_on_success() {
   file_to_cleanup=$1
   echo "Cleaning up temporary files..."
   if [[ $? == 0 ]]; then
      rm -rf "$file_to_cleanup"
   else
      echo "Error occurred, not cleaning up $file_to_cleanup"
   fi
}

function configure_k3d_cluster_istio() {
   cluster_name=$1

   istio_yaml_template="$(dirname $SOURCE)/etc/istio-operator.yaml.tmpl"
   istio_var="$(dirname $SOURCE)/etc/istio_var.sh"

   if [[ ! -r "$istio_yaml_template" ]]; then
      echo "Istio template file not found: $istio_yaml_template"
      exit 1
   fi

   if [[ ! -r "$istio_var" ]]; then
      echo "Istio variable file not found: $istio_var"
      exit 1
   fi

   source "$istio_var"
   isito_yamlfile=$(mktemp -t)
   envsubst < "$istio_yaml_template" > "$isito_yamlfile"

   install_kubernetes_cli
   install_istioctl
   _istioctl x precheck
   _istioctl install -y -f "$isito_yamlfile"
   _kubectl label ns default istio-injection=enabled --overwrite

   trap "cleanup_on_success $isito_yamlfile" EXIT
}


function install_smb_csi_driver() {
   if is_mac ; then
      echo "warning: SMB CSI driver is not supported on macOS"
      exit 0
   fi
   install_helm
   _helm repo add smb-csi-driver https://kubernetes-sigs.github.io/smb-csi-driver
   _helm repo update
   _helm upgrade --install smb-csi-driver smb-csi-driver/smb-csi-driver \
      --namespace kube-system

   if [[ $? != 0 ]]; then
      echo "Failed to install SMB CSI driver"
      exit 1
   fi
}

function create_nfs_share() {
   if grep -q "k3d-nfs" /etc/exports ; then
      echo "NFS share already exists, skip"
      return 0
   fi

   if is_mac ; then
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

function configure_user_kubectl_access() {
   cluster_name="${1:-k3d-cluster}"

   echo "Configuring kubectl access for non-root user..."

   # Create kube directory in user's home if it doesn't exist
   mkdir -p $HOME/.kube

   # Get kubeconfig from k3d and save it to user's directory
      _k3d kubeconfig get "$cluster_name" \
         > $HOME/.kube/config-"$cluster_name"

   # Set proper permissions
   chmod 600 $HOME/.kube/config-"$cluster_name"

   # Create/update the main config file
   if [ -f "$HOME/.kube/config" ]; then
      echo "Backing up existing kubeconfig to $HOME/.kube/config.bak"
      cp $HOME/.kube/config $HOME/.kube/config.bak
   fi

   cp $HOME/.kube/config-"$cluster_name" $HOME/.kube/config

   echo "kubectl is now configured for non-root access to $cluster_name"
   echo "You can verify with: kubectl get nodes"
   echo "If you have other clusters, you may want to merge configs using the KUBECONFIG environment variable"
}

function deploy_k3d_cluster() {
   cluster_name="${1:-k3d-cluster}"

   install_k3d
   create_k3d_cluster "$cluster_name"
   configure_k3d_cluster_istio "$cluster_name"
   configure_user_kubectl_access "$cluster_name"
   # install_smb_csi_driver
}
