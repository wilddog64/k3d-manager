# Terminal remediation outcome shown as current

## Finding

The dashboard row for `shopping-cart-order` showed `state=deployment_advanced`
with no `applied` timestamp. The exporter had marked the newest event for the
service/image pair `current=true`, even though `deployment_advanced` means the
requested remediation was not verified and a different deployment digest is
now live.

## Fix

The exporter now forces `current=false` for `superseded` and
`deployment_advanced` display states. These events remain available in the
Remediation History (audit) panel, while Current CVE Remediation Status only
contains actionable/latest non-terminal outcomes.

## Verification

The embedded exporter compiles through the existing observability BATS suite,
and a regression assertion verifies the terminal-state current flag behavior.
