# Copilot review findings: PR #160 (v1.43.15)

**Date:** 2026-11-12
**PR:** https://github.com/wilddog64/k3d-manager/pull/160
**Review note:** Copilot reported it could not complete the review at the selected tier (model policy), so
this is a partial review: one inline finding.

## Finding 1: `read_lines` assigns array elements with `eval` (scripts/tests/test_helpers.bash:204)

Copilot flagged the Bash < 4 branch of `read_lines`, which assigned each line with
`eval "${array_name}[$i]=$quoted"`. The value was `%q`-quoted, so a line's content could not inject. The
array name was not checked, though, and the repo's security rules say never to `eval`.

**Fix:**

Before:

```bash
    local line i=0 quoted
    unset "$array_name"
    [[ -r "$file" ]] || return 0
    while IFS= read -r line; do
      printf -v quoted '%q' "$line"
      eval "${array_name}[$i]=$quoted"
      (( i++ ))
    done < "$file"
```

After:

```bash
    local line i=0
    [[ "$array_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    unset "$array_name"
    [[ -r "$file" ]] || return 0
    while IFS= read -r line; do
      IFS= read -r "${array_name}[$i]" <<< "$line"
      (( i++ ))
    done < "$file"
```

**Copilot's suggested fix was wrong for this branch.** It proposed `printf -v "${array_name}[$i]"`, which
needs bash 4.1. The branch runs only on bash < 4, and on macOS `/bin/bash` 3.2.57 it failed with
`printf: 'arr[0]': not a valid identifier`, leaving the array empty. `read -r` into an array element works on
3.2 and assigns globally, as `eval` did.

**Evidence (2026-11-12, M4, `/bin/bash` 3.2.57):**
- On a fixture with a plain line, a line containing `$(touch …)` and backticks, leading and trailing
  spaces, an empty line, and mixed quotes, the new output is byte-identical (`cmp`) to the pre-fix `eval`
  output.
- No injection marker file was created.
- The array is visible after being set from inside a function.
- An invalid name such as `x[0]` returns 1.
- BATS: `read_lines.bats`, `run_command.bats`, `eso.bats`, `vault.bats`, `install_k3s.bats`, 49/49 ok, rc=0.
  These run on bash 5, which takes the `mapfile` branch.

**Root cause:** a bash 3.2 compatibility fallback written with `eval` before the no-eval rule was applied
to test helpers.

**Process note:** test a reviewer's suggested fix on the code path it changes. Here that path runs only on
an old interpreter, and the suggestion would have broken it while CI on bash 5 stayed green.
