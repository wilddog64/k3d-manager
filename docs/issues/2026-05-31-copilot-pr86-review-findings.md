# Copilot Review Findings — PR #86 (k3d-manager v1.5.1)

**Date:** 2026-05-31
**PR:** #86 — feat: OCI backup/restore, ACG credential automation, observability fixes (v1.5.1)
**Fixed in:** `504db6e8`

## Finding 1 — k3s-oci.sh: step labels still show 10/10 after adding steps 11/12

**File:** `scripts/lib/providers/k3s-oci.sh:107`
**Finding:** Help text and `_info` step labels still advertise 10 steps; bucket creation and initial backup are steps 11 and 12.
**Fix:** Updated `_info` labels to `Step 10/12`, `Step 11/12`, `Step 12/12`.
**Root cause:** Steps 11/12 were added without updating the step count in the progress messages.

## Finding 2 — k3s-oci-storage.sh: SSH failure and empty download not caught in oci_backup

**File:** `scripts/lib/providers/k3s-oci-storage.sh:127`
**Finding:** `ssh ... etcd-snapshot save` had no `|| return 1`; `ssh ... cat` redirect to local file had no exit-code check; empty download (remote file missing) would proceed to upload a zero-byte snapshot.
**Fix:** Added `|| return 1` to snapshot save SSH; added `|| { rm -f ...; return 1; }` to download; added `[[ ! -s ... ]]` guard to reject empty downloads before upload.
**Root cause:** Initial implementation focused on happy path only.

## Finding 3 — k3s-oci-storage.sh: snapshot name not validated before use in ssh/scp

**File:** `scripts/lib/providers/k3s-oci-storage.sh:195`
**Finding:** `_snapshot_name` is derived from user-supplied `--snapshot` arg or OCI object listing and used unvalidated in remote `ssh`/`scp` command strings, opening a shell injection path.
**Fix:** Added `[[ ! "${_snapshot_name}" =~ ^k3s-etcd-[0-9]{8}-[0-9]{6}\.db$ ]]` guard immediately after derivation.
**Root cause:** OWASP A03 — user input used in command construction without sanitization.
**Process note:** All user-supplied values used in remote SSH command strings must be validated against an allowlist pattern before use.

## Finding 4 — k3s-oci-storage.sh: scp/ssh in oci_restore not fail-fast

**File:** `scripts/lib/providers/k3s-oci-storage.sh:211`
**Finding:** `scp` and `ssh` restore commands had no `|| return 1`; a failed `scp` would silently proceed to `ssh` remote restore with a missing file.
**Fix:** Added `|| return 1` to both `scp` and `ssh` calls.
**Root cause:** Same as finding 2 — happy path only.

## Finding 5 — k3s-oci-storage.sh: no BATS coverage for error paths

**File:** `scripts/lib/providers/k3s-oci-storage.sh:98`
**Finding:** `oci_backup` and `oci_restore` had no BATS tests for SSH failure, empty download, invalid snapshot name, scp failure, or remote restore SSH failure.
**Fix:** Added 5 new BATS tests covering all error paths (tests 26–30); all pass.
**Root cause:** Error paths added without corresponding test coverage.

## Findings 6+7 — CHANGELOG: misleading "automate sign-in form" wording

**File:** `CHANGELOG.md:9,16`
**Finding:** CHANGELOG claimed ACG credential automation "automates sign-in form submission" — but CAPTCHA blocks full automation; user must complete sign-in manually.
**Fix:** Updated wording to "open sign-in page for manual completion when CAPTCHA is required" and "click sign-in button and navigate to sign-in form; user completes CAPTCHA manually when required".
**Root cause:** Commit messages described the intended behavior; actual behavior is manual fallback.
