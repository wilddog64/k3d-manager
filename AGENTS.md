# AGENTS.md

## Codex Workspace Sync (TL;DR)
- if remote is not setup, please base on section Setup Script to setup git orgin
- sync the repo - git pull and ensure tip is up-to-date
- install necessary tools based on what scrips required if they are missing
- please base on origin/partial-working branch (this is partially work)

---

## Setup Script (paste into: Project → Environment → Code execution → Setup scripts)
```bash
#!/usr/bin/env bash
set -euo pipefail
exec > >(tee -a "$HOME/_codex_setup.log") 2>&1 || true

# Ensure git
command -v git >/dev/null 2>&1 || { sudo apt-get update -y && sudo apt-get install -y git; }

# Clone or update repo
cd "$HOME"
if [ ! -d k3d-manager/.git ]; then
  git clone https://github.com/wilddog64/k3d-manager.git
fi

cd "$HOME/k3d-manager"
git remote set-url origin https://github.com/wilddog64/k3d-manager.git
git fetch origin main --prune
git switch -C main --track origin/main 2>/dev/null || git switch main
git pull --ff-only || true

# Markers to verify in the file tree
git rev-parse HEAD > "$HOME/k3d-manager/.codex_head_commit" || true
date -Is           > "$HOME/k3d-manager/.codex_last_sync"   || true
echo "OK"          > "$HOME/CODEX_SETUP_OK"                  || true
