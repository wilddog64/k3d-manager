# Digital Auditor Rules

1. **No Permission Cascades** – a function must not attempt the same privileged action through multiple ad-hoc sudo paths. Use `_run_command --prefer-sudo` once per operation.
2. **Centralized Platform Detection** – branching on `_is_mac` / `_is_debian_family` / `_is_redhat_family` outside `_detect_platform()` is forbidden unless gating unsupported features.
3. **Secret Hygiene** – tokens and passwords must never appear in command arguments (e.g., `kubectl exec -- VAULT_TOKEN=...`). Use stdin payloads or env files.
4. **Namespace Isolation (kubectl-specific)** – when using `kubectl apply` or `kubectl create`, prefer an explicit `-n <namespace>` flag; relying on `metadata.namespace` in manifests or non-`kubectl` consumers is acceptable when clearly intentional.
5. **Prompt Scope** – Copilot prompts must reject shell escape fragments (`shell(cd …)`, `shell(git push …)`, `shell(rm -rf …)`, `shell(sudo …)`, `shell(eval …)`, `shell(curl …)`, `shell(wget …)`).
