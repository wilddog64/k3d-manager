# k3s-aws SSM registration timeout must fall back to SSH

**Status:** Fixed on `k3d-manager-v1.26.0`
**Discovered:** 2026-08-20
**Component:** `scripts/lib/providers/k3s-aws.sh`

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` selected SSM and stalled while waiting for
the server to register. The provider previously returned failure after 150
seconds instead of trying the working SSH transport.

## Evidence

The affected instance was healthy but absent from SSM:

```text
EC2: running; system status: ok; instance status: ok
SSM InstanceInformationList: []
```

The latest EC2 console output identified the account-level configuration gap:

```text
SSM Agent unable to acquire credentials: <error>no valid credentials could be retrieved for ec2 identity.
Default Host Management Err: error calling RequestManagedInstanceRoleToken: AccessDeniedException: Systems Manager's instance management role is not configured for account: 218085830935
status code: 400
```

## Root cause

The provider treated an attached instance profile as proof that SSM was usable.
The account's Systems Manager Default Host Management Role was not configured,
so the agent could not obtain credentials or register with SSM.

## Fix

Tunnel setup now treats SSM as an optimistic transport choice. Registration or
SSM tunnel failure switches to autossh/SSH. The provider returns failure only
when the SSH fallback also fails. SSM success remains unchanged.

The account-level Default Host Management Role is still recommended for SSM
use, but it is no longer a provisioning prerequisite.
