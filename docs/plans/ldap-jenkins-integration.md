# Jenkins ↔ LDAP Integration Roadmap

## Goal
Wire Jenkins to authenticate against the managed LDAP deployment while Vault owns the `jenkins-admin` service account secret inside the `it develop` group.

## Plan
1. **Vault seeding for LDAP service accounts**  
   - Provision a KV path such as `ldap/service-accounts/jenkins-admin` during Vault bootstrap.  
   - Generate/rotate the password with existing secret helpers and store it alongside required metadata.  
   - Create a least-privilege Vault policy that exposes only this credential for Jenkins consumers.

2. **LDAP deployment alignment**  
   - Update `deploy_ldap` to reconcile the `it develop` group and `jenkins-admin` account using the Vault-managed password.  
   - Ensure ESO (or equivalent) syncs the Vault secret into Kubernetes so the LDAP Helm values pick it up without embedding cleartext credentials.

3. **Documentation and validation**  
   - Document the workflow for operators (Jenkins, LDAP, Vault teams) including rotation steps.  
   - Add or extend automated tests (BATS/integration) that verify the group membership and credentials wiring end-to-end.

