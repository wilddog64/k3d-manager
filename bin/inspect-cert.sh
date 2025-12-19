#!/usr/bin/env bash
# bin/inspect-cert.sh
# Unified certificate inspection tool - inspect certs from K8s secret or live endpoint

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
DEFAULT_HOST="jenkins.dev.local.me"
DEFAULT_PORT="443"
DEFAULT_TLS_NS="istio-system"
DEFAULT_TLS_SECRET="jenkins-tls"
MODE="both"

# Parse arguments
show_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Inspect TLS certificates from Kubernetes secret and/or live HTTPS endpoint.

OPTIONS:
  --mode MODE          Inspection mode: secret, live, or both (default: both)
  --host HOST          Hostname for live inspection (default: $DEFAULT_HOST)
  --port PORT          Port for live inspection (default: $DEFAULT_PORT)
  --namespace NS       K8s namespace for secret (default: $DEFAULT_TLS_NS)
  --secret NAME        K8s secret name (default: $DEFAULT_TLS_SECRET)
  -h, --help           Show this help

EXAMPLES:
  # Inspect both secret and live endpoint
  $(basename "$0")

  # Inspect only the K8s secret
  $(basename "$0") --mode secret

  # Inspect only the live endpoint
  $(basename "$0") --mode live

  # Custom host and port
  $(basename "$0") --host argocd.dev.local.me --port 443

EOF
  exit 0
}

HOST="$DEFAULT_HOST"
PORT="$DEFAULT_PORT"
TLS_NS="$DEFAULT_TLS_NS"
TLS_SECRET="$DEFAULT_TLS_SECRET"

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --namespace)
      TLS_NS="$2"
      shift 2
      ;;
    --secret)
      TLS_SECRET="$2"
      shift 2
      ;;
    -h|--help)
      show_usage
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# Validate mode
case "$MODE" in
  secret|live|both) ;;
  *)
    echo -e "${RED}Invalid mode: $MODE${NC}" >&2
    echo "Must be: secret, live, or both" >&2
    exit 1
    ;;
esac

# Inspect K8s secret
inspect_secret() {
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${BLUE}Certificate from Kubernetes Secret${NC}"
  echo -e "${BLUE}===================================================${NC}"
  echo "Namespace: $TLS_NS"
  echo "Secret:    $TLS_SECRET"
  echo

  if ! kubectl -n "$TLS_NS" get secret "$TLS_SECRET" &>/dev/null; then
    echo -e "${RED}Error: Secret ${TLS_NS}/${TLS_SECRET} not found${NC}"
    return 1
  fi

  local temp_cert="/tmp/ingress-cert-$$.crt"
  trap "rm -f $temp_cert" RETURN

  kubectl -n "$TLS_NS" get secret "$TLS_SECRET" \
    -o jsonpath='{.data.tls\.crt}' | base64 -d > "$temp_cert"

  echo -e "${GREEN}Certificate Details:${NC}"
  openssl x509 -in "$temp_cert" -noout \
    -subject -issuer -dates -ext subjectAltName -fingerprint -sha256

  # Check Istio gateway usage if istioctl is available
  if command -v istioctl &>/dev/null; then
    echo
    echo -e "${YELLOW}Istio Gateway Secret Usage:${NC}"
    local gw_pod
    gw_pod=$(kubectl -n istio-system get pod -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -n "$gw_pod" ]]; then
      istioctl -n istio-system proxy-config secret "$gw_pod" 2>/dev/null \
        | grep -A2 "$TLS_SECRET" || echo "  (not found in gateway config)"
    fi
  fi

  echo
}

# Inspect live endpoint
inspect_live() {
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${BLUE}Certificate from Live HTTPS Endpoint${NC}"
  echo -e "${BLUE}===================================================${NC}"
  echo "Host: $HOST"
  echo "Port: $PORT"
  echo

  # Get ingress IP
  local ip
  ip=$(kubectl get -n istio-system service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

  if [[ -z "$ip" ]]; then
    echo -e "${YELLOW}Warning: Could not get LoadBalancer IP, trying ClusterIP...${NC}"
    ip=$(kubectl get -n istio-system service istio-ingressgateway -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  fi

  if [[ -z "$ip" ]]; then
    echo -e "${RED}Error: Could not determine ingress gateway IP${NC}"
    return 1
  fi

  echo "IP: $ip"
  echo

  local temp_cert="/tmp/live-cert-$$.crt"
  trap "rm -f $temp_cert" RETURN

  # Extract the leaf certificate
  if ! openssl s_client -showcerts -servername "$HOST" -connect "$ip:$PORT" </dev/null 2>/dev/null \
    | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' | head -n 100 > "$temp_cert"; then
    echo -e "${RED}Error: Failed to connect to $HOST:$PORT${NC}"
    return 1
  fi

  if [[ ! -s "$temp_cert" ]]; then
    echo -e "${RED}Error: No certificate received from endpoint${NC}"
    return 1
  fi

  echo -e "${GREEN}Certificate Details:${NC}"
  openssl x509 -in "$temp_cert" -noout \
    -subject -issuer -dates -ext subjectAltName -fingerprint -sha256

  echo
}

# Main execution
case "$MODE" in
  secret)
    inspect_secret
    ;;
  live)
    inspect_live
    ;;
  both)
    inspect_secret
    echo
    inspect_live
    ;;
esac

echo -e "${GREEN}===================================================${NC}"
echo -e "${GREEN}Inspection Complete!${NC}"
echo -e "${GREEN}===================================================${NC}"
