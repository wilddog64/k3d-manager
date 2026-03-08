# Progress — lib-foundation

## Overall Status

**Active** — v0.1.0 shipped; v0.1.1 adds `_resolve_script_dir` helper.

---

## What Is Complete

- [x] GitHub repo created: `wilddog64/lib-foundation`
- [x] Directory structure: `scripts/lib/`, `scripts/tests/lib/`, `memory-bank/`
- [x] `CLAUDE.md` — navigation + key contracts + testing rules
- [x] `.clinerules` — Cline-compatible agent instructions
- [x] `memory-bank/` — context carried over from k3d-manager v0.6.5
- [x] Branch protection — `required_linear_history`, no force push, required status checks (`shellcheck`, `bats`)
- [x] CI — `.github/workflows/ci.yaml` — shellcheck + BATS 1.13.0, pre-extraction graceful skip, `env -i` clean env. ✅ green
- [x] `scripts/lib/core.sh` + `scripts/lib/system.sh` imported from k3d-manager (Codex) — shellcheck run; BATS suite empty (1..0)
- [x] `system.sh` shellcheck cleanup — SC2016 annotations, quoting fixes, and `_detect_cluster_name` locals (Codex)
- [x] `_resolve_script_dir` helper added to `core.sh` with BATS coverage (Codex, v0.1.1)

---

## What Is Pending

- [ ] Wire lib-foundation subtree back into k3d-manager (`git subtree pull/push`, Codex follow-up)
- [ ] Integrate lib-foundation as subtree remote back into k3d-manager
- [ ] Broader BATS coverage for remaining lib functions
- [ ] Consumer integration: `rigor-cli`
- [ ] Consumer integration: `shopping-carts`

---

## Known Constraints

| Item | Notes |
|---|---|
| `SCRIPT_DIR` dependency | `system.sh` sources `agent_rigor.sh` via `$SCRIPT_DIR` at load time — must resolve correctly in subtree layout |
| Contract stability | `_run_command`, `_detect_platform`, `_cluster_provider` — signature changes require all-consumer coordination |
| Clean env testing | BATS must run with `env -i` — ambient `SCRIPT_DIR` causes false passes |
