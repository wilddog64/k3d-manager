#!/usr/bin/env bash
# bin/update-hosts-entry.sh
# Update or add a single /etc/hosts entry. Must be run as root.
# Usage: update-hosts-entry.sh <hostname> <ip>
# Installed to: /usr/local/bin/k3d-manager-update-hosts by make install-sudoers

set -euo pipefail

_h="${1:?hostname required}"
_ip="${2:?ip required}"

_desired="${_ip} ${_h}"
_tmp="$(mktemp)"
grep -vE "^[0-9.]+[[:space:]]+${_h//./\\.}$" /etc/hosts > "$_tmp"
printf '%s\n' "$_desired" >> "$_tmp"
cat "$_tmp" > /etc/hosts
rm -f "$_tmp"
