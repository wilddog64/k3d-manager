# Makefile — k3d-manager ACG cluster lifecycle shortcuts
# Usage: make [target] [URL=https://...]

.DEFAULT_GOAL := help

URL ?= https://app.pluralsight.com/cloud-playground/cloud-sandboxes

.PHONY: up down refresh status creds help

## Provision full stack: credentials → cluster → ESO → ArgoCD
up:
	bin/acg-up "$(URL)"

## Tear down cluster and stop all background processes
down:
	bin/acg-down --confirm

## Refresh AWS credentials and restart tunnel (use when creds expire)
refresh:
	bin/acg-refresh "$(URL)"

## Show cluster nodes, pod status, tunnel health
status:
	bin/acg-status

## Extract AWS credentials only (no cluster changes)
creds:
	scripts/k3d-manager acg_get_credentials "$(URL)"

## Show this help
help:
	@echo ""
	@echo "  k3d-manager — ACG cluster lifecycle"
	@echo ""
	@echo "  Targets:"
	@echo "    make up        Provision full stack (credentials → cluster → ESO → ArgoCD)"
	@echo "    make down      Tear down cluster and stop all background processes"
	@echo "    make refresh   Refresh AWS credentials and restart tunnel"
	@echo "    make status    Show cluster nodes, pod status, tunnel health"
	@echo "    make creds     Extract AWS credentials only"
	@echo ""
	@echo "  Override sandbox URL (falls back to default if omitted):"
	@echo "    make up URL=https://app.pluralsight.com/hands-on/playground/cloud-sandboxes/..."
	@echo ""
	@echo "  Default URL: $(URL)"
	@echo ""
