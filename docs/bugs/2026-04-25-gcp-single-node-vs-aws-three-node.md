# Gap: GCP provider is single-node; AWS provider is 3-node

**Branch:** `k3d-manager-v1.2.0`
**File:** `scripts/lib/providers/k3s-gcp.sh`

## Description

AWS (`k3s-aws`) provisions a 3-node k3s cluster via CloudFormation:
1 server EC2 + 2 agent EC2s (`_ACG_INSTANCE_TYPE=t3.medium`).

GCP (`k3s-gcp`) provisions a single-node k3s cluster:
1 server GCE instance (`_GCP_MACHINE_TYPE=e2-standard-2`), no agents.

This is an inconsistency — the two providers behave differently for no
architectural reason. GCP was implemented as a minimal proof of concept.

## Required Work

To bring GCP to parity with AWS:
1. Add `_gcp_create_agent_instance` — create 2 agent GCE instances
2. Add `_gcp_k3sup_join` — join agents to server via k3sup
3. Update `_provider_k3s_gcp_deploy_cluster` to call both
4. Update `_provider_k3s_gcp_destroy_cluster` to delete agent instances

## Status

OPEN — no stress testing done to justify 3-node GCP yet; tracked for
consistency once GCP E2E smoke test is verified.
