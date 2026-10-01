# Bug: Hermes status history shows numeric unknown values without their cause

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30
**Status:** FIXED (pending final commit SHA)
**Severity:** low/medium — the history panel is technically correct but easy to misread during an
incident, especially when a sensor changes to `unknown`.

## Evidence

The **Sensor status history** panel displays series such as:

```text
data_layer (unknown) 2
```

The numeric value is an internal enum (`0` healthy, `1` degraded, `2` unknown), not a count of two
failures. The graph does not display the sensor's evidence text, so it cannot distinguish among the
actual causes of `data_layer` unknown: unavailable webhook credentials/source, a missing check, or
an ungradeable payload.

## Root cause

The panel plots `hermes_sensor_status` as a gauge over time and uses the status label in the legend,
but the metric value is the numeric enum. Evidence is attached as a label only in the current
snapshot table and is not presented as a history annotation or linked detail.

## Proposed fix

Make the history panel self-explanatory:

- add a visible legend/help note for the `0/1/2` status encoding;
- add an evidence-aware companion table or annotations for status changes to `unknown`/`degraded`;
- make clear that `unknown` means “source unavailable/ungradeable,” not a confirmed service failure;
- preserve the fail-closed sensor behavior.

## Acceptance

An operator viewing a historical `unknown` point can tell what the numeric value means and retrieve
the corresponding evidence without guessing or inspecting source code.
