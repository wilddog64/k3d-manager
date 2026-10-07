# Grafana latest-run panel interpreted seconds as milliseconds

## What was observed

The `Last run` panel displayed `1970-01-21 09:36:54` after the panel was changed from an
elapsed-duration query to Grafana's `dateTimeAsIso` unit.

## Root cause

Prometheus exposes `k3dm_test_last_timestamp_seconds` in Unix seconds. Grafana's absolute
datetime unit interprets the value as milliseconds, so the seconds value rendered near January
1970.

## Fix

The dashboard query now multiplies the metric by `1000` before applying `dateTimeAsIso`:

`max(k3dm_test_last_timestamp_seconds) * 1000`

The dashboard contract test asserts both the conversion and the absolute datetime unit.
