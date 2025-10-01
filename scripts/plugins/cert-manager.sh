#!/usr/bin/env bash

CERT_MANAGER_VARS="$PLUGINS_DIR/etc/cert-manager/vars.sh"

if [[ ! -f "$CERT_MANAGER_VARS" ]]; then
   _err "Cert-Manager vars file not found!"
fi
source "$CERT_MANAGER_VARS"
