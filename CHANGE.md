# Changes - k3d-manager

## Active Directory Integration - dated 2025-11-10

bda2bf3 k3d-manager::tests::jenkins: add Active Directory integration tests
b25f0a8 k3d-manager::plugins::jenkins: add production AD support with connectivity validation
32676f3 k3d-manager::jenkins: improve deployment reliability and observability
517edd7 k3d-manager::plugins::jenkins: add --enable-ad flag for AD schema testing
182d972 k3d-manager: add Jenkins authentication mode templates
ef1ef14 k3d-manager: improve deployment command consistency and AD DN configuration

### Features Added
- **Active Directory Testing Mode** (`--enable-ad`): Deploy OpenLDAP with AD schema for local testing
- **Production AD Integration** (`--enable-ad-prod`): Connect to production Active Directory servers
- **Pre-flight Validation**: Automatic DNS and LDAPS connectivity checks before deployment
- **Validation Bypass**: `--skip-ad-validation` flag for testing environments
- **Template-based Authentication**: Three distinct modes (default, AD testing, production AD)
- **Comprehensive Testing**: 8 new bats tests covering flag validation and mutual exclusivity

### Documentation
- Added Jenkins Authentication Modes section to README.md
- Updated CLAUDE.md with AD integration configuration details
- Documented all three authentication modes with usage examples

## Previous Releases - dated 2024-06-26

d509293 k3d-manager: release notes
598c4e6 test: cover Jenkins VirtualService headers
b89c02c docs: note Jenkins reverse proxy headers
f5ec68d k3d-manager::plugins::jenkins: setup reverse proxy
38d6d43 k3d-manager::plugins::jenkins: setup SAN -- subject alternative name
926d543 k3d-manager: change HTTPS_PORT dfault from 9443 to 8443
33f66f0 k3d-manager::plugins::vault: give a warning instead of bail out
482dcbe k3d-manager::plugins::vault: refactor _vault_post_revoke_request
64754f5 k3d-manager::plugins::vault: refactor _vault_exec to allow passing --no-exit, --perfer-sudo, and --require-sudo
7ae2a37 k3d-manager::plugins::vault: remove vault login from _vault_exec
8a37d38 k3d-manager::plugins::vault: add a _mount_vault_immediate_sc
499ff86 k3d-manager::plugins::vault: fix incorrect casing for wait condition
f350d11 Document test log layout
e3d0220 Refine test log handling
1bc3751 Document test case options
b510f3e Extend test runner CLI
a961192 k3d-manager: update k3s setup
43b1a93 Require sudo for manual k3s start
34a154a Test manual k3s start path
943bc83 Support k3s without systemd
5cda24d Stub systemd in bats
81ec87b Skip systemctl when absent
986c1c8 Cover sudo retry in tests
ce9d52b Guard sudo fallback in ensure
348b391 Improve k3s path creation fallback
a28c1b5 Ensure bats availability and fix Jenkins stubs
4d54a30 k3d-manager::tests::jenkins: set JENKINS_DEPLOY_RETRIES=1 in the failure test and relaxed stderr assert to match the updated error messages
edc251e k3d-manager::plugins::jenkins: add configurable retries, and cleanup failed pod between attempts
c1233b1 k3d-manager: guardrail pv/pvc mount
0e29a1e k3d-manager: make all mktemp come with namespace so we can clean leftover file easily
ec5f100 k3d-manager::tests::test_auth_cleanup: update _curl stub to follow the dynamic host
d0721e6 k3d-manager::test: jenkins tls check now respects VAULT_PKI_LEAF_HOST
9a19d04 k3d-manager::README: prune references and ctags entries for public wrappers
9366213 k3d-manager::plugins::jenkins: align with private helpers
f67eab9 k3d-manager::vault_pki: dropped the legacy extract_/remoovek_certificate_serial shims
a4d49f4 k3d-manager::cluster_provider: remove public wrappers
35d8301 Merge branch 'partial-working'
1f957db k3d-manager: update README and tags
2802acb k3d-manager::plugins::jenkins: switch internal calls to private vault helper from cert-rotator
0a7c327 k3d-manager::lib::vault_pki: add wrapper shims so the old function names can be call the new implementations
691cfa4 k3d-manager::lib/cluster_provider: resore original public cluster_provider_* to hide _prviate productions
8351f87 k3d-manager: update tags
4161077 k3d-manager: update README
f894ab9 k3d-manager::tests::vault: update call _vault_pki_extract_certificate_serial in assertions
7354361 k3d-manager::plugins::vault: swap to _vault_pki_* helpers after issuing or revoking certs
0886973 k3d-manager::plugins::jenkins: check _cluster_provider_is instead of the older public helper
6ca07c9 k3d-manager::plugins::jenkins: reused the private vault helpers
0094a95 k3d-manager::core::vault_pki: prefix serial helpers with _vault_pki_* to mark them private
fc952fb k3d-manager::core:: use a logger fallback in _cleanup_on_success and updated the provider setter call
8b64182 k3d-manager: switch to new _cluster_provider_* entry points
1005b9d k3d-manager::cluster_provider: scope cluster-provider helpers as private functions
dee3b23 k3d-manager::tests::test_helpers: rework read_lines fallback to avoid mapfile/printf incompatiblities
b6f3bb8 k3d-manager::tests::install_k3s: new test harness verifying _install_k3s
8befa5d k3d-manager::tests::vault: swap mapfile usage for the portable helper to keep vault tests
ad6abff k3d-manager::tests::jenkins: harden trap parsing for MacOS bash 3 edge cases
8fdadd9 k3d-manager::tests::deploy_cluster: avoid mapfile, and a python envsubst stub
eb5476e k3d-manager::plugins::jenkins: hardened trap parsing for MacOS bash 3 edge cases
e7a9b80 k3d-manager::vault_pki: replace bash-4 uppercase expand with portble tr call
68b6bcc k3d-manager::plugins::jenkins: made logging portable, resolved kubectl override via share helper
0e08c14 k3d-manager::provider::k3s: ensure provider install/deploy paths pass the cluster name
7b6913b k3d-manager::core:: add k3s assert staging, config rendering, and instller wiring
cd09d45 k3d-manager: remove https
2589792 k3d-manager: update AGENTS.md
5e6875d k3d-manager: add AGENTS.md
3d6a31d k3d-manager: use k3d.internal
7a3f38a k3d-manager::plugins::jenkins: update helm values.yaml to use controller.probes structure
2378f84 k3d-manager::plugins::jenkins: update helm value to use current probes structure
d22a79c k3d-manager::plugins::jenkins: remove duplicate functions
73501d4 k3d-manager::tests::jenkins: update test cases
be54ca2 k3d-manager::plugins::jenkins: update kubectl discovery helpers
132d6ab k3d-manager::plugins::jenkins: remove invalid syntax from cert-rotator.sh
