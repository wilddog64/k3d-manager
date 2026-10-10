# DR drill — second pass rejected (Claude review, 2026-10-09)

Its report says "19/19 BATS" and "Implemented D1–D9". Both are false in effect.

**The tests.** Almost every new test greps the source (line order, string presence) instead of
running the code. No test runs a restore or a drill end to end with stubs. No mutation output was
reported.

**The defects.** Each one below is a defect a behavioural test would have caught. Live names come
from a read-only check of the hub on 2026-10-09.

## Restore never restores
1. `_hub_data_copy_claim` declares `local encrypted` but never assigns it from `$4`.
   `_hub_data_restore_one` therefore gets an empty path: `[[ -f "" ]]` is false, the `.part-*`
   branch runs `find ""`, and **nothing is copied**.
2. `hub_data_restore` traps `rm -rf "$stage"` on EXIT, and `$stage` is `DR_DRILL_RESTORE_STAGE`
   (`$DR_DRILL_STAGE/restore`). V2–V5 then read `inventory.json` and `pv-pvc.yaml` from that
   deleted directory.
3. `bin/dr-drill` never exports `DR_DRILL_CONTEXT` or `DR_DRILL_CLUSTER`. `hub_data_restore` runs in
   a separate process (`scripts/k3d-manager hub_data_restore`), so every `--context "$DR_DRILL_CONTEXT"`
   is `--context ""`.

## Wrong live names
4. `postgres-keycloak` is a **Deployment**. `statefulset/postgres-keycloak` (inventory, scale) does
   not exist, and V5's `pod/postgres-keycloak-0` does not either.
5. The LDAP StatefulSet is `openldap`, with pod `openldap-0`. `statefulset/data-openldap` (inventory,
   scale) and V5's `pod/data-openldap-0` are both wrong.
6. There is no Keycloak CRD on the hub, so V3's `get keycloak ... .status.realmUserCount` always
   fails. Use the same psql count as the export inventory.
7. The `_hub_data_scale` calls at lines 213 and 215 are unguarded, so with the wrong names `set -e`
   aborts the restore.

## bin/dr-drill
8. **Preflight leftover-cluster check is inverted.** `awk ... END {exit found}` exits 0 when the
   cluster is **absent**, so a clean M2 always gets the refusal "leftover drill cluster exists".
9. **V0 can pass falsely.** If the check pod never reaches Running (image pull, scheduling), the
   `exec` fails and that counts as "curl failed", which is a pass. Wait for Ready first. Require
   curl's own failure exit code (6, 7 or 28), not exec's. Delete the check pod afterwards.
10. **V0 image is unpinned:** `curlimages/curl` floats on latest. Pin a tag.
11. **V0 covers two namespaces only** (`secrets`, `identity`). Every drill namespace must be covered.
12. **A failure in phase 3 or 4 writes no result.** `set -e` exits on unseal or restore failure
    before `_dr_drill_report`. A failed drill must still write `success:false` with the failing check,
    or failures are invisible to freshness and the metrics.
13. **Unseal and generate-root pass key material as argv inside the pod.** These calls put the value
    on the vault command line, where the pod's process list can see it:
    - `vault operator unseal "$SHARD"`
    - `generate-root -nonce "$NONCE" "$SHARD"`
    - `-otp "$OTP"`

    The vault CLI accepts `-` to read the key from stdin. Use that.
14. **A failed generate-root is never cancelled.** It leaves a root generation in progress that
    blocks the next attempt. Run `vault operator generate-root -cancel` on the failure path.

## hub_data.sh
15. **`_hub_data_vault_command` runs `eval "$1"`, and `$1` includes `${path}` read from
    `inventory.json`**, which is data-repo content, under a root token. Do not use eval. Pass the
    path as an argument, or on stdin, and validate it against `^[A-Za-z0-9_./-]+$`.
16. **Export writes a plaintext tar to the host stage before `age`.** Stream it instead:
    `docker exec ... tar -cf - | age -r ... -o file.age`.

## bin/dr-drill-publish
17. **Wrong Pushgateway URL.** `PUSHGATEWAY_URL` defaults to `127.0.0.1:19090`, which is the
    Prometheus auth proxy. The hub Pushgateway is `localhost:19094`.

## Tests to require (behavioural; stub binaries through PATH)
- An end-to-end restore with stub `kubectl`, `docker` and `age` asserts that each claim's
  encrypted file is decrypted and piped to `docker exec -i <node> tar -C <pv path> -xpf -`.
  Mutating item 1 must turn it red.
- After the restore, `bin/dr-drill`'s V2 still finds `inventory.json`.
- With `k3d cluster list` stubbed with no clusters, preflight passes; with the drill cluster listed,
  it exits 2.
- V0 with a pod that never becomes ready gives V0=false.
- A failing unseal still writes a result JSON with `success:false`.
- The publish test asserts the Pushgateway URL default is `:19094`.
- No grep-of-source tests for behaviour.
