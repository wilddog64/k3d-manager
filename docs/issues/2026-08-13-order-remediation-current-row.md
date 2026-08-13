# Order remediation row remains after deployment advanced

## Investigation

The live dashboard shows one order `failed` row and two payment `superseded`
rows. The order ConfigMaps contain five failures from August 6 with target
image `shopping-cart-order:sha-05ce65...@sha256:a8813e...` and reason
`ready_pod_digest_mismatch` (the pre-v1.23 multi-arch verifier behavior).

The live order Deployment is:

```text
order-service  ghcr.io/wilddog64/shopping-cart-order:sha-564ccfd24c38cc906b18befd12b4d5747cc861cf  1  1
```

The current inventory for that image contains three `UNKNOWN`-severity
findings (`CVE-2026-40200` and `CVE-2026-56852` across packages), not the old
critical CVE set in the failed remediation event.

## Conclusion

The order row is a historical failed promotion whose target image was later
replaced by a normal deployment rollout. It is not evidence that the current
order pod is running the failed target image, but the event ledger has no later
`applied` event for that service/image lineage, so the dashboard correctly
keeps it visible as the latest recorded event.

## Implemented follow-up

The exporter now compares failed event `to_image` against the current inventory
image and exposes `state="deployment_advanced"` when the workload has moved on.
The live current-status metrics now show:

```text
shopping-cart-order  state="deployment_advanced"  current="true"
shopping-cart-payment state="applied"             current="true"
```

Audit ConfigMaps remain retained.
