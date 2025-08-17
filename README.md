# k3d-install - K3d Kubernetes Cluster Setup with Istio and Storage Support

A comprehensive utility script for setting up K3d Kubernetes clusters with Istio service mesh and storage configurations across different operating systems.

## Overview

This script automates the deployment of K3d Kubernetes clusters with the following features:
- Container runtime setup (Colima for macOS, native Docker for Linux)
- K3d cluster creation with optimized defaults
- Istio service mesh installation and configuration
- Storage options (NFS, SMB CSI driver support)
- Cross-platform support (macOS, RedHat/Fedora, Debian)

## Prerequisites

- macOS, RedHat-based, or Debian-based Linux distribution
- Bash shell
- Internet connection for downloading components
- Sudo/root access (for Linux installations)

## Quick Start

# Clone this repository
git clone https://github.com/yourusername/k3d-install.git
cd k3d-install

# Make script executable
chmod +x scripts/k3d-install

# Run default installation workflow
./scripts/k3d-install

# Or run a specific function
./scripts/k3d-install create_k3d_cluster my-cluster
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

USAGE:
  ./scripts/k3d-install                    # Run default installation workflow
  ./scripts/k3d-install <function> [args]  # Run specific function

FUNCTIONS:
  install_colima                   # Install Colima container runtime (macOS)
  install_docker                   # Install Docker CLI and configure it
  install_k3d                      # Install K3d Kubernetes distribution
  create_k3d_cluster <name>        # Create cluster with specified name
  configure_k3d_cluster_istio      # Install Istio on the cluster
  install_helm                     # Install Helm package manager
  install_smb_csi_driver           # Install SMB CSI driver (Linux only)
  create_nfs_share                 # Setup NFS export on host
  deploy_k3d_cluster <name> [args] # Deploy K3d cluster with optional args

ISTIO TESTING:
  test_istio                       # Istio functionality tests
```
## Troubleshooting

### Port Forwarding Issues
If you encounter port forwarding issues during testing, you may need to manually clean up orphaned processes:
```bash
# Find and kill processes using specific ports
lsof -ti:8080,8443 | xargs kill

### NFS Connection Problems
NFS connectivity issues between host and K3d containers are known on macOS. The script includes diagnostic functions to help troubleshoot.

## License

MIT

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.
