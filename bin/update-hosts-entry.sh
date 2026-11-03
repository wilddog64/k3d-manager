#!/bin/bash
# bin/update-hosts-entry.sh
# Update or add a single validated /etc/hosts entry. Must be run as root.
# Usage: update-hosts-entry.sh <hostname> <IPv4-address>

set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

if [[ "$#" -ne 2 ]]; then
  echo "Usage: update-hosts-entry.sh <hostname> <IPv4-address>" >&2
  exit 2
fi

_h="$1"
_ip="$2"
if ((${#_h} > 253)) || [[ ! "${_h}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
  echo "Refusing invalid hostname or IPv4 address" >&2
  exit 2
fi
IFS='.' read -r -a _labels <<< "${_h}"
for _label in "${_labels[@]}"; do
  if ((${#_label} == 0 || ${#_label} > 63)) || \
      [[ ! "${_label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
    echo "Refusing invalid hostname or IPv4 address" >&2
    exit 2
  fi
done
if [[ ! "${_ip}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
  echo "Refusing invalid hostname or IPv4 address" >&2
  exit 2
fi
IFS='.' read -r -a _octets <<< "${_ip}"
for _octet in "${_octets[@]}"; do
  if ((10#${_octet} > 255)); then
    echo "Refusing invalid hostname or IPv4 address" >&2
    exit 2
  fi
done

_tmp="$(/usr/bin/mktemp /etc/hosts.k3d-manager.XXXXXX)"
trap '/bin/rm -f -- "${_tmp}"' EXIT
/usr/bin/awk -v host="${_h}" '{
  if (NF < 2) {
    print
    next
  }
  line = $1
  comment = 0
  for (i = 2; i <= NF; i++) {
    if ($i == "#") {
      comment = i
      break
    }
    if ($i != host) line = line "\t" $i
  }
  if (comment) {
    for (i = comment; i <= NF; i++) line = line "\t" $i
  }
  print line
}' /etc/hosts > "${_tmp}"
/usr/bin/printf '%s\t%s\n' "${_ip}" "${_h}" >> "${_tmp}"
/bin/cat "${_tmp}" > /etc/hosts
