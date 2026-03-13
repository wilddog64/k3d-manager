#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_SRC="$REPO_ROOT/scripts/hooks"
HOOKS_DST="$REPO_ROOT/.git/hooks"

for hook in "$HOOKS_SRC"/*; do
   [[ -f "$hook" ]] || continue
   hook_name="$(basename "$hook")"
   target="$HOOKS_DST/$hook_name"
   if [[ -L "$target" ]]; then
      echo "[hooks] $hook_name already a symlink — skipping"
      continue
   fi
   ln -sf "../../scripts/hooks/$hook_name" "$target"
   echo "[hooks] installed: $hook_name"

done
