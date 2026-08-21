# Bug: dns short-circuit advice incomplete

**Filed:** 2026-06-06
**Source:** /ask agent observation

## Description

The _analyze_failure short-circuit for host.k3d.internal returns /acg-refresh advice but acg-refresh does not restore CoreDNS host injection. The real fix requires patching the CoreDNS ConfigMap or restarting k3d with correct host args.
