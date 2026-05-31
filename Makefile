# Makefile — k3d-manager cluster lifecycle (provider-aware)
# Usage: make [target] [CLUSTER_PROVIDER=k3s-aws|k3s-gcp|k3s-oci] [URL=https://...]

.DEFAULT_GOAL := help

CLUSTER_PROVIDER ?= k3s-aws
URL ?= https://app.pluralsight.com/cloud-playground/cloud-sandboxes
GHCR_PAT ?=
KEEP_LOCAL ?= 0

.PHONY: up down refresh status creds chrome-cdp chrome-cdp-stop argocd-registration sync-apps ssm provision install-sudoers test help observability observability-acg observability-status vuln-scan

## Provision full stack (provider-aware: k3s-aws|k3s-gcp → bin/acg-up; k3s-oci → deploy_cluster)
up:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) mkdir -p "$(HOME)/.local/share/k3d-manager/logs" && \
	           CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager deploy_cluster --confirm 2>&1 | \
	           tee "$(HOME)/.local/share/k3d-manager/logs/k3s-oci-up.log" ;; \
	  *)       GHCR_PAT="$(GHCR_PAT)" bin/acg-up "$(URL)" ;; \
	esac
	@$(MAKE) --no-print-directory observability

## Tear down cluster (k3s-oci → destroy_cluster; others → bin/acg-down)
## Set KEEP_LOCAL=1 to preserve the local Hub cluster (k3s-aws/k3s-gcp only)
down:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager destroy_cluster ;; \
	  *)       bin/acg-down --confirm $(if $(filter 1,$(KEEP_LOCAL)),--keep-hub,) ;; \
	esac

## Refresh credentials and restart tunnel (k3s-aws/k3s-gcp only)
refresh:
	bin/acg-refresh "$(URL)"

## Show cluster nodes, pod status, tunnel health
status:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) CLUSTER_PROVIDER=k3s-oci KUBECONFIG=$(HOME)/.kube/k3s-oci.yaml \
	             kubectl get nodes,pods -A --no-headers 2>/dev/null \
	             || echo "OCI cluster unreachable" ;; \
	  k3s-gcp) APP_CONTEXT=ubuntu-gcp CLUSTER_PROVIDER=k3s-gcp bin/acg-status ;; \
	  *)       APP_CONTEXT=ubuntu-k3s CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) bin/acg-status ;; \
	esac

## Extract AWS credentials only (no cluster changes; k3s-aws only)
creds:
	scripts/k3d-manager acg_get_credentials "$(URL)"

## Install Chrome CDP launchd agent (enables credential automation without manual login)
chrome-cdp:
	scripts/k3d-manager acg_chrome_cdp_install

## Uninstall Chrome CDP launchd agent
chrome-cdp-stop:
	scripts/k3d-manager acg_chrome_cdp_uninstall

## Re-register ubuntu-k3s app cluster with ArgoCD (after sandbox recreation or IP change)
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
	APP_CONTEXT=$(if $(filter k3s-gcp,$(CLUSTER_PROVIDER)),ubuntu-gcp,ubuntu-k3s) bin/acg-sync-apps

## Ensure AWS Session Manager plugin is installed (required for SSM-based deployment)
ssm:
	@if command -v session-manager-plugin >/dev/null 2>&1; then \
	  echo "[make] session-manager-plugin already installed"; \
	elif command -v brew >/dev/null 2>&1; then \
	  brew install --cask session-manager-plugin; \
	else \
	  echo "[make] ERROR: cannot auto-install session-manager-plugin in this environment"; \
	  echo "[make] Install it manually from:"; \
	  echo "[make]   https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"; \
	  exit 1; \
	fi

## Provision ACG CloudFormation stack with SSM support (k3s-aws only)
provision: ssm
	K3S_AWS_SSM_ENABLED=true scripts/k3d-manager acg_provision --confirm

## Install passwordless sudo rules for k3d-manager macOS host operations (one-time setup)
install-sudoers:
	bin/install-sudoers.sh

## Deploy observability stack (Prometheus+Grafana+Trivy) to Hub k3d
observability:
	./scripts/k3d-manager deploy_observability

## Deploy observability stack (Prometheus+Trivy) to ACG ubuntu-k3s
observability-acg:
	./scripts/k3d-manager deploy_observability_acg

## Show pod status for monitoring/trivy-system on both clusters
observability-status:
	./scripts/k3d-manager observability_status

## Print VulnerabilityReport summary for both clusters
vuln-scan:
	./scripts/k3d-manager trivy_scan_report

## Run all BATS test suites
test:
	./scripts/k3d-manager test all

## Show this help
help:
	@echo ""
	@echo "  k3d-manager — cluster lifecycle"
	@echo ""
	@echo "  Targets (set CLUSTER_PROVIDER=k3s-aws|k3s-gcp|k3s-oci; default: k3s-aws):"
	@echo "    make up            Provision full stack"
	@echo "    make down          Tear down cluster (set KEEP_LOCAL=1 to preserve Hub on k3s-aws/gcp)"
	@echo "    make status        Show cluster nodes and pod status"
	@echo "    make test          Run all BATS test suites"
	@echo ""
	@echo "  k3s-aws / k3s-gcp only:"
	@echo "    make refresh       Refresh credentials and restart tunnel"
	@echo "    make creds         Extract AWS credentials only"
	@echo "    make chrome-cdp    Install Chrome CDP launchd agent (automated credentials)"
	@echo "    make chrome-cdp-stop   Uninstall Chrome CDP launchd agent"
	@echo "    make argocd-registration   Re-register ubuntu-k3s with ArgoCD"
	@echo "    make sync-apps             Sync ArgoCD data-layer and show pod status"
	@echo "    make ssm                   Ensure session-manager-plugin is installed"
	@echo "    make provision             Provision ACG stack via SSM (depends on ssm)"
	@echo "    make install-sudoers       Install passwordless sudo rules (one-time macOS setup)"
	@echo ""
	@echo "  Examples:"
	@echo "    make up                                          # k3s-aws (default)"
	@echo "    make up CLUSTER_PROVIDER=k3s-gcp"
	@echo "    make up CLUSTER_PROVIDER=k3s-oci"
	@echo "    make down CLUSTER_PROVIDER=k3s-oci"
	@echo "    make up URL=https://app.pluralsight.com/hands-on/playground/cloud-sandboxes/..."
	@echo ""
	@echo "  Default URL: $(URL)"
	@echo ""
