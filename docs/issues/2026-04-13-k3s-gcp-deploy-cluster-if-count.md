# Issue: `_provider_k3s_gcp_deploy_cluster` exceeds if-count threshold

**Function:** `_provider_k3s_gcp_deploy_cluster`
**File:** `scripts/lib/providers/k3s-gcp.sh`
**Current if-count:** 9 (threshold = 8)

This function orchestrates the full GCP deploy flow (SSH key generation, credential
load, pre-flight checks, instance creation, firewall setup, ssh/k3sup probes, kubeconfig
merge, node labeling, etc.). Multiple recent bugfixes added more guards, pushing the
`if` count to 9. Refactoring it requires splitting major phases into helpers, which is
out of scope for the current bugfix.

**Action:** Add this function to `scripts/etc/agent/if-count-allowlist` as a temporary
exception. Schedule a follow-up refactor (e.g., break out SSH/key generation, gcloud
pre-flight, and k3sup install into helpers) to bring the `if` count ≤ 8.
