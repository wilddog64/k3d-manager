# Plan: LDAP Rotator Variable Rename — Docs/Memory-Bank Cleanup

**Date:** 2026-02-27
**Status:** Code complete — docs cleanup only
**Branch:** `fix/ldap-rotator-rename` (create from `main`)
**Related:** `docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md`

---

## Background

GitGuardian flagged `LDAP_PASSWORD_ROTATOR_IMAGE` in `scripts/etc/ldap/vars.sh` as a
"Generic Password" false positive (variable name contains "PASSWORD", default value
`docker.io/bitnami/kubectl:latest` matches a credential pattern).

The fix — renaming `LDAP_PASSWORD_ROTATOR_*` to `LDAP_ROTATOR_*` — has **already been
applied to the code**. Verification:

```bash
grep -r "LDAP_ROTATOR\|LDAP_ROTATION" scripts/
# scripts/etc/ldap/vars.sh:        LDAP_ROTATOR_ENABLED, LDAP_ROTATOR_IMAGE, LDAP_ROTATION_SCHEDULE, LDAP_ROTATION_PORT
# scripts/plugins/ldap.sh:         LDAP_ROTATOR_IMAGE, LDAP_ROTATOR_ENABLED, LDAP_ROTATION_SCHEDULE
# scripts/etc/ldap/ldap-password-rotator.yaml.tmpl: LDAP_ROTATOR_IMAGE, LDAP_ROTATION_SCHEDULE

grep -r "LDAP_PASSWORD_ROTATOR" scripts/
# (no output — old names are gone from scripts/)
```

Only memory-bank files and one reference in `docs/issues/` still mention the old variable
names. This plan is a docs-only cleanup — **no code changes needed**.

---

## Scope

Three files need updating:

1. **`memory-bank/progress.md`** — mark the rename task `[x]` (it's done)
2. **`memory-bank/activeContext.md`** — remove "pending rename to LDAP_ROTATOR_IMAGE" from
   Operational Notes
3. **`docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md`** — update
   status to reflect the rename is complete

---

## Implementation Steps

1. **Create branch** from `main`:
   ```bash
   git checkout main && git pull
   git checkout -b fix/ldap-rotator-rename
   ```

2. **Edit `memory-bank/progress.md`**:
   - Find the line: `- [ ] **Rename \`LDAP_PASSWORD_ROTATOR_*\` → \`LDAP_ROTATOR_*\`** — fix GitGuardian false positive`
   - Change `[ ]` to `[x]`
   - Add a note: `(code renamed 2026-02-23; docs cleaned up 2026-02-27)`

3. **Edit `memory-bank/activeContext.md`**:
   - Find in Operational Notes: `**GitGuardian false positive**: \`LDAP_PASSWORD_ROTATOR_IMAGE\` — pending rename to \`LDAP_ROTATOR_IMAGE\`.`
   - Replace with: `**GitGuardian false positive resolved**: \`LDAP_PASSWORD_ROTATOR_IMAGE\` renamed to \`LDAP_ROTATOR_IMAGE\` in all scripts. See \`docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md\`.`

4. **Edit `docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md`**:
   - Change `**Status:** False Positive — No real secret exposed` to
     `**Status:** FIXED — Renamed to \`LDAP_ROTATOR_IMAGE\` (2026-02-27)`
   - Under the Resolution section, add a "Done" note confirming the rename is in `main`.

5. **Commit:**
   ```bash
   git add memory-bank/progress.md memory-bank/activeContext.md \
     docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md
   git commit -m "docs: mark LDAP_PASSWORD_ROTATOR rename complete

   Code was already renamed in scripts/ (LDAP_ROTATOR_IMAGE, LDAP_ROTATOR_ENABLED,
   LDAP_ROTATION_SCHEDULE, LDAP_ROTATION_PORT). Update memory-bank and issue doc
   to reflect the rename is done."
   ```

---

## No Validation Required

This is a docs-only change — no code execution needed. After committing, confirm with:

```bash
grep -r "LDAP_PASSWORD_ROTATOR" .
# Should only appear in the issue doc as historical reference (what GitGuardian flagged)
# and nowhere else.
```

---

## Acceptance Criteria

- [ ] `memory-bank/progress.md` shows `[x]` for the rename task
- [ ] `memory-bank/activeContext.md` Operational Notes no longer says "pending rename"
- [ ] `docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md` status updated to FIXED
- [ ] `grep -r "LDAP_PASSWORD_ROTATOR" scripts/` returns no output
