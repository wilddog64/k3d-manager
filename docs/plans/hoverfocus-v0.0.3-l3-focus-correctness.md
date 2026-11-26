# hoverfocus v0.0.3 L3 — focus correctness: yabai make-key sequence, Electron AX tree, bounded caches

**Status:** spec rev 1 — not reviewed; reviews due: Fable + Argon, plus a Neon blind review (operator rule); not dispatched
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent:** [`hoverfocus-v0.0.3-plan.md`](hoverfocus-v0.0.3-plan.md) (batch L3)
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.3` (cut from `main` at `d2cdb00`, the v0.0.2 merge)
**Risk:** medium (private SkyLight event records on the focus path; a wrong record silently sends keys nowhere)
**Implementer:** Luna (`codex`, `gpt-6-luna`, logic). Runs in parallel with F2 (no shared file). U1 waits for L3 to land
(both edit `Sources/hoverfocus-selftest/main.swift`). **Verifier:** Claude, from `## Acceptance` only.
**Filed:** 2026-11-25
**Intent approved:** pending
**Approval:** operator 2026-11-24 ("let's plan to work on hoverfocus v0.0.3"; D1-D3); operator 2026-11-25 "go ahead to do
1 .. 3" (write the L3/F2/U1 child specs)

## Fixes

| Input | Defect (v0.0.2, `d2cdb00`) |
|---|---|
| B1 `docs/hoverfocus/bugs/2026-11-23-hoverfocus-same-app-window-switch-no-effect.md` | Hovering another window of the frontmost app does not move key focus: `_SLPSSetFrontProcessWithOptions(…, 0x400)` on an already-front process does not change its key window |
| B2 `docs/hoverfocus/bugs/2026-11-23-hoverfocus-iterm-hollow-cursor-after-no-raise-focus.md` | After focus returns to a terminal, keys arrive but the window is not *key* (hollow cursor; menu shortcuts need a click) |
| Electron `docs/hoverfocus/bugs/2026-11-24-hoverfocus-electron-apps-no-focus.md` | Slack: variant B raised the window (P2b); VS Code: keys never arrive under B (P2c). The app's AX hit-test may also not reach an `AXWindow` until the Chromium AX tree is enabled (not proven either way) |
| Safari Cmd+W `docs/hoverfocus/bugs/2026-11-23-hoverfocus-safari-no-focus.md` | Safari gets typed text but not key-window status, so Cmd-shortcuts miss (D3 widens this to every Cmd hotkey) |
| A2 `docs/issues/2026-11-23-argon-hoverfocus-pr1-review-findings.md` #2 | `Controller.swift:157` `elements[windowID] = element` never evicts; grows for the life of the login item |

## External behaviour (proof, before dispatch)

Recorded in the parent plan, `## Probe results`; summarised here so the worker does not need the parent.

- **Variant Y works on all 8 app rows with no raise** (m2-air, macOS 26.5.1, 2026-11-25; logs on m2
  `~/hf-p2b-20261125T161602.txt` and `~/hf-p2b-20261125T163145.txt`): TextEdit, TextEdit two windows (same app), Safari,
  Slack, Terminal.app, Chrome, Mail, VS Code. Variant B (what v0.0.2 ships) fails VS Code and raises Slack. All 54 P2b
  trials' SkyLight calls returned rc 0.
- **Y is yabai `focus_window_without_raise` at tag `v7.1.25`** (`src/window_manager.c:1269-1322`, constants
  `src/window_manager.h:4-6`), cross-checked against `sbmpost/AutoRaise` tag `v5.7` `AutoRaise.mm:173-186`.
- **rc 1002 (`kCGErrorInvalidConnection`) seen in the M1a/P2 probes was a probe artifact**: those scripts never opened a
  window-server connection. The shipped app has one (`Sources/hoverfocus/main.swift:70` `NSApplication.shared`).
- **Electron accepts `AXManualAccessibility`** (rc 0 for VS Code pid 32780 and Slack pid 76191; Chrome refuses with
  rc -25205 and still focuses under Y by operator sight). The probe set it **before** every Electron trial, so the
  results above hold with the Chromium AX tree on. Behaviour 3 makes the app reach the same precondition.
- **AX read-back is not a valid check for Chromium, Mail or Electron**: P2c showed the AX focused element is not the
  element the keys reach. No selftest may rely on it; live evidence is by operator sight.

## Before You Start

1. `git log --oneline -1` shows the `v0.0.3` head (`d2cdb00` unless a later commit is named at dispatch);
   `swift build --disable-sandbox` and `swift run --disable-sandbox hoverfocus-selftest` pass. Every `swift` command
   carries `--disable-sandbox` (SwiftPM's sandbox cannot nest inside `sandbox-exec`).
2. Read `Sources/HoverFocusPlatform/Controller.swift`, `Sources/CSkyLight/CSkyLight.c`,
   `Sources/CSkyLight/include/CSkyLight.h`, `Sources/HoverFocusCore/Engine.swift`, `Sources/HoverFocusCore/Interface.swift`
   and `Sources/hoverfocus-selftest/main.swift`.
3. Do not edit `Interface.swift`, `Engine.swift`, `Package.swift`, anything under `Sources/hoverfocus/`, or any file
   outside `## Files`.

## Behaviour

### 1. The focus sequence (CSkyLight)

Symbols: add `SLPSPostEventRecordTo` (SkyLight) to `names[]`; the resolver arrays and loops grow from 3 to 4 entries
(`handles` stays 2). A missing symbol keeps today's behaviour (`hf_skylight_resolve` reports it,
`ControllerError.privateAPIUnavailable`).

New public C API in `CSkyLight.h` (Swift-importable: no Carbon types in the header):

```c
#define HF_RECORD_SIZE 0xf8
#define HF_CPS_USER_GENERATED 0x200
typedef struct { uint32_t high; uint32_t low; } hf_psn;   /* layout of ProcessSerialNumber */
typedef struct {
    int32_t (*get_psn)(int32_t pid, hf_psn *psn);
    int32_t (*set_front)(hf_psn *psn, uint32_t window_id, uint32_t mode);
    int32_t (*post)(hf_psn *psn, uint8_t *record);          /* record is HF_RECORD_SIZE bytes */
    void (*sleep_us)(uint32_t microseconds);
} hf_focus_ops;

void hf_record_make_key(uint8_t record[HF_RECORD_SIZE], uint32_t window_id, uint8_t phase);   /* phase 1 or 2 */
void hf_record_activation(uint8_t record[HF_RECORD_SIZE], uint32_t window_id, bool activate);
int hf_focus_sequence(const hf_focus_ops *ops, int32_t pid, uint32_t window_id,
                      int32_t front_pid, uint32_t front_window_id);
int hf_focus_without_raise(int32_t pid, uint32_t window_id, int32_t front_pid, uint32_t front_window_id);
```

Record layouts (all bytes not listed are 0; `window_id` is written little-endian as 4 bytes at 0x3c):

| Record | 0x04 | 0x08 | 0x3a | 0x20..0x2f | 0x8a |
|---|---|---|---|---|---|
| make-key, phase 1 | 0xf8 | 0x01 | 0x10 | all 0xff | 0 |
| make-key, phase 2 | 0xf8 | 0x02 | 0x10 | all 0xff | 0 |
| activation, `activate=false` (deactivate) | 0xf8 | 0x0d | 0 | 0 | 0x02 |
| activation, `activate=true` | 0xf8 | 0x0d | 0 | 0 | 0x01 |

`hf_focus_sequence` (pure orchestration over `ops`; the order is the contract):

1. `pid <= 0` or `ops == NULL` → return -1, no op called. `get_psn(pid)` non-zero → return -1, no further op.
2. **Same app** — `front_pid == pid && front_window_id != 0 && front_window_id != window_id`:
   `post(deactivation record for front_window_id)`, `sleep_us(40000)`, `post(activation record for window_id)`.
   Otherwise none of these three calls.
3. `set_front(psn, window_id, HF_CPS_USER_GENERATED)` (0x200, **not** 0x400).
4. `post(make-key phase 1)`, then `post(make-key phase 2)`, both for `window_id`.
5. Every step in 2-4 runs even if an earlier one returned non-zero (yabai does the same). Return 0 if every rc was 0,
   else the first non-zero rc.

`hf_focus_without_raise` resolves the symbols (unavailable → -1) and calls `hf_focus_sequence` with real ops
(`GetProcessForPID`, `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo`, `usleep`). The 40 ms sleep runs on the
main thread inside the tap callback, as in yabai; the tap is listen-only, so input is not delayed.

### 2. Controller: pass the frontmost window into the sequence

`applyDecision`'s no-raise branch calls `hf_focus_without_raise(target.pid, target.windowID, frontPid, frontWid)`, where
`frontPid` is `NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0` and `frontWid` is that app's
`kAXFocusedWindowAttribute` window ID (0 when unavailable). Factor the existing lookup in `systemState()`
(`Controller.swift:167-182`) into one private helper used by both; `systemState()` behaviour is unchanged. The raise
branch (`raiseApps`) is unchanged.

### 3. Electron: enable the AX tree when the hit-test does not reach a window

In `lookup(x:y:)`, when the hit-test does not end in a window ID (copy-element fails, or `hf_ax_window_id` is non-zero):

- Find the owning pid: `AXUIElementGetPid` on the returned element if the hit-test succeeded; otherwise the owner pid of
  the front-most on-screen window at layer 0 containing the point (`CGWindowListCopyWindowInfo(.optionOnScreenOnly, …)`,
  list order is front to back).
- If that pid is > 0 and not yet recorded, set `AXManualAccessibility = true` on `AXUIElementCreateApplication(pid)`
  once, record the pid whatever the rc, and log `ax-enable pid <pid> rc <rc>` at `.info` with `privacy: .public`.
  Never set `AXEnhancedUserInterface` (known to break window animation and positioning in other apps; Chrome focuses
  without either flag per P2c).
- Return `nil` for this lookup; the next lookup (≥16 ms later, `TapState`) retries the hit-test.
- The recorded-pid set is a `RecentCache<Int32, Bool>` (Behaviour 4) with capacity 256.

### 4. A2: bounded element cache

New `Sources/HoverFocusCore/RecentCache.swift`:

```swift
public struct RecentCache<Key: Hashable, Value> {
    public init(capacity: Int)                       // capacity >= 1 (precondition)
    public var count: Int { get }
    public mutating func value(for key: Key) -> Value?   // a hit marks the key most recent
    public mutating func set(_ value: Value, for key: Key)  // insert or replace, mark most recent; evict the least
                                                            // recent entry when count would exceed capacity
}
```

`Controller.elements` becomes `RecentCache<UInt32, AXUIElement>(capacity: 32)`; the raise branch reads it with
`value(for:)`. O(capacity) eviction is fine at these sizes.

### 5. Engine: no change, but prove the same-app path

`Engine.swift:59` skips when `target.windowID == state.focusedWindowID`. P2b passed same-app B in the probe while live
E-L1 step 3 failed, and P2 showed AX focused-window state reporting the target while keys went elsewhere. L3 does not
change the Engine; it adds a selftest row proving that a different window of the frontmost app fires, and the live
matrix (L3-EL) re-checks same-app TextEdit. If L3-EL same-app still fails with Y, the Engine skip is the next suspect
and gets its own bug doc; it is not patched blind here.

### 6. Selftest (`Sources/hoverfocus-selftest/main.swift`)

Add named `check` rows; fakes for `hf_focus_ops` are `@convention(c)` functions that append to a global call log
(`get_psn`, `set_front(wid, mode)`, `post(record bytes)`, `sleep(us)`), with settable return codes.

- **Records:** `hf_record_make_key` phases 1 and 2 and both activation records equal the table above byte for byte
  (build the expected 0xf8-byte array in Swift from the table; compare the whole array).
- **Different app:** `hf_focus_sequence(pid 10, wid 7, front_pid 20, front_wid 3)` → log is exactly
  `get_psn`, `set_front(7, 0x200)`, `post(make-key 1 for 7)`, `post(make-key 2 for 7)`; rc 0.
- **Same app:** `(pid 10, wid 7, front_pid 10, front_wid 3)` → `get_psn`, `post(deactivate 3)`, `sleep(40000)`,
  `post(activate 7)`, `set_front(7, 0x200)`, `post(make-key 1 for 7)`, `post(make-key 2 for 7)`.
- **Same app, no front window:** `front_wid 0` → same log as different app.
- **Guards:** pid 0 → -1 and empty log; `get_psn` returns -1 → -1 and log is `get_psn` only.
- **Errors do not stop the sequence:** `set_front` returns 1002 → all later posts still logged; rc 1002.
- **Symbols:** `hf_skylight_resolve_with_symbol_override("SLPSPostEventRecordTo")` reports it missing (inside the
  existing `skipSkyLight` guard); the existing guard row becomes `hf_focus_without_raise(-1, 0, 0, 0) != 0`.
- **RecentCache:** capacity 2: set a, b; read a; set c → b evicted, a and c present, count 2; replacing a key does not
  grow count; capacity 1 keeps only the last set.
- **Engine same-app:** `state.focusedWindowID = 3`, target window 7 of the same pid, dwell elapsed → `.focus(target)`;
  paired control: target window 3 → `.none`.

## Files

| File | Change |
|---|---|
| `Sources/CSkyLight/include/CSkyLight.h` | new types and functions; `hf_focus_without_raise` gains two parameters |
| `Sources/CSkyLight/CSkyLight.c` | 4th symbol; record builders; `hf_focus_sequence`; real ops |
| `Sources/HoverFocusCore/RecentCache.swift` | new |
| `Sources/HoverFocusPlatform/Controller.swift` | Behaviours 2-4 |
| `Sources/hoverfocus-selftest/main.swift` | rows in Behaviour 6 |

## Contract readers

- `hf_focus_without_raise` (signature change): callers `Controller.swift:249` and selftest `main.swift:159`; no other
  reader (`git grep -n hf_focus_without_raise` on `d2cdb00`). Both updated here.
- `hf_skylight_resolve` / `missing_symbol` text: `Controller.liveChecks` (`Controller.swift:272-275`) and
  `MenuModel.statusLine(for: .privateAPIUnavailable)`: a 4th possible symbol name, no format change.
- `Interface.swift` types (`WindowTarget`, `SystemState`, `Decision`): unchanged.
- U2 (focus indicator) will hook `applyDecision`; it is specified after L3 lands.

## What NOT to Do

- No edit outside `## Files`; no change to `Engine.swift`, the raise branch, the event mask or dwell logic.
- Do not set `AXEnhancedUserInterface`. Do not use AX read-back of typed text in any test.
- Do not run the app against the window server; use `swift run --disable-sandbox hoverfocus-selftest`.
- Run every command under
  `sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/bin/sudo") (literal "/bin/launchctl"))'`.

## Acceptance

```yaml
must:
  - id: L3-M1
    text: "hf_focus_sequence calls, in order: get_psn; for a same-app switch (front_pid == pid, front_window_id not 0 and not the target) deactivate(front window), sleep 40000 us, activate(target); then set_front(target, 0x200); then make-key phase 1 and phase 2 for the target; every step runs after an earlier non-zero rc and the first non-zero rc is returned"
  - id: L3-M2
    text: "the make-key and activation records match the layout table byte for byte (0xf8 bytes, window id little-endian at 0x3c)"
  - id: L3-M3
    text: "Controller passes the frontmost app's pid and AX focused window id into hf_focus_without_raise; when a hit-test does not reach a window id it sets AXManualAccessibility once per owning pid (never AXEnhancedUserInterface) and logs ax-enable"
  - id: L3-M4
    text: "Controller.elements is a RecentCache of capacity 32; RecentCache evicts the least recently used entry and a hit refreshes recency"
must_not:
  - id: L3-N1
    text: "focus is sent with kCPSNoWindows 0x400 or without the two make-key records (the v0.0.2 sequence that raises Slack and misses VS Code) (paired: the different-app log is exactly get_psn, set_front 0x200, make-key 1, make-key 2)"
  - id: L3-N2
    text: "a same-app switch skips the deactivate/activate pair, or a different-app switch sends it (paired: same-app with front window 0 behaves as different-app)"
  - id: L3-N3
    text: "the element cache grows without bound (paired: an entry read since the last insert survives eviction)"
evidence:
  - id: L3-E1
    proves: [L3-M1, L3-M2, L3-N1, L3-N2]
    kind: offline
    command: "swift build --disable-sandbox; swift run --disable-sandbox hoverfocus-selftest rc 0 with the records, different-app, same-app, same-app-no-front-window, guards and errors-do-not-stop rows passing. Red controls, each restored byte-identical: (a) mode 0x400 in step 3 — different-app and same-app rows fail; (b) drop make-key phase 2 — both rows fail; (c) remove the same-app branch — same-app row fails, different-app still passes; (d) send the pair whenever front_pid == pid even with front_window_id 0 — no-front-window row fails; (e) write 0x3a = 0x10 into activation records — records row fails; (f) return after the first non-zero rc — errors-do-not-stop row fails"
    intent: "The exact keyboard-focus sequence that worked in every app on m2 is what the app sends, step for step, and a change to any step is caught before it ships."
  - id: L3-E2
    proves: [L3-M4, L3-N3]
    kind: offline
    command: "same selftest run: RecentCache rows pass; git grep -n 'RecentCache<UInt32, AXUIElement>(capacity: 32)' -- Sources/HoverFocusPlatform/Controller.swift prints one line. Red controls, restored: (a) never evict — capacity-2 row fails; (b) value(for:) does not refresh recency — the read-a row fails"
    intent: "HoverFocus no longer keeps a growing list of every window it has ever seen, so a login item running for weeks does not slowly use more memory."
  - id: L3-E3
    proves: [L3-M3]
    kind: offline
    command: "same selftest run: Engine same-app row and its control pass, and the SLPSPostEventRecordTo override row passes; code reading of applyDecision and lookup quoted with line numbers against Behaviours 2 and 3; git grep -n 'AXEnhancedUserInterface' -- Sources prints nothing; git grep -n 'ax-enable' -- Sources/HoverFocusPlatform/Controller.swift prints one line"
    intent: "Hovering over another window of the app you are already in is treated as a focus change, and Slack or VS Code windows are made visible to HoverFocus without side effects on other apps."
  - id: L3-EL
    proves: [L3-M1, L3-M3]
    kind: live
    command: "operator on m2, v0.0.3 build with L3 (Claude reads the unified log over SSH): for TextEdit, TextEdit second window (same app), Safari, Chrome, Mail, Terminal.app, iTerm2, Slack and VS Code (Slack and VS Code freshly relaunched), each behind another app's window: rest the pointer on it, type a word — the word lands there and the window does not come to the front; then one Cmd shortcut that only works in a key window (Cmd+W on a scratch tab or document, Cmd+F, or Cmd+L in a browser) acts on the hovered app; on hovering back to iTerm2 and Terminal.app the cursor is solid. Claude records any ax-enable log lines and focus-failed errors"
    intent: "On m2, resting the pointer on a window behind others lets you type and use Cmd shortcuts in it, without bringing it to the front, in the nine everyday apps tested, including two windows of the same app and Slack and VS Code."
interface: "CSkyLight: hf_focus_without_raise gains front_pid and front_window_id; adds hf_psn, hf_focus_ops, hf_record_make_key, hf_record_activation, hf_focus_sequence; HoverFocusCore adds public RecentCache. No change to Interface.swift, config keys or CLI flags."
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each red control's failing output and `git diff --stat` after restoring it. Commit nothing; Claude lands.
