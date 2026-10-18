function _k3dm_push_deployment_metrics() {
  local action="$1"
  local provider="$2"
  local status="$3"
  local duration_secs="$4"
  local run_id="$5"
  local provider_short timestamp success_value base_url url payload

  [[ "${K3DM_DEPLOYMENT_METRICS:-1}" == "0" ]] && return 0
  [[ "${DRY_RUN:-0}" == "1" ]] && return 0

  case "${provider}" in
    k3s-aws) provider_short="aws" ;;
    k3s-gcp) provider_short="gcp" ;;
    k3s-az|k3s-azure) provider_short="azure" ;;
    *) provider_short="${provider}" ;;
  esac

  timestamp="$(date +%s)"
  success_value="0"
  [[ "${status}" == "success" ]] && success_value="1"
  base_url="${K3DM_DEPLOYMENT_PUSHGATEWAY_URL:-http://localhost:19094}"
  base_url="${base_url%/}"
  url="${base_url}/metrics/job/k3dm-cli/instance/${action}-${provider_short}"
  payload="# HELP k3dm_deployment_duration_seconds Duration of the deployment job in seconds
# TYPE k3dm_deployment_duration_seconds gauge
k3dm_deployment_duration_seconds{action=\"${action}\",provider=\"${provider_short}\",status=\"${status}\",job_id=\"${run_id}\"} ${duration_secs}
# HELP k3dm_deployment_last_timestamp_seconds Unix timestamp of last job completion
# TYPE k3dm_deployment_last_timestamp_seconds gauge
k3dm_deployment_last_timestamp_seconds{action=\"${action}\",provider=\"${provider_short}\",status=\"${status}\"} ${timestamp}
# HELP k3dm_deployment_success 1 if last job succeeded, 0 if failed
# TYPE k3dm_deployment_success gauge
k3dm_deployment_success{action=\"${action}\",provider=\"${provider_short}\",job_id=\"${run_id}\"} ${success_value}
"

  if ! printf '%s' "${payload}" | curl --silent --show-error --max-time 5 --data-binary @- "${url}" >/dev/null; then
    _warn "[deployment-metrics] Pushgateway push failed: ${url}"
  fi
  return 0
}
