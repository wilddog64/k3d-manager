# Web Console B capture kit — child c: simplify the operator path (fewer prompts, no hand-made token file)

**Status:** SPEC rev 1 — 2026-11-28, awaiting blind review (Fable + Neon)
**Parent:** [`web-console-b-capture-kit.md`](web-console-b-capture-kit.md) (enabling work of the parent; no release slot)
**Branch:** task branch from `k3d-manager-v1.47.0`
**Risk:** medium (touches how the capture token and the connector token reach the kit; the scan-term privacy contract)
**Implementer:** Luna (codex, `gpt-6-luna`)
**Verifier:** Claude, from `## Acceptance` only; the live run is sitting 1 itself, by the operator
**Filed:** 2026-11-28
**Intent approved:**
**Approval:** operator 2026-11-28, after deferring sitting 1: "this process still too complicate"; then "can you draft the spec and have neon/fable review it? send me intents when done. I can apporve it with my phone"

## Why

Sitting 1 today asks the operator for five dashboard steps, a hand-typed Keychain command, a hand-made token file
(`mkdir`, `cat`, `chmod`) and five copied IDs (account, app, tunnel, hostname, team). The operator stopped at the
first ID. Four of the five IDs, and both hand-typed shell steps, can be handled by the kit using only what it already
has: the read-only capture token and the operator's own terminal.

## Change

### C1 — `api` asks for one ID, resolves the rest by name

`scripts/lib/wcb_capture/api.py` `Api.run`:

1. Prompt `Cloudflare account id:` only (unchanged validation, `ACCOUNT_RE`).
2. Prompt `Application name [wcb-capture]:` and `Tunnel name [k3dm-capture-tunnel]:` (Enter takes the default;
   the names are validated `^[A-Za-z0-9._-]{1,64}$`).
3. Resolve with the read-only token, through the existing `_curl` (GET only, token only on stdin):
   - app: `GET /accounts/{account}/access/apps?name=<name>&exact=true` → exactly one result, its `id` (or `uid`)
     must match `ID_RE`; hostname = its `domain` up to the first `/`, which must be a non-empty hostname
     (`^[A-Za-z0-9.-]{1,253}$`).
   - tunnel: `GET /accounts/{account}/cfd_tunnel?name=<name>&is_deleted=false` → exactly one result, its `id` must
     match `ID_RE`.
   - team: `GET /accounts/{account}/access/organizations` → `auth_domain`; team = the label before the first `.`,
     `^[a-z0-9-]{1,63}$`.
4. Print one line per resolved item **without the value**: `app: resolved (1 match)`, `tunnel: resolved (1 match)`,
   `hostname: resolved`, `team: resolved`. On zero or several matches, a non-matching shape, an HTTP error or JSON
   that does not parse, print `<item>: not resolved (<reason without values>)` and **fall back to today's prompt** for
   that one value (same validation as today). The kit never guesses between several matches.
5. The resolution responses are held in memory only: nothing from them is written to `(1)/raw` or `(1)/filtered`.
   The existing endpoint loop fetches `apps` and `organization` again as today.
6. **Ordering invariant (privacy):** `(1)/terms` is written with all five values, as today (same file, same order,
   `0600`), **before** the first request of the existing endpoint loop and before anything is written under
   `(1)/raw` or `(1)/filtered`.

`api --after-disable` reuses `(1)/terms` when it is a regular file (not a symlink), mode `0600`, owned by the
operator, with exactly five non-empty lines passing today's validations; otherwise it runs steps 1–6.

### C2 — `api` offers to store the capture token when it is missing

When `security find-generic-password -s k3dm-cloudflare-access-capture-token` exits non-zero, `api` prints one line
saying the token is missing and asks `Store it now? macOS will prompt for it, hidden [y/N]`. On `y` it runs
`/usr/bin/security add-generic-password -a <login> -s k3dm-cloudflare-access-capture-token -w` with the operator's
terminal as stdin/stdout/stderr (no capture, no `input=`), so `security` itself prompts with echo off and the value
never passes through Python. Then it repeats the presence check by exit code and continues, or stops on failure.
On anything but `y`, it stops as today.

### C3 — `stage` takes the connector token with hidden input

`scripts/lib/wcb_capture/stage.py` `main`, after the commit confirmation and before the `sudo install` steps:

- If `(1)/tunnel-token` exists: refuse unless it is a regular file, not a symlink, mode `0600`, owned by the operator
  (the same test `supervisor.py:168-171` applies), then continue.
- If it does not exist: prompt with `getpass.getpass('Paste the tunnel connector token (hidden): ')`, strip
  surrounding whitespace, refuse unless it matches `^[A-Za-z0-9+/=_-]{40,4096}$` (no value in the message), then
  write it with `os.open(path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0o600)`, then confirm mode `0600` by `lstat`.
- The value is never printed, logged, put in argv or the environment, or written anywhere else.

### C4 — tests

In `scripts/tests/bin/test_wcb_capture_data.py` (api) and `scripts/tests/bin/test_wcb_capture_root.py` (stage),
with recording stubs for `curl`, `security` and `getpass`, fixtures under `tmp_path` that assert their scratch root
first.

## Files

| File | Change |
|---|---|
| `scripts/lib/wcb_capture/api.py` | C1, C2 |
| `scripts/lib/wcb_capture/stage.py` | C3 |
| `scripts/tests/bin/test_wcb_capture_data.py` | api tests |
| `scripts/tests/bin/test_wcb_capture_root.py` | stage tests |

The short operator card (`docs/howto/web-console-b-captures-card.md`) and the how-to edits (drop the hand-made token
file and the five-ID list) are written by Claude after this child lands, not by the worker.

## Contract readers

- `(1)/terms` — writer `scripts/lib/wcb_capture/api.py:97-100` (format and mode unchanged; written earlier relative to
  resolution, never later than today relative to the endpoint loop). Readers unchanged: `scripts/lib/wcb_capture/filters.py:35`,
  `scripts/lib/wcb_capture/scan.py:33`, `scripts/lib/wcb_capture/collect.py:39`; **new reader**:
  `api.py` for `--after-disable`.
- `(1)/tunnel-token` — today written by hand (`docs/howto/web-console-b-captures.md:75-81`); **new writer**
  `stage.py`. Reader unchanged: `scripts/lib/wcb_capture/supervisor.py:168-176` (checks regular, not symlink, `0600`,
  owner) and `isolation.py:120` (`--token-file` argv shape).
- Keychain item `k3dm-cloudflare-access-capture-token` — reader `api.py:46-54` unchanged; **new writer** `api.py` C2
  through `security add-generic-password` (today written by hand, `docs/howto/web-console-b-captures.md:48`).

## External behaviour (proof before dispatch)

Cloudflare's published OpenAPI schema, `cloudflare/api-schemas` `openapi.json` at `904c5434` (2026-11-27), read by
Claude on m4-air 2026-11-28:
- `GET /accounts/{account_id}/access/apps` (`access-applications-list-access-applications`) takes query `name`,
  `domain`, `exact`, `search`; schema `access_domain` is "the primary hostname and path secured by Access", example
  `test.example.com/admin` (hence "up to the first `/`").
- `GET /accounts/{account_id}/cfd_tunnel` (`cloudflare-tunnel-list-cloudflare-tunnels`) takes query `name`,
  `is_deleted`, `uuid`.
- `GET /accounts/{account_id}/access/organizations` returns `auth_domain`, "the unique subdomain assigned to your
  Zero Trust organization".
- Not proven: that the read-only token's permissions (Access: Apps and Policies Read, Cloudflare Tunnel Read,
  Access: Organizations Read) allow these list calls with filters. The fallback in C1 step 4 makes a refusal cost one
  prompt, not a failure; sitting 1's raw `apps` capture records the real behaviour.

## What NOT to Do

- No write call to Cloudflare; every request stays a GET through `_curl` (`proto =https`, token on stdin only).
- Do not print, log or store any resolved ID, hostname or team outside `(1)/terms`; no values in error text.
- Do not read the capture token or the connector token into a variable that is printed, logged, put in argv or env.
- Do not change `terms`' format, `supervisor.py`, `isolation.py`, `filters.py`, `scan.py`, `collect.py`, a1's root
  modules, `bin/k3dm-wcb-capture`, or the how-to.
- Commit nothing.

## Acceptance

```yaml
must:
  - id: S-M1
    text: "api with stubbed responses (one app, one tunnel, an organization with auth_domain) prompts only for the account id and the two names (Enter accepts defaults), writes (1)/terms with the five resolved values in today's order and mode 0600, then runs today's endpoint loop"
  - id: S-M2
    text: "for each of app, tunnel, hostname and team, zero matches, two matches, an HTTP error, unparseable JSON or a bad shape prints '<item>: not resolved' and prompts for that value only, with today's validation"
  - id: S-M3
    text: "api with the Keychain item missing and the answer y runs /usr/bin/security add-generic-password -a <login> -s k3dm-cloudflare-access-capture-token -w with inherited stdio, re-checks presence by exit code, and continues; any other answer stops as today"
  - id: S-M4
    text: "stage with no (1)/tunnel-token reads it through getpass, writes it O_EXCL|O_NOFOLLOW mode 0600 owned by the operator; with a valid existing file it continues without prompting"
  - id: S-M5
    text: "api --after-disable with a valid (1)/terms prompts for nothing and requests only the app-after-disable endpoint"
must_not:
  - id: S-N1
    text: "any resolved ID, hostname, team, the capture token or the connector token appears in stdout, stderr, an exception message, argv of any recorded command, or any file other than (1)/terms and (1)/tunnel-token"
    red_on_current: "red by mutation: print the resolved app id after resolution — the capture-all-output test fails"
  - id: S-N2
    text: "anything is written under (1)/raw or (1)/filtered before (1)/terms holds all five values"
    red_on_current: "red by mutation: write terms after the endpoint loop — the ordering test (records the order of file writes) fails"
  - id: S-N3
    text: "with two apps (or two tunnels) of the same name, api picks one instead of prompting"
    red_on_current: "red by mutation: take results[0] — the two-match test fails"
  - id: S-N4
    text: "stage writes through a symlinked (1)/tunnel-token, accepts an existing file that is not 0600 or not owned by the operator, or overwrites an existing file"
    red_on_current: "red by mutation: open without O_EXCL|O_NOFOLLOW — the symlink test fails"
  - id: S-N5
    text: "a Cloudflare request other than GET is made, or the token leaves curl's stdin config"
    red_on_current: "green on current and after: positive control kept (a3's test_api_token_only_enters_curl_stdin_and_curl_is_get extended to the resolution calls)"
evidence:
  - id: S-E1
    proves: [S-M1, S-M2, S-M5, S-N1, S-N2, S-N3, S-N5]
    kind: offline
    command: "python3 -m pytest scripts/tests/bin/test_wcb_capture_data.py -q: resolution happy path, every fallback case per item, after-disable reuse and its invalid-terms fallback, all-output capture test asserting none of the stub values or token appears outside terms, write-order recorder, two-match refusal, GET-only + stdin-token control. Red controls S-N1, S-N2, S-N3 run in an isolated copy and restored byte-identical"
    intent: "You type one ID instead of five; the tool finds the rest itself, never guesses between look-alikes, and never shows or saves those values anywhere except the one private file the privacy scan uses."
  - id: S-E2
    proves: [S-M3]
    kind: offline
    command: "pytest -k keychain: missing item + 'y' records exactly the security add-generic-password argv with no input= and no capture; 'n' stops; a failed re-check stops"
    intent: "If the capture token is not stored yet, the tool offers to store it and macOS asks for it with hidden typing; the tool itself never sees it."
  - id: S-E3
    proves: [S-M4, S-N4]
    kind: offline
    command: "python3 -m pytest scripts/tests/bin/test_wcb_capture_root.py -q -k tunnel_token: getpass stub write, mode and owner check, existing-valid skip, refusals for symlink, 0644, foreign owner and bad shape (message without the value). Red control S-N4 in an isolated copy"
    intent: "Pasting the tunnel token happens once, hidden, inside the tool; it lands in a private file the tool refuses to accept if anything about it looks tampered with."
  - id: S-E4
    proves: [S-M1, S-M3, S-M4]
    kind: live
    command: "operator sitting 1 on m4: api asks for the account id and two names (Enter twice) and prints 'resolved' lines; stage asks for the tunnel token hidden; Claude reads the collected output"
    intent: "Sitting 1 is the dashboard clicks, one ID, Enter twice and one hidden paste."
  - id: S-E5
    proves: [S-N1, S-N5]
    kind: offline
    command: "ruff on the two modules and two tests rc 0; CLT /usr/bin/python3 -IS py_compile rc 0; make test-pytest rc 0 (Claude, outside the sandbox)"
    intent: "The change passes every existing check, including on the Mac's built-in Python."
interface:
  - "api prompts: account id; Application name [wcb-capture]; Tunnel name [k3dm-capture-tunnel]; per-item fallback prompts as today"
  - "stage: hidden connector-token prompt when (1)/tunnel-token is absent"
```

## Worker definition of done

Focused pytest for `test_wcb_capture_data.py` and `test_wcb_capture_root.py` pass; red controls S-N1–S-N4 each run
in an isolated copy, named failing test reported, restored byte-identical; ruff and CLT compile rc 0; `git status`
shows only the four files in `## Files`. Skip `make test` and `make test-pytest` (sandbox socket noise; Claude runs
them outside the sandbox).
