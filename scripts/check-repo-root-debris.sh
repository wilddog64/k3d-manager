#!/usr/bin/env bash
# Fail when a commit would add test/job debris at the repository root.
#
# An unchecked "$(mktemp)" returns an empty string when TMPDIR is unwritable, so every
# path derived from it loses its directory and lands in the current working directory —
# which during a test run is the repo root. It is silent: no error, no red test.
# See docs/bugs/2026-09-24-empty-mktemp-writes-into-the-repo-root.md
#
# Staged files only. Untracked debris already sitting in the tree must not block an
# unrelated commit; only committing it is the failure.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

_staged() {
  if (( $# > 0 )); then
    printf '%s\n' "$@"
  else
    git diff --cached --name-only --diff-filter=ACMR
  fi
}

_hits=()
while IFS= read -r _path; do
  [[ -z "${_path}" ]] && continue
  [[ "${_path}" == */* ]] && continue
  case "${_path}" in
    .join-failures.*|*.join-failures.*) _hits+=("${_path}") ;;
    .pub|.key) _hits+=("${_path}") ;;
    .*.[0-9][0-9][0-9]*) _hits+=("${_path}") ;;
  esac
done < <(_staged "$@")

if (( ${#_hits[@]} > 0 )); then
  printf 'Repo-root debris staged for commit:\n' >&2
  printf '  %s\n' "${_hits[@]}" >&2
  printf '\nThese are written by a path derived from an EMPTY variable, usually an\n' >&2
  printf 'unchecked "$(mktemp)" under an unwritable TMPDIR, so the path lost its\n' >&2
  printf 'directory and resolved against the repo root.\n' >&2
  printf 'Fix the producer, do not just delete the file:\n' >&2
  printf '  docs/bugs/2026-09-24-empty-mktemp-writes-into-the-repo-root.md\n' >&2
  printf 'Tests should use "${BATS_TEST_TMPDIR}" rather than mktemp.\n' >&2
  exit 1
fi
