# `make status` Grafana login false 401

## Finding

The smoke check posted credentials to the Hub URL `https://grafana.3ai-talk.org`
but read `acg-kube-prometheus-stack-grafana` from the app-cluster context. That
Secret belongs to a different Grafana instance and produced HTTP 401.

## Resolution

The check now reads Hub `monitoring/grafana-admin-credentials`, the
Vault/ExternalSecret-managed Secret used by the Hub Grafana deployment. It no
longer passes the app-cluster context for this Hub URL.

