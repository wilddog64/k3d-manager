# Changelog

## [Unreleased]

### Fixed
- `bin/acg-up`: add Step 10g.5 to wire Keycloak cross-cluster reachability on ubuntu-k3s via SSH reverse tunnel + iptables DNAT + CoreDNS patch

## [1.4.5] - 2026-05-10

### Added
- ACG AWS sandbox provisioning (`acg_provision`, `acg_extend`, `acg_teardown`)
- LoadBalancer ingress for ArgoCD, Keycloak, Jenkins
- Plugin architecture with lazy loading

### Fixed
- Vault PKI bootstrap on cluster up

## [1.4.0] - 2026-05-01

### Added
- Initial release
