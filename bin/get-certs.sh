#!/usr/bin/env bash
TLS_NS=istio-system              # adjust
TLS_SECRET=jenkins-cert

kubectl -n "$TLS_NS" get secret "$TLS_SECRET" \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/ingress.crt

# Fingerprint & SANs of the cert you *intend* to serve
openssl x509 -in /tmp/ingress.crt -noout \
  -subject -issuer -dates -ext subjectAltName -fingerprint -sha256

# Make sure the Gateway is using the secret you checked
istioctl -n istio-system proxy-config secret $(kubectl -n istio-system get pod -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}') \
    | grep -A2 "$TLS_SECRET" || true
 
trap "rm -f /tmp/ingress.crt" EXIT
