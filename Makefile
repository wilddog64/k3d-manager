# Makefile — k3d-manager ACG cluster lifecycle shortcuts
# Usage: make [target] [URL=https://...]

.DEFAULT_GOAL := help

URL ?= https://app.pluralsight.com/cloud-playground/cloud-sandboxes
GHCR_PAT ?= $(shell gh auth token 2>/dev/null)
CLUSTER_PROVIDER ?= k3s-aws

.PHONY: up down refresh status creds chrome-cdp chrome-cdp-stop argocd-registration sync-apps ssm provision help

## Provision full stack: credentials → cluster → ESO → ArgoCD
up:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-aws) echo "[make] CLUSTER_PROVIDER=k3s-aws — running bin/acg-up..."; \
	           GHCR_PAT="$(GHCR_PAT)" bin/acg-up "$(URL)" ;; \
	  k3s-gcp) echo "[make] CLUSTER_PROVIDER=k3s-gcp — running deploy_cluster..."; \
	           CLUSTER_PROVIDER="$(CLUSTER_PROVIDER)" _GCP_SANDBOX_URL="$(URL)" scripts/k3d-manager deploy_cluster --confirm && \
	           echo "[make] CLUSTER_PROVIDER=k3s-gcp — running gcp_provision_stack..." && \
	           CLUSTER_PROVIDER="$(CLUSTER_PROVIDER)" GHCR_PAT="$(GHCR_PAT)" scripts/k3d-manager gcp_provision_stack ;; \
	  *)       echo "[make] CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) — running deploy_cluster..."; \
	           CLUSTER_PROVIDER="$(CLUSTER_PROVIDER)" _GCP_SANDBOX_URL="$(URL)" scripts/k3d-manager deploy_cluster --confirm ;; \
	esac

## Tear down cluster and stop all background processes
down:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-aws) bin/acg-down --confirm ;; \
	  *)       CLUSTER_PROVIDER="$(CLUSTER_PROVIDER)" scripts/k3d-manager destroy_cluster --confirm ;; \
	esac

## Refresh credentials and restart tunnel (use when creds expire)
refresh:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-aws) bin/acg-refresh "$(URL)" ;; \
	  *)       echo "[make] refresh not yet implemented for CLUSTER_PROVIDER=$(CLUSTER_PROVIDER)"; exit 1 ;; \
	esac

## Show cluster nodes, pod status, tunnel health
status:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-aws) bin/acg-status ;; \
	  *)       CLUSTER_PROVIDER="$(CLUSTER_PROVIDER)" scripts/k3d-manager status ;; \
	esac

## Extract cloud credentials only (no cluster changes)
creds:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-aws) scripts/k3d-manager acg_get_credentials "$(URL)" ;; \
	  k3s-gcp) scripts/k3d-manager gcp_get_credentials "$(URL)" ;; \
	  *)       echo "[make] creds not yet implemented for CLUSTER_PROVIDER=$(CLUSTER_PROVIDER)"; exit 1 ;; \
	esac

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
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-gcp) echo "[make] CLUSTER_PROVIDER=k3s-gcp — sync-apps is a no-op (stack deployed by make up)" ;; \
	  *)       bin/acg-sync-apps ;; \
	esac

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

## Provision full plugin stack (Vault + ESO + ArgoCD + apps)
provision:
	@case "$(CLUSTER_PROVIDER)" in \
	  *)       $(MAKE) --no-print-directory ssm; \
	           echo "[make] CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) — running acg_provision..."; \
	           K3S_AWS_SSM_ENABLED=true scripts/k3d-manager acg_provision --confirm ;; \
	esac

## Show this help
help:
	@echo ""
	@echo "  k3d-manager — ACG cluster lifecycle"
	@echo ""
	@echo "  Targets:"
	@echo "    make up        Provision cluster (AWS) or cluster + stack (GCP)"
	@echo "    make down      Tear down cluster and stop all background processes"
	@echo "    make refresh   Refresh AWS credentials and restart tunnel"
	@echo "    make status    Show cluster nodes, pod status, tunnel health"
	@echo "    make creds     Extract AWS credentials only"
	@echo "    make chrome-cdp        Install Chrome CDP launchd agent (enables automated credentials)"
	@echo "    make chrome-cdp-stop   Uninstall Chrome CDP launchd agent"
	@echo "    make argocd-registration   Re-register ubuntu-k3s with ArgoCD (after sandbox recreation)"
	@echo "    make sync-apps             Sync ArgoCD data-layer and show remote pod status"
	@echo "    make ssm                   Ensure session-manager-plugin is installed"
	@echo "    make provision             Provision ACG stack via SSM (AWS only)"
	@echo ""
	@echo "  Override sandbox URL (falls back to default if omitted):"
	@echo "    make up URL=https://app.pluralsight.com/hands-on/playground/cloud-sandboxes/..."
	@echo ""
	@echo "  Override cloud provider (default: k3s-aws):"
	@echo "    make up CLUSTER_PROVIDER=k3s-gcp"
	@echo "    make up CLUSTER_PROVIDER=k3d"
	@echo ""
	@echo "  GCP workflow (same commands as AWS):"
	@echo "    make up CLUSTER_PROVIDER=k3s-gcp GHCR_PAT=<pat>          Provision cluster + full stack"
	@echo "    make sync-apps CLUSTER_PROVIDER=k3s-gcp                   No-op (stack deployed by make up)"
	@echo ""
	@echo "  Current CLUSTER_PROVIDER: $(CLUSTER_PROVIDER)"
	@echo ""
	@echo "  Default URL: $(URL)"
	@echo ""
