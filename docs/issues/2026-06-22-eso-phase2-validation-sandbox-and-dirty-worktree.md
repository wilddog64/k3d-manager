# ESO Phase 2 validation sandbox and dirty worktree blockers

## What I tested / attempted

- Attempted to sync the branch with `git pull origin feat/eso-phase2-clustersecretstore`.
- Attempted the spec-prescribed manifest render checks with `kubectl apply --dry-run=client`.

## Actual output

`git pull origin feat/eso-phase2-clustersecretstore`

```text
error: cannot pull with rebase: Your index contains uncommitted changes.
error: Please commit or stash them.
```

`ARGOCD_NAMESPACE=cicd K3D_MANAGER_BRANCH=feat/eso-phase2-clustersecretstore envsubst < scripts/etc/argocd/applicationsets/eso-clustersecretstore.yaml | kubectl apply --dry-run=client -f -`

```text
error: error validating "STDIN": error validating data: failed to download openapi: Get "https://127.0.0.1:55355/openapi/v2?timeout=32s": dial tcp 127.0.0.1:55355: connect: operation not permitted; if you choose to ignore these errors, turn validation off with --validate=false
```

`VAULT_NS=secrets VAULT_VIRTUALSERVICE_HOST=vault.3ai-talk.org VAULT_VIRTUALSERVICE_GATEWAY=istio-system/default-gateway envsubst < scripts/etc/vault/virtualservice.yaml.tmpl | kubectl apply --dry-run=client -f -`

```text
error: error validating "STDIN": error validating data: failed to download openapi: Get "https://127.0.0.1:55355/openapi/v2?timeout=32s": dial tcp 127.0.0.1:55355: connect: operation not permitted; if you choose to ignore these errors, turn validation off with --validate=false
```

## Root cause

- The worktree already contained local modifications before the pull, so the branch sync could not proceed with `git pull`.
- `kubectl apply --dry-run=client` still attempted local API discovery in this sandbox. The connection to the local API endpoint was blocked, so the exact command failed before client-only parsing completed.

## Recommended follow-up

- Keep using the existing local changes without overwriting them, and sync the remote branch only after the worktree is clean.
- Use `kubectl create --dry-run=client --validate=false` for offline manifest parsing in this sandbox when API discovery is blocked.
