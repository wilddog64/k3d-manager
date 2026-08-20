# Bug: k3s-aws SSM readiness timeout bypasses SSH fallback

**Filed:** 2026-08-20
**Source:** live `make up` failure

## Observed output

```text
INFO: [k3s-aws] SSM tunnel mode active — ambient mesh (Cilium) unsupported this release; provisioning with flannel
INFO: [ssm] Waiting for i-0364bbde6f5e40a92 to appear Online in SSM...
ERROR: [ssm] Instance i-0364bbde6f5e40a92 did not become Online after 300s
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

## Root cause

The existing fallback in `_provider_k3s_aws_start_tunnel` handles failures while
starting the SSM port-forward. However, `deploy_app_cluster` enters
`_ssm_bootstrap_k3s` first when `K3S_AWS_SSM_ENABLED=true`; that function calls
`ssm_wait` for the server and each agent and returns non-zero on timeout. The
provider currently propagates that failure immediately, so execution never reaches
`_provider_k3s_aws_start_tunnel` and its SSH fallback.

## Recommended fix

Treat the SSM bootstrap as an optimistic transport attempt. If it fails, switch
`K3S_AWS_SSM_ENABLED=false`, log the reason, and retry `deploy_app_cluster --confirm`
through SSH. Provisioning should fail only when both the SSM bootstrap and the SSH
retry fail. Add provider BATS coverage for an SSM readiness timeout followed by a
successful SSH invocation, plus the existing both-transports-fail case.

This investigation did not modify the provider or deploy the sandbox.
