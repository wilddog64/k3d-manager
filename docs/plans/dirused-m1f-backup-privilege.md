# dirused M1f — read admin-locked folders when run elevated

**Status:** queued — after M1e merges; waiting on proof (P1, P2), then spec and intent approval
**Repo / branch:** wilddog64/dirused; `m1f-backup-privilege` from `main` after M1e
**Tracked:** separately from k3d-manager releases; out-of-band repo, no ideas-backlog step. This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Operator words (2026-11-17):** "queue M1f after M1e" — instead of an `/elevate` flag.

## Why

Some folders deny even Administrators (`System Volume Information`, other users' profiles), so dirused reports them as scan errors
and their size is missing. Relaunching elevated (`/elevate`) does not help a remote `\\server\c$` scan, because the server checks
the logged-in account, and it opens a new console window. Windows' backup privilege (SeBackupPrivilege) lets a process that
holds it read past folder permissions when it opens with backup intent; Administrators and Backup Operators hold it, disabled.

## Sketch (to be confirmed by proof)

- When the process token holds SeBackupPrivilege, enable it at start (`AdjustTokenPrivileges`); no new flag.
- Directory handles already use `FILE_FLAG_BACKUP_SEMANTICS` (M1e), so no change to how folders are opened.
- When any folder is denied, end with: `N folders denied — run from an admin prompt to include them.` (text only; JSON gains a count only if proof shows it is needed.)
- Not elevated: behaviour unchanged.

## Proof needed before the spec (Claude, read-only, dirused-dev VM)

- **P1, local:** elevated, privilege enabled, M1e's listing on `C:\System Volume Information` and another user's profile succeeds; without it, access denied (control).
- **P2, SMB:** the same over `\\localhost\c$`, to see whether the SMB server honours backup intent for a remote admin. Only loopback is available; the real-server case is the operator's office check.
- If P2 fails, M1f is local-drive only, and the closing line says so.
