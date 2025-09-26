# AGENTS.md

## Codex Workspace Sync over SSH (TL;DR)
- Paste the **Setup Script** below into: **Project → Environment → Code execution → Setup scripts**.
- After the first start, open the file tree and copy the key from **`~/GITHUB_SSH_KEY.pub`** into GitHub:  
  **GitHub → Settings → SSH and GPG keys → New SSH key → Paste → Save**.
- Then **Stop → Start** the workspace once to let it clone/update via SSH.
- To sync later (when terminal works): `cd ~/k3d-manager && git pull --ff-only`.
- Tools installed: **git**, **openssh-client**, **curl**, **jq**, **kubectl**.
- Verify files in the tree after start:  
  `~/_codex_setup.log`, `~/GITHUB_SSH_KEY.pub`, `~/k3d-manager/.codex_head_commit`, `~/k3d-manager/.codex_last_sync`, `~/CODEX_SETUP_OK`.

---

## Setup Script (paste into: Project → Environment → Code execution → Setup scripts)
```bash
#!/usr/bin/env bash
set -euo pipefail

# Log everything (visible in the file tree)
exec > >(tee -a "$HOME/_codex_setup.log") 2>&1 || true
echo "== CODEx SSH setup start: $(date -Is) =="

# ---------------------------------------
# 0) Base packages (idempotent installs)
# ---------------------------------------
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends git openssh-client curl jq ca-certificates

# ---------------------------------------
# 1) SSH key + config (force GitHub over 443)
# ---------------------------------------
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
KEY="$HOME/.ssh/id_ed25519"
EMAIL="${EMAIL:-codex-$(hostname)-$(date +%Y%m%d)@local}"

if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY" -N ""
fi

# SSH config to bypass blocked port 22 (use GitHub's SSH on 443)
cat > "$HOME/.ssh/config" <<'EOF'
Host github.com
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
EOF
chmod 600 "$HOME/.ssh/config"

# Known hosts (avoid interactive prompts)
ssh-keyscan -p 443 ssh.github.com 2>/dev/null >> "$HOME/.ssh/known_hosts" || true
ssh-keyscan github.com 2>/dev/null >> "$HOME/.ssh/known_hosts" || true
chmod 600 "$HOME/.ssh/known_hosts" || true

# Make the public key easy to find/copy in the file tree
cp -f "$KEY.pub" "$HOME/GITHUB_SSH_KEY.pub" || true

# Smoke test (will succeed only after you add the key to GitHub)
ssh -T -p 443 -o StrictHostKeyChecking=accept-new git@ssh.github.com || true

# ---------------------------------------
# 2) Clone or update repository via SSH
# ---------------------------------------
REPO_SSH="git@github.com:wilddog64/k3d-manager.git"
WORKDIR="$HOME/k3d-manager"

cd "$HOME"
if [ ! -d "$WORKDIR/.git" ]; then
  echo "[clone] $REPO_SSH"
  if ! git clone "$REPO_SSH" "$WORKDIR"; then
    echo "[warn] SSH auth failed. Add the key from ~/GITHUB_SSH_KEY.pub to GitHub, then Stop→Start the workspace."
    echo "NEED_SSH_KEY" > "$HOME/SSH_NEEDS_SETUP"
    # Still exit 0 so the workspace finishes starting
  fi
fi

if [ -d "$WORKDIR/.git" ]; then
  cd "$WORKDIR"

  # Git hygiene for containers
  git config --global --add safe.directory "$WORKDIR" || true
  git config --global fetch.prune true || true
  git config --global pull.ff only || true

  # Ensure SSH remote and update main
  git remote set-url origin "$REPO_SSH" || true
  git fetch origin main --prune || true
  git switch -C main --track origin/main 2>/dev/null || git switch main || true
  git pull --ff-only || true

  # Verification markers
  git rev-parse HEAD > "$WORKDIR/.codex_head_commit" || true
  date -Is         > "$WORKDIR/.codex_last_sync"     || true
fi

# Success marker
echo "OK" > "$HOME/CODEX_SETUP_OK" || true
echo "== CODEx SSH setup end: $(date -Is) =="
