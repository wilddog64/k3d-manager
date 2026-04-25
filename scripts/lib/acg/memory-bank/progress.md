# Progress — lib-acg

## v0.1.0 Track (branch: `main`)

- [x] **Repo skeleton** — COMPLETE. CLAUDE.md, README.md, package.json, placeholder
      scripts/lib/cdp.sh, scripts/plugins/acg.sh, scripts/plugins/gcp.sh, scripts/vars.sh,
      playwright/, memory-bank/.
- [ ] **lib-foundation subtree** — PLANNED. Pull into scripts/lib/foundation/.
- [ ] **Phase 3 migration** — PLANNED. Copy acg.sh, gcp.sh, playwright/*.js, vars.sh from
      k3d-manager; extract _browser_launch + _cdp_ensure_acg_session into cdp.sh.
- [ ] **BATS tests** — PLANNED. Add tests/lib/cdp.bats for cdp.sh primitives.
- [ ] **Pre-commit hooks** — PLANNED. shellcheck + node --check gates.
