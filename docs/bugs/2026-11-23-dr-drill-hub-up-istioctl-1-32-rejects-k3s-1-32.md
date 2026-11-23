# Bug: `make dr-drill` (and any fresh `hub-up`) fails: unpinned Homebrew istioctl 1.32 rejects the pinned k3s v1.32 image

**Status:** OPEN — spec rev 2 (Fable rev 1 review: NEEDS FIXES, 1 blocker, 5 should-fix, 5 nits; all applied); captured 2026-11-23 by Claude from the operator's m2-air run
**Priority:** P2 (operator, 2026-11-23; flagged — it blocks the DR drill and a from-scratch hub rebuild on this Mac)
**Triage:** patch → v1.45.1 (operator, 2026-11-23); pin target: match the live hub — corrected 2026-11-23 to k3s v1.32.0 + Istio 1.31.x (pin 1.31.4, the first CVE-free 1.31; hub's 1.31.1 to be raised to match)
**Branch:** k3d-manager-v1.45.1
**Introduced by:** pre-existing (istioctl never pinned); exposed by Homebrew upgrading istioctl to 1.32.0 on m2-air 2026-11-12
**Should have been caught by:** live check (the weekly drill; not run 2026-11-04 → 2026-11-23)
**Introducing change reviewed:** no
**Waiting on:** dispatch — since 2026-11-23 (operator intent approval; m4-air istioctl 1.30.0 must be replaced before its next deploy, see Rollout survey)
**Approval:** pending (operator decision 2026-11-23: pin 1.31.4, no k3s bump, archive + SHA-256, refuse other minors)
**Intent approved:** pending
**Prior art:** `docs/bugs/2026-11-22-istio-ambient-appset-targets-retired-ubuntu-k3s.md` (exact-slug glob + grep; vector store unavailable) — read, different root cause; `CHANGELOG.md:2565` — recurrence: k3s was raised to v1.32.0-k3s1 in July "to satisfy the istioctl precheck floor" (same class)
**Detected by:** operator, `make dr-drill` on m2-air, 2026-11-23 ~03:55 PST; also explains the failing daily `Hub DR drill freshness` workflow in `wilddog64/k3dm-hub-data` (stale since 2026-11-04 result)

## Evidence

- Drill output: `Error [IST0142] (Cluster) The Kubernetes Version "v1.32.0+k3s1" is lower than the minimum version: 1.33`,
  then `ERROR: failed to execute istioctl x precheck: 1`, `ERROR: [hub-up] Step 1/5 failed: creating local Hub cluster`.
- m2-air (read-only, 2026-11-23): `/opt/homebrew/bin/istioctl -> ../Cellar/istioctl/1.32.0/bin/istioctl` (link dated
  2026-11-12); `istioctl version --remote=false` → `client version: 1.32.0`.
- k3s pin: `scripts/etc/cluster.yaml.tmpl:7` `image: rancher/k3s:v1.32.0-k3s1`.
- Precheck: `scripts/lib/providers/k3d.sh:105` and `scripts/lib/providers/k3s.sh:89` run `_istioctl x precheck`.
- Unpinned istioctl: `scripts/lib/core.sh:457-461` (`_install_istioctl`) accepts any `istioctl` on PATH; when absent it
  installs the latest candidate from `istio/istio` `master` (`downloadIstioCandidate.sh`). Same in
  `scripts/lib/foundation/scripts/lib/core.sh:455` (lib-foundation subtree: upstream first).
- Last good drill 2026-11-04 predates the 2026-11-12 upgrade.
- **Live hub** (m5-air, context `k3d-k3d-cluster`, read-only 2026-11-23 by Claude): server `v1.32.0+k3s1`, istiod
  `docker.io/istio/pilot:1.31.1`. It matches the template's k3s pin. (Correction: an earlier line here recorded the m2-air
  cluster, `v1.31.5+k3s1` + Istio 1.28.3, as the hub; that is an older cluster, not the hub. Its Istio 1.28 is past
  end of life, Jul 1 2026.)
- istio.io supported-releases, read verbatim 2026-11-23 (no last-updated date on the page): 1.31 → k8s 1.32–1.37,
  EOL ~Mar 2027, no known CVEs from 1.31.4; 1.32 → k8s 1.33–1.37; 1.28 → 1.30–1.34, EOL Jul 1 2026.

## Workaround (untested)

Put an istioctl whose support range includes Kubernetes 1.32 ahead of `/opt/homebrew/bin` for the drill only, from the
official Istio release archive, and re-run `make dr-drill` in Terminal.

## Fix direction (operator decision)

1. Pin istioctl: a version variable, install or verify that version, refuse a PATH istioctl of another minor (upstream
   in lib-foundation first; repo rule A08 pins). And/or
2. Bump `rancher/k3s` in `cluster.yaml.tmpl` to a supported 1.33+ tag — but the drill must rebuild what the live hub
   runs, so first record the hub's server version and Istio version (read-only) and match them.

Either way the istioctl that `hub-up` uses should be the version the live hub's control plane runs.

## Triage input (2026-11-23; decision pending with the operator)

- **Fable (blind, from this doc and the repo):** P2; `patch → v1.45.1`. Pin istioctl from the tagged release archive with
  checksum, refuse a PATH istioctl of another minor; lib-foundation first, then the local `scripts/lib/core.sh` (sourced
  last, `scripts/k3d-manager:81-86`, so it is the live definition). `_istioctl install` (`k3d.sh:106`, `k3s.sh:90`)
  also picks the control-plane version; no hub Istio version is pinned anywhere. Carry any k3s bump to v1.46.0.
  Proposed 1.31.4 (istio.io supported-releases, fetched through a summary 2026-11-23: 1.31 → k8s 1.32–1.37).
- **Claude:** P2 agreed. Fable did not see the live versions: the hub runs k8s 1.31.5 + Istio 1.28.3, which a
  1.31.x pin would not match (1.31 does not list k8s 1.31). The pin choice is either "match the hub" (1.28.x, if its
  range covers the drill's k3s) or "pin forward" (1.31.x) with a hub upgrade in v1.46.0. Re-read the istio.io table
  directly before the spec.
- Adjacent, not this bug (Fable): ambient Istio pinned at an end-of-life 1.24.2 (`scripts/etc/argocd/vars.sh:76`); k3d
  installed from `k3d-io/k3d` `main` unpinned (`scripts/lib/providers/k3d.sh:75`).

---

# Fix spec (rev 1, 2026-11-23, Claude; Fable review pending)

**Decision (operator, 2026-11-23):** pin istioctl to **1.31.4**. Install it from the tagged Istio release archive and
verify it against a pinned SHA-256. Refuse a PATH istioctl whose minor version is not 1.31. No k3s bump; any k3s bump is
carried to v1.46.0.

**Out of scope:**
- Raising the live hub's istiod from 1.31.1 to 1.31.4 (`_istioctl install` on an existing hub). The operator does this
  separately; it is a live change.
- k3s `v1.32.0-k3s1` (`scripts/etc/cluster.yaml.tmpl:7`), left unchanged. 1.31 supports k8s 1.32–1.37.
- Ambient Istio 1.24.2 (`scripts/etc/argocd/vars.sh:76`, `scripts/plugins/istio_ambient.sh:26`,
  `scripts/plugins/shopping_cart.sh:1384`) and the unpinned k3d installer (`scripts/lib/providers/k3d.sh:75`). File
  these separately if they are not already filed.
- `_istioctl` (`scripts/lib/foundation/scripts/lib/system.sh:1307`), unchanged.

## Routing — lib-foundation first, then k3d-manager

The rule is `feedback_lib_edits_upstream_first`, plus lib-foundation `CLAUDE.md`: "Never edit `scripts/lib/foundation/`
inside a consumer directly — fix here, PR, tag, then subtree pull". `_install_istioctl` exists twice:
- in the subtree, `scripts/lib/foundation/scripts/lib/core.sh:455` (upstream `lib-foundation/scripts/lib/core.sh:455`);
- in a local copy, `scripts/lib/core.sh:457`.

The local copy is the live one, because `scripts/k3d-manager:81-86` sources the foundation `core.sh` first and the
local `core.sh` last. The two copies differ only in `pushd`/`popd` redirection. Patching only the local copy would leave
the pin unshared and the subtree still installing from `master`.

So the fix goes upstream, and the local copy is deleted so that the subtree definition becomes the live one. This
removes the duplicate and keeps future pin bumps to one file. rigor-cli and shopping-carts do not call
`_install_istioctl` (grep, 2026-11-23).

| Child | Repo / branch | Worker | Files | Depends on |
|---|---|---|---|---|
| **A** | `lib-foundation` branch `release/v0.5.8` (exists locally and on origin, equal to `main` `15d5001`, clean; v0.5.7 → **v0.5.8**) | **Luna** | 3 | — |
| **B** | `k3d-manager` `k3d-manager-v1.45.1` | **Luna** | 2 (+ subtree pull) | A merged and tagged v0.5.8; Claude runs the subtree pull first |
| **C** | `k3d-manager` `k3d-manager-v1.45.1` | **Flash** | 1 | B landed |

The lib-foundation release (PR, CI, tag v0.5.8) and the `git subtree pull --prefix=scripts/lib/foundation ... v0.5.8
--squash` are done by Claude, not by a worker. Together the three children use one dispatch slot at a time, run in
series.

## Files

| Child | File | Change |
|---|---|---|
| A | `lib-foundation/scripts/lib/core.sh` | Rewrite `_install_istioctl` (Behaviour 1–7). Add `_istioctl_pinned_sha256`. Add the header comment ("comment on touch"). |
| A | `lib-foundation/scripts/tests/lib/install_istioctl.bats` (new) | Offline BATS for M1–M5 and N1–N4, using stubbed `istioctl`, `curl`, `shasum`/`sha256sum`, `uname` and `rm` on PATH. `tar` is the real one (it extracts the fixture tarball). |
| A | `lib-foundation/docs/api/functions.md` | Update the `_install_istioctl` row (pinned archive + SHA-256, refuses another minor) and add a `_istioctl_pinned_sha256` row, next to `_install_promtool` (`:81`). |
| B | `scripts/lib/core.sh` | Delete the local `_install_istioctl` (lines 457–493) so the subtree v0.5.8 definition is live. Nothing else. |
| B | `scripts/tests/lib/install_istioctl_dispatch.bats` (new) | Proves that the definition the dispatcher loads is the pinned one (no `downloadIstioCandidate`, refuses a 1.32 PATH stub), and that `_provider_k3d_configure_istio` / the k3s Istio deploy never call `_istioctl` after a refusal (N5). |
| B | `scripts/lib/foundation/**` | Arrives only through Claude's subtree pull. The worker does not edit it. |
| C | `CHANGELOG.md` | v1.45.1 entry: istioctl pinned to 1.31.4, how to override the pin, and the error message with its fix. |

## Behaviour

1. **Pin variable.** `ISTIOCTL_VERSION` defaults to `1.31.4` inside `_install_istioctl`, as `${ISTIOCTL_VERSION:-1.31.4}`.
   This follows the `_install_promtool` precedent (`PROMTOOL_VERSION`, `system.sh:807-808`). It is not set anywhere in
   k3d-manager. An operator who exports a different version is deliberately moving the pin.
2. **Pinned checksums.** `_istioctl_pinned_sha256 <version> <os> <arch>` prints the SHA-256 for `1.31.4` and
   `osx|linux` × `arm64|amd64` (table in *External behaviour*). For any other combination it returns non-zero. This
   follows the `_promtool_pinned_sha256` precedent.
3. **Existing istioctl, same minor → accept.** Check, in order, `"${install_dir}/istioctl"` (if executable) and then
   `command -v istioctl`, following the `_install_promtool` precedent of checking `$target` first (`system.sh:811`). The
   install-dir check matters because `k3d.sh:59` installs into `~/.local/bin` before `k3d.sh:63-66` adds it to PATH, so a
   PATH-only check would re-download about 105 MB on every run. For the first candidate found, run
   `"<path>" version --remote=false`, read stdout only (stderr discarded), and match the anchored pattern
   `^client version: ([0-9]+)\.([0-9]+)\.` on its first matching line. If `X.Y` equals the pin's `X.Y`, print
   `istioctl <found> at <path> matches pin <ISTIOCTL_VERSION> (minor <X.Y>)` and return 0. Patch skew, such as 1.31.1
   against a 1.31.4 pin, is accepted.
4. **Existing istioctl, other minor or unparsable → refuse with `_err` (exits).** Anything that does not match the
   anchored pattern counts as `unknown` and is refused (fail closed). Download nothing. Call `_err` with one message
   that names:
   - the found version, or `unknown`;
   - its resolved path;
   - the pinned version;
   - the fix: `put istioctl <pin> first on PATH (https://github.com/istio/istio/releases/tag/<pin>), e.g. 'brew unlink
     istioctl', or set ISTIOCTL_VERSION to deliberately move the pin`.

   Example: `ERROR: istioctl 1.32.0 at /opt/homebrew/bin/istioctl does not match the pinned 1.31.4 (minor 1.31) ...`.

   **Why `_err` (exit) and not `return 1`.** `scripts/k3d-manager` has no `set -e` and runs
   `$function_name "$@" || exit_code=$?` (`:574-578`), so errexit is off for the whole call tree, and all four call sites
   are bare calls (`k3d.sh:59`, `:61`, `:104`, `k3s.sh:88`). A `return 1` would be ignored: `k3d.sh:105-106` /
   `k3s.sh:89-90` would go on to run `_istioctl x precheck` and `install` with the refused binary, and a mismatched minor
   whose support range covers k8s 1.32 would pass precheck and install the wrong control plane. Today's function already
   ends in `exit 1` on its failure path (`core.sh:478`), so exiting keeps the contract. Rejected alternative (b): add
   `|| return 1` at the four call sites and check `_provider_k3d_install` at `k3d.sh:189/191`. That widens child B to
   two more files, and the callers of `_provider_k3d_install` are themselves unchecked, so it would not stop the run
   either without a wider change. Behaviour 5 and 6 failures use `_err` for the same reason.
5. **Absent → pinned archive.** Detect `os` from `uname -s` (Darwin→`osx`, Linux→`linux`) and `arch` from `uname -m`
   (arm64|aarch64→`arm64`, x86_64|amd64→`amd64`). Then:
   - Look up the checksum. If there is none, `_err` naming `<version>-<os>-<arch>`, without any download.
   - Download
     `${ISTIOCTL_BASE_URL:-https://github.com/istio/istio/releases/download}/<v>/istioctl-<v>-<os>-<arch>.tar.gz`
     with `curl -fsSL` into a private `mktemp -d`.
   - Verify it with `shasum -a 256 "<tarball>"`, or `sha256sum "<tarball>"` as a fallback; with neither tool, `_err`.
   - On a mismatch, remove the temp dir and `_err` with `expected` and `actual`; install nothing.
   - Only after a match, extract `istioctl` and install it to `install_dir`. Keep the existing behaviour: default
     `/usr/local/bin`, `mkdir -p` with a `_run_command --prefer-sudo` fallback, and `cp` with `--prefer-sudo` when the
     directory is not writable.
6. **Post-install check.** Run the installed binary by full path, `"${install_dir}/istioctl" version --remote=false`
   (not the PATH lookup, because `install_dir` may not be on PATH yet). It must report the pinned version through the
   same anchored pattern. Otherwise `_err`.
7. **No side effects on the caller.**
   - Never fetch `raw.githubusercontent.com/istio/istio/master/...` or `downloadIstioCandidate.sh`.
   - Do not install a global `trap ... EXIT` (the current code replaces the caller's EXIT trap with
     `rm -rf /tmp/istio-*`). Clean up the private temp dir before returning.
   - No `cd`/`pushd` into `/tmp`, and no `rm` outside the private temp dir.
   - Bash 3.2 compatible.
   - Every expansion is quoted.

## External behaviour (proof, per "prove external behaviour before dispatch")

- **Release:** `gh release view 1.31.4 --repo istio/istio`, run on m4-air on 2026-11-23T16:40Z. It shows tag `1.31.4`,
  published 2026-11-06T19:01:19Z, not a prerelease. Its assets include `istioctl-1.31.4-{osx-arm64,osx-amd64,
  linux-amd64,linux-arm64}.tar.gz` plus `.sha256` for each. A combined `istioctl-1.31.4-osx.tar.gz` also exists; do not use it.
- **Checksums:** the published `.sha256` assets, downloaded with `gh release download 1.31.4 --repo istio/istio` on
  m4-air, 2026-11-23T16:40Z:

  | os-arch | SHA-256 (`istioctl-1.31.4-<os-arch>.tar.gz`) |
  |---|---|
  | osx-arm64 (darwin-arm64) | `2be63df4a0fedb10c9c5402cdbf2f666e84330f3c68aef244975225ea63ef675` |
  | osx-amd64 (darwin-amd64) | `da2398901943b3718566ca59311e045a0d99089006394fb573f34c23cd720311` |
  | linux-amd64 | `7c00227d87f280c2450483e3518e3a73af62c057363b779ea80931c409e8852e` |
  | linux-arm64 | `3a1a82af8788059192d411e92d952c32d31a69bc20a039b3915f536d395e0c24` |

  osx-arm64 was cross-checked: the downloaded tarball, re-hashed locally with `shasum -a 256`, equals the published
  value. The other three are the published values only (not re-hashed).
- **Archive layout:** the osx-arm64 tarball holds a single entry, `istioctl`, at the archive root (mode 0755,
  105091426 bytes, per `tar -tvzf`). It is not wrapped in a `istio-<v>/bin/` directory.
- **Version output:** the extracted 1.31.4 binary was run on m4-air on 2026-11-23. Both `istioctl version --remote=false`
  and `--short` print exactly `client version: 1.31.4`. On m2-air (Homebrew 1.32.0, 2026-11-23, in Evidence above) it
  prints `client version: 1.32.0`.
- **Support range:** istio.io supported-releases, read 2026-11-23: 1.31 supports k8s 1.32–1.37, so it accepts k3s
  `v1.32.0+k3s1`, and 1.32 needs k8s ≥ 1.33. That explains IST0142 above.

Not independently re-checked by the Fable reviewer (no network in that review): the four checksums and the istio.io
support ranges. Claude re-fetched the four published `.sha256` assets on m4-air, 2026-11-23, and they match the table.

BATS stubs reproduce these captured lines verbatim, with a comment naming m4-air or m2-air and 2026-11-23.

## Rollout survey (read-only, Claude, 2026-11-23T16:54Z)

After the fix, every `deploy_cluster` / Istio deploy refuses an existing istioctl whose minor is not 1.31.

| Host | Role | `command -v istioctl` | `istioctl version --remote=false` | After the fix |
|---|---|---|---|---|
| m2-air | DR drill host | `/opt/homebrew/bin/istioctl` (Evidence above) | `client version: 1.32.0` | refused (E6) until `brew unlink istioctl` |
| m4-air | dev / worker | `/Users/cliang/.local/bin/istioctl` | `client version: 1.30.0` | **refused**: replace it (delete it so the pinned archive installs, or install 1.31.4) before the next Istio deploy from this Mac |
| m5-air (`ssh -o BatchMode=yes m5-air.local`) | live hub | `/Users/cliang/.local/bin/istioctl` | `client version: 1.31.1` | accepted (patch skew) |

CI: `grep -rn istioctl .github/workflows` finds nothing (2026-11-23), so no workflow installs or runs istioctl; the BATS
suites stub `_install_istioctl` (`k3d_install.bats:18`). The e2e runner path calls `deploy_cluster` on the M2 only.
The m4-air 1.30.0 binary is in `~/.local/bin`, which Behaviour 3 now checks first, so it is refused even if another
istioctl sits on PATH. The operator should know this before the release lands.

## Contract readers

These were found by `git grep -n -E "_install_istioctl|function _istioctl|ISTIOCTL_VERSION|ISTIO_VERSION"` over
`scripts bin Makefile .github` (k3d-manager) and over lib-foundation, rigor-cli and shopping-carts, on 2026-11-23.

**Writers** (what decides the istioctl binary or the pin):
- `scripts/lib/core.sh:457`: local `_install_istioctl`, the live copy. B deletes it.
- `scripts/lib/foundation/scripts/lib/core.sh:455` (upstream `lib-foundation/scripts/lib/core.sh:455`): A rewrites it;
  B receives it through the subtree pull.
- `ISTIOCTL_VERSION` and `ISTIOCTL_BASE_URL` are new. Today grep finds no reader or writer outside the new function.
- Outside the repos: Homebrew writes `/opt/homebrew/bin/istioctl` (m2-air, 1.32.0). After the fix that binary is refused
  (Behaviour 4) instead of being silently used.

**Callers** (behaviour change: a mismatched PATH istioctl now stops them with the Behaviour 4 error):
- `scripts/lib/providers/k3d.sh:59` (`_install_istioctl "$HOME/.local/bin"`, mac) and `:61` (default dir): tool
  install during `_provider_k3d_install`.
- `scripts/lib/providers/k3d.sh:104`: k3d Istio deploy, which runs `_istioctl x precheck` (`:105`) and `install` (`:106`).
- `scripts/lib/providers/k3s.sh:88`: k3s Istio deploy, which runs precheck (`:89`) and install (`:90`).
- Entry callers of those: `scripts/lib/providers/k3d.sh:189`, `:191`, `:197` and `scripts/lib/providers/orbstack.sh:61`,
  `:66`. With Behaviour 4 exiting, a refusal ends these runs too, which is the intent.

**Readers of the installed binary:**
- `scripts/lib/foundation/scripts/lib/system.sh:1307` (`_istioctl`). Unchanged; it runs whichever `istioctl` is on PATH.
  `_install_istioctl` runs first at every call site above, so the minor check guards it.

**Unguarded direct users of PATH `istioctl` (unchanged, out of scope):** `bin/istio-sanity-check:4` and
`bin/inspect-cert:126,133` call `istioctl` straight from PATH without `_install_istioctl`. They are read-only diagnostics;
note them, do not change them in this patch.

**Docs:** `lib-foundation/docs/api/functions.md:77-84` lists the install functions; child A updates it.

**Tests:**
- `scripts/tests/lib/k3d_install.bats:18` replaces `_install_istioctl` with `{ :; }`. It is unaffected, and B must keep it
  green.
- lib-foundation has no istioctl test today (`grep istioctl scripts/tests/lib/*.bats` finds nothing). A adds the first one.

**Not readers:** `AMBIENT_ISTIO_VERSION` (`scripts/etc/argocd/vars.sh:76`, `istio_ambient.sh:26,35,45`,
`shopping_cart.sh:1384`, `k3s-hostinger.sh:935`, `istio-ambient.yaml:89`). It is the ambient Helm chart version, a
separate pin, and is out of scope.

## Acceptance

```yaml
must:
  - M1: With istioctl absent, _install_istioctl downloads exactly
        <base>/1.31.4/istioctl-1.31.4-<os>-<arch>.tar.gz for each of osx-arm64, osx-amd64, linux-amd64, linux-arm64,
        verifies it against the pinned SHA-256, and installs istioctl into install_dir.
  - M2: _istioctl_pinned_sha256 prints the four published 1.31.4 checksums verbatim and returns non-zero for any other
        version or os/arch.
  - M3: An existing istioctl reporting "client version: 1.31.x" (stub 1.31.1 and 1.31.4), either on PATH or at
        ${install_dir}/istioctl when install_dir is not on PATH, is accepted, with rc 0, no download and a line naming
        the found version and the pin.
  - M4: An existing istioctl of another minor (stub "client version: 1.32.0" and "client version: 1.30.0"), or with
        output not matching ^client version: X.Y. (e.g. "1.32.0" alone, or the line only on stderr), exits non-zero via
        _err. One ERROR line names the found version (or "unknown"), its path, the pin 1.31.4 and the fix (release URL,
        'brew unlink istioctl', ISTIOCTL_VERSION).
  - M5: ISTIOCTL_VERSION overrides the pin. With ISTIOCTL_VERSION=1.32.0 the 1.32.0 PATH stub is accepted, and with
        istioctl absent it fails on "no pinned checksum for 1.32.0-<os>-<arch>" without any download.
  - M6: After B, the definition the dispatcher loads (source scripts/k3d-manager's library order) is the subtree v0.5.8
        one, and scripts/lib/core.sh no longer defines _install_istioctl.
must_not:
  - N1: Must not accept a PATH istioctl whose minor differs from the pin.
        Red today: the current code prints "istioctl already exists, skip installation" and returns 0 for the 1.32.0 stub.
  - N2: Must not fetch from istio/istio master or run downloadIstioCandidate.sh.
        Red today: the curl stub log records raw.githubusercontent.com/istio/istio/master/release/downloadIstioCandidate.sh.
  - N3: Must not install (no file in install_dir, no cp call) when the downloaded archive's SHA-256 differs from the pin.
        Red today: there is no checksum step, so the current code copies the binary the candidate script reports.
  - N4: Must not replace the caller's EXIT trap.
        Red today: after the call, `trap -p EXIT` shows "rm -rf /tmp/istio-*" instead of the caller's sentinel trap.
  - N5: _istioctl is never invoked after a refusal. Sourcing the provider Istio deploy (k3d.sh:102-107 and
        k3s.sh:86-91) with a 1.32.0 istioctl stub and an _istioctl function that logs its arguments, inside
        `run bash -c`, the run exits non-zero and the _istioctl log is empty.
        Red today: the old function returns 0 for 1.32.0 ("already exists, skip installation") and the log shows
        "x precheck" and "install -y -f ..." (and with only rc 1, the bare call would still continue to them).
evidence:
  - {id: E1, proves: [M1, M2, N2, N3], kind: offline, intent: pending, command: "lib-foundation: env -i HOME=\"$BATS_TMP\" PATH=\"<stub dir>:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin\" TMPDIR=\"$TMPDIR\" bash --norc --noprofile -c 'bats scripts/tests/lib/install_istioctl.bats' (lib-foundation CLAUDE.md:110-111 form, stub dir first; each case asserts command -v istioctl resolves to the stub or to nothing)", red_control: "the N2 and N3 cases fail against lib-foundation main@15d5001 core.sh: the curl stub serves, for the downloadIstioCandidate.sh URL, a script that creates istio-1.31.4/bin/istioctl and prints the captured 'add the ... directory' line (host and date in a comment), so the old code reaches cp and the N3 'no cp, no file in install_dir' assertion fails; the candidate URL appears in the curl log for N2"}
  - {id: E2, proves: [M3, M4, N1], kind: offline, intent: pending, command: "same suite, the existing-istioctl cases (stub istioctl prints the captured m4-air/m2-air/m5-air lines; one case puts the 1.31.4 stub only in install_dir, not on PATH)", red_control: "the N1 case fails on main@15d5001: rc 0 and 'already exists, skip installation' for the 1.32.0 stub"}
  - {id: E3, proves: [M5], kind: offline, intent: pending, command: "same suite, the ISTIOCTL_VERSION override cases", red_control: "positive control for M4: the same 1.32.0 stub is refused when the variable is unset"}
  - {id: E4, proves: [N4], kind: offline, intent: pending, command: "same suite, run bash -c 'trap \"echo sentinel\" EXIT; source core.sh; _install_istioctl \"$dir\"; trap -p EXIT' with stubs, asserting the output still contains sentinel (inside run bash -c so the BATS EXIT trap is never touched)", red_control: "fails on main@15d5001 (trap replaced by rm -rf /tmp/istio-*)"}
  - {id: E5, proves: [M6, N1, N2, N5], kind: offline, intent: pending, command: "k3d-manager: the same env -i form with bats scripts/tests/lib/install_istioctl_dispatch.bats scripts/tests/lib/k3d_install.bats", red_control: "fails on k3d-manager-v1.45.1@a6968d2c: the loaded definition still contains downloadIstioCandidate, accepts the 1.32.0 stub, and the _istioctl log shows x precheck"}
  - {id: E6, proves: [M4, N1, N5], kind: live, intent: pending, command: "operator on m2-air (Homebrew istioctl 1.32.0 still linked, any manually placed 1.31.4 removed from PATH and ~/.local/bin first): make dr-drill; expect the Behaviour 4 ERROR naming 1.32.0, /opt/homebrew/bin/istioctl and 1.31.4, and no 'x precheck' output after it", red_control: "today's run ends in IST0142 at x precheck (Evidence above)"}
  - {id: E7, proves: [M1], kind: live, intent: pending, command: "operator on m2-air after 'brew unlink istioctl' and with no 1.31.x istioctl in PATH or ~/.local/bin (check with command -v istioctl and ls ~/.local/bin/istioctl first; if one is there, E7 proves M3 instead, and say so): make dr-drill; hub-up Step 1/5 downloads the 1.31.4 archive, verifies it and passes x precheck", red_control: "E6 on the same machine minutes earlier"}
interface:
  - "_install_istioctl [install_dir]: same signature and default (/usr/local/bin); rc 0 means an istioctl of the pinned minor is in install_dir, on PATH, or installed; any refusal or failure exits via _err"
  - "_istioctl_pinned_sha256 <version> <os> <arch>: new; os is osx|linux, arch is arm64|amd64"
  - "ISTIOCTL_VERSION (default 1.31.4), ISTIOCTL_BASE_URL (default https://github.com/istio/istio/releases/download): new env vars, read only by _install_istioctl"
```

The stubs live in `$BATS_TEST_TMPDIR/bin`, which is first on `PATH`.
- Each stub's output reproduces a capture under *External behaviour*, with a comment naming the host and date.
- The `curl` stub logs its URL and never touches the network. For a release-archive URL it writes a fixture tarball
  (built with the real `tar`) holding a stub `istioctl` printing `client version: 1.31.4`. For the
  `downloadIstioCandidate.sh` URL (red runs only) it writes a script that creates `istio-1.31.4/bin/istioctl` and prints
  the captured "add the ... directory" line, so the old code reaches its `cp` and the red controls really fail.
- The checksum stub asserts that its argument is the downloaded tarball path (exit 97 otherwise), then returns the
  pinned value, or a wrong value for N3, which proves the verify step reads the tool's output.
- An `rm` stub (logging, refusing any path outside `$BATS_TEST_TMPDIR`) is on PATH in every red-control run, because
  the old function runs `pushd /tmp` and `trap 'rm -rf /tmp/istio-*' EXIT TERM`, which would delete real `/tmp/istio-*`
  on the worker's machine.
- `uname` is stubbed per os/arch case.
- `install_dir` is a scratch dir. The fixture asserts it lives under `$BATS_TEST_TMPDIR` before any call.

`_run_command` is a stub that logs and runs the command with sudo disabled, so the real `/usr/local/bin` and real `sudo`
are never reached (`feedback_mutation_harness_sudo_guard`, `feedback_never_run_install_targets_unstubbed`).

## Worker definition of done

- Change only the files listed for your child. A does not touch k3d-manager. B does not edit `scripts/lib/foundation/`.
  C changes only `CHANGELOG.md`. Nobody touches `docs/bugs/`.
- Offline only: no network, no cluster, no real `istioctl`/`curl` download, no real `sudo`, scratch `HOME`.
- Show each new test red against the pre-fix code first (N1–N4 on lib-foundation `main@15d5001`, E5 on
  `k3d-manager-v1.45.1@a6968d2c`), then green.
- Because refusals now `_err` (exit), every refusal case runs under `run bash -c '...'` (or `run` on a sourced
  wrapper), never directly in the test shell.
- Mutation checks (A). Each mutation must turn its test red:
  - remove the checksum comparison → N3;
  - compare the full version instead of the minor → the 1.31.1 case of M3;
  - drop the `ISTIOCTL_VERSION` default → M1;
  - replace `_err` with `return 1` in the refusal → N5 (B's dispatch test);
  - drop the `${install_dir}/istioctl` check → the install-dir case of M3.
- Run `shellcheck` on the touched `.sh` files, and the full BATS suite with the `env -i` form from lib-foundation
  `CLAUDE.md:110-111` (PATH includes `/opt/homebrew/bin`; the stub dir goes first for the istioctl suite).
- Paste each command with its rc and the proving lines. Leave changes uncommitted. No live checks: E6 and E7 are the
  operator's.
