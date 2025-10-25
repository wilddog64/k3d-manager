# LDAP Integration Plan

## Goals
- Integrate LDAP support into `k3d-manager` with minimal, repo-aligned changes.
- Ensure Vault/Jenkins pieces interact cleanly with new LDAP configurations.

## Current State
- `scripts/plugins/ldap.sh` scaffolded but incomplete.
- LDAP templates (`scripts/etc/ldap/values.yaml.tmpl`, `scripts/etc/ldap/eso.yaml`, `scripts/etc/ldap/vars.sh`) need validation and alignment with existing conventions.
- Modifications pending review in `scripts/plugins/jenkins.sh` and `scripts/etc/vault/vars.sh`.
- House rules in `AGENTS.md` updated for guidance.
- `_create_jenkins_admin_vault_policy` seeds `secret/eso/jenkins-admin`, but no ExternalSecret currently syncs that credential into Jenkins.

## Plan of Action
1. **Refit Helm Values**
   - Update `scripts/etc/ldap/values.yaml.tmpl` to match the `openldap-bitnami` schema (service port maps, envFrom, LDIF mounts).
   - Introduce placeholders for ESO-synced secrets instead of inline `auth.*` blocks.
2. **Vault-Sourced Secrets**
   - Define an `ExternalSecret` that reads `${LDAP_ADMIN_VAULT_PATH}` and writes the admin/config passwords into a Kubernetes secret consumed via `envFrom`.
   - Optionally sync bootstrap LDIF content from Vault into a second secret and enable `mount_ldif_secret`.
3. **Plugin Enhancements**
   - Ensure `deploy_ldap` applies the ESO manifest, seeds/waits for Vault-backed secrets, and then runs the Helm upgrade.
   - Keep generic credential helpers in `scripts/lib/system.sh` for future OCI/private registry use.
   - Extend `deploy_jenkins` so it applies a Jenkins-specific `ExternalSecret` (templated under `scripts/etc/jenkins/`) that maps `secret/eso/jenkins-admin` into the existing `jenkins-admin` Kubernetes secret before running the Helm upgrade; wait for the secret to populate.
4. **Integration Touchpoints**
   - Confirm Jenkins/Vault consumers still reference the new secret names.
   - Verify ESO role/serviceaccount configuration aligns with Vault auth.
   - Maintain the current `scripts/etc/jenkins/values.yaml` wiring (`JENKINS_ADMIN_USER/PASS`) so only the secret source changes.
5. **Post-Reboot Unseal Flow**
   - Capture Vault unseal shards locally via the shared secret helpers (Keychain/secret-tool) and provide a helper script to replay them.
   - Document the manual reboot recovery workflow and earmark the interface for a future cloud KMS auto-unseal.
6. **Validation & Rollout Notes**
   - Run `helm upgrade --install ... --dry-run` (or k3d smoke test) to confirm templates render.
   - Document how to pivot between Vault-managed secrets and static overrides if needed later.

## Deliverables
- Updated scripts/templates ready for manual testing.
- Summary of verification steps and any outstanding questions.

## Open Questions
- Confirm target LDAP chart version and expected secret structure.
- Determine whether to source credentials from Vault or static secrets by default.
- Clarify desired naming for the Jenkins-bound LDAP group/user and how Jenkins will map roles.
- Decide whether ESO should live in `jenkins` or a shared namespace and which service account/policy pair should own the Jenkins sync.

## Next Steps After Review
- Run agreed validation commands.
- Assist with deployment/testing feedback loop.
