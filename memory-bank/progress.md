# Progress — k3d-manager

## v1.0.1 SHIPPED

**PR #58** merged to main (`a8b6c583`) 2026-03-31. Tagged v1.0.1, released. `enforce_admins` restored.
**Retro:** `docs/retro/2026-03-31-v1.0.1-retrospective.md`

**Scope shipped:**
- [x] `bin/` convenience scripts: `acg-up`, `acg-down`, `acg-refresh`, `acg-status`, `rotate-ghcr-pat`
- [x] Claude skills: `~/.claude/commands/acg-up.md`, `acg-down.md`, `acg-refresh.md`, `acg-status.md`
- [x] README: Directory Layout + Convenience Scripts table + How-To link
- [x] `docs/howto/acg-credentials-flow.md` — ASCII decision tree
- [x] `memory-bank/projectbrief.md` — updated to reflect k3s-aws 3-node + ACG scope
- [x] `.github/copilot-instructions.md` — acg_*, tunnel_*, Playwright review rules
- [x] `~/.claude/commands/post-merge.md` — Step 7b standing docs audit added

---

## v1.0.2 ACTIVE — branch `k3d-manager-v1.0.2`

**Cut from:** `a8b6c583` (2026-03-31)

### Todo

- [ ] **Gemini: all 5 pods Running** — spec `docs/plans/v1.0.2-all-pods-running.md`
  - Blocked: Vault → EC2 connectivity (socat workaround in progress)
  - acg_extend TTL extension failed (see bugfix below)

- [x] **Codex: reverse Vault tunnel** — spec `docs/plans/v1.0.2-reverse-vault-tunnel.md`; commit `4ff3cc3`
  - autossh plist now forwards k3s API and reverses Vault port 8200

- [x] **Codex: acg_extend bugfix** — spec `docs/plans/v1.0.2-bugfix-acg-extend-selector.md`; commit `26a34cd`
  - Static `scripts/playwright/acg_extend.js` replaces Gemini prompt; `antigravity_acg_extend` runs it directly

- [ ] **Codex: acg_watch_start/stop launchd** — spec `docs/plans/v1.0.2-acg-watch-launchd.md`
  - Sandbox TTL extension survives terminal death and Gemini session blocks
  - `acg_watch_start` writes wrapper + plist; `bin/acg-up` calls it instead of `acg_watch &`

- [ ] **lib-foundation PR #22** — `feat/v0.3.16`, `grep -Fqx --` fix; needs Copilot review + merge + subtree pull

- [ ] **docs/api/functions.md** — add new public functions: `acg_*`, `tunnel_*`, `aws_*`, `bin/` scripts

### Issues Logged

- `docs/issues/2026-03-31-pluralsight-session-expiry-independent-of-sandbox-ttl.md`
- `docs/issues/2026-03-31-acg-extend-button-not-found.md`

---

## Roadmap (shipped + planned)

| Version | Status | Scope |
|---------|--------|-------|
| v0.9.20 | SHIPPED `bfd66fe` | `_antigravity_launch` `--password-store=basic`; `_ensure_k3sup` |
| v0.9.21 | SHIPPED `f98f2a8` | `_ensure_k3sup` + `deploy_app_cluster` auto-install |
| v1.0.0  | SHIPPED `807c0432` | `k3s-aws` provider foundation |
| v1.0.1  | SHIPPED `a8b6c583` | Multi-node + CloudFormation + bin/ scripts + copilot-instructions |
| v1.0.2  | ACTIVE | Full stack: all 5 pods Running + E2E green |
| v1.0.3  | PLANNED | Service mesh: Istio + MetalLB + GUI access |
| v1.0.4  | PLANNED | Samba AD DC plugin |
| v1.0.5  | PLANNED | GCP cloud provider (`k3s-gcp`) |
| v1.0.6  | PLANNED | Azure cloud provider (`k3s-azure`) |
