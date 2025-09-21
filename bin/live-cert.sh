#!/usr/bin/env bash
HOST=jenkins.dev.local.me
PORT=8443
IP=127.0.0.1   # or your ingress IP

# Dump the leaf cert actually served (no trust required)
openssl s_client -showcerts -servername "$HOST" -connect "$IP:$PORT" </dev/null \
  | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' | head -n 100 > /tmp/live.crt

# Fingerprint & SANs of the *served* cert
openssl x509 -in /tmp/live.crt -noout \
  -subject -issuer -dates -ext subjectAltName -fingerprint -sha256

trap "rm -f /tmp/live.crt" EXIT
