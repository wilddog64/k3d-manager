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
