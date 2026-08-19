# Grafana remediation-success panels dropped affected-app attribution

## Observed behavior

The CVE Auto-Patch dashboard showed a remediation success count, but hovering the success visualization
did not identify the shopping-cart app that had been remediated.

The durable remediation event metric did contain that data. At investigation time, it reported verified
applied events for `shopping-cart-payment` and `shopping-cart-product-catalog` through the
`exported_service` label.

## Root cause

Panels **Remediation Jobs Succeeded** and **Remediation Jobs (cve-auto-*) Outcomes** used
`sum(kube_job_status_succeeded{...})`. The aggregation removed `job_name`, and Kubernetes Job metrics
expire after their Jobs are removed. The panels therefore retained only a count and could not expose an
app name in a Grafana tooltip.

## Fix

The success series now uses the retained `cve_remediation_state{state="applied",current="true"}` event
metric grouped by `exported_service`. The stat panel displays the service name with its value, and the
outcomes chart preserves the same label for its legend and hover tooltip. Persistent event records remain
the attribution source after the underlying Kubernetes Job has expired.
