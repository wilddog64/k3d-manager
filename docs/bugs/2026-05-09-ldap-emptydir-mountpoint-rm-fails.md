# Bug: LDAP pod CrashLoopBackOff — emptyDir at ldif/custom is a mount point, rm -rf fails

**Branch:** shopping-cart-infra `main` → new branch `fix/ldap-ldif-staging`
**Severity:** High — `identity/ldap` pod stays in CrashLoopBackOff on every fresh cluster bring-up
**Repo affected:** `wilddog64/shopping-cart-infra`

---

## Before You Start

```bash
cd ~/src/gitrepo/personal/shopping-cart-infra
git checkout main && git pull
git checkout -b fix/ldap-ldif-staging
```

Read this file in full before touching anything:
- `identity/ldap/deployment.yaml`

Do NOT touch any other files.

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `identity/ldap/deployment.yaml`
- Do NOT commit to `main`
- Do NOT update memory-bank — Claude handles that after verification

---

## Symptom

```
identity   ldap-<hash>   0/1   CrashLoopBackOff   ...
```

Pod logs (previous):
```
***  INFO   | Remove config files...
rm: cannot remove '/container/service/slapd/assets/config/bootstrap/ldif/custom': Device or resource busy
***  ERROR  | /container/run/startup/slapd failed with status 1
```

---

## Root Cause

The `osixia/openldap:1.5.0` startup script ends with:
```bash
rm -rf ${CONTAINER_SERVICE_DIR}/slapd/assets/config   # cleanup after first-start bootstrap
```

This removes the entire `assets/config/` tree. When it descends into `ldif/custom/`, which is a
kernel mount point (emptyDir from Bug 5 fix in PR #41), the kernel returns `EBUSY` and `rm`
fails with exit 1.

**Mounting ANY volume at `ldif/custom` makes it a kernel mount point that cannot be deleted
by `rm -rf`, regardless of whether it is ConfigMap or emptyDir.**

---

## Fix

`osixia/openldap:1.5.0` supports `LDAP_SEED_INTERNAL_LDIF_PATH` (verified in startup.sh line 114):

```bash
copy_internal_seed_if_exists "${LDAP_SEED_INTERNAL_LDIF_PATH}" \
  "${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/custom"
```

When this env var is set, the startup script copies LDIF files from that path INTO `ldif/custom`
(the image's own writable overlay layer — a plain directory, not a mount point) before processing
them. Then `rm -rf assets/config` at cleanup succeeds because `ldif/custom` is never a mount point.

**Solution: set `LDAP_SEED_INTERNAL_LDIF_PATH=/ldif-staging`, mount the emptyDir at `/ldif-staging`
instead of at `ldif/custom`.**

---

## Exact Changes to `identity/ldap/deployment.yaml`

### Change 1 — init container: rename destination volume and path

Old `volumeMounts` in `initContainers[0]` (copy-ldif):
```yaml
        volumeMounts:
        - name: ldap-bootstrap
          mountPath: /ldif-source
          readOnly: true
        - name: ldap-bootstrap-writable
          mountPath: /ldif-dest
```

New:
```yaml
        volumeMounts:
        - name: ldap-bootstrap
          mountPath: /ldif-source
          readOnly: true
        - name: ldap-ldif-staging
          mountPath: /ldif-staging
```

Old `command`:
```yaml
        command: ['sh', '-c', 'cp /ldif-source/* /ldif-dest/ && chown -R 911:911 /ldif-dest/']
```

New (no chown needed — the startup script copies these into the overlay FS via `copy_internal_seed_if_exists`):
```yaml
        command: ['sh', '-c', 'cp /ldif-source/* /ldif-staging/']
```

### Change 2 — main container: remove ldif/custom mount, add staging mount, add env var

Remove this `volumeMount` from `containers[0]` (openldap):
```yaml
        - name: ldap-bootstrap-writable
          mountPath: /container/service/slapd/assets/config/bootstrap/ldif/custom
```

Add this `volumeMount` instead:
```yaml
        - name: ldap-ldif-staging
          mountPath: /ldif-staging
```

Add an explicit `env` block to `containers[0]` (insert after `image:`, before `envFrom:`):
```yaml
        env:
        - name: LDAP_SEED_INTERNAL_LDIF_PATH
          value: /ldif-staging
```

### Change 3 — volumes: rename the emptyDir

Remove:
```yaml
      - name: ldap-bootstrap-writable
        emptyDir: {}
```

Add:
```yaml
      - name: ldap-ldif-staging
        emptyDir: {}
```

---

## Why This Works

1. Init container copies `*.ldif` from the ConfigMap into the `ldap-ldif-staging` emptyDir at `/ldif-staging`.
2. Main container starts. Startup script line 114: `copy_internal_seed_if_exists /ldif-staging ldif/custom` — copies files into `ldif/custom` (plain overlay-FS dir, NOT a mount point).
3. Startup script line 375: reads `ldif/custom/*.ldif` and imports them into OpenLDAP.
4. Startup script line 554: `rm -rf assets/config` — succeeds because `ldif/custom` is a plain directory, not a mount point.
5. Pod reaches Running state.

`ldif/custom` is NEVER a mount point in this design.

---

## Commit Message (exact)

```
fix(ldap): use LDAP_SEED_INTERNAL_LDIF_PATH to avoid emptyDir mountpoint conflict
```

---

## Definition of Done

- [ ] `identity/ldap/deployment.yaml`: init container mounts `ldap-ldif-staging` emptyDir at `/ldif-staging`
- [ ] `identity/ldap/deployment.yaml`: init container command copies to `/ldif-staging/` (not `/ldif-dest/`, no chown)
- [ ] `identity/ldap/deployment.yaml`: main container has `env: [{name: LDAP_SEED_INTERNAL_LDIF_PATH, value: /ldif-staging}]`
- [ ] `identity/ldap/deployment.yaml`: main container mounts `ldap-ldif-staging` at `/ldif-staging`
- [ ] `identity/ldap/deployment.yaml`: NO volumeMount at `ldif/custom` in main container
- [ ] `identity/ldap/deployment.yaml`: `ldap-ldif-staging` emptyDir volume present; `ldap-bootstrap-writable` removed
- [ ] Commit message exact as above
- [ ] Commit pushed to `origin/fix/ldap-ldif-staging`
- [ ] Report: commit SHA
