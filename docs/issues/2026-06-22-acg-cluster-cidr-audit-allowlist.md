# ACG CloudFormation template trips `_agent_audit` hardcoded-IP check

## What I tested

- Staged the Phase 1 lib-acg import into `scripts/lib/acg/`.
- Ran `_agent_audit` on the staged diff with the repo's normal audit path.

## Actual output

```text
WARN: Agent audit: hardcoded IP address in scripts/lib/acg/etc/acg-cluster.yaml — use a CoreDNS hostname instead:
WARN: 19:      CidrBlock: 10.0.0.0/16
38:      CidrBlock: 10.0.1.0/24
55:      DestinationCidrBlock: 0.0.0.0/0
103:          CidrIp: 10.0.0.0/16
```

## Root cause

`scripts/lib/acg/etc/acg-cluster.yaml` is a CloudFormation template that intentionally contains
CIDR literals for the ACG sandbox network. The repository's `_agent_audit` hardcoded-IP scan
flags any IPv4 literal in staged `.yaml` / `.yml` files, so this template is a false positive for
that policy.

## Recommended follow-up

- Document a repo-level `AGENT_IP_ALLOWLIST` path for intentional network templates like
  `scripts/lib/acg/etc/acg-cluster.yaml`.
- Keep the allowlist scoped to this template only so the audit still catches accidental IPv4
  literals elsewhere.
