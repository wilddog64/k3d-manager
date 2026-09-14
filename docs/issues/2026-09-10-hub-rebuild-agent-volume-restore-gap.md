# Hub rebuild lacks an agent-volume restore procedure

## What was inspected

Before the authorized datastore rebuild, the live k3d topology and rendered
cluster configuration were inspected read-only.

```text
NAME                       ROLE           CLUSTER       STATUS
k3d-k3d-cluster-agent-0    agent          k3d-cluster   running
k3d-k3d-cluster-agent-1    agent          k3d-cluster   running
k3d-k3d-cluster-agent-2    agent          k3d-cluster   running
k3d-k3d-cluster-server-0   server         k3d-cluster   running
k3d-k3d-cluster-serverlb   loadbalancer   k3d-cluster   running
```

The configured create path is:

```yaml
servers: 1
agents: 3
```

The server's K3s datastore is one Docker volume, while durable claims are
`local-path` data under the agent storage trees. Those include Keycloak/LDAP,
Vault, Trivy, and Prometheus data.

## Root cause

The controlled-rebuild plan described replacing the server datastore and
rejoining agents, but k3d's standard create path creates new agent containers.
It does not adopt the old agents or map old local-path PVC directories to the
new PVC UIDs. A normal cluster delete/create therefore risks making the captured
agent storage unreachable despite retaining the Docker volumes.

## Impact

The external-copy/checksum gate remains necessary but is not sufficient. The
destructive rebuild is blocked until a restore procedure maps every captured
durable claim to its newly provisioned local-path destination and proves data
ownership/permissions before workloads start.

## Recommended follow-up

1. Derive a claim-name-to-source-directory manifest from the captured PV/PVC
   export and agent storage backup.
2. Render a disposable restore rehearsal that creates a new cluster without
   deleting the existing cluster or volumes.
3. Reapply desired state, identify each newly assigned local-path directory,
   restore the mapped source data with services scaled down, and verify Vault,
   Keycloak/LDAP, and Prometheus ownership.
4. Only then authorize the live server-datastore replacement.

No hub resource, container, volume, PVC, or datastore was changed by this
inspection.
