#!/usr/bin/env bash
# bin/update-hosts-entry.sh
# Update or add a single /etc/hosts entry. Must be run as root.
# Usage: update-hosts-entry.sh <hostname> <ip>
# Installed to: /usr/local/bin/k3d-manager-update-hosts by make install-sudoers

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: update-hosts-entry.sh <hostname> <ip>" >&2
  exit 2
fi

_h="$1"
_ip="$2"

if [[ ! "$_h" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]]; then
  echo "Invalid hostname: $_h" >&2
  exit 2
fi

if [[ ! "$_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  echo "Invalid IPv4 address: $_ip" >&2
  exit 2
fi

IFS='.' read -r -a _octets <<< "$_ip"
for _octet in "${_octets[@]}"; do
  if (( 10#$_octet > 255 )); then
    echo "Invalid IPv4 address: $_ip" >&2
    exit 2
  fi
done

_desired="${_ip} ${_h}"
_tmp="$(mktemp)"
_hosts_file="/etc/hosts"
if [[ "$EUID" -ne 0 && -n "${K3DM_HOSTS_FILE:-}" ]]; then
  _hosts_file="$K3DM_HOSTS_FILE"
fi
grep -vE "^[0-9.]+[[:space:]]+${_h//./\\.}$" "$_hosts_file" > "$_tmp"
printf '%s\n' "$_desired" >> "$_tmp"
cat "$_tmp" > "$_hosts_file"
rm -f "$_tmp"
