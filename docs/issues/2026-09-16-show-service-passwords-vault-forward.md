# `show-service-passwords` returned `N/A` while Vault was reachable only in-cluster

## Symptom

The command printed no passwords:

```text
ArgoCD      https://argocd.3ai-talk.org
  user:     admin
  password: N/A
Grafana     https://grafana.3ai-talk.org
  user:     admin
  password: N/A
Prometheus  https://prometheus.3ai-talk.org
  user:     admin
  password: N/A
Alertmanager https://alertmanager.3ai-talk.org
  user:     admin
  password: N/A
Keycloak    https://keycloak.3ai-talk.org
  admin user:     admin / N/A
  dev users:      admin / N/A  |  developer / N/A  |  operator / N/A
```

## Investigation

`Makefile:show-service-passwords` reads the display credentials through the local Vault API at `http://127.0.0.1:18200`. When checked afterward, the Vault port-forward LaunchAgent was running and listening on both loopback families:

```text
gui/501/com.k3d-manager.vault-port-forward = { state = running }
TCP 127.0.0.1:18200 (LISTEN)
TCP [::1]:18200 (LISTEN)
```

Re-running `make show-service-passwords` then resolved the credentials. No service credential rotation was needed.

## Root cause

The original `N/A` output was a transient local Vault port-forward failure (or restart window). The target suppresses Vault/curl/JSON errors and substitutes `N/A`, so it does not distinguish an unavailable local Vault API from a missing Vault field.

## Recovery

Run:

```text
make install-vault-port-forward
make show-service-passwords
```

The first command reinstalls/bootstraps `com.k3d-manager.vault-port-forward`; the second verifies the display mirrors without exposing them in logs or documentation.

## Follow-up

Consider changing the target to print a concise `Vault unavailable (run make install-vault-port-forward)` diagnostic while retaining `N/A` only for an actual missing field. Do not print Vault tokens or credential values in diagnostics.
