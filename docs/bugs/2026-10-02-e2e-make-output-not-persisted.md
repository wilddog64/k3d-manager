# `make e2e` / `make e2e-sandbox`: harness output is never saved, so a terminal-launched run cannot be diagnosed

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. When the operator runs `make e2e` from their own terminal, only the operator sees the setup
output (vCluster creation, credential resolution, substrate deploy). The harness saves only the Playwright Job log
(`~/.k3dm/e2e/<run-id>.log`), and only once the run reaches the Job. Run `1790958044-29337` (2026-10-02) failed
on a missing GHCR PAT before that point, so the summary JSON was the only record.
**Status:** FIXED (pending)

## Fix (`Makefile`, targets `e2e` and `e2e-sandbox` only)

Record the whole run with `script(1)`, not `tee`. `tee` makes stdout a pipe, which disables the interactive GHCR
PAT prompt (`shopping_cart_prompt_ghcr_pat` requires `-t 0` and `-t 1`) and the Tier 2 ACG manual login.
`script` runs the command on a pseudo-terminal and returns its exit status (verified on macOS 2026-10-02: TTY
preserved, `exit 7` → `rc=7`). The PAT prompt uses `read -s`, so the pasted PAT is never echoed into the log.

Old:
```make
e2e:
	./scripts/k3d-manager e2e_verify_vcluster $(DIGEST)
```
New:
```make
e2e:
	@$(call _e2e_recorded,e2e,./scripts/k3d-manager e2e_verify_vcluster $(DIGEST))
```
Old:
```make
e2e-sandbox:
	./scripts/k3d-manager e2e_verify_sandbox $(DIGEST)
```
New:
```make
e2e-sandbox:
	@$(call _e2e_recorded,e2e-sandbox,./scripts/k3d-manager e2e_verify_sandbox $(DIGEST))
```

Define `_e2e_recorded` once, directly above the `e2e` target's `##` help comment (a `define` is not a target, so
it does not appear in `make help`):

```make
define _e2e_recorded
mkdir -p "$(HOME)/.k3dm/e2e"; \
_log="$(HOME)/.k3dm/e2e/make-$(1)-$$(date -u +%Y%m%dT%H%M%SZ).log"; \
echo "[$(1)] recording full output to $${_log}"; \
umask 077; \
if [ "$$(uname -s)" = Darwin ]; then script -q "$${_log}" $(2); else script -q -e -c "$(2)" "$${_log}"; fi
endef
```

Do not change the `##` help lines, `e2e-remote`, `e2e-replay` or any other target, and do not touch
`scripts/plugins/e2e.sh`.

## Tests (new `bin/makefile_e2e_recorded.bats` under `scripts/tests/`, next to the other `makefile_*.bats`; no cluster)

1. `make -n e2e` output contains `script -q`, `.k3dm/e2e/make-e2e-` and `e2e_verify_vcluster`.
2. `make -n e2e-sandbox` output contains `script -q`, `.k3dm/e2e/make-e2e-sandbox-` and `e2e_verify_sandbox`.
3. `make -n e2e DIGEST=sha256:abc` passes `sha256:abc` through to `e2e_verify_vcluster`.
4. Exit-status propagation: with `HOME` set to `$BATS_TEST_TMPDIR`, a copy of the `_e2e_recorded` macro run with
   `$(2)` = `/bin/sh -c 'exit 7'` (via a minimal temp Makefile that `include`s nothing but the extracted define)
   exits 7 and creates exactly one `make-*.log` with mode `600`.
5. `make help` still lists `e2e` and `e2e-sandbox` and does not list `_e2e_recorded`.

Mutation, `cp`-restored and `cmp`-proved: replace the macro body's `script -q "$${_log}" $(2)` with
`$(2) | tee "$${_log}"` → test 1 is red.

## Rules

- `bats` on the new file is green; `make -n e2e` and `make help` run cleanly. Do NOT run `make e2e` or
  `make e2e-sandbox` for real.
- If `docs/howto/` or `docs/guides/` documents running `make e2e`, add one sentence naming the
  `~/.k3dm/e2e/make-e2e-<UTC timestamp>.log` file.
- No cluster, network or git commits. Leave changes uncommitted. Do not touch `CHANGELOG.md` or memory-bank.
- Update this doc: Status FIXED, plus a short Resolution section.

## Resolution

The `e2e` and `e2e-sandbox` targets now record the complete pseudo-terminal output in a mode-600
timestamped log under `~/.k3dm/e2e/`, preserving interactive prompts and the harness exit status.
