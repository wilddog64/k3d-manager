# Issue: Copilot PR #31 Review — vCluster plugin findings (two rounds)

## Date
2026-03-15

## PR
[#31 v0.9.1 — vCluster Plugin](https://github.com/wilddog64/k3d-manager/pull/31)

## Reviewer
`copilot-pull-request-reviewer` (GitHub Copilot) — two review passes

---

## Round 1 — initial vCluster plugin (commits `68b263c`, `f444c4b`)

### Finding 1 — `vcluster_destroy` deletes shared namespace (P1)

**File:** `scripts/plugins/vcluster.sh`

**Problem:** `vcluster delete ... --delete-namespace` was passed unconditionally. Since all
vClusters share `VCLUSTER_NAMESPACE` (default: `vclusters`), deleting one tenant would
remove the entire namespace and terminate all other active vClusters — including parallel
CI jobs creating ephemeral clusters in the same namespace.

**Fix:** Removed `--delete-namespace`. `vcluster delete` without the flag removes only the
vCluster resources, leaving the shared namespace intact.

**Status:** FIXED — commit `68b263c`

---

### Finding 2 — KUBECONFIG multi-file merge overwrites partial config (P2)

**File:** `scripts/plugins/vcluster.sh` line 78

**Problem:** `vcluster_use` extracted only the first path from a multi-file `KUBECONFIG`
chain (`IFS=':' read -r base_config _ <<< "$KUBECONFIG"`), merged the vCluster kubeconfig
against just that file, then rewrote it and exported `KUBECONFIG` pointing only to it.
Contexts from all other files in the chain were silently dropped.

**Fix:** `merge_chain="${KUBECONFIG:-$base_config}"` — pass the full chain to
`kubectl config view --flatten` so all existing contexts are preserved in the merged output.

**Status:** FIXED — commit `68b263c`

---

### Finding 3 — kubeconfig written with world-readable permissions (P1)

**File:** `scripts/plugins/vcluster.sh`

**Problem:** Both `vcluster_use` and `_vcluster_export_kubeconfig` wrote kubeconfig content
using `printf > file` followed by `chmod 600`. A window existed between file creation and
`chmod` where the file was readable by anyone with access to the filesystem (process umask
applies on creation, not retroactively).

**Fix:** Replaced both writes with `_write_sensitive_file`, which sets `umask 077` before
creating the file — permissions are safe from the first byte written.

**Status:** FIXED — commit `68b263c`

---

### Finding 4 — `_vcluster_ensure_exists` partial name match (P2)

**File:** `scripts/plugins/vcluster.sh`

**Problem:** Existence check used `[[ "$list_output" != *"$name"* ]]` — a substring match.
A cluster named `dev` would falsely match `dev2`, `dev-staging`, or even the `NAME` header
row. Could silently proceed with a destroy on the wrong cluster.

**Fix:** Parse `vcluster list` output column by column, skip the header row, and match the
first column exactly.

**Status:** FIXED — commit `68b263c`

---

### Finding 5 — DNS-label validation missing on vCluster name (P2)

**File:** `scripts/plugins/vcluster.sh` line 200

**Problem:** The `name` argument was used both to construct a filesystem path
(`$VCLUSTER_KUBECONFIG_DIR/$name.yaml`) and as a kubectl label selector value. No
validation prevented names containing `/`, `..`, leading hyphens, or shell metacharacters —
enabling path traversal and invalid selectors.

**Fix:** Added regex validation against `^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$` (DNS-label
pattern) in `_vcluster_kubeconfig_path`. Rejects all special characters before any path
construction or selector use.

**Status:** FIXED — commit `f444c4b`

---

## Round 2 — after test refactor + smoke test fixes (commit `a89ba81`)

### Finding 6 — Linux CLI auto-install hardcodes amd64 (P1)

**File:** `scripts/plugins/vcluster.sh` line 137

**Problem:** `_vcluster_install_cli` on Linux fetched `vcluster-linux-amd64` unconditionally.
On ARM64 Linux hosts (e.g., Raspberry Pi, Ampere VMs, ARM64 CI runners), the binary is not
runnable — all `vcluster_*` commands would fail at the prerequisites check on first use.

**Fix:** Detect `uname -m` and map `x86_64 → amd64`, `aarch64/arm64 → arm64`. Unknown
architectures get a clear error. Download URL uses the detected `$dl_arch` variable.

**Status:** FIXED — commit `a89ba81`

---

### Finding 7 — `brew install` with `--prefer-sudo` breaks Homebrew (P2)

**File:** `scripts/plugins/vcluster.sh` line 131

**Problem:** `_run_command --prefer-sudo -- brew install loft-sh/tap/vcluster` would run
Homebrew as root whenever passwordless sudo was available. Homebrew explicitly forbids
running as root — it causes ownership issues on formula files and leaves the installation in
a broken state for the normal user.

**Fix:** Changed to `_run_command -- brew install loft-sh/tap/vcluster` (no `--prefer-sudo`).
Homebrew always runs as the current user.

**Status:** FIXED — commit `a89ba81`

---

### Finding 8 — KUBECONFIG merge skips flatten when first file absent (P2)

**File:** `scripts/plugins/vcluster.sh` line 103

**Problem:** After the Round 1 fix, `vcluster_use` still gated `kubectl config view --flatten`
on `[[ -f "$base_config" ]]`. If `KUBECONFIG=/tmp/new:/path/existing` and `/tmp/new` did
not yet exist, the condition was false — only the bare vCluster kubeconfig was written,
silently dropping all contexts from `/path/existing`.

**Fix:** Removed the conditional branch entirely. `kubectl config view --flatten` is always
called against the full `merge_chain`, regardless of whether `base_config` exists. The
flatten command handles missing files in the chain gracefully.

**Status:** FIXED — commit `a89ba81`

---

### Finding 9 — `_match_category` inner function leaks into global namespace (P2)

**File:** `scripts/lib/help/utils.sh` line 122

**Problem:** `_match_category()` was declared inside `_usage()`. Bash function declarations
are always global — not block-scoped — so calling `_usage` permanently added `_match_category`
to the global function table. A function with that name in a plugin or library would be
silently overridden after the first `_usage` call.

**Fix:** Renamed to `__usage_match_category` (double-underscore prefix signals internal/
private utility). All call sites updated. The name is now collision-resistant by convention.

**Status:** FIXED — commit `a89ba81`

---

### Finding 10 — README invocation path mismatch (nit)

**File:** `README.md` line 72 / `scripts/lib/help/utils.sh`

**Problem:** README examples showed `./scripts/k3d-manager` (correct — invoked from repo
root), but the usage text output by `_usage()` said `Usage: ./k3d-manager ...` and
`Run ./k3d-manager --help ...`. New users reading the help output would try the wrong path.

**Fix:** Updated `_usage()` to output `./scripts/k3d-manager` in both the `Usage:` line and
the `Run ... --help` footer. Updated the README sample block to match.

**Status:** FIXED — commit `a89ba81`

---

### Finding 11 — `--delete-namespace` spec/implementation conflict (doc)

**File:** `docs/plans/v0.9.1-vcluster-plugin.md`, `docs/plans/v0.9.1-vcluster-codex-task.md`

**Problem:** Both spec docs still described `vcluster delete ... --delete-namespace --wait`
as the intended behavior. The implementation removed this flag in Round 1 (Finding 1), but
the specs were never updated — creating confusion when Copilot re-flagged the discrepancy.

**Fix:** Updated both spec docs to document the intentional omission with rationale: shared
namespace must not be deleted when a single tenant is removed.

**Status:** FIXED — commit `d9ed235`

---

## Lessons

- **Shared namespace + `--delete-namespace` is a footgun** — always check whether a CLI
  delete flag targets a shared or per-resource namespace before using it.
- **Inner bash functions are not scoped** — never define helper functions inside another
  function if they might collide with the global namespace. Use `__` prefix for private utils.
- **KUBECONFIG merge logic is subtle** — both the "first file only" bug and the "missing
  first file" bug came from trying to be clever about the merge path. The simple fix
  (always flatten the full chain) was also the most correct.
- **Brew must not run as root** — `--prefer-sudo` is appropriate for filesystem operations
  but not package managers that manage their own file ownership.
- **Always detect architecture for binary downloads** — amd64 hardcodes are a common
  oversight; `uname -m` + a case statement is a one-time fix that future-proofs all
  ARM64 environments.
