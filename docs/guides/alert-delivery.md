# Alert delivery

Alertmanager is intentionally default-deny: the root route receiver is `null`, and child routes
are the explicit exits. Warning alerts now have a general `severity = warning` exit after the
named warning allowlist, so the allowlist keeps its faster timing while unnamed warnings still
reach `platform-warning`.

The rendered route tree is what matters. The template in
`scripts/etc/prometheus/alertmanager.yaml.tmpl` becomes the generated Secret named
`alertmanager-<alertmanager-name>-generated`; inspect that Secret rather than only the template.
The renderer also refuses success when an Alertmanager CR names a missing `configSecret`.

## Confirm delivery

1. Check the CR's `spec.configSecret`, then verify that Secret exists in `monitoring`.
2. Inspect the generated Secret's config and confirm it has child routes and a receiver with an
   `email_configs` or other delivery configuration. The only key is `alertmanager.yaml.gz`, which is
   base64 **and** gzipped — there is no plain `alertmanager.yaml` key, so a reader that asks for one
   silently gets an empty config that looks like a total blackout:

   ```bash
   kubectl -n monitoring get secret alertmanager-<name>-generated \
     -o jsonpath='{.data.alertmanager\.yaml\.gz}' | base64 -d | gunzip
   ```
3. Confirm the alert is firing in Prometheus, then check Alertmanager's notification logs. The
   `notifications_total` metric counts attempts, not successful receipt.
4. Run `bin/k3dm-alert-delivery-status --json` for the read-only route-tree shape across the hub
   and registered app-cluster contexts. Hermes reports a confirmed blackout after one cycle.

## Triage: an alert is firing in Prometheus but no mail arrived

| Symptom | Check | Remedy |
|---|---|---|
| Alertmanager delivers nothing on one cluster | The CR references a `configSecret` that does not exist | `kubectl -n monitoring get alertmanager -o jsonpath='{.items[0].spec.configSecret}'` then `get secret` on that name; seed the credentials and render the Secret |
| A warning is firing but no notification is queued | The generated route tree has no `severity = warning` child route | Reapply the observability template and inspect the generated Secret |
| The generated tree has a null root and no children | The generated Secret is stale or was generated from the operator fallback | Restore the referenced config Secret, re-render, and verify the generated route tree |
| Alertmanager shows notification attempts but no message arrived | SMTP logs, recipient address, and provider delivery status | Fix the SMTP or recipient-side failure; configuration alone cannot prove receipt |
