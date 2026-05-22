# Copilot PR #79 Review Findings

**Date:** 2026-05-22
**PR:** #79 — fix(acg): credential wait, extraction visibility, OIDC issuer

## Finding 1 — ACG_CLUSTER_TEMPLATE exported unconditionally (FIXED)

**File:** `scripts/plugins/acg.sh:14`
**Finding:** `ACG_CLUSTER_TEMPLATE` was unconditionally overwritten on every `_acg_stub_load` call, preventing callers from pre-setting it.
**Fix:** Applied fallback pattern — caller-set value is preserved:
```bash
# Before
export ACG_CLUSTER_TEMPLATE="${_k3dm_root}/scripts/etc/acg-cluster.yaml"
# After
export ACG_CLUSTER_TEMPLATE="${ACG_CLUSTER_TEMPLATE:-${_k3dm_root}/scripts/etc/acg-cluster.yaml}"
```
**Root cause:** Template variable was written as a simple assignment; fallback idiom was not applied.

---

## Finding 2 — acg_check_ttl contract: empty output + zero exit (DEFERRED to lib-acg)

**File:** `scripts/lib/acg/scripts/plugins/acg.sh:460` (subtree)
**Finding:** `acg_check_ttl` can return exit 0 with empty output when the sandbox node is missing. Callers that test exit code only will silently misread a missing-node as a valid TTL.
**Action:** Fix upstream in lib-acg. Track on `lib-acg` next release branch.

---

## Finding 3 — Pre-commit hook: unquoted `$_refs` in printf (DEFERRED to lib-acg)

**File:** `scripts/lib/acg/scripts/hooks/pre-commit:50` (subtree)
**Finding:** `$_refs` passed unquoted to `printf` — will word-split on filenames with spaces.
**Action:** Fix upstream in lib-acg: `printf '  %s\n' "${_refs}"`.

---

## Finding 4 — package.json version mismatch (DEFERRED to lib-acg)

**File:** `scripts/lib/acg/package.json:5` (subtree)
**Finding:** `package.json` declares `0.2.0`; lockfile still has `0.1.0`; docs reference `0.3.0`.
**Action:** Align in lib-acg before next subtree pull.

---

## Finding 5 — CHANGELOG/code mismatch for --provider and process.argv (DEFERRED to lib-acg)

**File:** `scripts/lib/acg/CHANGELOG.md:42` (subtree)
**Finding:** CHANGELOG claims `acg_extend.js` uses `process.argv.includes` for `--check` detection but vendored code still uses positional `process.argv[3]`.
**Action:** Fix in lib-acg — either update the code or correct the CHANGELOG entry.

---

## Finding 6 — CHANGELOG page.evaluate claim (FALSE POSITIVE)

**File:** `CHANGELOG.md:9`
**Finding:** Copilot flagged the entry claiming `_waitForCredentials` has a `page.evaluate` fallback.
**Resolution:** The fallback exists at `acg_credentials.js:466`:
```js
value = await inputs.first().evaluate(el => el.value || '').catch(() => '');
```
`element.evaluate()` is functionally equivalent to `page.evaluate()` scoped to the element. CHANGELOG entry is accurate — no fix needed.

---

## Finding 7 — package-lock.json version mismatch (DEFERRED to lib-acg)

**File:** `scripts/lib/acg/package-lock.json:16` (subtree)
**Finding:** `package-lock.json` declares root package `version` as `0.1.0` (both top-level and `packages[""].version`), while `package.json` declares `0.2.0`. Lockfile must be regenerated or edited to match.
**Action:** Fix upstream in lib-acg: run `npm install` to regenerate the lockfile after aligning `package.json` version.

---

## Finding 8 — dismiss.click() in page.evaluate() may not trigger React handlers (DEFERRED to lib-acg)

**File:** `scripts/lib/acg/playwright/acg_credentials.js:406` (subtree)
**Finding:** The "Extend Your Session" dialog dismissal uses `dismiss.click()` inside `page.evaluate()`. For React-managed components, `click()` may not fire synthetic event handlers. The restart flow already uses `dispatchEvent(new MouseEvent('click', { bubbles: true }))` — the same pattern should be applied here for consistency and reliability.
**Action:** Fix upstream in lib-acg: replace `dismiss.click()` with `dismiss.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))` inside the `page.evaluate()` callback.
