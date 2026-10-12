# Headless Pluralsight auto-login hangs on `locator.click()` preconditions

**Filed:** 2026-09-24
**Branch:** `feat/v0.4.18-credential-test-observability`
**File:** `scripts/lib/acg/playwright/lib/pluralsight_login.js`
**Severity:** high — headless auto-login had never succeeded; every failure was mis-reported as an expired session.
**Status:** **RESOLVED & OPERATOR-CONFIRMED 2026-09-24.** `make credential-test` now reaches
`ACG_SESSION_OK path=auto-login` and completes the full chain: sandbox start, credential
extraction, and `sts:GetCallerIdentity` validation.

---

## How it surfaced

The v0.4.18 credential-test observability work (`1bcde41`) added an always-on credential
report and path-explicit `ACG_SESSION_OK` markers. On the operator's first live
`make credential-test` run after that landed, the new instrumentation produced, in order:

```
ACG_CREDENTIALS: username=present password=present
Session not authenticated — attempting headless Pluralsight login...
auto-login error: locator.click: Timeout 30000ms exceeded.
  waiting for locator('input[type="password"]').first()
  locator resolved to <input id="Password" ...>
  attempting click action
    waiting for element to be visible, enabled and stable
headless auto-login did not succeed.
ACG_SESSION_EXPIRED
ERROR: ACG_SESSION_EXPIRED
```

**This is the finding the instrumentation was built to expose.** Before v0.4.18 the same run
printed a bare `ACG_SESSION_EXPIRED` with no credential report and no path marker, so the
operator's only reasonable reading was "the session expired, sign in again." The credential
report rules that out — the Keychain values load correctly through `_secret_load_data` — and
the path marker proves execution reached the auto-login branch. The real state is that
**headless auto-login fails, and has been failing silently behind a misleading marker.**

Both invocations (with and without `K3DM_ACG_REQUIRE_CREDENTIALS=1`) behaved identically,
which also confirms the new gate does not false-positive when credentials are present.

---

## What is measured vs. what is not

Stated plainly, because an earlier hypothesis in this investigation was wrong.

**Measured:**

- Credentials load correctly: `username=present password=present`, via the real loader.
- The machine is genuinely signed out — both CDP tabs sit on `app.pluralsight.com/id/signin`.
- The hang is `field.click()` inside `fillIfVisible`, on `input[type="password"]`.
- A read-only CDP probe against that live page reported the field **visible, enabled,
  editable**, with identical bounding boxes across two animation frames (**stable: true**),
  `pointer-events: auto`, `animation: none`, and `document.elementFromPoint` at the field's
  centre returning the input itself.

**Not measured / not proven:**

- Which of *visible, enabled, stable* actually failed during the operator's run. The probe
  says a click **should** succeed against the current page state, so the naive
  "the form animates, so the element is never stable" hypothesis is **disproven**.
- Reproducing the failure requires driving a real login with the operator's credentials.
  That is out of bounds for automated investigation, so no root cause is claimed here.

**This fix is therefore justified as precondition reduction plus documented precedent, not
as a reproduced root cause.** Every change below removes a way for the flow to hang or to
fail silently, and none of them depends on knowing which condition tripped. The only real
verification gate is the operator re-running `make credential-test`.

---

## Defects

### D1 — `fillIfVisible` clicks a text input before filling it

`pluralsight_login.js:77-86`:

```js
async function fillIfVisible(page, selector, value, timeoutMs) {
  const field = page.locator(selector).first();
  if (await field.isVisible({ timeout: timeoutMs }).catch(() => false)) {
    await field.click();
    await field.fill('');
    await field.fill(value);
    return true;
  }
  return false;
}
```

Playwright's actionability requirements are asymmetric:

| action | visible | enabled | editable | **stable** | **in viewport** |
|---|---|---|---|---|---|
| `locator.click()` | ✅ | ✅ | — | ✅ | ✅ |
| `locator.fill()`  | ✅ | ✅ | ✅ | — | — |

For an `<input>`, `fill()` focuses and sets the value on its own. The preceding `click()`
buys nothing and adds two preconditions — **stable** (unchanged bounding box across two
animation frames) and the viewport requirement — that `fill()` does not have. It is the
only statement in this function that can wait on those two conditions, and it is the
statement that timed out.

### D2 — the visibility guard never waits

`locator.isVisible()` **returns immediately**; its `timeout` option is effectively a no-op.
So the `5000` passed at both call sites is inert, and a field that is still rendering is
silently classified as absent.

This is the same defect shape found repeatedly in this subsystem: **safety that looks
present but isn't.** Compare `2026-07-07-acg-session-check-render-race-false-negative.md`.

### D3 — the guard's return value is discarded, so the form submits blind

`pluralsight_login.js:98-101`:

```js
  await fillIfVisible(page, EMAIL_SELECTOR, username, 5000);
  await fillIfVisible(page, PASSWORD_SELECTOR, password, 5000);

  await page.locator(SUBMIT_SELECTOR).first().click();
```

`fillIfVisible` returns a boolean that both call sites throw away. Combined with D2, a
still-rendering field means the credential is never typed, submit fires against an empty
form, and the operator sees only the generic terminal `login_failed` — with no signal
distinguishing "wrong password" from "we never filled the password box."

### D4 — the submit click ignores this subsystem's documented click precedent

`sandbox.js:9-16` carries the precedent in a comment:

```js
// The Pluralsight sandbox SPA ignores Playwright's synthetic click (force:true only skips
// actionability checks — it still issues the click the SPA drops). Reveal/provision buttons
// must be driven with a dispatched DOM MouseEvent after scrolling into view.
```

`_robustClick` — `scrollIntoView` + `dispatchEvent(new MouseEvent('click', ...))` — is
implemented in `sandbox.js:11-16` and `acg_restart.js:96-101`. **`pluralsight_login.js` is
the one file that never received it.** Per the standing note on this trap, `force: true` is
*not* the fix: it bypasses actionability but **not** the viewport requirement.

The recorded history is that this defect recurred at least three times (lib-acg v0.1.2
`sandbox.js`, v0.1.3 `acg_restart.js` Start Sandbox, v0.1.9 2026-06-21 the same sites)
**because each fix was applied narrowly to the file that happened to break.** Fixing the
submit click in the same pass — rather than waiting for it to bite once D1–D3 let execution
reach it — is the direct lesson of those three recurrences.

---

### D5 — `EMAIL_SELECTOR` never matches: CSS attribute values are case-sensitive

**Found after F1–F4 shipped, and this one IS a reproduced root cause.** With the click hang gone,
the operator's next `make credential-test` run reached the new D3 diagnostic:

```
ACG_CREDENTIALS: username=present password=present
INFO: Session not authenticated — attempting headless Pluralsight login...
ACG_LOGIN_FIELDS_MISSING: email=missing password=filled
INFO: headless auto-login did not succeed.
```

Password filled; email never matched. A read-only CDP probe of the live signin form shows why:

| field | type | name | id | visible |
|---|---|---|---|---|
| email | `text` | `Username` | `Username` | 418×48, yes |
| password | `password` | `Password` | `Password` | 418×48, yes |

The old selector was `input[type="email"], input[name="username"], input[name="email"]`. Every arm
misses:

- `input[type="email"]` — the field is `type="text"`.
- `input[name="username"]` — **`"Username"` ≠ `"username"`. CSS attribute *values* are
  case-sensitive** (attribute *names* are not, which is the trap). Pluralsight's ASP.NET identity
  form uses PascalCase throughout.
- `input[name="email"]` — no such field exists.

Measured through Playwright's own selector engine against the live page:

```
OLD: count=0 firstVisible=n/a
NEW: count=1 firstVisible=true
```

`count=0` on a fully rendered, visible form is the bug, reproduced end to end. This is **not** a
hypothesis like D1 — the before/after counts were measured on the live DOM.

Also probed, because it would have changed the verdict: `ShowCaptcha` is `"False"` and there are
**zero** reCAPTCHA iframes, so no captcha is armed and unattended login is genuinely feasible.

### D5 fix

```js
// Pluralsight's identity form uses PascalCase attributes (name="Username", id="Username") on a
// type="text" input. CSS attribute VALUES are case-sensitive, so a lowercase [name="username"]
// arm matches nothing -- measured live: the old selector returned count=0 while the form was
// fully rendered and visible. Keep the " i" flag on every name/id arm.
const EMAIL_SELECTOR = 'input[type="email"], input[name="username" i], input[name="email" i], input[id="username" i]';
```

The ` i` case-insensitivity flag was confirmed to be honored by **Playwright's** CSS parser, not
just the browser's native `querySelectorAll` — worth checking separately, since Playwright
implements its own selector engine.

**Why D1–D4 hid this.** D2's non-waiting `isVisible()` returned `false` for the unmatched email
locator and D3 discarded that `false`, so the form submitted with only a password and failed as a
generic `login_failed`. The selector bug and the precondition bugs were stacked: fixing D1–D4 did
not fix login, it *revealed* what was actually broken. That is the point of the D3 diagnostic, and
it worked on its first run.

---

## Fix

### F1 — `pluralsight_login.js`: add `_robustClick`

Insert after the `MFA_SELECTORS` block. Matches the throwing variant in
`acg_restart.js:96-101` (see *Deliberately out of scope* on why the two existing copies are
not unified here):

```js
// The Pluralsight identity SPA drops Playwright's synthetic click (force:true skips
// actionability but still issues the click the SPA ignores, and does not waive the
// viewport requirement). Drive submit with a dispatched DOM MouseEvent instead.
async function _robustClick(locator) {
  await locator.evaluate(el => {
    el.scrollIntoView({ block: 'center', inline: 'center' });
    el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
  });
}
```

### F2 — `fillIfVisible`: wait for real, drop the click

Replace the whole function:

```js
async function fillIfVisible(page, selector, value, timeoutMs) {
  const field = page.locator(selector).first();
  try {
    await field.waitFor({ state: 'visible', timeout: timeoutMs });
  } catch {
    return false;
  }
  await field.fill('');
  await field.fill(value);
  return true;
}
```

`waitFor({ state: 'visible' })` genuinely waits, so `timeoutMs` becomes meaningful (D2).
Dropping `click()` removes the stable + viewport preconditions (D1). `fill('')` is retained
unchanged to keep the patch minimal.

### F3 — `loginWithPage`: consume the return values, then dispatch submit

Replace:

```js
  await fillIfVisible(page, EMAIL_SELECTOR, username, 5000);
  await fillIfVisible(page, PASSWORD_SELECTOR, password, 5000);

  await page.locator(SUBMIT_SELECTOR).first().click();
```

with:

```js
  const emailFilled = await fillIfVisible(page, EMAIL_SELECTOR, username, FIELD_TIMEOUT_MS);
  const passwordFilled = await fillIfVisible(page, PASSWORD_SELECTOR, password, FIELD_TIMEOUT_MS);

  if (!emailFilled || !passwordFilled) {
    console.error(`ACG_LOGIN_FIELDS_MISSING: email=${emailFilled ? 'filled' : 'missing'} password=${passwordFilled ? 'filled' : 'missing'}`);
    return { ok: false, reason: 'login_form_unavailable' };
  }

  await _robustClick(page.locator(SUBMIT_SELECTOR).first());
```

and add near the other module constants:

```js
const FIELD_TIMEOUT_MS = 15000;
```

`5000` was inert under D2; once the wait is real it becomes a live budget, and 5s is thin
for this SPA's identity form. 15s stays well inside the caller's own 30s ceiling.

The new `login_form_unavailable` reason is safe to introduce: `_autoLogin` in
`acg_session_check.js` reads only `result.reason === 'mfa_required'` and `result.ok`, so no
existing branch changes. **Do not emit the username or password into the log line** — only
the two literal states `filled` / `missing`.

### F4 — export `_robustClick`

Add `_robustClick` to `module.exports` so the new jest tests can reach it. Keep the existing
alphabetical ordering of the export block.

---

## Tests — `scripts/lib/acg/tests/providers/pluralsight_login.test.js`

The existing mocks predate this change and must be extended, or the suite fails on a
missing method rather than on behavior:

- `makeLocator` needs `waitFor` (resolving when the mock is visible, rejecting when not) and
  `evaluate` (resolving, recording that it was called).
- The submit locator now receives `evaluate`, not `click`.

Add these cases:

1. **`fillIfVisible` no longer clicks the field** — after a successful `loginWithPage`,
   assert the email and password locators' `click` mock was **never** called, and `fill` was.
   *This is the D1 regression guard.*
2. **a field that never becomes visible returns `login_form_unavailable`** — `waitFor`
   rejects for `PASSWORD_SELECTOR`; assert `{ ok: false, reason: 'login_form_unavailable' }`
   and that the submit locator's `evaluate` was **never** called (proves the form is not
   submitted blind — the D3 guard).
3. **submit is dispatched, not clicked** — on the success path assert the submit locator's
   `evaluate` was called and its `click` was not. *The D4 guard.*
4. **the missing-field log line leaks no credential** — capture `console.error`, assert the
   emitted string contains `ACG_LOGIN_FIELDS_MISSING` and does **not** contain the test
   password value.

Before committing, confirm each new test actually fails against the **pre-fix** source —
a test that passes both before and after guards nothing.

---

## Deliberately out of scope

- **Unifying the two existing `_robustClick` copies** into a shared module. The duplication
  is real and is plausibly why this defect recurred, but the copies are **not identical**:
  `sandbox.js:11-16` swallows errors with `.catch(() => {})`, `acg_restart.js:96-101` does
  not. Collapsing them would silently change error handling in the live sandbox-provisioning
  path, which cannot be verified without a live sandbox. Filed as follow-up instead of
  smuggled into a bugfix.
- **Rewiring the k3d-manager Tier 2 preflight** in `scripts/plugins/e2e.sh` from Keychain
  existence to the real loader. Waits on the v0.4.18 subtree pull.
- Any edit under `scripts/lib/acg/` **in k3d-manager** — that is a subtree; this fix is
  upstream-only.

---

## Verification

Fix implemented in **`8a74258`**, local == origin.

| Gate | Who | Status |
|---|---|---|
| `node --check` on both modified JS files | Claude | ✅ clean |
| jest suite green, count rises from 32 | Claude | ✅ 7 suites / **36** tests |
| new tests fail against pre-fix source | Claude | ✅ **4 failed / 32 passed** pre-fix |
| `npm run check` clean | Claude | ✅ clean |
| `make bats` still 138/138 | Claude | ✅ 138 ok, 0 not ok, 0 skips |
| **`make credential-test` reaches `ACG_SESSION_OK path=auto-login`** | **operator only** | ✅ **CONFIRMED 2026-09-24** |

The agent (`codex exec`) wrote the change and ran `node --check` plus jest, but could not
commit — `.git/index.lock: Operation not permitted`, its known sandbox limit — and so left the
mutation check, `npm run check` and `make bats` unrun. It stopped and reported rather than
working around the lock, which is correct. Claude reviewed the diff, ran the four outstanding
gates, and committed.

The mutation check was performed by swapping in the pre-fix source from `b48ad1c4` by file copy
(not `git stash`, which is what failed for the agent) and confirming **exactly** the four new
tests go red while all 32 pre-existing tests stay green:

```
● pluralsight login helper › fillIfVisible no longer clicks the fields
● pluralsight login helper › a field that never becomes visible returns login_form_unavailable
● pluralsight login helper › submit is dispatched, not clicked
● pluralsight login helper › the missing-field log line leaks no credential
Tests: 4 failed, 32 passed, 36 total
```

---

## Outcome — operator-confirmed 2026-09-24

The operator's third `make credential-test` run closed the loop:

```
ACG_CREDENTIALS: username=present password=present
INFO: Session not authenticated — attempting headless Pluralsight login...
ACG_SESSION_OK path=auto-login
INFO: Using provider aws
INFO: Clicking Open Sandbox...
INFO: Clicking Start Sandbox (Step 2)...
INFO: Extracting credentials...
INFO: Found 4 copyable inputs.
INFO: AWS credentials written to ~/.aws/credentials [default]
INFO: AWS credentials validated (sts:GetCallerIdentity OK)
```

`ACG_SESSION_OK path=auto-login` from a signed-out start is the first successful headless
Pluralsight login in this subsystem's history, and the chain behind it completed end to end —
sandbox start, credential extraction, and live STS validation. **All five defects are fixed and
the fix is confirmed, not merely plausible.**

Note the marker itself is what makes this legible: `path=auto-login` proves the credentials were
read and used. A bare `ACG_SESSION_OK` would have been indistinguishable from
`path=existing-session`, which never touches the credential store at all.

### What this bug is worth remembering for

Three separate diagnoses were wrong before the right one, and each was only reachable after the
previous layer was removed:

| Symptom seen | Natural reading | Actual state |
|---|---|---|
| `ACG_SESSION_EXPIRED` (pre-v0.4.18) | session expired, sign in again | auto-login had never worked |
| `locator.click` 30s timeout | the form animates, element never stable | **disproven** by probe; click was simply unnecessary |
| generic `login_failed` | wrong password | email field never matched at all |

The fix that mattered was not any one code change but **naming the failing stage**. D1–D4 did not
repair login; they exposed D5. `ACG_LOGIN_FIELDS_MISSING: email=missing password=filled` pointed
straight at the selector on its first run, after two rounds of theorizing had pointed elsewhere.

**Rule earned: when a symptom is generic, instrument the stages before theorizing about any one of
them.** And probe the live DOM before adjusting timeouts — a `count=0` locator on a rendered,
visible form is a wrong selector, never a slow page.

### Round 2 — D5 selector fix

Fix in **`b180104`**.

| Gate | Who | Status |
|---|---|---|
| `node --check` on both modified JS files | Claude | ✅ clean |
| jest count rises from 36 | Claude | ✅ 7 suites / **39** tests |
| new tests fail against the old selector | Claude | ✅ **3 failed / 36 passed** |
| `npm run check` clean | Claude | ✅ clean |
| `make bats` still 138/138 | Claude | ✅ 138 ok, 0 not ok, 0 skips |
| live Playwright selector count 0 → 1 | Claude | ✅ measured on the live form |
| **`make credential-test` reaches `ACG_SESSION_OK path=auto-login`** | **operator only** | ✅ **CONFIRMED 2026-09-24** |

**Test-coverage limitation, stated plainly.** jest here has no DOM — the suite is offline and
`jest-environment-jsdom` is not installed — so the three new tests assert the selector's *shape*
(no bare case-sensitive arm survives; every `name`/`id` arm carries ` i`), not CSS matching
behavior. Installing jsdom for one test would add a dependency to an offline suite, which is out
of proportion. The behavioral proof is the live Playwright probe above (`count=0` → `count=1`),
which cannot run in CI because it needs the operator's CDP browser. The shape assertions are
written as disappearance gates so the regression cannot silently return.

### Known cosmetic residue

`_robustClick` is exported but no test imports it directly (the guards assert through the submit
locator's `evaluate` mock instead). The export was requested by this spec and is harmless, but it
widens the module surface with an underscore-private for no current consumer. Left as-is rather
than churn a verified tree; fold into the `_robustClick` dedup follow-up.

