# Issue — `acg-extend` Playwright CDP attach fails on Chrome 147

## What I tried

- Ran `./bin/acg-extend-test https://app.pluralsight.com/hands-on/playground/cloud-sandboxes --provider gcp` against the existing Chrome CDP session on port `9222`.
- The run failed before it could exercise the provider-scoped selector because Playwright's browser-level CDP attach path errored.
- I then validated the DOM scoping with a direct CDP websocket probe against the existing page, without launching a new Chrome instance.

## Actual output

```text
INFO: Using provider gcp
ERROR: CDP connection is required for this run: browserType.connectOverCDP: Protocol error (Browser.setDownloadBehavior): Browser context management is not supported.
Call log:
  - <ws preparing> retrieving websocket url from http://localhost:9222
  - <ws connecting> ws://localhost:9222/devtools/browser/84fd3a89-051f-4644-a46d-3ac715d5cca2
  - <ws connected> ws://localhost:9222/devtools/browser/84fd3a89-051f-4644-a46d-3ac715d5cca2
  - <ws disconnecting> ws://localhost:9222/devtools/browser/84fd3a89-051f-4644-a46d-3ac715d5cca2
  - <ws disconnected> ws://localhost:9222/devtools/browser/84fd3a89-051f-4644-a46d-3ac715d5cca2 code=1000 reason=
```

Direct CDP probe output:

```json
[
  {
    "selector": "button[data-heap-id*=\"AWS Sandbox - Open Sandbox\"]",
    "count": 1,
    "texts": [
      "Open Sandbox"
    ],
    "heaps": [
      "Hands-on Playground - Click - AWS Sandbox - Open Sandbox"
    ]
  },
  {
    "selector": "button[data-heap-id*=\"Azure Sandbox - Open Sandbox\"]",
    "count": 1,
    "texts": [
      "Open Sandbox"
    ],
    "heaps": [
      "Hands-on Playground - Click - Azure Sandbox - Open Sandbox"
    ]
  },
  {
    "selector": "button[data-heap-id*=\"Google Cloud Sandbox - Open Sandbox\"]",
    "count": 1,
    "texts": [
      "Open Sandbox"
    ],
    "heaps": [
      "Hands-on Playground - Click - Google Cloud Sandbox - Open Sandbox"
    ]
  }
]
```

## Root cause

- Playwright's `chromium.connectOverCDP('http://localhost:9222')` path is failing against this Chrome build with `Browser.setDownloadBehavior` / browser-context-management unsupported.
- Before I added the `ACG_REQUIRE_CDP` guard, the harness would fall through to `launchPersistentContext(...)`, which is what opened the extra Chrome instance the user complained about.

## Follow-up

- Keep `ACG_REQUIRE_CDP=1` on `bin/acg-extend-test` so the harness fails fast instead of opening a second browser.
- If full end-to-end validation is still needed, replace the Playwright browser-level CDP attach in the test harness with a direct page-websocket CDP client that does not depend on Playwright's browser-context setup.
