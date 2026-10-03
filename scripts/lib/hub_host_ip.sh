#!/usr/bin/env bash
# scripts/lib/hub_host_ip.sh — the Mac's address as seen from the hub's k3d server container.

function _hub_docker_host_ip() {
  local _container="${1:-k3d-k3d-cluster-server-0}"
  local _out
  _out=$(docker exec "${_container}" sh -c 'nslookup host.docker.internal 2>/dev/null' 2>/dev/null || true)
  printf '%s\n' "${_out}" \
    | awk '/^Name:/{seen=1; next} seen && /^Address/ {sub(/^Address:[[:space:]]*/, ""); if ($0 ~ /^[0-9]+(\.[0-9]+)+$/) {print; exit}}'
}
