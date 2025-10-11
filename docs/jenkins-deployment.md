# Jenkins Deployment Guide

## Vault PKI setup

The Vault plugin in [`scripts/plugins/vault.sh`](scripts/plugins/vault.sh) automates the entire PKI bootstrap that Jenkins and other services need. When you run `./scripts/k3d-manager deploy_vault ha`, the plugin installs the Helm chart, initialises and unseals the HA cluster, enables the Kubernetes auth method and only then evaluates the PKI helpers. Once Vault is healthy, `_vault_setup_pki` runs (if `VAULT_ENABLE_PKI=1`) to mount PKI, generate the root CA and provision the requested role before `_vault_pki_issue_tls_secret` optionally writes a Kubernetes TLS secret.

### Configuration knobs

You can override the defaults by exporting the variables before calling the plugin or by editing the helper files under `scripts/etc`.

**`scripts/etc/vault/vars.sh`**

| Variable | Default | Purpose |
| --- | --- | --- |
| `VAULT_ENABLE_PKI` | `1` | Toggle the entire PKI bootstrap routine. |
| `VAULT_PKI_PATH` | `pki` | Mount path for the PKI secrets engine (for example, `pki` vs `pki_int`). |
| `VAULT_PKI_ROLE` | `jenkins-tls` | Name of the Vault role that will issue leaf certificates. |
| `VAULT_PKI_CN` | `dev.local.me` | Common name used when generating the root CA. |
| `VAULT_PKI_MAX_TTL` | `87600h` | Maximum lifetime for the root CA (10 years by default). |
| `VAULT_PKI_ROLE_TTL` | `720h` | Maximum lifetime for leaf certificates issued by the role. |
| `VAULT_PKI_ALLOWED` | *(empty)* | Comma-separated list of allowed domains/SANs for the role; an empty value allows any host. |
| `VAULT_PKI_ENFORCE_HOSTNAMES` | `true` | Whether Vault should enforce hostname validation when issuing leaf certs. |

**`scripts/etc/jenkins/jenkins-vars.sh`**

| Variable | Default | Purpose |
| --- | --- | --- |
| `VAULT_PKI_ISSUE_SECRET` | `1` | Immediately mint a TLS secret after PKI is ready. |
| `VAULT_PKI_SECRET_NS` | `istio-system` | Namespace where the TLS secret will be written. |
| `VAULT_PKI_SECRET_NAME` | `jenkins-tls` | Name of the Kubernetes `tls` secret to create. |
| `VAULT_PKI_LEAF_HOST` | `jenkins.dev.local.me` | Common name/SAN for the leaf certificate request (also used as the default VirtualService host). |
| `JENKINS_VIRTUALSERVICE_HOSTS` | *(empty)* | Optional comma-separated list of hosts to render into the Istio `VirtualService`; defaults to `VAULT_PKI_LEAF_HOST`. |

The rendered Istio VirtualService now sets `X-Forwarded-Proto` and `X-Forwarded-Port` headers so Jenkins generates HTTPS links when requests traverse the shared Istio ingress gateway. If you supply a custom `virtualservice.yaml.tmpl`, keep those headers and ensure the destination port stays aligned with the Helm chart's `controller.servicePort` (default `8081`).

> **Note:** When `VAULT_PKI_ALLOWED` is not provided, the Jenkins plugin derives the Vault role's `allowed_domains` from `VAULT_PKI_LEAF_HOST`. Domains under `nip.io` and `sslip.io` are automatically permitted so dynamic DNS entries continue to validate without manual configuration.

### Jenkins deployment prerequisites

The Jenkins plugin renders Istio and workload manifests from templates using `envsubst`. Before running `./scripts/k3d-manager deploy_jenkins`, ensure the GNU gettext package (for `envsubst`) and the LastPass CLI (`lpass`) are installed and on your `PATH`. The helper will attempt to install both automatically via Homebrew/apt/dnf when they are missing; if that fails (for example, due to missing sudo or offline hosts) use the manual commands below.

| Platform | Installation command |
| --- | --- |
| macOS | `brew install gettext lastpass-cli` <br/>`brew link --force gettext` |
| Debian/Ubuntu | `sudo apt install gettext-base lastpass-cli` |
| Fedora/RHEL/CentOS | `sudo dnf install gettext lastpass-cli` |

### LastPass-backed Active Directory credentials

`deploy_jenkins` seeds the Vault secret `secret/jenkins/ad-ldap` before Helm runs. By default it pulls the bind DN and password from the PACIFIC LastPass entry for `svcADReader` using the local LastPass CLI, so make sure `lpass` is installed, on your `PATH`, and already authenticated (`lpass status`). The helper writes the credentials to Vault over `kubectl exec` without echoing them to the terminal.

If the sync step fails, rerun `bin/sync-lastpass-ad.sh` to populate the secret manually and then invoke `deploy_jenkins` again. Operators can opt out of the automatic sync with `deploy_jenkins --no-sync-from-lastpass` when testing or working against a fixture vault.

### Dynamic build agents

`deploy_jenkins` seeds two Kubernetes pod templates via Jenkins Configuration-as-Code. Each template is marked `EXCLUSIVE`, so jobs must request the matching label:

- `linux-build-agent` uses the controller-configured JNLP image (`jenkins/inbound-agent:latest`) and provides a plain Linux workspace for traditional builds.
- `powershell-build-agent` relies on the same auto-injected JNLP container but adds a `pwsh` sidecar (`mcr.microsoft.com/powershell:lts-debian-11`) for PowerShell-heavy pipelines.

Both templates run under the `jenkins` service account, derive the namespace via the downward API, and keep the controller free of build work (the Helm values set `numExecutors` to `0`). Target either agent with `agent { label '...' }` in your Jenkinsfile to launch ephemeral pods inside the cluster.

### Disconnected clusters and preloaded charts

Air-gapped environments can still deploy the Jenkins and External Secrets Operator stacks by downloading the Helm charts ahead of time and pointing the plugins at the local files. From a workstation with network access:

```bash
mkdir -p ~/k3d-manager-charts
helm pull external-secrets/external-secrets \
  --repo https://charts.external-secrets.io \
  --destination ~/k3d-manager-charts
helm pull jenkins/jenkins \
  --repo https://charts.jenkins.io \
  --destination ~/k3d-manager-charts
```

Copy the resulting `.tgz` archives to a location the disconnected operators can read, then export the overrides before running `deploy_eso` or `deploy_jenkins`:

```bash
export ESO_HELM_CHART_REF=/opt/charts/external-secrets-<version>.tgz
export ESO_HELM_REPO_URL=
export JENKINS_HELM_CHART_REF=/opt/charts/jenkins-<version>.tgz
export JENKINS_HELM_REPO_URL=
```

When the chart reference resolves to a local path—or when the repo URL is empty or also points at local storage—the plugins skip `_helm repo add` and `_helm repo update`, allowing the deployment to proceed without reaching the public repositories. Operators that mirror the charts internally can instead set `ESO_HELM_REPO_URL` or `JENKINS_HELM_REPO_URL` to their mirror and adjust the chart reference to match.
