#!/usr/bin/env bash
# 1) Generate the pin from the **live** endpoint (leaf cert public key)
HOST=jenkins.dev.local.me
PORT=443

IP=$(kubectl get -n istio-system service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [[ -z "$IP" ]]; then
   echo "Could not get IP of istio-ingressgateway service"
   exit 1
fi

PIN=$(
  openssl s_client -servername "$HOST" -connect "$IP:$PORT" </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary | base64
)

# 2) Curl with pin (note the TWO slashes after sha256)
curl -vk --resolve "$HOST:$PORT:$IP" \
  --pinnedpubkey "sha256//$PIN" \
  "https://$HOST:$PORT/login"
