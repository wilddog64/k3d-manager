# Issue: Argo CD browser TLS bootstrap should not fail when the previous cert is already gone

## Summary
During `make up`, the browser TLS bootstrap reached the certificate cleanup path and reported that the previous cert serial could not be found, then still attempted a revoke:

```text
use_csr_sans                          true
use_pss                               falseWARN: [vault] certificate with serial_number 51:25:70:79:23:4B:FF:60:C6:CB:E9:DB:F7:AE:64:58:CE:41:1C:02 not found at pki/cert/
Key                        Value
---                        -----
revocation_time            1778551585
revocation_time_rfc3339    2026-05-12T02:06:25.282337446Z
state                      revokedmake: *** [up] Error 1
```

## Root Cause
The Vault revoke helper was still issuing a revoke request even when the serial lookup already showed that the cert no longer existed under `pki/cert/`. That made the cleanup path too eager for a rebuild scenario where the prior cert had already been replaced or revoked by an earlier run.

## Fix
- [`scripts/plugins/vault.sh`](/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/plugins/vault.sh) now treats a missing cert serial as a best-effort cleanup case and returns success without attempting the revoke write.
- [`scripts/tests/plugins/vault.bats`](/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/tests/plugins/vault.bats) now covers the missing-cert path so the cleanup helper cannot abort bootstrap again.

## Verification
- `shellcheck -S warning scripts/plugins/vault.sh scripts/plugins/argocd.sh`
- `bats scripts/tests/plugins/vault.bats scripts/tests/plugins/argocd.bats`
- `_agent_audit`
