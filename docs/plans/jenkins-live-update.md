# Jenkins Live Update Support

## Goal
Allow `k3d-manager deploy_jenkins` to perform in-place Jenkins upgrades (essentially `helm upgrade …`) while preserving readiness feedback that mirrors the bootstrap workflow.

## Proposed Steps
1. **Detect live-update intent**  
   - Add a `--live-update` (or similar) flag to `deploy_jenkins`.  
   - When the namespace, release, and chart are already present, skip destructive bootstrap steps (PVC provisioning, credential seeding unless explicitly requested, etc.).

2. **Run Helm upgrade with rendered manifests**  
   - Reuse the existing manifest rendering pipeline (values, annotations, init scripts).  
   - Invoke Helm using `upgrade --install` so brand-new clusters still deploy successfully.  
   - Collect Helm output for traceability when `ENABLE_TRACE=1`.

3. **Poll readiness**  
   - Extend `_wait_for_jenkins_ready` to support detecting rolling upgrades (watch for pod `READY` transitions, not just initial creation).  
   - Surface actionable status when the rollout fails (events summary, failing container logs).

4. **Optional: smoke-check Vault secrets after upgrade**  
   - Re-run the lightweight smoke checks added earlier (`_jenkins_verify_controller_vault_files`) if the controller restarted.

5. **CLI ergonomics & docs**  
   - Update `deploy_jenkins -h` with the new flag.  
   - Document the live-update workflow in `README` / `docs/jenkins.md`, noting when to use `--no-sync-from-lastpass`.

## Testing
- Unit/BATS coverage for the new flag, ensuring helm upgrade path is invoked.  
- Mock readiness polling to simulate a rolling upgrade success/failure.  
- Manual validation: run `deploy_jenkins --live-update`, confirm the script waits for the rollout and exits cleanly when Jenkins is ready.
