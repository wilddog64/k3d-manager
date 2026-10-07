# `make test-all` case 236 uses an empty `_e2e_recorded` fixture

Status: FIXED
Severity: Medium
Area: Test fixture

## Evidence

The live `make test-all` run completed 328 cases but failed only case 236:

```text
ok 235 e2e passes DIGEST through to the vcluster harness
not ok 236 recorded output preserves exit status and is mode 600
# (in test file scripts/tests/bin/makefile_e2e_recorded.bats, line 43)
#   `[ "${status}" -eq 2 ]' failed
...
[k3dm-test-metrics] 1707 cases, 1 failed
make: *** [test-all] Error 2
```

The focused test's captured output was:

```text
make: `probe' is up to date.
```

The fixture uses:

```text
awk '/^define _e2e_recorded$/{copy=1} copy{print} /^endef$/{exit}' "${MAKEFILE}" > "${minimal}"
```

There is an earlier `endef` in the full Makefile. The awk command exits at that
first `endef`, before reaching `define _e2e_recorded`, so the generated Makefile
contains no macro definition and the `probe` recipe is empty. The intended failing
`script` command never executes.

## Root cause

The fixture extractor's `endef` condition is not scoped to the point where the
target macro was found. It can silently create an incomplete Makefile whenever a
previous Make macro appears before `_e2e_recorded`.

## Recommended fix

Use a state-aware extractor that starts copying only at `_e2e_recorded` and exits
only after that definition's matching `endef`, or avoid extracting the macro by
using a temporary include that references the real Makefile. Add an assertion that
the generated fixture contains `script -q` before running the probe.

Implemented by scoping the `endef` exit condition to the active copy state and
asserting that the generated fixture contains the recording command. The focused
test passes, and the complete `scripts/tests/bin` suite passes 328/328.
