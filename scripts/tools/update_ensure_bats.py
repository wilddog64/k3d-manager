#!/usr/bin/env python3
"""Update scripts/lib/system.sh to ensure Bats >= 1.5.0."""
from __future__ import annotations

from pathlib import Path

REPLACEMENT = """function _version_ge() {
   local lhs_str=\"$1\"
   local rhs_str=\"$2\"
   local IFS=.
   local -a lhs rhs

   read -r -a lhs <<< \"$lhs_str\"
   read -r -a rhs <<< \"$rhs_str\"

   local len=${#lhs[@]}
   if (( ${#rhs[@]} > len )); then
      len=${#rhs[@]}
   fi

   for ((i=0; i<len; ++i)); do
      local l=${lhs[i]:-0}
      local r=${rhs[i]:-0}
      if ((10#$l > 10#$r)); then
         return 0
      elif ((10#$l < 10#$r)); then
         return 1
      fi
   done

   return 0
}

function _bats_version() {
   if ! _command_exist bats ; then
      return 1
   fi

   local version
   version=\"$(bats --version 2>/dev/null | awk '{print $2}')\"
   if [[ -n \"$version\" ]]; then
      printf '%s\\n' \"$version\"
      return 0
   fi

   return 1
}

function _bats_meets_requirement() {
   local required=\"$1\"
   local current

   current=\"$(_bats_version 2>/dev/null)\" || return 1
   if [[ -z \"$current\" ]]; then
      return 1
   fi

   _version_ge \"$current\" \"$required\"
}

function _sudo_available() {
   if ! command -v sudo >/dev/null 2>&1; then
      return 1
   fi

   sudo -n true >/dev/null 2>&1
}

function _install_bats_from_source() {
   local version=\"${1:-1.10.0}\"
   local url=\"https://github.com/bats-core/bats-core/releases/download/v${version}/bats-core-${version}.tar.gz\"
   local tmp_dir

   tmp_dir=\"$(mktemp -d 2>/dev/null || mktemp -d -t bats-core)\"
   if [[ -z \"$tmp_dir\" ]]; then
      echo \"Failed to create temporary directory for bats install\" >&2
      return 1
   fi

   if ! _command_exist curl || ! _command_exist tar ; then
      echo \"Cannot install bats from source: curl and tar are required\" >&2
      rm -rf \"$tmp_dir\"
      return 1
   fi

   echo \"Installing bats ${version} from source...\" >&2
   if ! _run_command -- curl -fsSL \"$url\" -o \"${tmp_dir}/bats-core.tar.gz\"; then
      rm -rf \"$tmp_dir\"
      return 1
   fi

   if ! tar -xzf \"${tmp_dir}/bats-core.tar.gz\" -C \"$tmp_dir\"; then
      rm -rf \"$tmp_dir\"
      return 1
   fi

   local src_dir=\"${tmp_dir}/bats-core-${version}\"
   if [[ ! -d \"$src_dir\" ]]; then
      rm -rf \"$tmp_dir\"
      return 1
   fi

   local prefix=\"${HOME}/.local\"
   mkdir -p \"$prefix\"

   if _run_command -- bash \"$src_dir/install.sh\" \"$prefix\"; then
      rm -rf \"$tmp_dir\"
      return 0
   fi

   if _sudo_available; then
      if _run_command --prefer-sudo -- bash \"$src_dir/install.sh\" /usr/local; then
         rm -rf \"$tmp_dir\"
         return 0
      fi
   fi

   echo \"Cannot install bats: write access to ${prefix} or sudo is required\" >&2
   rm -rf \"$tmp_dir\"
   return 1
}

function _ensure_bats() {
   local required=\"1.5.0\"

   if _bats_meets_requirement \"$required\"; then
      return 0
   fi

   local pkg_attempted=0

   if _command_exist brew ; then
      _run_command -- brew install bats-core
      pkg_attempted=1
   elif _command_exist apt-get && _sudo_available; then
      _run_command --prefer-sudo -- apt-get update
      _run_command --prefer-sudo -- apt-get install -y bats
      pkg_attempted=1
   elif _command_exist dnf && _sudo_available; then
      _run_command --prefer-sudo -- dnf install -y bats
      pkg_attempted=1
   elif _command_exist yum && _sudo_available; then
      _run_command --prefer-sudo -- yum install -y bats
      pkg_attempted=1
   elif _command_exist microdnf && _sudo_available; then
      _run_command --prefer-sudo -- microdnf install -y bats
      pkg_attempted=1
   fi

   if _bats_meets_requirement \"$required\"; then
      return 0
   fi

   local target_version=\"${BATS_PREFERRED_VERSION:-1.10.0}\"
   if _install_bats_from_source \"$target_version\" && _bats_meets_requirement \"$required\"; then
      return 0
   fi

   if (( pkg_attempted == 0 )); then
      echo \"Cannot install bats >= ${required}: no suitable package manager or sudo access available.\" >&2
   else
      echo \"Cannot install bats >= ${required}. Please install it manually.\" >&2
   fi

   exit 127
}
"""


def apply(target: Path) -> None:
    text = target.read_text()
    start = text.find("function _version_ge() {")
    if start == -1:
        start = text.find("function _ensure_bats() {")
    if start == -1:
        raise SystemExit("Could not locate _ensure_bats block in system.sh")

    end = text.find("function _ensure_cargo()", start)
    if end == -1:
        raise SystemExit("Could not locate _ensure_cargo in system.sh")

    updated = text[:start] + REPLACEMENT + "\n\n" + text[end:]
    target.write_text(updated)


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    apply(repo_root / "scripts" / "lib" / "system.sh")


if __name__ == "__main__":
    main()
