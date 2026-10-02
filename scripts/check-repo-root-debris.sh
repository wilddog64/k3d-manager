#!/usr/bin/env bash
# Fail when test/job debris appears at the repository root.
#
# An unchecked "$(mktemp)" returns an empty string when TMPDIR is unwritable, so every
# path derived from it loses its directory and lands in the current working directory —
# which during a test run is the repo root. It is silent: no error, no red test.
# See docs/bugs/2026-09-24-empty-mktemp-writes-into-the-repo-root.md
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

_hits=()
while IFS= read -r _path; do
  _path="${_path#./}"
  case "${_path}" in
    .join-failures.*|*.join-failures.*) _hits+=("${_path}") ;;
    .pub|.key) _hits+=("${_path}") ;;
    .*.[0-9][0-9][0-9]*) _hits+=("${_path}") ;;
  esac
done < <(find . -maxdepth 1 -type f -print)

if (( ${#_hits[@]} > 0 )); then
  printf 'Repo-root debris found:\n' >&2
  printf '  %s\n' "${_hits[@]}" >&2
  printf '\nThese are written by a path derived from an EMPTY variable, usually an\n' >&2
  printf 'unchecked "$(mktemp)" under an unwritable TMPDIR, so the path lost its\n' >&2
  printf 'directory and resolved against the repo root.\n' >&2
  printf 'Fix the producer, do not just delete the file:\n' >&2
  printf '  docs/bugs/2026-09-24-empty-mktemp-writes-into-the-repo-root.md\n' >&2
  printf 'Tests should use "${BATS_TEST_TMPDIR}" rather than mktemp.\n' >&2
  exit 1
fi
