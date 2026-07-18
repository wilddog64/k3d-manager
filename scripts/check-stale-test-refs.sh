#!/usr/bin/env bash
# Fail when a commit removes a string from scripts/etc/ that scripts/tests/ still asserts.
set -euo pipefail

_range="${1:-HEAD^..HEAD}"
cd "$(git rev-parse --show-toplevel)"

_hits=0
_report() {
  printf '%s\n  removed from: %s\n' "$1" "$2"
  printf '%s\n' "$3" | sed 's/^/  still asserted in: /'
  _hits=$((_hits + 1))
}

while IFS= read -r _file; do
  [[ -z "${_file}" ]] && continue
  _base="$(basename "${_file}")"
  while IFS= read -r _line; do
    _frag="${_line#"${_line%%[![:space:]]*}"}"
    _frag="${_frag%"${_frag##*[![:space:]]}"}"
    [[ ${#_frag} -lt 10 ]] && continue
    [[ "${_frag}" != *:* && "${_frag}" != *[[:space:]]* ]] && continue
    [[ "${_frag}" == *'${'* ]] && continue
    [[ -f "${_file}" ]] && grep -qF -- "${_frag}" "${_file}" 2>/dev/null && continue
    _consumers="$(grep -rlF -- "${_frag}" scripts/tests/ 2>/dev/null || true)"
    [[ -z "${_consumers}" ]] && continue
    if grep -rqF -- "${_frag}" scripts/etc/ 2>/dev/null; then
      _tied="$(printf '%s\n' "${_consumers}" | xargs -r grep -lF -- "${_base}" 2>/dev/null || true)"
      [[ -n "${_tied}" ]] && _report "MOVED OUT OF ${_base}: ${_frag}" "${_file}" "${_tied}"
    else
      _report "REMOVED: ${_frag}" "${_file}" "${_consumers}"
    fi
  done < <(git diff "${_range}" -- "${_file}" | grep '^-' | grep -v '^---' | sed 's/^-//' \
    | awk '{ print } /"/ { n=split($0, a, /"/); for (i=2; i<=n; i+=2) if (length(a[i]) >= 10) print a[i] }' \
    | sort -u || true)
done < <(git diff --name-only "${_range}" -- scripts/etc/ || true)

if (( _hits > 0 )); then
  printf '\n%s stale test reference(s) — retarget the tests or list them in the spec gates.\n' "${_hits}"
  exit 1
fi
printf 'no stale test references\n'
