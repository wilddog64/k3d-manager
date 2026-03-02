# Issue: Jenkins LDAP config namespace hardcoded and cert-rotator sidecar hang

**Date:** 2026-03-01
**Component:** `scripts/plugins/jenkins.sh`, `scripts/etc/jenkins/jenkins-cert-rotator.yaml.tmpl`

## Description

1. The `deploy_jenkins` function was hardcoding the namespace `jenkins` when trying to retrieve the `jenkins-ldap-config` secret from Kubernetes. This caused the script to fail to find the secret when deploying to other namespaces like `cicd`, resulting in empty LDAP configuration variables.
2. The `jenkins-cert-rotator` CronJob pods were being injected with an Istio sidecar, which prevented them from reaching "Completed" status after the main task finished.

## Root Cause

1. Use of hardcoded literal `jenkins` instead of the local `$ns` variable in `scripts/plugins/jenkins.sh`.
2. Lack of Istio sidecar exclusion in the CronJob template.

## Fix

1. Replaced hardcoded `jenkins` with `$ns` in `scripts/plugins/jenkins.sh`.
2. Added `sidecar.istio.io/inject: "false"` annotation to `jenkins-cert-rotator.yaml.tmpl`.
