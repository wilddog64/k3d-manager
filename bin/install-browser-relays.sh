#!/usr/bin/env bash
# Install the fixed launchd socket relays used by the browser listeners.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! declare -f _run_command >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/lib/system.sh"
fi

_mode=install
case "${1:-}" in
  "") ;;
  --dry-run) _mode=dry-run ;;
  --uninstall) _mode=uninstall ;;
  --help|-h) echo "Usage: bin/install-browser-relays.sh [--dry-run|--uninstall]"; exit 0 ;;
  *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac
[[ "$#" -le 1 ]] || { echo "Too many arguments" >&2; exit 2; }

_launchd_dir=/Library/LaunchDaemons
if [[ "$EUID" -ne 0 && -n "${K3DM_LAUNCHD_DIR:-}" ]]; then
  _launchd_dir="$K3DM_LAUNCHD_DIR"
fi
_scratch_parent="${TMPDIR:-/tmp}"
if [[ "$_mode" == dry-run && "$EUID" -ne 0 && -n "${K3DM_LAUNCHD_DIR:-}" ]]; then
  _scratch_parent="$K3DM_LAUNCHD_DIR"
fi
_scratch="$(mktemp -d "${_scratch_parent%/}/.k3dm-relays.XXXXXX")"
trap 'rm -rf -- "$_scratch"' EXIT
_jobs=(com.k3d-manager.relay.argocd-https com.k3d-manager.relay.keycloak-http com.k3d-manager.relay.hostinger-frontend-http com.k3d-manager.relay.sandbox-frontend-http com.k3d-manager.loopback-aliases)
_legacy=(argocd-browser-https keycloak-browser-http frontend-browser-http sandbox.frontend-browser-http loopback-alias sandbox.loopback-alias)

_relay_plist() {
  local label="$1" ip="$2" service="$3" high="$4" file="$5"
  cat > "$file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>${label}</string>
<key>Sockets</key><dict><key>Listeners</key><dict><key>SockNodeName</key><string>${ip}</string><key>SockServiceName</key><string>${service}</string><key>SockType</key><string>stream</string><key>SockFamily</key><string>IPv4</string></dict></dict>
<key>inetdCompatibility</key><dict><key>Wait</key><false/></dict>
<key>UserName</key><string>nobody</string>
<key>ProgramArguments</key><array><string>/usr/bin/nc</string><string>${ip}</string><string>${high}</string></array>
</dict></plist>
EOF
}

_relay_plist com.k3d-manager.relay.argocd-https 127.0.0.1 443 18443 "$_scratch/${_jobs[0]}.plist"
_relay_plist com.k3d-manager.relay.keycloak-http 127.0.0.1 80 18080 "$_scratch/${_jobs[1]}.plist"
_relay_plist com.k3d-manager.relay.hostinger-frontend-http 127.0.0.2 80 18082 "$_scratch/${_jobs[2]}.plist"
_relay_plist com.k3d-manager.relay.sandbox-frontend-http 127.0.0.3 80 18083 "$_scratch/${_jobs[3]}.plist"
cat > "$_scratch/${_jobs[4]}.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>com.k3d-manager.loopback-aliases</string>
<key>ProgramArguments</key><array><string>/bin/sh</string><string>-c</string><string>/sbin/ifconfig lo0 alias 127.0.0.2 up; /sbin/ifconfig lo0 alias 127.0.0.3 up; /bin/launchctl bootout system/com.k3d-manager.relay.hostinger-frontend-http; /bin/launchctl bootstrap system /Library/LaunchDaemons/com.k3d-manager.relay.hostinger-frontend-http.plist; /bin/launchctl bootout system/com.k3d-manager.relay.sandbox-frontend-http; /bin/launchctl bootstrap system /Library/LaunchDaemons/com.k3d-manager.relay.sandbox-frontend-http.plist; exit 0</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF

if [[ "$_mode" == uninstall ]]; then
  for _job in "${_jobs[@]}"; do
    _path="${_launchd_dir}/${_job}.plist"
    _run_command --interactive-sudo --soft -- /bin/launchctl bootout system "$_path" || true
    _run_command --interactive-sudo --soft -- /bin/rm -f -- "$_path" || true
  done
  exit 0
fi

if [[ "$_mode" == dry-run ]]; then
  for _job in "${_jobs[@]}"; do
    _file="$_scratch/${_job}.plist"
    /usr/bin/plutil -lint "$_file" >/dev/null
    cat "$_file"
  done
  exit 0
fi

for _old in "${_legacy[@]}"; do
  _path="${_launchd_dir}/com.k3d-manager.${_old}.plist"
  _run_command --interactive-sudo --soft -- /bin/launchctl bootout system "$_path" || true
  _run_command --interactive-sudo -- /bin/rm -f -- "$_path"
done
for _job in "${_jobs[@]}"; do
  _path="${_launchd_dir}/${_job}.plist"
  _run_command --interactive-sudo --soft -- /bin/launchctl bootout system "$_path" || true
  _run_command --interactive-sudo -- /usr/bin/install -o root -g wheel -m 0644 "$_scratch/${_job}.plist" "$_path"
  _run_command --interactive-sudo -- /bin/launchctl bootstrap system "$_path"
done
