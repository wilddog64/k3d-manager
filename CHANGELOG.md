# Changelog

## [Unreleased]

### Fixed
- `bin/acg-up`: fix CoreDNS patch inserting duplicate `hosts {}` block — now merges into existing NodeHosts block instead of appending
- `bin/acg-up`: fix Keycloak cross-cluster tunnel targeting wrong node — use control-plane label selector instead of `items[0]` (which returns whichever node is listed first, usually an agent)
- `bin/acg-up`: fix realm JSON path for Keycloak cross-cluster tunnel (`identity/config/` → `identity/keycloak/`)
- `scripts/lib/providers/k3s-aws.sh`: add `timeout 60` to TTL extension pre-flight to prevent `make up` hanging indefinitely
- `bin/get-keycloak-password`: add new script to query Keycloak SSO user passwords from Vault

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
