# Historical branch pruning recommendation

## What was checked
- `docs/next-improvements`
- `k3d-manager-v1.1.0`
- `k3d-manager-v1.2.0`
- `k3d-manager-v1.3.0`
- `k3d-manager-v1.4.0`
- `k3d-manager-v1.4.1`
- `k3d-manager-v1.4.2`
- `k3d-manager-v1.4.3`
- `k3d-manager-v1.4.4`

## Actual result
None of those branch tips are ancestors of current `main` or current `k3d-manager-v1.4.5`.

## Recommendation
- Keep these branches if branch history and release auditability matter.
- Delete them only if the team explicitly wants to prune old branch refs and is comfortable losing the named pointers.
- Do not treat them as safe-to-delete by default just because they are not part of the active release line.

## Follow-up
- If branch hygiene becomes a cleanup task, document the delete/keep decision per branch before removing any refs.
