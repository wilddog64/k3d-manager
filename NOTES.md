  # v1.1.0

  ## Highlights
  - Jenkins plugin now fronts through an Istio reverse
  proxy, carries the correct SAN entries, and offers
  configurable deployment retries with automatic cleanup of
  failed pods.
  - Vault helpers were consolidated to a new private
  API, adding immediate service-account mounts, richer
  `_vault_exec` flags, and warning-only pre-checks for
  smoother recovery.
  - k3s provisioning works without systemd, tightens sudo
  guardrails, and hardens path creation so installs succeed
  on a wider range of hosts.

  ## Upgrade Notes
  - Default `HTTPS_PORT` changed to `8443` (was `9443`);
  override `HTTPS_PORT` if you depend on the previous
  mapping.
  - Jenkins PV/PVC mounts now have guard rails—confirm
  that your environment explicitly enables the mount if you
  expect it.

  ## Detailed Changes

  ### Jenkins
  - Added an Istio VirtualService reverse proxy and
  propagated SAN configuration to align TLS with the new
  front door.
  - Introduced configurable deployment retries and cleaned
  up broken pods between attempts.
  - Unified usage of the new private Vault helpers,
  improving certificate rotation and shared logging.
  - Hardened kubectl discovery, trap parsing, and logging
  for macOS/bash 3 compatibility.
  - Documented the reverse proxy headers and covered them
  with tests.

  ### Vault
  - Renamed and privatized PKI helpers, adding shim
  wrappers so legacy names still resolve.
  - Extended `_vault_exec` with `--no-exit`, `--prefer-
  sudo`, and `--require-sudo` flags for better
  orchestration control.
  - Added `_mount_vault_immediate_sc`, refined revoke
  handling, and fixed wait-condition casing.
  - Downgraded Vault pre-check failures to warnings,
  preventing unnecessary aborts.

  ### k3s / Cluster Provider
  - Passed cluster names through install/deploy paths,
  added staging assertions, and improved path fallback
  logic.
  - Required sudo for manual k3s starts, added tests for
  that path, and supported hosts without `systemd`.
  - Skipped `systemctl` when absent, improved `mktemp`
  naming, and guarded PV/PVC mounts to avoid accidental
  attachment.
  - Cleaned up provider wrappers, steering consumers to the
  private entry points.

  ### CLI & Test Harness
  - Expanded `scripts/k3d-manager` with richer CLI options,
  better test selection, and clearer output.
  - Documented test case options and log layout; refined
  log handling to make failures easier to triage.
  - Added new bats coverage for k3s install, sudo retry
  paths, Jenkins deployment resilience, and Vault cleanup
  flows.
  - Ensured bats availability, provided a portable envsubst
  stub, and replaced mapfile usage for cross-platform
  compatibility.

  ### Documentation
  - Updated README guidance, trimmed stale references, and
  refreshed tag listings.
  - Noted the Jenkins reverse proxy headers and adjusted
  ctags/entry references.

  ## Contributors
  - chengkai liang (@wilddog64)