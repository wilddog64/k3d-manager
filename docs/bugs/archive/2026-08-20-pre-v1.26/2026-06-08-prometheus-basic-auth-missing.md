# Bug: Prometheus Basic Auth Missing

**Filed:** 2026-06-08
**Source:** /ask agent observation

## Description

A warning indicates that the Prometheus basic authentication Vault secret was not found, resulting in an unauthenticated configuration for Prometheus. This could expose the Prometheus UI without proper access control and should be addressed by configuring the basic auth secret in Vault.
