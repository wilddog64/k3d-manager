# Cluster status screenshot: transient ESO parse errors and thread delivery follow-up

## Observed output

The captured Slack status reported:

```text
Cluster status: FAIL — k3s-hostinger (7 ok / 9 warn / 5 fail)
ESO ClusterSecretStore: Expecting value: line 1 column 1 (char 0)
ESO ExternalSecrets: Expecting value: line 1 column 1 (char 0)
Hub ESO ClusterSecretStore: Expecting value: line 1 column 1 (char 0)
Hub ESO ExternalSecrets: Expecting value: line 1 column 1 (char 0)
Data layer: 4 not ready: postgresql-orders, postgresql-payment
```

The report also appeared as a top-level Slack message, so the channel-aware threading fix could
not be confirmed from this capture.

## Live verification

Immediately afterward, the read-only full status check returned:

```text
✅ ESO ClusterSecretStore: Ready=True
✅ ESO ExternalSecrets: 20/20 synced
✅ Hub ESO ClusterSecretStore: Ready=True
✅ Hub ESO ExternalSecrets: 9/9 synced
✅ Data layer: 4/4 ready
Overall: HEALTHY
```

This indicates a transient empty/non-JSON probe response. The existing v1.35.0 health-probe
diagnostics specification covers preserving the command exit code and bounded stderr so this case
can be distinguished from a real ESO outage. No ESO remediation was performed.

## Follow-up

- Reproduce `/cluster-status` after the webhook restart and verify the response is a thread reply.
- Preserve the underlying ESO command exit code and redacted stderr when JSON parsing fails.
