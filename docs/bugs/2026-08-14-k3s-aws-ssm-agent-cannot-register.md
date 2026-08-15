# k3s-aws provisioning waits for an SSM agent that never registers

**Status:** Open
**Discovered:** 2026-08-14
**Component:** `scripts/lib/providers/k3s-aws.sh` SSM tunnel bring-up

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` reached the SSM tunnel phase and remained at:

```text
INFO: [k3s-aws] SSM tunnel mode active — ambient mesh (Cilium) unsupported this release; provisioning with flannel
INFO: [ssm] Waiting for i-015dbcd49b4f8eec6 to appear Online in SSM...
```

The ambient-mesh/flannel message is informational. The blocker is the missing SSM
registration. The provider's wait helper polls `PingStatus` every five seconds and
returns an error after 30 attempts (150 seconds).

## Evidence (2026-08-14)

The local provisioning process was observed waiting, then exited. Read-only AWS
checks showed the instance was running and healthy, but SSM had no managed-instance
record:

```text
{
    "InstanceInformationList": []
}
```

EC2 state and profile:

```text
{
    "State": "running",
    "Profile": "arn:aws:iam::525259624675:instance-profile/k3d-manager-cluster-ssm-profile",
    "Subnet": "subnet-08d2dcf9d994d5b4b",
    "PrivateIp": "10.0.1.204",
    "PublicIp": "54.190.133.35"
}
```

The profile association was reported as `associated`; its role was
`k3d-manager-cluster-ssm-role`, with `AmazonSSMManagedInstanceCore` attached and an
EC2 trust relationship. EC2 system and instance checks were both `ok`.

The instance console output identified the registration failure:

```text
SSM Agent unable to acquire credentials: <error>no valid credentials could be retrieved for ec2 identity.
Default Host Management Err: error calling RequestManagedInstanceRoleToken:
AccessDeniedException: Systems Manager's instance management role is not configured for account: 525259624675
</error>
```

## Root cause

The SSM agent starts, but cannot obtain usable instance credentials and therefore
never calls home to Systems Manager. The attached instance profile appears correct
from the control plane, so the remaining gap is the instance-side credential path
(profile propagation/IMDS access or agent startup ordering) and must be verified on
the host. Without an SSM managed-instance record, `ssm_tunnel` cannot start.

## Impact

Fresh SSM-mode k3s-aws provisioning cannot continue past tunnel setup. This is a
bring-up blocker; the flannel fallback itself is not the cause.

## Recommended follow-up

1. Add a preflight that verifies the instance profile association and waits for
   `PingStatus=Online` with an actionable diagnostic when it times out.
2. On a reproduced instance, verify IMDS credential retrieval and the
   `amazon-ssm-agent` service/log before retrying; recreate the instance if profile
   propagation did not complete at launch.
3. Confirm the account's SSM instance-management configuration and required network
   egress/endpoints, then add a provider BATS regression for the empty SSM response
   and timeout path.

No live mutation or deployment was performed while investigating this issue.
