# dirused M4 — new-release notice and `/update` self-update

**Filed:** 2026-11-18
**Status:** DRAFT — blind review done (Fable + Astra, adjudicated below); waits on operator decisions D1-D2 and intent approval, then dispatch to Luna
**Repo / branch:** wilddog64/dirused / `m4-update-notice` (from main after PR #25 merges)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** medium (first network call; replaces its own executable)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the work laptop.

## Problem

Operator, 2026-11-18: "I don't see auto detect new version and install of dirused when new release come out". Nothing was
ever built: a release is a zip downloaded by hand from GitHub. The exe does not even know its own version: the Release
workflow publishes without `-p:Version`, so every build reports assembly version `1.0.0`.

## Operator decisions (2026-11-18)

- **Notice + `/update`:** "Notice + /update (Recommended)". Runs check GitHub at most once a day and print a one-line
  notice; `/update` downloads, verifies and replaces the exe. Nothing installs without `/update`.
- **Network:** "Yes, with opt-out". dirused may call github.com from the work laptop; a switch and an env var turn the
  check off; a failed check is silent and never fails a scan.
- **D1 (pending): grace wait.** A scan that finishes before the check would otherwise never record a result. Proposed:
  after the report, wait at most 1 second more for an in-flight check, then exit without it.
- **D2 (pending): authenticating corporate proxy.** `HttpClient` uses the system proxy but sends no proxy credentials, so a
  proxy that answers 407 blocks the check and `/update` on the laptop. Proposed: send the Windows logon credentials to the
  proxy only (`DefaultProxyCredentials = CredentialCache.DefaultCredentials`); nothing is sent to GitHub.

## Proof of external behaviour

Claude, M4, 2026-11-18T16:35Z, curl 8.7.1, read-only probes of the public repo:

- `GET https://api.github.com/repos/wilddog64/dirused/releases/latest` returns **404**: every release is marked prerelease,
  and `/latest` skips prereleases. The updater must list releases instead.
- `GET .../releases?per_page=2` returns `v0.0.10` and `v0.0.9`, `draft: false`, `prerelease: true`, each with assets
  `dirused-<tag>-win-x64.zip`, `dirused-<tag>-win-arm64.zip` and a `.sha256` for each. `browser_download_url` is
  `https://github.com/wilddog64/dirused/releases/download/<tag>/<name>`, which redirects to
  `https://release-assets.githubusercontent.com/...`.
- The `.sha256` body is `<64 lowercase hex>  <zip name>\r\n` (written by PowerShell `Set-Content`: **CRLF**). Parse
  whitespace-separated tokens; never compare whole lines.
- The x64 zip holds `dirused.exe`, `live-check.ps1`, `README.txt` at its root. Its SHA-256 matched the `.sha256` file.
- The API needs a `User-Agent` header; unauthenticated calls are limited to 60 per hour per IP (shared by a corporate NAT).

Not proven here (from .NET documentation, to confirm in Windows CI or the live check): the SDK appends `+<commit>` to the
informational version; Windows allows renaming a running exe but not overwriting it.

## Rollout note

v0.0.10 and older contain no update code, so they never show a notice. The first release with M4 (N) must be installed
by hand once. The notice and `/update` can only be seen live when release N+1 exists, so E2 needs two releases cut after
this lands. `/update` replaces only `dirused.exe`; `live-check.ps1` and `README.txt` beside it stay at the old version.

## Trust model

The release account and GitHub's TLS are the trust root. The `.sha256` comes from the same release, so it proves the
download is intact, not who published it. Signed manifests are out of scope. Within that model: system certificate
validation stays on, and every URL and redirect is checked (Change 5).

## Change

1. **Version stamping.** `Directory.Build.props` sets `<Version>0.0.0-dev</Version>`. `release.yml` passes
   `-p:Version=<X.Y.Z>` only when `GITHUB_REF_NAME` matches `^v\d+\.\d+\.\d+$`; other refs (e.g. `workflow_dispatch` from
   main) build as `0.0.0-dev`. `Dirused.Cli` reads its informational version, strips any `+...`, and passes it into the
   update code (Common never reads its own assembly version). `/version` prints `dirused <version> (<rid>)`, exit 0.
2. **Release source.** `IReleaseSource` (test seam) with a GitHub implementation: one `GET
   /repos/wilddog64/dirused/releases?per_page=100` (newest 100 releases only; no pagination), `User-Agent: dirused/<version>`,
   10-second timeout, HTTPS, system proxy (proxy credentials per D2). Candidates: non-draft releases (prereleases included)
   whose tag matches `^v(\d+)\.(\d+)\.(\d+)$`, compared as three numbers, with both `dirused-<tag>-<rid>.zip` and its
   `.sha256` for this process's architecture (`win-x64` / `win-arm64`, injected in tests). Newest candidate wins; a newer
   release missing this arch's assets is skipped.
3. **Notice.** All orchestration lives in `Dirused.Common` (`UpdateCheck`) with injected stdout/stderr writers, source,
   clock, state directory and version, so the portable tests drive it. State file
   `%LOCALAPPDATA%\dirused\update-check.json` `{attemptedUtc, latest, noticedUtc}`:
   - A scan starts a check in the background if `attemptedUtc` is absent or more than 24 h old. `attemptedUtc` is written
     **before** the request, so a failure or an abandoned check still throttles the next 24 h.
   - On success, `latest` is stored. On failure the previous `latest` is kept. Errors are silent.
   - After the report: wait for an in-flight check at most the D1 grace time, then stop waiting.
   - If the stored `latest` is newer than this version and `noticedUtc` is absent or more than 24 h old, print one line to
     **stderr** and set `noticedUtc`: `dirused 0.0.11 is available (you have 0.0.10). Run: dirused /update`. So the notice
     prints at most once a day even across a 200-host loop.
   - State writes go to a temp file then rename. A missing, corrupt, locked or future-dated file counts as "never
     checked". `latest` is re-validated against the tag pattern before printing.
   - The check never changes stdout or the exit code.
4. **When no check happens.** `/noupdatecheck`, `DIRUSED_NO_UPDATE_CHECK=1`, `/help`, `/version`, usage errors, `/update`
   itself, and any version that is `-dev` or does not parse: no request and no notice. The existing `Program.Run(args,
   output, error)` overloads used by tests get no release source; only `Main` wires the GitHub source.
5. **`/update`.** Standalone: with targets or any other switch, including `/help`, it is a usage error (exit 1).
   `DIRUSED_NO_UPDATE_CHECK` does not block an explicit `/update`. Refuse with exit 1 and a reason if the version is
   dev or unparsable, or if the process file name is not `dirused.exe` (e.g. `dotnet.exe`, `testhost.exe`). Otherwise:
   - Pick as in 2. Not newer: print `dirused 0.0.10 is up to date`, exit 0. No candidate at all: print why, exit 1.
   - Take an exclusive lock file `dirused.update.lock` beside the exe. If held, exit 1.
   - Download into a fixed staging folder `.dirused-update\` beside the exe (same volume), with a 120-second timeout and a
     100 MB cap per file. Asset URLs must start with `https://github.com/wilddog64/dirused/releases/download/`; follow
     redirects only to HTTPS hosts `github.com`, `objects.githubusercontent.com` or `release-assets.githubusercontent.com`.
   - The `.sha256` must hold exactly a 64-hex token and a file-name token equal to the zip name. The zip's SHA-256 must match.
   - From the verified zip, read only the single root entry named exactly `dirused.exe` (reject the zip if it is missing,
     duplicated, or any entry path contains `..` or a drive or root). Stream it to `.dirused-update\dirused.exe`. Never
     `ExtractToDirectory`.
   - Rename the running `dirused.exe` to `dirused.exe.old` (if a `dirused.exe.old` exists and cannot be deleted, exit 1
     with nothing changed), then move the new exe into place. If the move fails, rename `.old` back; if that also fails,
     print the full `.old` path and how to restore it. Print `updated dirused 0.0.10 -> 0.0.11`, exit 0.
   - Any failure: print the reason, leave `dirused.exe` byte-identical, remove the staging folder, release the lock, exit 1.
6. **Cleanup at start** (only when the process file name is `dirused.exe` and the lock is not held): delete a leftover
   `dirused.exe.old` and `.dirused-update\` beside the exe; ignore failure.
7. **Help and docs.** Usage text lists `/version`, `/update`, `/noupdatecheck`, keeping the 79-column help limit
   asserted in `FleetRunnerTests.cs`. README and `tools/PACKAGE-README.txt` explain the notice, the opt-outs, the trust
   model, that `/update` replaces only the exe, and manual recovery from `dirused.exe.old` (e.g. an AppLocker block of the
   new exe). CHANGELOG `[Unreleased]`.
8. **`tools/live-check.ps1`** sets `$env:DIRUSED_NO_UPDATE_CHECK = '1'` at the top, because `Invoke-Dirused` (line 16)
   merges stderr into stdout before the JSON checks parse it.

## Tests

Portable (`tests/Dirused.Tests.Portable/`, fake `IReleaseSource`, fake clock, fake file system or scratch folders; each
fixture asserts it points at its scratch folder first):

- **U1** newest by number (`0.0.10 > 0.0.9`), prereleases included, drafts and releases missing this arch's zip or
  `.sha256` skipped; injected arch picks the matching asset.
- **U2** notice once a day: a second run inside 24 h makes no request and prints no notice; after 24 h both happen. The
  notice goes to stderr; stdout and exit code are identical to the same run with `/noupdatecheck` (positive control: the
  notice text appears when newer).
- **U3** silent failure: source throws (timeout, 403, 407, bad JSON) → no output, exit code unchanged, `attemptedUtc`
  written, previous `latest` kept.
- **U4** opt-out: `/noupdatecheck` and `DIRUSED_NO_UPDATE_CHECK=1` make zero source calls (positive control: one call without).
- **U5** dev and unparsable versions make zero source calls; `/update` refuses with exit 1.
- **U6** `/update` success in a scratch folder: new exe in place, old renamed, cleaned at next start.
- **U7** checksum mismatch, wrong file-name token, missing asset, zip with no / duplicate / `..` entry, oversize, URL
  or redirect to another host: exe bytes unchanged, staging gone, exit 1. Up to date: exit 0, nothing downloaded.
- **U8** `.sha256` with CRLF and two spaces parses; a 63-char or non-hex token is rejected.
- **U9** `/update` with a target, another switch or `/help` is a usage error; `/version` likewise standalone.
- **U10** tag filter: `v0.1.0-rc1`, `latest`, `0.0.12` ignored; `v0.0.11` picked.
- **U11** a source that never returns: the run returns within the grace time plus 0.5 s, no notice, stdout unchanged.
- **U12** a scan when a newer release exists makes zero asset downloads (spy separates release listing from downloads).
- **U13** injected file-system faults: `.old` exists and is locked → exit 1, exe unchanged; move fails → `.old` renamed
  back; both fail → message names the `.old` path. Lock held → exit 1.
- **U14** corrupt, future-dated and concurrent-written state files count as never checked and never throw.

Windows (`tests/Dirused.Tests/`): **W1** one test through `Program.Run` with a fake source shows the notice on stderr and
stdout unchanged; **W2** the existing `Program.Run` overloads make no network call (no source wired).

## Files

- `Directory.Build.props`, `src/Dirused.Cli/Program.cs`, `src/Dirused.Cli/Dirused.Cli.csproj`
- `src/Dirused.Common/ArgParser.cs`
- `src/Dirused.Common/Update/` (new: `IReleaseSource.cs`, `GitHubReleaseSource.cs`, `UpdateCheck.cs`, `SelfUpdater.cs`, `Sha256File.cs`, `UpdateState.cs`)
- `tests/Dirused.Tests.Portable/UpdateTests.cs` (new), `tests/Dirused.Tests/UpdateWiringTests.cs` (new)
- `.github/workflows/release.yml`, `tools/live-check.ps1`
- `README.md`, `tools/PACKAGE-README.txt`, `CHANGELOG.md`

## Contract readers

- `release.yml` asset names `dirused-<tag>-<rid>.zip` and `.zip.sha256` (`release.yml:24-32`): read by the new release
  source; unchanged.
- stderr of a scan: read by `tools/live-check.ps1:16` (merged into stdout, parsed as JSON at `:34`, checks at 52, 77, 93,
  131). Fixed by Change 8.
- `ArgParser.UsageText`: read by usage tests and the 79-column assertion in `FleetRunnerTests.cs`.
- `Program.Run(args, output, error)`: called by 10 Windows tests; they must stay network-free (Change 4, W2).
- Exit codes 0/1/3/4: unchanged for scans; `/update` uses 0 and 1 only.

## What NOT to Do

- No automatic install; no asset is downloaded except by `/update`.
- No GitHub token, no auth header to GitHub, no telemetry; only the `User-Agent` (and, per D2, proxy credentials to the proxy).
- Never write the notice to stdout; never change a scan's exit code for the check.
- Do not change asset names, release triggers or the prerelease flag.
- Do not disable certificate validation.

## Review adjudication (Claude, 2026-11-18)

Accepted from both: fast scans never record (attempt-first throttle, D1); portable tests could not see `Program.cs`
(orchestration moved to Common, U11-U12, W1-W2); dev/test hosts would self-update `dotnet.exe`/`testhost.exe` and hit
GitHub from existing tests (Change 4-5); `live-check.ps1` missed reader (verified `:16` merges `2>&1`); version source
and `workflow_dispatch` (Directory.Build.props exists; tag-gated stamping); URL/redirect/zip-entry hardening; notice vs
check frequency; state races; partial-failure paths; E2 strengthened. Accepted from Fable only: authenticating proxy (D2).
Accepted from Astra only: update lock vs concurrent startup cleanup; pagination bound. Rejected: Astra's signed manifest
(out of scope, trust model stated instead); "N4 forbids metadata" (N4 reworded to asset downloads).

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
    text: /update replaces dirused.exe with the newest release for this architecture after its SHA-256 matches
  - id: M3
    text: tag-built releases report their tag version through /version; other builds report 0.0.0-dev
must_not:
  - id: N1
    text: "the check writes to stdout, changes a scan's exit code, or holds a scan more than the grace time (U2, U3, U11, W1)"
  - id: N2
    text: "/noupdatecheck, DIRUSED_NO_UPDATE_CHECK=1, a dev build, or an existing Program.Run test call makes a request (U4, U5, W2)"
  - id: N3
    text: "a failed /update changes or removes the current exe (U7, U13)"
  - id: N4
    text: "an asset is downloaded or installed without /update (U12)"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3, N4]
    kind: offline
    command: portable tests U1-U14 with a fake release source and file system; Windows tests W1-W2; Windows CI on the PR
    intent: The notice shows up once a day without slowing a scan or touching its output, the off switch really turns it off, and a failed update leaves your working copy alone.
  - id: E2
    proves: [M1, M2, M3]
    kind: live
    command: "operator, work laptop, after releases N (installed by hand) and N+1: dirused /version shows N; delete update-check.json; dirused C:\\ /json > o.json shows the notice and o.json parses; a second run shows no notice; a run with DIRUSED_NO_UPDATE_CHECK=1 shows none; dirused /update succeeds; dirused /version shows N+1; a scan works; dirused.exe.old is gone after that scan"
    intent: On your work laptop, an old copy tells you about the new release and updates itself with one command.
```

**Intent approved:** pending (operator)
