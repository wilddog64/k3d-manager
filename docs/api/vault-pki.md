# Vault PKI Reference

The Vault plugin (`scripts/plugins/vault.sh`) automates the entire PKI bootstrap that Jenkins and other services need. When you run `./scripts/k3d-manager deploy_vault`, the plugin installs the Helm chart, initialises and unseals the HA cluster, enables Kubernetes auth, and then runs the PKI helpers. `_vault_setup_pki` runs (if `VAULT_ENABLE_PKI=1`) to mount PKI, generate the root CA, and provision the requested role. `_vault_pki_issue_tls_secret` then optionally writes a Kubernetes TLS secret.

---

## Configuration Variables

### `scripts/etc/vault/vars.sh`

| Variable | Default | Purpose |
|---|---|---|
| `VAULT_ENABLE_PKI` | `1` | Toggle the entire PKI bootstrap routine |
| `VAULT_PKI_PATH` | `pki` | Mount path for the PKI secrets engine (e.g. `pki` vs `pki_int`) |
| `VAULT_PKI_ROLE` | `jenkins-tls` | Name of the Vault role that issues leaf certificates |
| `VAULT_PKI_CN` | `dev.local.me` | Common name used when generating the root CA |
| `VAULT_PKI_MAX_TTL` | `87600h` | Maximum lifetime for the root CA (10 years) |
| `VAULT_PKI_ROLE_TTL` | `720h` | Maximum lifetime for leaf certificates |
| `VAULT_PKI_ALLOWED` | *(empty)* | Comma-separated allowed domains/SANs; empty = allow any host |
| `VAULT_PKI_ENFORCE_HOSTNAMES` | `true` | Whether Vault enforces hostname validation on leaf certs |

### `scripts/etc/jenkins/jenkins-vars.sh`

| Variable | Default | Purpose |
|---|---|---|
| `VAULT_PKI_ISSUE_SECRET` | `1` | Immediately mint a TLS secret after PKI is ready |
| `VAULT_PKI_SECRET_NS` | `istio-system` | Namespace where the TLS secret will be written |
| `VAULT_PKI_SECRET_NAME` | `jenkins-tls` | Name of the Kubernetes `tls` secret to create |
| `VAULT_PKI_LEAF_HOST` | `jenkins.dev.local.me` | Common name/SAN for the leaf certificate request |
| `JENKINS_VIRTUALSERVICE_HOSTS` | *(empty)* | Optional comma-separated hosts for the Istio VirtualService; defaults to `VAULT_PKI_LEAF_HOST` |

> When `VAULT_PKI_ALLOWED` is not provided, the Jenkins plugin derives `allowed_domains` from `VAULT_PKI_LEAF_HOST`. Domains under `nip.io` and `sslip.io` are automatically permitted.

---

## Example Workflow

```bash
# 1. Export overrides
export VAULT_ENABLE_PKI=1
export VAULT_PKI_PATH=pki_int
export VAULT_PKI_CN="dev.local.me"
export VAULT_PKI_ALLOWED="jenkins.dev.local.me,*.dev.local.me"
export VAULT_PKI_ENFORCE_HOSTNAMES=true
export VAULT_PKI_SECRET_NS=istio-system
export VAULT_PKI_SECRET_NAME=jenkins-tls
export VAULT_PKI_LEAF_HOST=jenkins.dev.local.me

# 2. Deploy Vault — initialises, configures PKI, generates CA, creates TLS secret
./scripts/k3d-manager deploy_vault

# 3. Verify
kubectl get secret -n istio-system jenkins-tls -o jsonpath='{.type}'
kubectl get secret -n istio-system jenkins-tls -o jsonpath='{.data.tls\.crt}' \
  | base64 -d \
  | openssl x509 -noout -subject -issuer
```

Seeing `kubernetes.io/tls` as the type and the expected subject/issuer confirms the PKI issuer workflow ran successfully.

---

## Certificate Rotator

The Jenkins cert rotator CronJob automatically revokes superseded certificates in Vault after applying a new Kubernetes TLS secret. Re-running `deploy_jenkins` on existing clusters refreshes the Vault policy if the `revoke` capability is missing.

Default image: `docker.io/google/cloud-sdk:slim`

Override via `JENKINS_CERT_ROTATOR_IMAGE` (env or `scripts/etc/jenkins/jenkins-vars.sh`) if your registry differs.

---

## Air-Gapped / Disconnected Clusters

Download charts from a workstation with network access:

```bash
mkdir -p ~/k3d-manager-charts
helm pull external-secrets/external-secrets \
  --repo https://charts.external-secrets.io \
  --destination ~/k3d-manager-charts
helm pull jenkins/jenkins \
  --repo https://charts.jenkins.io \
  --destination ~/k3d-manager-charts
```

Then export local chart overrides before deploying:

```bash
export ESO_HELM_CHART_REF=/opt/charts/external-secrets-<version>.tgz
export ESO_HELM_REPO_URL=
export JENKINS_HELM_CHART_REF=/opt/charts/jenkins-<version>.tgz
export JENKINS_HELM_REPO_URL=
```

When the chart reference is a local path (or repo URL is empty), the plugins skip `helm repo add`/`helm repo update`.

---

## Prerequisites

`envsubst` must be on `PATH` before running `deploy_jenkins` (used to render Istio and workload manifests from templates):

| Platform | Command |
|---|---|
| macOS | `brew install gettext && brew link --force gettext` |
| Debian/Ubuntu | `sudo apt install gettext` |
| Fedora/RHEL/CentOS | `sudo dnf install gettext` |
