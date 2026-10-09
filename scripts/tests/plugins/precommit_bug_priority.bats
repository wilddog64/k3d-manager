#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${repo}/docs/bugs"
  git -C "${repo}" init -q
  git -C "${repo}" config user.email test@example.invalid
  git -C "${repo}" config user.name Test
  printf '%s\n' '# seed' >"${repo}/README.md"
  git -C "${repo}" add README.md
  git -C "${repo}" commit -qm seed
  hook="${BATS_TEST_DIRNAME}/../../../.githooks/pre-commit"
}

run_hook() {
  cd "${repo}"
  run env K3DM_SKIP_DOC_LINKS=1 K3DM_SKIP_ROOT_DEBRIS=1 bash "${hook}"
}

@test "new bug doc without Priority is rejected" {
  printf '%s\n' '# Bug' '**Status:** Open' >"${repo}/docs/bugs/new.md"
  git -C "${repo}" add docs/bugs/new.md
  run_hook
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"needs **Priority:**"* ]]
}

@test "new bug doc with P2 is accepted" {
  printf '%s\n' '# Bug' '**Status:** Open' '**Priority:** P2' >"${repo}/docs/bugs/new.md"
  git -C "${repo}" add docs/bugs/new.md
  run_hook
  [ "${status}" -eq 0 ]
}

@test "modified legacy bug doc without Priority is accepted" {
  printf '%s\n' '# Bug' '**Status:** Open' >"${repo}/docs/bugs/legacy.md"
  git -C "${repo}" add docs/bugs/legacy.md
  git -C "${repo}" commit -qm legacy
  printf '%s\n' '# Bug changed' '**Status:** Open' >"${repo}/docs/bugs/legacy.md"
  git -C "${repo}" add docs/bugs/legacy.md
  run_hook
  [ "${status}" -eq 0 ]
}

@test "the staged copy is checked, not the working tree" {
  printf '%s\n' '# Bug' '**Status:** Open' >"${repo}/docs/bugs/new.md"
  git -C "${repo}" add docs/bugs/new.md
  printf '%s\n' '# Bug' '**Status:** Open' '**Priority:** P2' >"${repo}/docs/bugs/new.md"
  run_hook
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"needs **Priority:**"* ]]
}
