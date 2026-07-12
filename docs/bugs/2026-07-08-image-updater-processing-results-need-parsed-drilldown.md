# Bugfix: Image Updater processing logs need parsed drilldown, not repeated generic lines

## Problem

The `Image Updater Processing Results` Grafana panel is useful only in a very
rough sense today. It shows the same `Processing results:` prefix on every row,
but hides the fields that matter for triage:

- `applications`
- `images_considered`
- `images_skipped`
- `images_updated`
- `errors`

That makes the panel feel repetitive instead of actionable.

## Root Cause

The panel is querying Loki as a generic log search:

```logql
{namespace="cicd",pod=~"argocd-image-updater.*"} |= "Processing results:"
```

That returns the raw line, but it does not parse the inner logfmt payload, so
Grafana renders the same prefix over and over.

## Fix

Update the panel query so it:

1. extracts the inner log line,
2. regex-parses the `msg=` payload into the counters we care about,
3. formats the row as a compact per-cycle summary.

The panel should still allow log-details drilldown, but the main view should now
show the actual counters instead of the repeated prefix.

## Required Change

`scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`

**OLD**
```logql
{namespace="cicd",pod=~"argocd-image-updater.*"} |= "Processing results:"
```

**NEW**
```logql
{namespace="cicd",pod=~"argocd-image-updater.*"} | json | line_format "{{.log}}" | regexp "Processing results: applications=(?P<applications>\\d+) images_considered=(?P<images_considered>\\d+) images_skipped=(?P<images_skipped>\\d+) images_updated=(?P<images_updated>\\d+) errors=(?P<errors>\\d+)" | line_format "applications={{.applications}} images_considered={{.images_considered}} images_skipped={{.images_skipped}} images_updated={{.images_updated}} errors={{.errors}}"
```

## Expected Outcome

- the panel becomes a real cycle summary instead of a repeated prefix
- the raw log line is still available in panel details
- operators can tell at a glance whether Image Updater is idle, skipping, or updating
