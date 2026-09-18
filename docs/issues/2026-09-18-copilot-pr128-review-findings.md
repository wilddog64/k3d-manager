# Copilot review findings — PR #128 (v1.35.0)

**Date:** 2026-09-18
**PR:** [#128](https://github.com/wilddog64/k3d-manager/pull/128) — v1.35.0
**Findings:** 3 — 1 already fixed before review landed, 2 hardening, 0 false positives

---

## F1 — `Makefile:690/693/702`: `set -euo pipefail` under make's default `/bin/sh`

> `test-bin` runs under make's default `/bin/sh` (dash on Ubuntu), so `set -euo pipefail` will
> fail because `pipefail` is not supported. Set the target's `SHELL` to bash (or wrap the recipe in
> `bash -c`) so this works in CI.

**Status: already fixed in `2c205e3e`**, pushed before the review was posted — Copilot reviewed
`404d2139`. Independently discovered from the CI failure itself:

```
/bin/sh: 1: set: Illegal option -o pipefail
make: *** [Makefile:684: test-bin] Error 2
```

Fixed with a file-level `SHELL := /bin/bash` rather than per-target `SHELL`, because the same
defect sat latently in **five** recipes, not three: Copilot found the three new test targets, and
the two it could not see from the diff were the live AWS targets `fleet-render` and `fleet-plan`,
which would have failed identically on any Linux host. A per-target fix would have left those two.

Reproduced deterministically before fixing — `/bin/dash` is installed on this workstation:

```
$ make SHELL=/bin/dash test-bin
/bin/dash: 1: set: Illegal option -o pipefail
make: *** [test-bin] Error 2
```

**Root cause:** macOS `/bin/sh` is bash in sh mode and accepts `pipefail`; Debian/Ubuntu `/bin/sh`
is dash and rejects it. The recipe was written and tested only on macOS.

---

## F2 — `scripts/plugins/argocd.sh:11`: guarded source of a required dependency

> `argocd.sh` now unconditionally calls `_acg_provider_state_dir` to set
> `ARGOCD_BROWSER_TLS_DIR`, but sourcing `lib/provider.sh` is guarded and can silently no-op. […]
> Since provider helpers are required here, fail fast when `provider.sh` is missing.

**Valid.** Not reachable today — the dispatcher sources `lib/provider.sh` unconditionally at
`scripts/k3d-manager:68`, and both `bin/cluster-up` and `bin/cluster-refresh` source it too — so
this is hardening, not a live defect. But the guard actively lied about the contract: an
`if [[ -r ]]` wrapper says "optional", while line 68 says "required". If it ever no-opped, the
command substitution at `argocd.sh:68` would yield an empty prefix and put the Vault-PKI-issued
TLS material at the absolute path `/argocd-browser-https-tls/` — silently wrong, which is worse
than a hard failure.

Before:

```bash
PROVIDER_LIB="$SCRIPT_DIR/lib/provider.sh"
if [[ -r "$PROVIDER_LIB" ]]; then
   source "$PROVIDER_LIB"
fi
```

After:

```bash
PROVIDER_LIB="$SCRIPT_DIR/lib/provider.sh"
if [[ ! -r "$PROVIDER_LIB" ]]; then
   printf '[argocd] required provider helpers not readable: %s\n' "$PROVIDER_LIB" >&2
   return 1 2>/dev/null || exit 1
fi
source "$PROVIDER_LIB"
```

`return 1 2>/dev/null || exit 1` so it aborts correctly whether the file is sourced (the normal
case) or executed.

---

## F3 — `scripts/lib/providers/k3s-hostinger.sh:379`: uses `_acg_provider_state_dir` without sourcing it

> `_hostinger_write_argocd_browser_https_wrapper` now uses `_acg_provider_state_dir` in a command
> substitution, but this file doesn't source `scripts/lib/provider.sh`. […] Ensure provider helpers
> are available inside the wrapper writer before using `_acg_provider_state_dir`.

**Valid, and the sharper of the two.** The file depended on an **implicit global** — it worked only
because something earlier in the load order had sourced `provider.sh`. It sources its other two
dependencies (`plugins/shopping_cart.sh`, `etc/hostinger/vars.sh`) explicitly at the top, so this
one was simply missing. Fixed to match the file's own idiom:

```bash
# _acg_provider_state_dir resolves the provider-scoped TLS paths below; source it
# here rather than relying on the dispatcher having loaded it first.
source "${SCRIPT_DIR}/lib/provider.sh"
```

`_acg_provider_state_dir` is not guarded behind `declare -f` deliberately —
`reference_dispatcher_lazy_load_cross_plugin_calls` records that a `declare -f` guard is a smell;
sourcing the dependency is the established idiom.

**This finding proved itself immediately.** Making the dependency explicit turned
`provider_contract.bats:241` red:

```
not ok 241 _hostinger_refresh_access_layer restarts argocd port-forward before cloudflared
# .../k3s-hostinger.sh: line 10: /tmp/bats-run-TnzCPS/test/241/scripts/lib/provider.sh: No such file or directory
```

That test builds a sandbox `SCRIPT_DIR` with empty stubs for the file's dependencies, and had
never provided `provider.sh` — so the case had been passing only because `setup()` leaked the real
function into the BATS process via `test_helpers.bash`. Exactly the fragility Copilot described.
The sandbox now gets the **real** `provider.sh` (copied, like the wrapper templates), because the
case exercises the wrapper writer that calls it and an empty stub would not do.

---

## Process note

F1 is a second instance of this release's own theme: a gate that passes on the maintainer's macOS
workstation and cannot work on the Linux runner. Three separate instances landed on this one PR —
`rg` vs `grep`, a sibling-repo fixture, and `sh` vs `bash`. The review rules added to
`.github/copilot-instructions.md` under **Test Reachability (v1.35.0+)** already cover host-state
dependence in tests; F1 shows the same rule is needed for the **Makefile**, whose recipes are also
a host-dependent execution environment. A `SHELL` declaration is now present, so the class is
closed at the source rather than per-recipe.

F2 and F3 are the same defect in two forms: a required dependency treated as optional. The lesson
worth keeping is that the harm is not a crash but a **plausible wrong path** — an empty
`_acg_provider_state_dir` yields `/argocd-browser-https-tls/tls.key`, which looks like a path and
is writable as root. Fail fast beats a cert in the wrong place.
