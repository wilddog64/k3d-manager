# LDAP Integration Plan

## Goals
- Integrate LDAP support into `k3d-manager` with minimal, repo-aligned changes.
- Ensure Vault/Jenkins pieces interact cleanly with new LDAP configurations.

## Current State
- `scripts/plugins/ldap.sh` scaffolded but incomplete.
- LDAP templates (`scripts/etc/ldap/values.yaml.tmpl`, `scripts/etc/ldap/eso.yaml`, `scripts/etc/ldap/vars.sh`) need validation and alignment with existing conventions.
- Modifications pending review in `scripts/plugins/jenkins.sh` and `scripts/etc/vault/vars.sh`.
- House rules in `AGENTS.md` updated for guidance.

## Plan of Action
1. **Context Review**
   - Compare LDAP artifacts against existing plugin patterns (Vault, Jenkins).
   - Identify gaps (naming, environment variables, secrets handling).
2. **Script Refinement**
   - Finalize `scripts/plugins/ldap.sh` with deployment, upgrade, and validation steps consistent with other plugins.
   - Fix typos, ensure idempotency, add safety defaults only if consistent with file.
3. **Template Alignment**
   - Update LDAP Helm values and ESO manifests to use placeholders, correct URLs, and follow existing naming standards.
   - Cross-check namespace/service details with repo defaults.
   - Add base LDIF entries for initial Jenkins group and user.
4. **Integration Touchpoints**
   - Ensure Jenkins/Vault changes reference LDAP values correctly.
   - Wire Vault-generated credentials into a Kubernetes secret in the `jenkins` namespace for Jenkins logins.
   - Verify shared variables (`vars.sh`) are exported and consumed properly.
5. **Validation & Documentation**
   - Outline manual/automated checks (lint, shellcheck, helm template) runnable without network.
   - Draft follow-up notes for user testing (no commits per request).

## Deliverables
- Updated scripts/templates ready for manual testing.
- Summary of verification steps and any outstanding questions.

## Open Questions
- Confirm target LDAP chart version and expected secret structure.
- Determine whether to source credentials from Vault or static secrets by default.
- Clarify desired naming for the Jenkins-bound LDAP group/user and how Jenkins will map roles.

## Next Steps After Review
- Run agreed validation commands.
- Assist with deployment/testing feedback loop.
