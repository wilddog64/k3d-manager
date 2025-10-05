#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scratch/update-cert-rotator.sh [options]

Options:
  -n, --namespace <ns>    Jenkins namespace (default: jenkins)
  -h, --help              Show this message

The script re-renders the Jenkins cert-rotator ConfigMap and CronJob using the
latest templates under scripts/etc/jenkins and applies them to the cluster.
USAGE
}

jenkins_ns="jenkins"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      jenkins_ns="${2:?--namespace requires a value}"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scripts_dir="${repo_root}/scripts"
values_file="${scripts_dir}/etc/jenkins/vars.sh"
template_file="${scripts_dir}/etc/jenkins/jenkins-cert-rotator.yaml.tmpl"

if [[ ! -r "$values_file" ]]; then
  echo "Missing values file: $values_file" >&2
  exit 1
fi
if [[ ! -r "$template_file" ]]; then
  echo "Missing template file: $template_file" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$values_file"

export JENKINS_NAMESPACE="$jenkins_ns"
export JENKINS_CERT_ROTATOR_SCRIPT_B64="$(base64 < "${scripts_dir}/etc/jenkins/cert-rotator.sh" | tr -d '\n')"
export JENKINS_CERT_ROTATOR_VAULT_PKI_LIB_B64="$(base64 < "${scripts_dir}/lib/vault_pki.sh" | tr -d '\n')"
export JENKINS_CERT_ROTATOR_ISTIO_INJECT="${JENKINS_CERT_ROTATOR_ISTIO_INJECT:-false}"
export JENKINS_CERT_ROTATOR_SCRIPT_B64="$(base64 < "${scripts_dir}/etc/jenkins/cert-rotator.sh" | tr -d '\n')"
export JENKINS_CERT_ROTATOR_VAULT_PKI_LIB_B64="$(base64 < "${scripts_dir}/lib/vault_pki.sh" | tr -d '\n')"


rendered=$(mktemp -t jenkins-rotator.XXXXXX.yaml)
trap 'rm -f "$rendered"' EXIT

envsubst < "$template_file" > "$rendered"

echo "Applying cert-rotator resources to namespace '$jenkins_ns'..."
kubectl apply -f "$rendered"

echo "Done. If you need the CronJob to run immediately, create a job manually with:\n  kubectl -n $jenkins_ns create job rotator-manual --from=cronjob/jenkins-cert-rotator"
