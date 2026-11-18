# dirused M4 — new-release notice and `/update` self-update

**Filed:** 2026-11-18
**Status:** DRAFT — waits on spec review (medium risk: Fable + Astra blind, Claude adjudicates), intent approval, then dispatch to Luna
**Repo / branch:** wilddog64/dirused / `m4-update-notice` (from main after PR #24 merges)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** medium (first network call; replaces its own executable)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the work laptop.

## Problem

Operator, 2026-11-18: "I don't see auto detect new version and install of dirused when new release come out". Nothing was
ever built: a release is a zip downloaded by hand from GitHub. The exe does not even know its own version: the Release
workflow publishes without `-p:Version`, so every build reports assembly version `1.0.0`.

## Operator decisions (2026-11-18)

- **Notice + `/update`:** "Notice + /update (Recommended)". Each run checks GitHub at most once a day and prints a one-line
  notice; `/update` downloads, verifies and replaces the exe. Nothing installs without `/update`.
- **Network:** "Yes, with opt-out". dirused may call github.com from the work laptop; a switch and an env var turn the
  check off; a failed check is silent and never slows or fails a scan.

## Proof of external behaviour

Claude, M4, 2026-11-18T16:35Z, curl 8.7.1, read-only probes of the public repo:

- `GET https://api.github.com/repos/wilddog64/dirused/releases/latest` returns **404**: every release is marked prerelease,
  and `/latest` skips prereleases. The updater must list releases instead.
- `GET .../releases?per_page=2` returns `v0.0.10` and `v0.0.9`, `draft: false`, `prerelease: true`, each with assets
  `dirused-<tag>-win-x64.zip`, `dirused-<tag>-win-arm64.zip` and a `.sha256` for each. `browser_download_url` is
  `https://github.com/wilddog64/dirused/releases/download/<tag>/<name>`, which redirects to
  `https://release-assets.githubusercontent.com/...`.
- The `.sha256` body is `<64 lowercase hex>  <zip name>\r\n` (written by PowerShell `Set-Content`: **CRLF**). Parse the
  first whitespace-separated token; never compare whole lines.
- The x64 zip holds `dirused.exe`, `live-check.ps1`, `README.txt` at its root. Its SHA-256 matched the `.sha256` file.
- The API needs a `User-Agent` header; unauthenticated calls are limited to 60 per hour per IP (shared by a corporate NAT;
  the once-a-day cache keeps dirused far below that).

## Rollout note

v0.0.10 and older contain no update code, so they will never show a notice. The first release with M4 (call it N)
must be installed by hand once. The notice and `/update` can only be seen live when release N+1 exists. E2 therefore
needs two releases cut after this lands.

## Change

1. **Version stamping:** `release.yml` publishes with `-p:Version=<tag without v>` (e.g. `0.0.11`). The csproj default is
   `0.0.0-dev`. `/version` prints `dirused <version> (<rid>)` and exits 0. A `-dev` build never prints a notice.
2. **Release source:** one `IReleaseSource` interface (test seam) with a GitHub implementation: `GET
   /repos/wilddog64/dirused/releases?per_page=20`, `User-Agent: dirused/<version>`, 5-second timeout, HTTPS only, the system proxy settings (the `HttpClient` default on Windows, needed behind a corporate proxy). Pick
   the highest version among non-draft releases whose tag matches `^v(\d+)\.(\d+)\.(\d+)$` (other tags ignored;
   compare the three numbers, never strings) (prereleases included) that has both the zip and `.sha256`
   for this process's architecture (`win-x64` or `win-arm64`, from `RuntimeInformation.ProcessArchitecture`).
3. **Notice:** on a normal scan, at most once per 24 hours, check in the background while the scan runs. State file
   `%LOCALAPPDATA%\dirused\update-check.json` `{checkedUtc, latest}`. After the report, if `latest` is newer, write one line
   to **stderr** (so `/json` and `/csv` on stdout stay clean): `dirused 0.0.11 is available (you have 0.0.10). Run: dirused /update`.
   If the check has not finished when the report is done, do not wait and do not record a check. Any error (offline,
   proxy, 403 rate limit, bad JSON) is silent and changes nothing. The exit code never changes because of the check.
4. **Opt-out:** the `/noupdatecheck` switch, or env `DIRUSED_NO_UPDATE_CHECK=1`, skips the check entirely (no request).
   `/help`, `/version` and usage errors never check.
5. **`/update`:** takes no targets and no other switches (usage error, exit 1, otherwise). Fetch releases, pick as in 2.
   If not newer: print `dirused 0.0.10 is up to date`, exit 0. Otherwise download the zip and `.sha256` to a temp
   directory next to the exe, verify the SHA-256, extract `dirused.exe`, then rename the running exe to `dirused.exe.old`
   and move the new one into place (Windows allows renaming a running exe, not overwriting it). Print
   `updated dirused 0.0.10 -> 0.0.11`, exit 0. Any failure (network, missing asset, checksum mismatch, no write access to the
   exe's folder) prints the reason, leaves the current exe in place and unchanged, removes the temp files, and exits 1.
   If the final move fails after the rename, rename `dirused.exe.old` back.
6. **Cleanup:** at start, delete a leftover `dirused.exe.old` beside the exe; ignore failure.
7. **Help and docs:** usage text lists `/version`, `/update`, `/noupdatecheck`; README and `tools/PACKAGE-README.txt` say
   how the notice works and how to turn it off; CHANGELOG `[Unreleased]`.

## Tests

Portable (`tests/Dirused.Tests.Portable/`, fake `IReleaseSource`, fake clock, scratch state dir and scratch exe folder;
each fixture asserts it points at the scratch folder first):

- **U1 picks newest by semver**, prereleases included, drafts and releases missing this arch's zip or `.sha256` skipped;
  `0.0.10 > 0.0.9` (not string order).
- **U2 notice once a day:** a check inside 24 h makes no request; after 24 h it does; the notice goes to stderr, stdout
  byte-identical to a run with `/noupdatecheck` (positive control: the notice text appears when newer).
- **U3 silent failure:** source throws (timeout, 403, bad JSON) → no output, exit code as without the check, state not written.
- **U4 opt-out:** `/noupdatecheck` and `DIRUSED_NO_UPDATE_CHECK=1` make zero calls to the source (positive control: one call without).
- **U5 dev build never notifies.**
- **U6 `/update` success** in a scratch folder: new exe in place, old renamed then cleaned at next start.
- **U7 checksum mismatch / missing asset / up to date:** exe bytes unchanged, temp files gone, exit 1 (0 for up to date).
- **U8 `.sha256` with CRLF and two spaces parses**; a 63-char or non-hex token is rejected.
- **U9 `/update` with a target or another switch is a usage error.**
- **U10 tag filter:** `v0.1.0-rc1`, `latest` and `0.0.12` (no `v`) are ignored; `v0.0.11` is picked.

Windows CI runs the same tests; the rename-while-running path is covered by the live check.

## Files

- `src/Dirused.Cli/Program.cs`, `src/Dirused.Cli/Dirused.Cli.csproj`
- `src/Dirused.Common/ArgParser.cs`
- `src/Dirused.Common/Update/` (new: `IReleaseSource.cs`, `GitHubReleaseSource.cs`, `UpdateCheck.cs`, `SelfUpdater.cs`, `Sha256File.cs`)
- `tests/Dirused.Tests.Portable/UpdateTests.cs` (new), `tests/Dirused.Tests.Portable/ArgParserTests.cs` (if it exists)
- `.github/workflows/release.yml`
- `README.md`, `tools/PACKAGE-README.txt`, `CHANGELOG.md`

## Contract readers

- `release.yml` asset names `dirused-<tag>-<rid>.zip` and `.zip.sha256` (`release.yml:24-32`): read by the new release
  source; asset naming must not change in this spec.
- `ArgParser.UsageText`: read by existing usage tests; grep `UsageText` in `tests/` before editing.
- Exit codes 0/1/3/4: unchanged for scans; `/update` uses 0 and 1 only.

## What NOT to Do

- No automatic install; nothing is downloaded except by `/update`.
- No GitHub token, no auth header, no telemetry, nothing sent but the `User-Agent`.
- Never write the notice to stdout; never delay or fail a scan for the check.
- Do not change asset names, release triggers or the prerelease flag.

## Acceptance

```yaml
interface:
  - "dirused /version"
  - "dirused /update"
  - "dirused <targets> /noupdatecheck ; env DIRUSED_NO_UPDATE_CHECK=1"
must:
  - id: M1
    text: a run of an older release prints one stderr line naming the newer version and `dirused /update`, at most once a day
  - id: M2
    text: /update replaces the exe with the newest release for this architecture after its SHA-256 matches
  - id: M3
    text: release builds report their tag version through /version
must_not:
  - id: N1
    text: "the check writes to stdout, delays a scan, or changes its exit code (U2, U3)"
  - id: N2
    text: "/noupdatecheck or DIRUSED_NO_UPDATE_CHECK=1 still makes a request (U4)"
  - id: N3
    text: "a failed /update (bad checksum, missing asset, network) changes or removes the current exe (U7)"
  - id: N4
    text: "anything is downloaded or installed without /update"
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3, N4]
    kind: offline
    command: portable tests U1-U9 with a fake release source, plus Windows CI on the PR
    intent: The notice shows up once a day without slowing a scan or touching its output, the off switch really turns it off, and a failed update leaves your working copy alone.
  - id: E2
    proves: [M1, M2, M3]
    kind: live
    command: "operator, work laptop, after two releases with M4 (N installed by hand, N+1 published): with N, run a scan (notice appears), run dirused /update (updated), run dirused /version (new version)"
    intent: On your work laptop, an old copy tells you about the new release and updates itself with one command.
```

**Intent approved:** pending (operator)
