#!/usr/bin/env bash

_ensure_cloudflare_tunnel_agent() {
  local _tunnel_dir="$1"
  local _prefix="${2:-[acg-up]}"
  local _tunnel_urls_file="${_tunnel_dir}/tunnel-urls.txt"
  local _cloudflared_config="${HOME}/.cloudflared/config.yml"

  if ! command -v cloudflared >/dev/null 2>&1; then
    _warn "${_prefix} cloudflared not found — skipping named tunnel"
    return 0
  fi
  if [[ ! -f "${_cloudflared_config}" ]]; then
    _warn "${_prefix} ~/.cloudflared/config.yml not found — skipping named tunnel (run: cloudflared tunnel login && cloudflared tunnel create k3d-manager)"
    return 0
  fi

  local _named_tunnel_label="com.k3d-manager.cloudflare-tunnel"
  local _named_tunnel_log="${_tunnel_dir}/logs/cloudflare-tunnel.log"
  local _named_tunnel_plist="${HOME}/Library/LaunchAgents/${_named_tunnel_label}.plist"
  local _named_tunnel_plist_tmp="${_tunnel_dir}/run/cloudflare-tunnel.plist"
  local _cloudflared_bin
  _cloudflared_bin="$(command -v cloudflared)"
  mkdir -p "${_tunnel_dir}/logs" "${_tunnel_dir}/run" "${HOME}/Library/LaunchAgents"

  cat > "${_named_tunnel_plist_tmp}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_named_tunnel_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_cloudflared_bin}</string>
    <string>tunnel</string>
    <string>--config</string>
    <string>${_cloudflared_config}</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_named_tunnel_log}</string>
  <key>StandardErrorPath</key>
  <string>${_named_tunnel_log}</string>
</dict>
</plist>
PLIST

  local _tunnel_launchctl_log="${_tunnel_dir}/logs/cloudflare-tunnel-launchctl.log"
  : > "${_tunnel_urls_file}"
  if [[ -f "${_named_tunnel_plist}" ]] && diff -q "${_named_tunnel_plist_tmp}" "${_named_tunnel_plist}" >/dev/null 2>&1; then
    rm -f "${_named_tunnel_plist_tmp}"
    _info "${_prefix} Cloudflare named tunnel LaunchAgent unchanged — skipping reinstall"
  else
    : > "${_tunnel_launchctl_log}"
    launchctl bootout "gui/$(id -u)" "${_named_tunnel_plist}" \
      >"${_tunnel_launchctl_log}" 2>&1 || true
    local _named_tunnel_plist_legacy="/Library/LaunchDaemons/${_named_tunnel_label}.plist"
    if [[ -f "${_named_tunnel_plist_legacy}" ]]; then
      _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_named_tunnel_plist_legacy}" \
        >/dev/null 2>&1 || true
      _run_command --prefer-sudo --quiet --soft -- rm -f "${_named_tunnel_plist_legacy}" \
        >/dev/null 2>&1 || true
    fi
    : > "${_tunnel_launchctl_log}"
    [[ -f "${_named_tunnel_plist}" ]] || _ACG_TUNNEL_PLIST_CREATED=1
    if ! install -m 644 "${_named_tunnel_plist_tmp}" "${_named_tunnel_plist}" \
        >"${_tunnel_launchctl_log}" 2>&1; then
      _warn "${_prefix} failed to install tunnel plist — skipping"
    else
      rm -f "${_named_tunnel_plist_tmp}"
      : > "${_tunnel_launchctl_log}"
      if ! launchctl bootstrap "gui/$(id -u)" "${_named_tunnel_plist}" \
          >"${_tunnel_launchctl_log}" 2>&1; then
        _warn "${_prefix} failed to bootstrap cloudflare tunnel"
      fi
    fi
  fi
  local _argocd_url="${ARGOCD_PUBLIC_URL:-https://argocd.${CF_DOMAIN:-3ai-talk.org}}"
  local _frontend_url="${FRONTEND_PUBLIC_URL:-https://frontend.${CF_DOMAIN:-3ai-talk.org}}"
  local _keycloak_public_url="${KEYCLOAK_PUBLIC_URL:-https://keycloak.${CF_DOMAIN:-3ai-talk.org}}"
  {
    printf 'argocd=%s\n' "${_argocd_url}"
    printf 'frontend=%s\n' "${_frontend_url}"
    printf 'keycloak=%s\n' "${_keycloak_public_url}"
  } > "${_tunnel_urls_file}"
  _info "${_prefix} Cloudflare tunnel URLs written to ${_tunnel_urls_file}"
  _info "${_prefix} ArgoCD public URL:   ${_argocd_url}"
  _info "${_prefix} Frontend public URL: ${_frontend_url}"
  _info "${_prefix} Keycloak public URL: ${_keycloak_public_url}"
}
