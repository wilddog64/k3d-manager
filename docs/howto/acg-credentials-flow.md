# ACG Credential Extraction — Flow Reference

This document traces every decision point in `acg_get_credentials` for debugging.

---

## Full Flow

```
acg_get_credentials [sandbox-url]
│
├─ node installed?  ──── NO ──► ERROR: install Node.js
│
├─ playwright module installed?  ──── NO ──► ERROR: cd scripts/playwright && npm install
│
├─ curl 127.0.0.1:9222/json  ──── OK ──► Chrome already running, skip launch
│
└─ NOT OK ──► _antigravity_launch
              │
              ├─ macOS:  open -a "Google Chrome" --args
              │            --remote-debugging-port=9222
              │            --password-store=basic
              │            --user-data-dir=~/.local/share/k3d-manager/profile
              │
              └─ Linux:  google-chrome / chromium --remote-debugging-port=9222
                           --password-store=basic
                           --user-data-dir=~/.local/share/k3d-manager/profile &
                         │
                         └─ Chrome binary not found?  ──► ERROR

              _antigravity_browser_ready 30
              │
              └─ polls 127.0.0.1:9222/json every 1s for up to 30s
                 timeout?  ──► ERROR: Chrome did not become ready

node scripts/playwright/acg_credentials.js <sandbox-url> --provider aws|gcp
│
├─ chromium.connectOverCDP('http://127.0.0.1:9222')
│  └─ FAIL ──► ERROR: CDP connection refused (Chrome not on port 9222)
│
├─ Find Pluralsight tab
│  ├─ search contexts()[0].pages() for hostname ending in .pluralsight.com
│  └─ fallback: pages()[0]
│     └─ no pages at all ──► ERROR
│
├─ Navigation decision
│  ├─ not on app.pluralsight.com  ──► page.goto(targetUrl)
│  ├─ already on exact targetUrl  ──► skip (SPA auth preserved)
│  ├─ on pluralsight, target is cloud-sandboxes  ──► SPA navigate (link click or location.assign)
│  └─ on pluralsight, other path  ──► page.goto(targetUrl)
│
├─ Wait for aria-busy to clear (30s timeout, non-fatal)
│
├─ Sign-in check
│  ├─ "Sign In" button visible?  ──── NO ──► already authenticated, skip
│  │
│  └─ YES ──► click Sign In
│             wait for id.pluralsight.com (15s)
│             fill email from PLURALSIGHT_EMAIL env var (or wait for Password Manager)
│             click Continue if visible
│             wait for password field
│             click password field → wait 2s for Google Password Manager auto-fill
│             click Submit
│             wait for redirect back to app.pluralsight.com (60s)
│             └─ timeout ──► ERROR
│             wait for aria-busy to clear again (30s, non-fatal)
│
├─ Credentials panel already open?
│  ├─ input[aria-label="Copyable input"] visible (3s)  ──► skip Start/Open flow
│  │
│  └─ NOT visible ──► look for buttons in order:
│                     1. "Start Sandbox" ──► click, wait 10s
│                     2. "Open Sandbox"  ──► click, wait 10s
│                        └─ then check for nested "Start Sandbox" ──► click, wait 10s
│                     3. "Resume Sandbox" ──► click, wait 10s
│                     (none found: proceed anyway — may already be on credentials page)
│
├─ Wait for input[aria-label="Copyable input"] (15s)
│  └─ timeout ──► ERROR: credentials panel did not appear
│
├─ Extract values from all Copyable inputs
│  ├─ primary: match parent element innerText for "access key id" / "secret access key" / "session token"
│  └─ fallback (text match failed): positional — index 2=AccessKey, 3=SecretKey, 4=SessionToken
│
├─ accessKey AND secretKey found?  ──── NO ──► ERROR: Could not find AWS credentials
│
└─ stdout: AWS_ACCESS_KEY_ID=...
           AWS_SECRET_ACCESS_KEY=...
           AWS_SESSION_TOKEN=...   (omitted if not present)

Back in acg_get_credentials (bash)
│
├─ perl extract AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN from node output
│
├─ access_key or secret_key empty?
│  └─ YES ──► FALLBACK: manual paste
│             "pbpaste | ./scripts/k3d-manager acg_import_credentials"
│             return 1
│
└─ _aws_write_credentials access_key secret_key session_token
   └─ writes [default] profile to ~/.aws/credentials
```

---

## Common Failure Points

| Symptom | Likely cause | Fix |
|---|---|---|
| `CDP connection refused` | Chrome not running on 9222 | `acg_get_credentials` auto-launches; if it fails, check `ps aux \| grep chrome` for a conflicting Chrome instance without `--remote-debugging-port` |
| `No browser context found` | Chrome launched but no window/tab open | Open any tab in the `playwright-auth` Chrome window |
| `Chrome did not become ready` | macOS Keychain blocked Chrome startup | Confirm `--password-store=basic` is in the launch args; check `~/.local/share/k3d-manager/profile` exists |
| Sign-in loop / stuck on id.pluralsight.com | `PLURALSIGHT_EMAIL` not set + Password Manager didn't fire | Set `export PLURALSIGHT_EMAIL=you@example.com` before running |
| `credentials panel did not appear` | Sandbox not started, or UI changed | Manually click "Start Sandbox" in the Chrome window, then re-run |
| `Could not find AWS credentials` (positional fallback hit) | Pluralsight changed DOM order | Check `input[aria-label="Copyable input"]` count in DevTools; update positional index in `acg_credentials.js` |
| `playwright npm module not found` | npm install not run | `cd scripts/playwright && npm install` |

---

## Chrome Profile

The dedicated profile at `~/.local/share/k3d-manager/profile` keeps Pluralsight session cookies separate from your main Chrome. Once you sign in once, subsequent `acg_get_credentials` calls skip the sign-in flow entirely — as long as Chrome stays open.

To reset the session: `rm -rf ~/.local/share/k3d-manager/profile`
