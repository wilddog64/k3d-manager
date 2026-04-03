# Issue: Task 15 ArgoCD Registration and Sync Challenges

## Date
2026-03-10

## Symptoms
1. **Bash Version Incompatibility:** SSH sessions to M2 Air defaulted to Bash 3.2, which caused `declare -A` errors in plugins.
2. **Passphrase-Protected SSH Keys:** The existing `~/.ssh/id_ed25519` key was passphrase-protected, and `argocd` CLI could not handle the prompt or use the SSH agent via non-interactive SSH.
3. **GitHub Deploy Key Reuse:** GitHub forbids using the same Deploy Key for multiple repositories.
4. **HTTPS vs. SSH URL Mismatch:** Application manifests used HTTPS URLs, but repositories were registered in ArgoCD using SSH, causing `ComparisonError`.
5. **ArgoCD Manifest Caching:** ArgoCD `repo-server` cached old manifests, requiring `kubectl patch` to force URL updates.

## Root Cause
- Default macOS Bash is too old for modern associative array support.
- `argocd` CLI's SSH implementation doesn't natively integrate with `ssh-agent` in all environments.
- Architectural decision to use Deploy Keys instead of a personal account key created a many-to-one mapping conflict on GitHub.

## Resolution
1. **Bash:** Explicitly used `/opt/homebrew/bin/bash` for script execution and BATS testing.
2. **SSH Keys:** Generated unique passphrase-free keys for each repository (`~/.ssh/basket-id_ed25519`, etc.) and added them as GitHub Deploy Keys using `gh api`.
3. **URLs:** Updated Application CR manifests on M2 Air to use SSH URLs (`git@github.com:...`).
4. **Caching:** Used `kubectl patch app` to bypass ArgoCD caching and force the use of SSH URLs.

## Status
FIXED in Task 15.
