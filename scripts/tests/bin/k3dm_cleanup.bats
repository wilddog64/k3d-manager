#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  TMP_ROOT="${BATS_TEST_TMPDIR}/tmp"
  HOME_ROOT="${BATS_TEST_TMPDIR}/home"
  RUN_ROOT="${HOME_ROOT}/.local/share/k3d-manager/run"
  mkdir -p "${TMP_ROOT}" "${RUN_ROOT}" "${HOME_ROOT}/.local/share/k3d-manager/logs"
  mkdir -p "${BATS_TEST_TMPDIR}/stubbin"
  : > "${BATS_TEST_TMPDIR}/calls"
  cat > "${BATS_TEST_TMPDIR}/stubbin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/calls"
case "$1 $2" in
  "info ") exit 0 ;;
  "volume ls")
    [ -f "${BATS_TEST_TMPDIR}/volumes" ] && cat "${BATS_TEST_TMPDIR}/volumes"
    ;;
  "volume inspect")
    volume="$3"
    format="$5"
    if [[ "${format}" == *CreatedAt* ]]; then
      sed -n "s/^${volume} created=//p" "${BATS_TEST_TMPDIR}/meta"
    elif [[ "${format}" == *com.docker.volume.anonymous* ]]; then
      grep -q "^${volume} anon$" "${BATS_TEST_TMPDIR}/meta" && echo anon
    fi
    ;;
  "volume rm") exit 0 ;;
esac
EOF
  cat > "${BATS_TEST_TMPDIR}/stubbin/trivy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/calls"
exit 0
EOF
  cat > "${BATS_TEST_TMPDIR}/stubbin/brew" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/calls"
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/stubbin/docker" "${BATS_TEST_TMPDIR}/stubbin/trivy" "${BATS_TEST_TMPDIR}/stubbin/brew"
  export PATH="${BATS_TEST_TMPDIR}/stubbin:${PATH}"
}

_touch_old() {
  touch -t 202507010101 "$1"
}

@test "k3dm-cleanup prunes old repo-owned tmp leftovers and keeps recent ones" {
  mkdir -p "${TMP_ROOT}/playwright-artifacts-old" "${TMP_ROOT}/playwright-artifacts-new"
  : > "${TMP_ROOT}/k3dm-ask-old.out"
  : > "${TMP_ROOT}/k3dm-ask-new.out"
  : > "${TMP_ROOT}/k3d-manager-acg-watch.err"
  : > "${TMP_ROOT}/k3d-manager-acg-watch.out"
  : > "${TMP_ROOT}/k3dm-gcp-creds.old"
  : > "${TMP_ROOT}/k3dm-gcp-creds.new"

  _touch_old "${TMP_ROOT}/playwright-artifacts-old"
  _touch_old "${TMP_ROOT}/k3dm-ask-old.out"
  _touch_old "${TMP_ROOT}/k3d-manager-acg-watch.err"
  _touch_old "${TMP_ROOT}/k3d-manager-acg-watch.out"
  _touch_old "${TMP_ROOT}/k3dm-gcp-creds.old"

  run env HOME="${HOME_ROOT}" K3DM_TMP_ROOT="${TMP_ROOT}" "${REPO_ROOT}/bin/k3dm-cleanup"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"playwright artifact dirs"* ]]
  [[ "${output}" == *"ask transcript files"* ]]

  [ ! -e "${TMP_ROOT}/playwright-artifacts-old" ]
  [ -e "${TMP_ROOT}/playwright-artifacts-new" ]
  [ ! -e "${TMP_ROOT}/k3dm-ask-old.out" ]
  [ -e "${TMP_ROOT}/k3dm-ask-new.out" ]
  [ ! -e "${TMP_ROOT}/k3d-manager-acg-watch.err" ]
  [ ! -e "${TMP_ROOT}/k3d-manager-acg-watch.out" ]
  [ ! -e "${TMP_ROOT}/k3dm-gcp-creds.old" ]
  [ -e "${TMP_ROOT}/k3dm-gcp-creds.new" ]
}

@test "k3dm-cleanup prunes old repo-owned run-dir leftovers and keeps recent ones" {
  : > "${RUN_ROOT}/k3dm-ask-old.out"
  : > "${RUN_ROOT}/k3dm-ask-new.out"
  : > "${RUN_ROOT}/k3d-manager-acg-watch.err"
  : > "${RUN_ROOT}/k3d-status.out"
  : > "${RUN_ROOT}/alertmanager-local.html"
  : > "${RUN_ROOT}/alertproxy-bats.log"
  : > "${RUN_ROOT}/k3dm-products.json"

  _touch_old "${RUN_ROOT}/k3dm-ask-old.out"
  _touch_old "${RUN_ROOT}/k3d-manager-acg-watch.err"
  _touch_old "${RUN_ROOT}/k3d-status.out"
  _touch_old "${RUN_ROOT}/alertmanager-local.html"
  _touch_old "${RUN_ROOT}/alertproxy-bats.log"
  _touch_old "${RUN_ROOT}/k3dm-products.json"

  run env HOME="${HOME_ROOT}" K3DM_TMP_ROOT="${TMP_ROOT}" K3DM_RUN_DIR="${RUN_ROOT}" "${REPO_ROOT}/bin/k3dm-cleanup"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${RUN_ROOT}"* ]]

  [ ! -e "${RUN_ROOT}/k3dm-ask-old.out" ]
  [ -e "${RUN_ROOT}/k3dm-ask-new.out" ]
  [ ! -e "${RUN_ROOT}/k3d-manager-acg-watch.err" ]
  [ ! -e "${RUN_ROOT}/k3d-status.out" ]
  [ ! -e "${RUN_ROOT}/alertmanager-local.html" ]
  [ ! -e "${RUN_ROOT}/alertproxy-bats.log" ]
  [ ! -e "${RUN_ROOT}/k3dm-products.json" ]
}

@test "k3dm-cleanup prunes only placeholder TemporaryDirectory folders" {
  mkdir -p "${TMP_ROOT}/TemporaryDirectory.stale" "${TMP_ROOT}/TemporaryDirectory.live"
  : > "${TMP_ROOT}/TemporaryDirectory.stale/.keep-directory"
  : > "${TMP_ROOT}/TemporaryDirectory.live/.keep-directory"
  : > "${TMP_ROOT}/TemporaryDirectory.live/real-file.txt"
  _touch_old "${TMP_ROOT}/TemporaryDirectory.stale"
  _touch_old "${TMP_ROOT}/TemporaryDirectory.live"

  run env HOME="${HOME_ROOT}" K3DM_TMP_ROOT="${TMP_ROOT}" "${REPO_ROOT}/bin/k3dm-cleanup"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"TemporaryDirectory placeholders"* ]]

  [ ! -e "${TMP_ROOT}/TemporaryDirectory.stale" ]
  [ -e "${TMP_ROOT}/TemporaryDirectory.live" ]
}

@test "k3dm-cleanup keeps the five newest screenshots" {
  local i
  for i in 1 2 3 4 5 6 7; do
    printf 'png-%s' "${i}" > "${TMP_ROOT}/k3dm-acg-screenshot-${i}.png"
    touch -t "20250701010${i}" "${TMP_ROOT}/k3dm-acg-screenshot-${i}.png"
  done

  run env HOME="${HOME_ROOT}" K3DM_TMP_ROOT="${TMP_ROOT}" "${REPO_ROOT}/bin/k3dm-cleanup"
  [ "${status}" -eq 0 ]

  run bash -lc "find '${TMP_ROOT}' -maxdepth 1 -name 'k3dm-acg-screenshot-*.png' | sort"
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | wc -l | tr -d ' ')" -eq 5 ]
  [[ "${output}" != *"k3dm-acg-screenshot-1.png"* ]]
  [[ "${output}" != *"k3dm-acg-screenshot-2.png"* ]]
  [[ "${output}" == *"k3dm-acg-screenshot-7.png"* ]]
}

@test "k3dm-cleanup removes old Packer artifacts and port markers only" {
  local packer_dir="${HOME_ROOT}/.cache/packer"
  local port_dir="${HOME_ROOT}/.cache/port"
  mkdir -p "${packer_dir}" "${port_dir}"
  : > "${packer_dir}/old.iso"
  : > "${packer_dir}/old.lock"
  : > "${packer_dir}/new.iso"
  : > "${port_dir}/old-marker"
  : > "${port_dir}/new-marker"
  _touch_old "${packer_dir}/old.iso"
  _touch_old "${packer_dir}/old.lock"
  _touch_old "${port_dir}/old-marker"

  run env HOME="${HOME_ROOT}" K3DM_TMP_ROOT="${TMP_ROOT}" \
    K3DM_PACKER_RETENTION_DAYS=30 K3DM_PORT_RETENTION_DAYS=7 \
    "${REPO_ROOT}/bin/k3dm-cleanup"
  [ "${status}" -eq 0 ]
  [ ! -e "${packer_dir}/old.iso" ]
  [ ! -e "${packer_dir}/old.lock" ]
  [ -e "${packer_dir}/new.iso" ]
  [ ! -e "${port_dir}/old-marker" ]
  [ -e "${port_dir}/new-marker" ]
}

@test "k3dm-cleanup removes old orphaned volumes and keeps everything else" {
  printf '%s\n' k3d-old-server-data anonold anonnew k3dm-gobuild-cache otherproject-db > "${BATS_TEST_TMPDIR}/volumes"
  printf '%s\n' \
    'k3d-old-server-data created=2026-01-01T00:00:00Z' \
    'otherproject-db created=2026-01-01T00:00:00Z' \
    'anonold created=2026-01-01T00:00:00Z' \
    "anonnew created=$(date -u +%F)T00:00:00Z" \
    'k3dm-gobuild-cache created=2026-01-01T00:00:00Z' \
    'anonold anon' 'anonnew anon' 'k3dm-gobuild-cache anon' > "${BATS_TEST_TMPDIR}/meta"

  run env HOME="${HOME_ROOT}" K3DM_TMP_ROOT="${TMP_ROOT}" "${REPO_ROOT}/bin/k3dm-cleanup"
  [ "${status}" -eq 0 ]
  run grep -c 'volume rm k3d-old-server-data' "${BATS_TEST_TMPDIR}/calls"
  [ "${output}" -eq 1 ]
  run grep -c 'volume rm anonold' "${BATS_TEST_TMPDIR}/calls"
  [ "${output}" -eq 1 ]
  run grep -c 'volume rm anonnew' "${BATS_TEST_TMPDIR}/calls"
  [ "${output}" -eq 0 ]
  run grep -c 'volume rm k3dm-gobuild-cache' "${BATS_TEST_TMPDIR}/calls"
  [ "${output}" -eq 0 ]
  run grep -c 'volume rm otherproject-db' "${BATS_TEST_TMPDIR}/calls"
  [ "${output}" -eq 0 ]
}

@test "k3dm-cleanup can disable Docker volume pruning" {
  printf '%s\n' k3d-old-server-data anonold > "${BATS_TEST_TMPDIR}/volumes"
  printf '%s\n' \
    'k3d-old-server-data created=2026-01-01T00:00:00Z' \
    'anonold created=2026-01-01T00:00:00Z' 'anonold anon' > "${BATS_TEST_TMPDIR}/meta"

  run env HOME="${HOME_ROOT}" K3DM_TMP_ROOT="${TMP_ROOT}" K3DM_DOCKER_VOLUME_PRUNE=0 "${REPO_ROOT}/bin/k3dm-cleanup"
  [ "${status}" -eq 0 ]
  run grep -c 'volume rm' "${BATS_TEST_TMPDIR}/calls"
  [ "${output}" -eq 0 ]
}

@test "k3dm-cleanup prunes weekly caches on the prune day" {
  run env HOME="${HOME_ROOT}" K3DM_TMP_ROOT="${TMP_ROOT}" K3DM_WEEKLY_CACHE_PRUNE_DAY="$(date +%u)" "${REPO_ROOT}/bin/k3dm-cleanup"
  [ "${status}" -eq 0 ]
  run grep -c 'clean --all' "${BATS_TEST_TMPDIR}/calls"
  [ "${output}" -eq 1 ]
  run grep -c 'cleanup -s' "${BATS_TEST_TMPDIR}/calls"
  [ "${output}" -eq 1 ]
}

@test "k3dm-cleanup skips weekly caches off the prune day" {
  other_day=$(( $(date +%u) % 7 + 1 ))
  run env HOME="${HOME_ROOT}" K3DM_TMP_ROOT="${TMP_ROOT}" K3DM_WEEKLY_CACHE_PRUNE_DAY="${other_day}" "${REPO_ROOT}/bin/k3dm-cleanup"
  [ "${status}" -eq 0 ]
  run grep -c 'clean --all' "${BATS_TEST_TMPDIR}/calls"
  [ "${output}" -eq 0 ]
  run grep -c 'cleanup -s' "${BATS_TEST_TMPDIR}/calls"
  [ "${output}" -eq 0 ]
}
