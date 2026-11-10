#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/../../.."
  VAGRANTFILE="${REPO_ROOT}/scripts/etc/machine/vagrant/control-linux/Vagrantfile"
  [ -f "${VAGRANTFILE}" ]
}

@test "E1 / N1: control-linux Vagrantfile never installs Ansible with pip and uses default mode with roles path" {
  if grep -E 'install_mode\s*=\s*["'\'']pip["'\'']' "${VAGRANTFILE}"; then
    echo "Vagrantfile must not install Ansible with pip" >&2
    return 1
  fi

  # Must use default install mode (Ubuntu apt ansible-core)
  grep -E 'install_mode\s*=\s*["'\'']default["'\'']' "${VAGRANTFILE}"

  # Must set roles path for provisioner
  grep -E 'galaxy_roles_path\s*=\s*["'\''].*["'\'']' "${VAGRANTFILE}"

  # Must set ansible.limit to 'all' when inventory_path is set to avoid empty host target pattern
  if grep -E 'inventory_path\s*=' "${VAGRANTFILE}"; then
    if ! grep -E 'limit\s*=\s*["'\'']all["'\'']' "${VAGRANTFILE}"; then
      echo "ansible.limit must be set to 'all' when inventory_path is set" >&2
      return 1
    fi
    if ! grep -E 'extra_vars.*["'\'']ansible_connection["'\'']\s*=>\s*["'\'']local["'\'']' "${VAGRANTFILE}"; then
      echo "ansible.extra_vars must set ansible_connection to 'local' when inventory_path is set" >&2
      return 1
    fi
  fi
}

@test "E1 / N2: control-linux Vagrantfile runs aarch64-guarded SVE/SME kernel fix before Ansible" {
  local shell_line ansible_line
  shell_line="$(grep -n 'config\.vm\.provision\s*["'\'']shell["'\'']' "${VAGRANTFILE}" | cut -d: -f1 || true)"
  ansible_line="$(grep -n 'config\.vm\.provision\s*["'\'']ansible_local["'\'']' "${VAGRANTFILE}" | cut -d: -f1 || true)"

  [ -n "${shell_line}" ]
  [ -n "${ansible_line}" ]
  [ "${shell_line}" -lt "${ansible_line}" ]

  # The grub fix must be guarded by aarch64 check
  grep -E 'uname -m.*aarch64|aarch64.*uname -m' "${VAGRANTFILE}"

  # Must add both arm64.nosve and arm64.nosme
  grep -F 'arm64.nosve' "${VAGRANTFILE}"
  grep -F 'arm64.nosme' "${VAGRANTFILE}"
  grep -F 'update-grub' "${VAGRANTFILE}"

  # Flags must not be written to GRUB_CMDLINE_LINUX_DEFAULT
  if grep -E 'GRUB_CMDLINE_LINUX_DEFAULT.*arm64\.nos(ve|me)' "${VAGRANTFILE}"; then
    echo "flags must not be written to GRUB_CMDLINE_LINUX_DEFAULT" >&2
    return 1
  fi

  # Flags must be written to GRUB_CMDLINE_LINUX
  grep -E 'GRUB_CMDLINE_LINUX.*arm64\.nosve' "${VAGRANTFILE}"

  # Must never touch /etc/sudoers, /etc/profile, or /etc/zshrc
  run grep -E '/etc/(sudoers|profile|zshrc)' "${VAGRANTFILE}"
  [ "${status}" -ne 0 ]
}

@test "control-linux Vagrantfile passes ruby syntax check" {
  command -v ruby >/dev/null 2>&1 || skip "ruby not found"
  run ruby -c "${VAGRANTFILE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Syntax OK"* ]]
}
