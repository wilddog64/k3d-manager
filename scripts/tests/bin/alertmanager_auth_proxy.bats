#!/usr/bin/env bats

@test "alertmanager auth proxy requires basic auth and forwards headers" {
  run grep -nF 'WWW-Authenticate' bin/alertmanager-auth-proxy
  [ "$status" -eq 0 ]

  run grep -nF 'Authorization' bin/alertmanager-auth-proxy
  [ "$status" -eq 0 ]

  run grep -nF 'X-Forwarded-Host' bin/alertmanager-auth-proxy
  [ "$status" -eq 0 ]

  run grep -nF 'X-Forwarded-Proto' bin/alertmanager-auth-proxy
  [ "$status" -eq 0 ]
}

@test "alertmanager auth proxy rereads rotated credentials without restart" {
  local creds_file
  creds_file="${BATS_TEST_TMPDIR}/alertmanager-basic-auth.env"

  cat > "${creds_file}" <<EOF
ALERTMANAGER_BASIC_AUTH_USER=admin
ALERTMANAGER_BASIC_AUTH_PASSWORD=first-pass
ALERTMANAGER_BACKEND_URL=http://127.0.0.1:19093
EOF

run python3 - "${BATS_TEST_DIRNAME}/../../../bin/alertmanager-auth-proxy" "${creds_file}" <<'PY'
import base64
import importlib.util
from importlib.machinery import SourceFileLoader
import sys

module_path, creds_file = sys.argv[1:3]
loader = SourceFileLoader("alertmanager_auth_proxy", module_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

def auth_header(user, password):
    token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    return f"Basic {token}"

handler = module.AlertmanagerProxyHandler.__new__(module.AlertmanagerProxyHandler)
handler.credentials_file = creds_file
handler.headers = {"Authorization": auth_header("admin", "first-pass")}
handler.log_message = lambda *args, **kwargs: None
assert handler._auth_ok() is True

with open(creds_file, "w", encoding="utf-8") as handle:
    handle.write(
        "ALERTMANAGER_BASIC_AUTH_USER=admin\n"
        "ALERTMANAGER_BASIC_AUTH_PASSWORD=second-pass\n"
        "ALERTMANAGER_BACKEND_URL=http://127.0.0.1:19093\n"
    )

handler.headers = {"Authorization": auth_header("admin", "second-pass")}
assert handler._auth_ok() is True

handler.headers = {"Authorization": auth_header("admin", "first-pass")}
assert handler._auth_ok() is False
print("ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}
