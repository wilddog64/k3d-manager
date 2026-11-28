# Web Console B capture kit — child c: simplify the operator path (one ID, no hand-made token file)

**Status:** SPEC rev 2 — 2026-11-28; rev 1 reviewed blind by Fable and Neon (both NEEDS FIXES), every finding folded in (table at the end)
**Parent:** [`web-console-b-capture-kit.md`](web-console-b-capture-kit.md) (enabling work of the parent; no release slot)
**Branch:** task branch from `k3d-manager-v1.47.0`
**Risk:** medium (how the capture token and the connector token reach the kit; the scan-term privacy contract)
**Implementer:** Luna (codex, `gpt-6-luna`)
**Verifier:** Claude, from `## Acceptance` only; the live run is sitting 1 itself, by the operator
**Filed:** 2026-11-28
**Intent approved:**
**Approval:** operator 2026-11-28, after deferring sitting 1: "this process still too complicate"; then "can you draft the spec and have neon/fable review it? send me intents when done. I can apporve it with my phone"

## Why

Sitting 1 today asks for five dashboard steps, a hand-typed Keychain command, a hand-made token file (`mkdir`, `cat`,
`chmod`) and five copied IDs. The operator stopped at the first ID. After this child: the dashboard steps, **one ID**
(the account), and **one hidden paste** (the tunnel token). The kit finds the rest with the read-only token, or asks
for the one value it could not find.

## Change

### C1 — `api` asks for the account ID and resolves the rest

`scripts/lib/wcb_capture/api.py` `Api.run`, in this order (fixed; tests assert it):

1. Prompt `Cloudflare account id:`; validate with `ACCOUNT_RE` **before any Keychain or network call** (keeps
   `test_wcb_capture_data.py:163-178`'s `calls == []` on a bad account).
2. Token presence by exit code, with C2's offer when missing; then read the token as today (`_token`).
3. Resolve, through the existing `_curl` (GET only, `proto =https`, token on stdin only), with **fixed names**
   `wcb-capture` (app) and `k3dm-capture-tunnel` (tunnel) — no name prompts:
   - app: `GET /accounts/{account}/access/apps?name=wcb-capture&exact=true`
   - tunnel: `GET /accounts/{account}/cfd_tunnel?name=k3dm-capture-tunnel&is_deleted=false`
   - team: `GET /accounts/{account}/access/organizations`
   Each response is accepted only when `returncode == 0`, the body parses as JSON, `success` is not `false`, and
   `result_info.total_pages` is absent or `<= 1`. **Matching is client-side**, never trusting the server filter:
   - app: exactly one item with `name == 'wcb-capture'`; its `id` (or `uid`) matches `ID_RE`; hostname = its `domain`
     up to the first `/`, lowercased, matching
     `^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$`.
   - tunnel: exactly one item with `name == 'k3dm-capture-tunnel'` and no `deleted_at`; its `id` matches `ID_RE`.
   - team: `auth_domain` lowercased matches `^([a-z0-9-]{1,63})\.cloudflareaccess\.com$`; team = group 1.
4. For each value print `<item>: resolved` or `<item>: not resolved (<reason>)` — **no values** — where `<reason>` is
   one of the closed set `0 matches`, `multiple matches`, `http error`, `invalid json`, `unexpected shape`,
   `invalid field`, `more than one page`. An unresolved value falls back to today's prompt and validation for that
   value only. An app that does not resolve means both `app id` and `hostname` are prompted; an app that resolves with
   a bad `domain` prompts `hostname` only. The kit never picks between several matches.
5. Resolution responses stay in memory: nothing from them is written to `(1)/raw` or `(1)/filtered`.
6. **Write `(1)/terms`** (five values, today's order) safely: `isolation.check_write`, refuse if the path exists
   (including a dangling symlink, by `lstat`), create with `os.open(O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0o600)`,
   `os.fchmod(fd, 0o600)`, `fstat` check, unlink on a short write. When an earlier `terms` exists and is safe, it is
   replaced by writing a temp file in `(1)` the same way and `os.replace` onto it; an unsafe existing `terms` is
   `isolation.Refused('unsafe terms file')`.
7. Only then: `Capture gateway CA too? [y/N]` (skipped for `--after-disable`), then the existing endpoint loop.

**`api --after-disable`:** read `(1)/terms` with `os.open(O_RDONLY|O_NOFOLLOW)` + `fstat`:
- absent → steps 1–7 (without the gateway prompt);
- present but not a regular file, not `0600`, or not owned by `os.getuid()` (or a dangling symlink) →
  `isolation.Refused('unsafe terms file')`;
- safe but not exactly five values passing today's validations → refuse with `terms invalid; re-run api`;
- safe and valid → no prompts at all; only the `app-after-disable` request.

### C2 — `api` offers to store the capture token when it is missing

Only when `find-generic-password -s k3dm-cloudflare-access-capture-token` exits **44** (item not found; proof
below): print `capture token not in Keychain` and ask `Store it now? macOS will prompt for it, hidden [y/N]`. Any
other non-zero exit (locked Keychain, cancel) stops with `token lookup failed` as today, with no offer.

On `.strip().lower() == 'y'`: run `[self._binary('security'), 'add-generic-password', '-a', <login>, '-s',
'k3dm-cloudflare-access-capture-token', '-w']` through a **second runner path** that passes
`env={'PATH': '/usr/bin:/bin', 'HOME': <operator home>}` and **no** `capture_output`, `input`, `stdin`, `stdout` or
`stderr`, so `security` prompts on the terminal itself and the value never passes through Python. `<login>` is
`pwd.getpwuid(os.getuid()).pw_name`. A non-zero exit from `add-generic-password` stops; otherwise re-check presence
by exit code and continue, or stop. Any answer but `y` stops as today.

### C3 — `stage` takes the connector token with one hidden paste

`scripts/lib/wcb_capture/stage.py` `main`, after the commit confirmation and before the `sudo install` steps.
Signature unchanged (`test_wcb_capture_e2e.py:145` sets a 3-tuple of defaults); test seams are module attributes
`_secret_prompt = getpass.getpass` and `_operator_uid = os.getuid`, monkeypatched in tests.

1. `isolation.refuse_multiplexer(os.environ, ())` (tmux/screen refused, as for the other sensitive subcommands).
2. `path = first / 'tunnel-token'`; `lstat`:
   - exists (any kind, including a dangling symlink): continue only if it is a regular file, mode `0600`, owner
     `_operator_uid()`, size > 0; else `isolation.Refused('unsafe token file')`. No prompt.
   - absent: go on.
3. Refuse `isolation.Refused('no terminal for hidden input')` unless `sys.stdin.isatty()`. Prompt with
   `_secret_prompt('Paste the tunnel connector token (hidden): ')` under
   `warnings.simplefilter('error', getpass.GetPassWarning)`; a `GetPassWarning` becomes
   `isolation.Refused('cannot disable terminal echo')`.
4. Strip whitespace; refuse `isolation.Refused('token shape invalid')` unless `^[A-Za-z0-9+/=_-]{40,4096}$`.
5. `isolation.check_write(path)`; `os.open(path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0o600)`; `os.fchmod(fd, 0o600)`;
   `fstat` regular, `0600`, owner; write all bytes; on any error or short write, close and unlink, then refuse.
6. The value is never printed, logged, put in argv or env, or written anywhere else. Every refusal text is fixed and
   carries no value (`stage.py:79-80` prints `str(exc)`).

### C4 — tests

- `test_wcb_capture_data.py`: the five existing api tests (`:94-256`) are **rewritten** for the new prompt order.
  Keep the existing 8-endpoint assertion on the endpoint-loop calls and assert the 3 resolution calls separately
  (no existing assertion line removed; if one must go, add `# agent-audit: allow assert-removed <reason>`).
- `test_wcb_capture_root.py`: stage tests through `_secret_prompt` / `_operator_uid`; update
  `test_stage_uses_git_show_and_refuses_dirty` (`:205-241`) for the token prompt.
- `test_wcb_capture_e2e.py`: its `Runner` (`:66`) returns resolvable apps/tunnels/organization responses and
  `api_answers` (`:150`) becomes the account ID plus the gateway answer; the token prompt goes through
  `_secret_prompt`.
- Fixtures under `tmp_path` assert their scratch root first.

## Files

| File | Change |
|---|---|
| `scripts/lib/wcb_capture/api.py` | C1, C2 |
| `scripts/lib/wcb_capture/stage.py` | C3 |
| `scripts/tests/bin/test_wcb_capture_data.py` | api tests rewritten and added |
| `scripts/tests/bin/test_wcb_capture_root.py` | stage tests |
| `scripts/tests/bin/test_wcb_capture_e2e.py` | runner responses and answers for C1/C3 |

The short operator card (`docs/howto/web-console-b-captures-card.md`) and the how-to edits are written by Claude
after this child lands. The card tells the operator to copy the connector token from the tunnel page **immediately
before** `stage` (copying the account ID would overwrite it in the clipboard).

## Parent contract amendments (approved with this spec's intents)

1. Parent `web-console-b-capture-kit.md:123-125` "api performs only the listed GET calls": adds three GET
   resolution calls (apps list with `name`/`exact` query, `cfd_tunnel` list with `name`/`is_deleted` query,
   organizations), all through `_curl`.
2. Parent `:548` "an id in neither form is refused before any call": the account ID still is; app and tunnel IDs are
   now resolved (or prompted) after the token read and resolution calls, and validated before `terms` is written.
3. Parent `:425` `(1)/tunnel-token` writer: operator by hand → `stage` (C3). Reader unchanged.

## Contract readers

- `(1)/terms` — writer `api.py:97-100` (format unchanged; write hardened, C1 step 6). Readers:
  `filters.py:35`, `scan.py:33`, `collect.py:39-49` unchanged; **new reader** `api.py` (`--after-disable`).
- `(1)/tunnel-token` — today by hand (`docs/howto/web-console-b-captures.md:75-81`); **new writer** `stage.py`.
  Readers unchanged: `supervisor.py:168-176` (regular, not symlink, `0600`, owner), `isolation.py:120`.
- Keychain item `k3dm-cloudflare-access-capture-token` — reader `api.py:46-54` unchanged; **new writer** `api.py`
  C2 via `security add-generic-password` (today by hand, how-to `:48`).
- `stage.main` defaults tuple — reader `test_wcb_capture_e2e.py:145` (signature kept).

## External behaviour (proof before dispatch)

- **Cloudflare API** — published OpenAPI schema `cloudflare/api-schemas` `openapi.json` at `904c5434`
  (2026-11-27), read by Claude on m4-air 2026-11-28: apps list takes `name`, `domain`, `exact`, `search`;
  `access_domain` is "the primary hostname and path secured by Access" (example `test.example.com/admin`);
  `cfd_tunnel` list takes `name`, `is_deleted`, `uuid`; organizations returns `auth_domain`, "the unique subdomain
  assigned to your Zero Trust organization". **Not proven:** that the read-only token may call these lists, or that
  the server honours the filters; client-side matching (C1 step 3) and per-value fallback make either failure cost
  one prompt, never a wrong object.
- **`security`** — m4-air, macOS 26.5.2, 2026-11-28 (Claude): `man security`, `add-generic-password`: "`-w password`
  Specify password to be added. Put at end of command to be prompted (recommended)"; "`-U` Update item if it already
  exists (if omitted, the item cannot already exist)". `security find-generic-password -s
  k3dm-nonexistent-probe-item-20261128` exit **44** (presence probe of a made-up item; nothing read).

## What NOT to Do

- No write call to Cloudflare; every request stays a GET through `_curl`.
- No resolved ID, hostname or team in stdout, stderr, exception text or argv; no values in refusal text.
- The capture token never on disk; the connector token only in `(1)/tunnel-token`.
- Do not change `terms`' format, `supervisor.py`, `isolation.py`, `filters.py`, `scan.py`, `collect.py`, a1's root
  modules, `bin/k3dm-wcb-capture`, `stage.main`'s signature, or the how-to.
- Commit nothing.

## Acceptance

```yaml
must:
  - id: S-M1
    text: "api with resolvable stub responses prompts only for the account id (plus the gateway y/N), prints four 'resolved' lines with no values, writes (1)/terms with the five values in today's order (0600, O_EXCL|O_NOFOLLOW), then runs today's 8-endpoint loop"
  - id: S-M2
    text: "app: 0 matches, a name that differs client-side (server filter ignored), 2 matches, http error, invalid json, success false or more than one page each print 'app: not resolved (<closed reason>)' and prompt app id and hostname; a bad domain prompts hostname only; the same per-item for tunnel; an auth_domain not ending .cloudflareaccess.com prompts team"
  - id: S-M3
    text: "Keychain lookup exit 44 + 'y' runs security add-generic-password -a <pwd login> -s k3dm-cloudflare-access-capture-token -w through the second runner with no capture/input/stdin/stdout/stderr, checks its exit, re-checks presence and continues; exit 36 gives no offer and stops"
  - id: S-M4
    text: "stage with no (1)/tunnel-token, on a tty, reads it via the hidden prompt and writes it 0600 owned by the operator; with a valid existing file it continues without prompting"
  - id: S-M5
    text: "api --after-disable with a safe valid (1)/terms calls input zero times and requests only app-after-disable"
must_not:
  - id: S-N1
    text: "the capture token appears anywhere on disk or in output/argv/env; the connector token appears anywhere but (1)/tunnel-token; a resolved id, hostname or team appears in stdout, stderr, exception text, argv, (1)/filtered/* or (1)/ca/*, or any resolution response is written under (1)/raw or (1)/filtered"
    red_on_current: "red by mutation: print the resolved app id after resolution — the output-capture test fails (stub loop responses do contain the values, and filtered/* is checked for them)"
  - id: S-N2
    text: "any endpoint-loop request is made, or anything written under (1)/raw or (1)/filtered, before (1)/terms holds all five values"
    red_on_current: "red by mutation: write terms after the first loop request — the curl stub, which asserts terms has five lines and raw/ and filtered/ are empty at the first loop call, fails"
  - id: S-N3
    text: "api binds an app or tunnel when the list holds several items of that name, or a single item whose name differs"
    red_on_current: "red by mutation: take result[0] without the client-side name check — the filter-ignored and two-match tests fail"
  - id: S-N4
    text: "stage writes through a symlink or onto an existing file planted between its check and its open, accepts an existing token file that is a symlink (live or dangling), not 0600, not owned by the operator or empty, or prompts with echo on"
    red_on_current: "red by mutation: (a) open without O_EXCL|O_NOFOLLOW — the test whose secret-prompt stub plants a symlink before returning fails; (b) accept mode 0644 — the 0644 test fails; (c) drop the GetPassWarning filter — the echo-fallback test fails"
  - id: S-N5
    text: "api offers to store the token on a Keychain exit other than 44, or the add-generic-password call captures or feeds stdio"
    red_on_current: "red by mutation: add capture_output=True to the add call — the keychain test fails; offer on any non-zero — the exit-36 test fails"
  - id: S-N6
    text: "--after-disable rewrites or follows an unsafe (1)/terms (symlink, dangling symlink, 0644, foreign owner) instead of refusing"
    red_on_current: "red by mutation: fall back to resolution on unsafe terms — the unsafe-terms test fails"
  - id: S-N7
    text: "a Cloudflare request other than GET is made, or the token leaves curl's stdin config"
    red_on_current: "green on current and after: positive control kept (a3's test_api_token_only_enters_curl_stdin_and_curl_is_get, extended to the 3 resolution calls)"
evidence:
  - id: S-E1
    proves: [S-M1, S-M2, S-M5, S-N1, S-N2, S-N3, S-N6, S-N7]
    kind: offline
    command: "python3 -m pytest scripts/tests/bin/test_wcb_capture_data.py -q: happy path and prompt order; every fallback reason per item; filter-ignored single item; after-disable valid (zero input calls), absent, unsafe (symlink, dangling, 0644, foreign uid via _operator_uid-style seam) and invalid content; output-capture test with value-bearing loop stubs; first-loop-call order assertion; GET-only + stdin-token control. Red controls S-N1, S-N2, S-N3, S-N6 in an isolated copy, restored byte-identical"
    intent: "You type one ID instead of five; the tool finds the rest itself, never picks between look-alikes, and keeps those values only in the one private file the privacy scan uses."
  - id: S-E2
    proves: [S-M3, S-N5]
    kind: offline
    command: "pytest -k keychain: exit 44 + 'y' records exactly the add-generic-password argv with no capture/input/stdio kwargs; add failure stops; re-check failure stops; exit 36 no offer; 'n' stops. Red controls S-N5 (both) in an isolated copy"
    intent: "If the capture token is not stored yet, the tool offers to store it and macOS asks for it with hidden typing; the tool never sees it, and a locked Keychain is not mistaken for a missing token."
  - id: S-E3
    proves: [S-M4, S-N1, S-N4]
    kind: offline
    command: "python3 -m pytest scripts/tests/bin/test_wcb_capture_root.py -q (whole file): hidden-prompt write, fchmod/fstat, existing-valid skip, refusals for live and dangling symlink, 0644, foreign owner, empty file, bad shape, no tty, echo fallback, tmux/screen env, plant-in-prompt race; connector token absent from stdout, stderr, runner calls and every other file. Red controls S-N4 (a)-(c) in an isolated copy"
    intent: "Pasting the tunnel token happens once, hidden, inside the tool; it lands in a private file the tool refuses to use if anything about it looks tampered with."
  - id: S-E4
    proves: [S-M1, S-M3, S-M4]
    kind: live
    command: "operator sitting 1 on m4: api asks only for the account id (and the gateway y/N), prints 'resolved' lines; stage asks for the tunnel token hidden; Claude reads the collected output"
    intent: "Sitting 1 becomes the dashboard clicks, one ID and one hidden paste."
  - id: S-E5
    proves: [S-N1, S-N7]
    kind: offline
    command: "python3 -m pytest scripts/tests/bin/test_wcb_capture_e2e.py -q; ruff on the two modules and three tests rc 0; CLT /usr/bin/python3 -IS py_compile rc 0; make test-pytest rc 0 (Claude, outside the sandbox)"
    intent: "The change passes every existing check, end to end through the real command, including on the Mac's built-in Python."
interface:
  - "api prompts: account id; per-item fallback prompts only when a value does not resolve; gateway y/N (not on --after-disable)"
  - "stage: hidden connector-token prompt when (1)/tunnel-token is absent; refuses under tmux/screen"
```

## Worker definition of done

Focused pytest for `test_wcb_capture_data.py`, `test_wcb_capture_root.py` and `test_wcb_capture_e2e.py` pass; red
controls S-N1–S-N6 each run in an isolated copy, named failing test reported, restored byte-identical; ruff and CLT
compile rc 0; `_agent_audit` rc 0; `git status` shows only the five files in `## Files`. Skip `make test` and
`make test-pytest` (sandbox socket noise; Claude runs them outside the sandbox).

## Review dispositions (rev 1 → rev 2)

| # | Finding (reviewer) | Disposition |
|---|---|---|
| 1 | Server filter trusted; one unrelated item binds silently (Fable blocker 1, Neon 6) | Client-side name match, `total_pages`, `success`, `returncode`; filter-ignored test; S-N3 |
| 2 | S-N1 unsatisfiable: `raw/*` holds the values (Fable 2, Neon 2) | S-N1 split: tokens vs resolved values; `filtered/*` checked with value-bearing stubs |
| 3 | e2e test omitted, would break (Neon 1) | Added to Files, readers, C4; `stage.main` signature kept |
| 4 | Unsafe `terms` on `--after-disable` silently rewritten (Fable 5, Neon 3) | Refuse unsafe; write hardened; S-N6 |
| 5 | Gateway prompt before after-disable branch (Fable 6, Neon 4) | Skipped on after-disable; zero input calls asserted |
| 6 | Symlink red control cannot go red; dangling symlink; check_write; fstat (Fable 3, 10; Neon 5) | `lstat` pre-check, plant-in-prompt race test, `check_write`, `fchmod`/`fstat`, unlink on short write |
| 7 | getpass echo fallback; tmux (Fable 4, Neon 7) | tty required, `GetPassWarning` → refuse, `refuse_multiplexer` |
| 8 | Keychain exit codes, login source, runner path, order (Fable 7, 9; Neon 8) | Offer only on 44 (proved), pwd login, second runner, fixed order; S-N5 |
| 9 | Parent invariants changed undeclared (Fable 7) | Parent contract amendments section |
| 10 | Test seams; owner param misuse; tests rewritten (Fable 8, Neon 10, 11) | Module seams, `_operator_uid`, rewrite stated, audit marker rule |
| 11 | Reason text could leak; derived-value fallback (Fable 11, Neon 9) | Closed reason set; app failure prompts id + hostname |
| 12 | Ordering test vague (Fable 12) | First-loop-call assertion; mutation "after the first loop request" |
| 13 | Cut the name prompts; clipboard order (Fable 13) | Fixed names, zero Enters; card note |
| 14 | `auth_domain` custom domain, hostname case/shape (Neon 6) | `.cloudflareaccess.com` anchor; lowercase DNS-label regex |
