# scripts/plugins/external-secrets.sh
# External Secrets Operator + Bitwarden Secrets Manager plugin for k3d-manager

# Install ESO and enable the Bitwarden SDK server dependency
function deploy_eso() {
  local ns="${1:-external-secrets}"

  # Namespace
  _kubectl --quiet get ns "$ns" >/dev/null 2>&1 || _kubectl create ns "$ns"

  # Helm repo
  _helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
  _helm repo update >/dev/null 2>&1

# Ensure TLS secret for the Bitwarden SDK server exists (self-signed quick path)
if ! _kubectl --quiet -n "$ns" get secret bitwarden-tls-certs >/dev/null 2>&1; then
  echo "Generating self-signed TLS for Bitwarden SDK server in namespace $ns"
  tmpdir="$(mktemp -d)"
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -subj "/CN=bitwarden-sdk-server.${ns}.svc" \
    -addext "subjectAltName=DNS:bitwarden-sdk-server.${ns}.svc,DNS:bitwarden-sdk-server.${ns}.svc.cluster.local" \
    -keyout "$tmpdir/tls.key" -out "$tmpdir/tls.crt" >/dev/null 2>&1
  cp "$tmpdir/tls.crt" "$tmpdir/ca.crt"   # self-signed: use server cert as CA
  _kubectl -n "$ns" create secret generic bitwarden-tls-certs \
    --from-file=tls.crt="$tmpdir/tls.crt" \
    --from-file=tls.key="$tmpdir/tls.key" \
    --from-file=ca.crt="$tmpdir/ca.crt" >/dev/null 2>&1
  rm -rf "$tmpdir"
fi
# Ensure TLS secret for the Bitwarden SDK server exists (self-signed quick path)
if ! _kubectl --quiet -n "$ns" get secret bitwarden-tls-certs >/dev/null 2>&1; then
  echo "Generating self-signed TLS for Bitwarden SDK server in namespace $ns"
  tmpdir="$(mktemp -d)"
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -subj "/CN=bitwarden-sdk-server.${ns}.svc" \
    -addext "subjectAltName=DNS:bitwarden-sdk-server.${ns}.svc,DNS:bitwarden-sdk-server.${ns}.svc.cluster.local" \
    -keyout "$tmpdir/tls.key" -out "$tmpdir/tls.crt" >/dev/null 2>&1
  cp "$tmpdir/tls.crt" "$tmpdir/ca.crt"   # self-signed: use server cert as CA
  _kubectl -n "$ns" create secret generic bitwarden-tls-certs \
    --from-file=tls.crt="$tmpdir/tls.crt" \
    --from-file=tls.key="$tmpdir/tls.key" \
    --from-file=ca.crt="$tmpdir/ca.crt" >/dev/null 2>&1
fi
# Ensure TLS secret for the Bitwarden SDK server exists (self-signed quick path)
if ! _kubectl --quiet -n "$ns" get secret bitwarden-tls-certs >/dev/null 2>&1; then
  echo "Generating self-signed TLS for Bitwarden SDK server in namespace $ns"
  tmpdir="$(mktemp -d)"
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -subj "/CN=bitwarden-sdk-server.${ns}.svc" \
    -addext "subjectAltName=DNS:bitwarden-sdk-server.${ns}.svc,DNS:bitwarden-sdk-server.${ns}.svc.cluster.local" \
    -keyout "$tmpdir/tls.key" -out "$tmpdir/tls.crt" >/dev/null 2>&1
  cp "$tmpdir/tls.crt" "$tmpdir/ca.crt"   # self-signed: use server cert as CA
  _kubectl -n "$ns" create secret generic bitwarden-tls-certs \
    --from-file=tls.crt="$tmpdir/tls.crt" \
    --from-file=tls.key="$tmpdir/tls.key" \
    --from-file=ca.crt="$tmpdir/ca.crt" >/dev/null 2>&1
fi

  # Install ESO + CRDs + Bitwarden SDK server
  _helm upgrade --install external-secrets external-secrets/external-secrets \
    -n "$ns" --create-namespace \
    --set installCRDs=true \
    --set bitwarden-sdk-server.enabled=true

  # Wait for controllers and the SDK server
  _kubectl -n "$ns" rollout status deploy/external-secrets --timeout=120s
  _kubectl -n "$ns" rollout status deploy/bitwarden-sdk-server --timeout=120s

  trap 'cleanup_on_success "$tmpdir"' EXIT
  echo "ESO installed with Bitwarden SDK server in namespace $ns"
}

