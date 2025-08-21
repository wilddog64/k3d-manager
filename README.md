# K3d Installation Script

A comprehensive utility script for setting up K3d Kubernetes clusters with Istio service mesh and storage configurations across different operating systems.

## Overview

This script automates the deployment of K3d Kubernetes clusters with the following features:
- Container runtime setup (Colima for macOS, native Docker for Linux)
- K3d cluster creation with optimized defaults
- Istio service mesh installation and configuration
- Storage options (NFS, SMB CSI driver support)
- Cross-platform support (macOS, RedHat/Fedora, Debian)
- **Modular design:** Core functions are organized in separate files (`system.sh`, `test.sh`) for easier maintenance and extension.

## Prerequisites

- macOS, RedHat-based, or Debian-based Linux distribution
- Bash shell
- Internet connection for downloading components
- Sudo/root access (for Linux installations)

## Quick Start

```bash
# Clone this repository
git clone https://github.com/yourusername/k3d-manager.git
cd k3d-manager

# symlink k3d-manager script to a directory in your PATH
sudo ln -sf $(pwd)/scripts/k3d-manager /usr/local/bin/k3d-manager

# Run default installation workflow
k3d-manager

# Or run a specific function
k3d-manager create_k3d_cluster my-cluster
```
# Testing istio functionality
To test Istio functionality after deployment, you can run:
```bash
k3d-manager test_istio
```

## Project Structure

```
[ 38K]  .
├── [ 11K]  LICENSE
├── [4.0K]  README.md
└── [ 23K]  scripts
    ├── [1.6K]  etc
    │   ├── [  78]  cluster_var.sh
    │   ├── [ 465]  cluster.yaml.tmpl
    │   ├── [ 153]  istio_var.sh
    │   └── [ 748]  istio-operator.yaml.tmpl
    ├── [2.1K]  k3d-manager
    └── [ 19K]  lib
        ├── [4.4K]  core.sh
        ├── [9.3K]  system.sh
        └── [5.2K]  test.sh

```

## Supported Platforms

- **macOS**: Uses Colima as container runtime with Docker CLI
- **RedHat Family**: Fedora, CentOS, RHEL with native Docker
- **Debian Family**: Ubuntu, Debian with native Docker
- **WSL**: Basic support for Windows Subsystem for Linux

## Features

### Container Runtime Setup
- Automatic installation of Colima on macOS
- Docker CLI configuration
- Platform-specific optimizations

### K3d Cluster Creation
- Customizable cluster configuration
- LoadBalancer service exposure
- Traefik disabled by default (for Istio compatibility)
- Host-to-cluster networking

### Istio Integration
- Automatic Istio installation and configuration
- Resource-optimized profile for development environments
- Namespace injection setup
- Gateway and VirtualService configuration

### Storage Options
- NFS share setup and configuration
- SMB CSI driver installation (Linux only)

## Command Reference

```
USAGE:
  ./scripts/k3d-manager                    # Run default installation workflow
  ./scripts/k3d-manager <function> [args]  # Run specific function

FUNCTIONS:
  (See system.sh and test.sh for available system and test functions)
  install_colima                   # Install Colima container runtime (macOS)
  install_docker                   # Install Docker CLI and configure it
  install_k3d                      # Install K3d Kubernetes distribution
  create_k3d_cluster <name>        # Create cluster with specified name
  configure_k3d_cluster_istio      # Install Istio on the cluster
  install_helm                     # Install Helm package manager
  install_smb_csi_driver           # Install SMB CSI driver (Linux only)
  create_nfs_share                 # Setup NFS export on host
  deploy_k3d_cluster <name>        # Deploy K3d cluster with Istio and storage

ISTIO TESTING:
  test_istio                       # Istio functionality tests (see test.sh)
```

## Troubleshooting

### Port Forwarding Issues
If you encounter port forwarding issues during testing, you may need to manually clean up orphaned processes:

```bash
# Find and kill processes using specific ports
pkill -f "kubectl" # this will kill all kubectl port-forward processes
```

### NFS Connection Problems
NFS connectivity issues between host and K3d containers are known on macOS. The script includes diagnostic functions to help troubleshoot.

## License

[Apache License 2.0](LICENSE)

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.

