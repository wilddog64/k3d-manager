#!/usr/bin/env bash
# Make sure the Gateway is using the secret you checked
TLS_SECRET="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
istioctl -n istio-system proxy-config secret $(kubectl -n istio-system get pod -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}') \
  | grep -A2 "$TLS_SECRET" || true
