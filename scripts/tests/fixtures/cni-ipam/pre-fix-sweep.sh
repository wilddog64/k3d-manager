#!/usr/bin/env bash
set -euo pipefail

d="${CNI_IPAM_DIR:-/var/lib/cni/networks/cbr0}"
mode="${1:-dry-run}"

exec 9>"${d}/lock"
flock 9

live="$(k3s crictl pods -q --no-trunc)"
running_ips="$(k3s kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | sort -u)"

removed=0
kept=0
for f in "${d}"/10.42.0.*; do
  ip="$(basename "${f}")"
  id="$(head -n1 "${f}" | tr -d '\r')"
  if printf '%s\n' "${live}" | grep -qxF -- "${id}"; then
    kept=$((kept + 1))
    continue
  fi
  if printf '%s\n' "${running_ips}" | grep -qxF -- "${ip}"; then
    echo "SKIP ${ip}: no sandbox but a pod reports this IP"
    kept=$((kept + 1))
    continue
  fi
  if [[ "${mode}" == "--apply" ]]; then
    rm -f -- "${f}"
  fi
  removed=$((removed + 1))
done

echo "mode=${mode} kept=${kept} stale=${removed}"
echo "reservations now: $(ls "${d}" | grep -c '^10\\.42\\.')"
