# Makefile — k3d-manager ACG cluster lifecycle shortcuts
# Usage: make [target] [URL=https://...]

.DEFAULT_GOAL := help

URL ?= https://app.pluralsight.com/cloud-playground/cloud-sandboxes
GHCR_PAT ?= $(shell gh auth token 2>/dev/null)

.PHONY: up down refresh status creds chrome-cdp chrome-cdp-stop argocd-registration sync-apps help

## Provision full stack: credentials → cluster → ESO → ArgoCD
up:
	@echo "[make] Running bin/acg-up..."
	@GHCR_PAT="$(GHCR_PAT)" bin/acg-up "$(URL)"

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

## Install Chrome CDP launchd agent (enables credential automation without manual login)
chrome-cdp:
	scripts/k3d-manager acg_chrome_cdp_install

## Uninstall Chrome CDP launchd agent
chrome-cdp-stop:
	scripts/k3d-manager acg_chrome_cdp_uninstall

## Re-register ubuntu-k3s app cluster with ArgoCD (use after sandbox recreation or IP change)
argocd-registration:
	@_token=$$(kubectl get secret argocd-manager-token -n kube-system --context ubuntu-k3s \
	  -o jsonpath='{.data.token}' 2>/dev/null | base64 -d | tr -d '\n'); \
	if [ -z "$$_token" ]; then \
	  echo "ERROR: argocd-manager-token not found on ubuntu-k3s — is the cluster up?"; \
	  exit 1; \
	fi; \
	_ctx_cluster=$$(kubectl config view \
	  -o jsonpath='{.contexts[?(@.name=="ubuntu-k3s")].context.cluster}' 2>/dev/null); \
	if [ -z "$$_ctx_cluster" ]; then \
	  echo "ERROR: ubuntu-k3s context not found in kubeconfig"; \
	  exit 1; \
	fi; \
	_server=$$(kubectl config view \
	  -o jsonpath="{.clusters[?(@.name==\"$$_ctx_cluster\")].cluster.server}" 2>/dev/null); \
	if [ -z "$$_server" ]; then \
	  echo "ERROR: server for cluster $$_ctx_cluster not found in kubeconfig"; \
	  exit 1; \
	fi; \
	_prev_ctx=$$(kubectl config current-context 2>/dev/null || echo ""); \
	trap '[ -n "$$_prev_ctx" ] && kubectl config use-context "$$_prev_ctx" >/dev/null 2>&1 || true' EXIT; \
	kubectl config use-context k3d-k3d-cluster >/dev/null || exit 1; \
	ARGOCD_APP_CLUSTER_TOKEN="$$_token" \
	ARGOCD_APP_CLUSTER_SERVER="$$_server" \
	  scripts/k3d-manager register_app_cluster && \
	kubectl rollout restart statefulset/argocd-application-controller \
	  -n cicd --context k3d-k3d-cluster && \
	kubectl rollout status statefulset/argocd-application-controller \
	  -n cicd --context k3d-k3d-cluster --timeout=90s

## Sync ArgoCD data-layer and show remote pod status
sync-apps:
	bin/acg-sync-apps

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
	@echo "    make chrome-cdp        Install Chrome CDP launchd agent (enables automated credentials)"
	@echo "    make chrome-cdp-stop   Uninstall Chrome CDP launchd agent"
	@echo "    make argocd-registration   Re-register ubuntu-k3s with ArgoCD (after sandbox recreation)"
	@echo "    make sync-apps             Sync ArgoCD data-layer and show remote pod status"
	@echo ""
	@echo "  Override sandbox URL (falls back to default if omitted):"
	@echo "    make up URL=https://app.pluralsight.com/hands-on/playground/cloud-sandboxes/..."
	@echo ""
	@echo "  Default URL: $(URL)"
	@echo ""
