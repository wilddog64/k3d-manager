#!/usr/bin/env bash
set -euo pipefail

ipam_dir="${CNI_IPAM_DIR:-/var/lib/cni/networks/cbr0}"
state_file="${K3DM_CNI_IPAM_STATE:-/var/lib/k3dm/cni-ipam-sweep.state}"
subnet_env="${FLANNEL_SUBNET_ENV:-/run/flannel/subnet.env}"
min_age_min="${K3DM_CNI_IPAM_MIN_AGE_MINUTES:-10}"
mode="${1:---dry-run}"

case "${mode}" in
  --dry-run|--apply) ;;
  *)
    printf 'Usage: k3dm-cni-ipam-sweep [--dry-run|--apply]\n' >&2
    exit 2
    ;;
esac

if [[ ! -d "${ipam_dir}" ]]; then
  printf 'k3dm-cni-ipam-sweep: no IPAM directory %s\n' "${ipam_dir}" >&2
  exit 1
fi

exec 9>>"${ipam_dir}/lock"
flock 9

live="$(k3s crictl pods -q --no-trunc)"
if [[ -z "${live}" ]]; then
  printf 'k3dm-cni-ipam-sweep: refusing — crictl lists no pod sandboxes\n' >&2
  exit 1
fi
running_ips="$(k3s kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | sort -u)"
if [[ -z "${running_ips//[[:space:]]/}" ]]; then
  printf 'k3dm-cni-ipam-sweep: refusing — the API reports no pod IPs\n' >&2
  exit 1
fi

kept=0
stale=0
young=0
for f in "${ipam_dir}"/*; do
  name="$(basename "${f}")"
  [[ "${name}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
  id="$(head -n1 "${f}" | tr -d '\r')"
  if printf '%s\n' "${live}" | grep -qxF -- "${id}"; then
    kept=$((kept + 1))
    continue
  fi
  if printf '%s\n' "${running_ips}" | grep -qxF -- "${name}"; then
    printf 'SKIP %s: no sandbox but a pod reports this IP\n' "${name}"
    kept=$((kept + 1))
    continue
  fi
  if [[ -n "$(find "${f}" -mmin "-${min_age_min}")" ]]; then
    young=$((young + 1))
    continue
  fi
  if [[ "${mode}" == "--apply" ]]; then
    rm -f -- "${f}"
  fi
  stale=$((stale + 1))
done

reservations=0
for f in "${ipam_dir}"/*; do
  if [[ "$(basename "${f}")" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    reservations=$((reservations + 1))
  fi
done

range_size=0
prefix=""
if [[ -r "${subnet_env}" ]]; then
  prefix="$(sed -n 's#^FLANNEL_SUBNET=.*/\([0-9][0-9]*\)$#\1#p' "${subnet_env}")"
fi
if [[ -n "${prefix}" ]]; then
  range_size=$(( (1 << (32 - prefix)) - 2 ))
fi

alloc_errors="$(journalctl -u k3s --since '-1h' --no-pager -o cat 2>/dev/null | grep -c 'no IP addresses available' || true)"
alloc_errors="${alloc_errors:-0}"

mkdir -p "$(dirname "${state_file}")"
tmp="${state_file}.tmp"
printf 'last_run=%s\nmode=%s\nkept=%s\nstale=%s\nyoung=%s\nreservations=%s\nrange_size=%s\nalloc_errors_1h=%s\n' \
  "$(date +%s)" "${mode#--}" "${kept}" "${stale}" "${young}" "${reservations}" "${range_size}" "${alloc_errors}" \
  > "${tmp}"
chmod 0644 "${tmp}"
mv -f -- "${tmp}" "${state_file}"

printf 'mode=%s kept=%s stale=%s young=%s reservations=%s range_size=%s alloc_errors_1h=%s\n' \
  "${mode#--}" "${kept}" "${stale}" "${young}" "${reservations}" "${range_size}" "${alloc_errors}"
