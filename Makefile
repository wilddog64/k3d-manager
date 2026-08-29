# Makefile — k3d-manager cluster lifecycle (provider-aware)
# Usage: make [target] [CLUSTER_PROVIDER=k3s-aws|k3s-az|k3s-gcp|k3s-oci] [URL=https://...]

.DEFAULT_GOAL := help

CLUSTER_PROVIDER ?= k3s-aws
ACG_AGENT_COUNT  ?= 2
URL ?= https://app.pluralsight.com/cloud-playground/cloud-sandboxes
GHCR_PAT ?=
KEEP_LOCAL    ?= 0
CLEANUP_STALE ?= 0
BRANCH        ?= $(shell git rev-parse --abbrev-ref HEAD)
INFRA_CONTEXT ?= k3d-k3d-cluster
ARGOCD_NS     ?= cicd

.PHONY: up down refresh fleet-render fleet-validate fleet-plan fleet-up cleanup-stale-sandbox cleanup-stale-clusters cleanup-stale-resources status status-full status-json preflight creds chrome-cdp chrome-cdp-stop argocd-registration sync-apps sync-branch sync-main ssm provision install-sudoers setup-worker deploy-worker cloudflared-backup alertmanager-secret backup restore test e2e help observability platform-ops observability-acg observability-status monitoring-pause monitoring-resume vuln-scan trivy-scan-report show-service-passwords update-webhook-slack update-webhook-slack-roles update-webhook-slack-secret install-vault-port-forward uninstall-vault-port-forward install-prometheus-port-forward uninstall-prometheus-port-forward install-alertmanager-port-forward uninstall-alertmanager-port-forward install-node-health-watch uninstall-node-health-watch clean-tmp e2e-remote e2e-runner-health e2e-replay e2e-runner-unlock

## Provision full stack (provider-aware: k3s-aws|k3s-gcp → bin/cluster-up; k3s-oci → deploy_cluster)
up:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) mkdir -p "$(HOME)/.local/share/k3d-manager/logs" && \
	           CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager deploy_cluster --confirm 2>&1 | \
	           tee "$(HOME)/.local/share/k3d-manager/logs/k3s-oci-up.log" ;; \
	  k3s-hostinger) CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager deploy_cluster --confirm ;; \
	  *)       GHCR_PAT="$(GHCR_PAT)" K3DM_RESUME="$(K3DM_RESUME)" bin/cluster-up "$(URL)" ;; \
	esac
	@$(MAKE) --no-print-directory observability
	@$(MAKE) --no-print-directory platform-ops

## Tear down cluster (k3s-oci → destroy_cluster; others → bin/cluster-down)
## Set KEEP_LOCAL=1 to preserve the local Hub cluster (k3s-aws/k3s-gcp only)
down:
	@set +e; \
	_down_rc=0; \
	_keep_hub_flag=; \
	if [ "$(KEEP_LOCAL)" = "1" ] || [ "$(CLEANUP_STALE)" = "1" ]; then \
	  _keep_hub_flag=--keep-hub; \
	fi; \
	case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager destroy_cluster || _down_rc=$$? ;; \
	  k3s-hostinger) CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager destroy_cluster --confirm || _down_rc=$$? ;; \
	  *)       bin/cluster-down --confirm $$_keep_hub_flag || _down_rc=$$? ;; \
	esac; \
	if [ "$(CLEANUP_STALE)" = "1" ]; then \
	  $(MAKE) --no-print-directory cleanup-stale-resources CLUSTER_PROVIDER="$(CLUSTER_PROVIDER)" CONFIRM=1 || _cleanup_rc=$$?; \
	  if [ "$${_cleanup_rc:-0}" -ne 0 ]; then _down_rc=$${_cleanup_rc}; fi; \
	fi; \
	exit $$_down_rc

## Refresh credentials and restart tunnel (provider-aware)
refresh:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-hostinger) CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager refresh_cluster ;; \
	  *)       $(if $(filter command line environment,$(origin CLUSTER_PROVIDER)),CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) )bin/cluster-refresh "$(URL)" ;; \
	esac

## Render the count-driven ACG CloudFormation fleet (offline; k3s-aws only)
fleet-render:
	@if [ "$(CLUSTER_PROVIDER)" != "k3s-aws" ]; then echo "fleet-render skipped (CLUSTER_PROVIDER=$(CLUSTER_PROVIDER); k3s-aws-only)"; else ACG_AGENT_COUNT="$(ACG_AGENT_COUNT)" bash -c '\
	  set -euo pipefail; \
	  source scripts/lib/foundation/scripts/lib/acg/acg.sh; \
	  _acg_validate_agent_count; \
	  _rendered=$$(mktemp "$${TMPDIR:-/tmp}/k3d-manager-fleet.XXXXXX.yaml"); \
	  trap "rm -f -- \"$$_rendered\"" EXIT; \
	  _acg_render_template "$$_ACG_AGENT_COUNT" scripts/etc/acg-cluster.yaml "$$_rendered"; \
	  _instances=$$(grep -c "^  Agent[0-9][0-9]*Instance:" "$$_rendered"); \
	  _outputs=$$(grep -c "^  Agent[0-9][0-9]*PublicIP:" "$$_rendered"); \
	  [ "$$_instances" -eq "$(ACG_AGENT_COUNT)" ] && [ "$$_outputs" -eq "$(ACG_AGENT_COUNT)" ] || { echo "fleet-render count assertion failed" >&2; exit 1; }; \
	  cat "$$_rendered"'; fi

## Validate the rendered ACG CloudFormation fleet (live AWS validation; k3s-aws only)
fleet-validate:
	@if [ "$(CLUSTER_PROVIDER)" != "k3s-aws" ]; then echo "fleet-validate skipped (CLUSTER_PROVIDER=$(CLUSTER_PROVIDER); k3s-aws-only)"; exit 0; fi; \
	_rendered=$$(mktemp "$${TMPDIR:-/tmp}/k3d-manager-fleet.XXXXXX.yaml"); trap 'rm -f -- "$$_rendered"' EXIT; \
	ACG_AGENT_COUNT="$(ACG_AGENT_COUNT)" bash -c 'source scripts/lib/foundation/scripts/lib/acg/acg.sh && _acg_validate_agent_count && _acg_render_template "$$_ACG_AGENT_COUNT" scripts/etc/acg-cluster.yaml "$$1"' _ "$$_rendered"; \
	aws cloudformation validate-template --template-body "file://$$_rendered"

## Plan an ACG fleet CloudFormation change set without provisioning resources (live AWS; k3s-aws only)
fleet-plan: SHELL := /bin/bash
fleet-plan:
	@if [ "$(CLUSTER_PROVIDER)" != "k3s-aws" ]; then echo "fleet-plan skipped (CLUSTER_PROVIDER=$(CLUSTER_PROVIDER); k3s-aws-only)"; exit 0; fi; \
	set -euo pipefail; \
	source scripts/lib/foundation/scripts/lib/acg/acg.sh; \
	ACG_AGENT_COUNT="$(ACG_AGENT_COUNT)" _acg_validate_agent_count; \
	_region="$${ACG_REGION:-us-west-2}"; \
	_ami=$$(aws ec2 describe-images --region "$$_region" --owners "$$_ACG_AMI_OWNER" \
	  --filters "Name=name,Values=$$_ACG_AMI_FILTER" "Name=state,Values=available" \
	  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text); \
	_rendered=$$(mktemp "$${TMPDIR:-/tmp}/k3d-manager-fleet.XXXXXX.yaml"); \
	_plan_stack="k3d-manager-cluster-plan"; _cs="fleet-plan-$$(date +%s)"; \
	trap 'rm -f -- "$$_rendered"; aws cloudformation delete-stack --region "$$_region" --stack-name "$$_plan_stack" >/dev/null 2>&1 || true' EXIT; \
	_acg_render_template "$$_ACG_AGENT_COUNT" scripts/etc/acg-cluster.yaml "$$_rendered"; \
	aws cloudformation create-change-set --region "$$_region" --stack-name "$$_plan_stack" \
	  --change-set-name "$$_cs" --change-set-type CREATE --template-body "file://$$_rendered" \
	  --parameters ParameterKey=KeyName,ParameterValue="$$_ACG_KEY_NAME" \
	    ParameterKey=AllowedCidr,ParameterValue="$$ACG_ALLOWED_CIDR" \
	    ParameterKey=InstanceType,ParameterValue="$$_ACG_INSTANCE_TYPE" \
	    ParameterKey=AmiId,ParameterValue="$$_ami" \
	  --capabilities CAPABILITY_NAMED_IAM; \
	aws cloudformation wait change-set-create-complete --region "$$_region" \
	  --stack-name "$$_plan_stack" --change-set-name "$$_cs"; \
	aws cloudformation describe-change-set --region "$$_region" \
	  --stack-name "$$_plan_stack" --change-set-name "$$_cs" \
	  --query 'Changes[].ResourceChange.{Action:Action,Type:ResourceType,LogicalId:LogicalResourceId}' \
	  --output table

## Provision and join the count-driven ACG fleet (live node-join rung; k3s-aws only)
fleet-up:
	@if [ "$(CLUSTER_PROVIDER)" != "k3s-aws" ]; then echo "fleet-up skipped (CLUSTER_PROVIDER=$(CLUSTER_PROVIDER); k3s-aws-only)"; exit 0; fi
	@ACG_AGENT_COUNT="$(ACG_AGENT_COUNT)" CLUSTER_PROVIDER=k3s-aws scripts/k3d-manager deploy_cluster --confirm

## Remove stale state from an expired k3s-aws sandbox (dry-run unless CONFIRM=1)
cleanup-stale-sandbox:
	@CLUSTER_PROVIDER="$(CLUSTER_PROVIDER)" CONFIRM="$(CONFIRM)" bin/cleanup-stale-sandbox

## Remove expired, managed ephemeral ArgoCD cluster registrations (dry-run by default)
cleanup-stale-clusters:
	@ARGOCD_HUB_CONTEXT="$(INFRA_CONTEXT)" ARGOCD_NAMESPACE="$(ARGOCD_NS)" bin/cleanup-stale-clusters $(if $(filter 1 true yes,$(CONFIRM)),--confirm,--dry-run)

## Run both stale-resource cleanup paths (dry-run unless CONFIRM=1; sandbox path is k3s-aws-only)
cleanup-stale-resources:
	@$(MAKE) --no-print-directory cleanup-stale-clusters CONFIRM="$(CONFIRM)"
	@if [ "$(CLUSTER_PROVIDER)" = "k3s-aws" ]; then \
	  $(MAKE) --no-print-directory cleanup-stale-sandbox CLUSTER_PROVIDER=k3s-aws CONFIRM="$(if $(filter 1 true yes,$(CONFIRM)),1,0)"; \
	else \
	  echo "cleanup-stale-sandbox skipped (CLUSTER_PROVIDER=$(CLUSTER_PROVIDER); k3s-aws-only)"; \
	fi

## Restart the k3s-hostinger laptop edge only (cloudflared + port-forwards) — no GitOps reapply
refresh-edge:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-hostinger) CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager refresh_access_layer ;; \
	  *) echo "refresh-edge is k3s-hostinger-only (CLUSTER_PROVIDER=$(CLUSTER_PROVIDER))"; exit 1 ;; \
	esac

## Show cluster nodes, pods, endpoint + ESO health (provider-aware)
status:
	@_provider="$(CLUSTER_PROVIDER)"; if [ "$(origin CLUSTER_PROVIDER)" = file ]; then _provider=k3s-hostinger; if [ -r "$(HOME)/.local/share/k3d-manager/active-provider" ]; then _provider="$$(cat "$(HOME)/.local/share/k3d-manager/active-provider")"; fi; fi; case "$$_provider" in \
	  k3s-oci) CLUSTER_PROVIDER=k3s-oci KUBECONFIG=$(HOME)/.kube/k3s-oci.yaml \
	             kubectl get nodes,pods -A --no-headers 2>/dev/null \
	             || echo "OCI cluster unreachable" ;; \
	  *)       $(if $(filter command line environment,$(origin APP_CONTEXT)),APP_CONTEXT=$(APP_CONTEXT) )CLUSTER_PROVIDER="$$_provider" bin/cluster-status --summary $(if $(SERVICE),--service "$(SERVICE)",) ;; \
	esac

status-full:
	@$(if $(filter command line environment,$(origin APP_CONTEXT)),APP_CONTEXT=$(APP_CONTEXT) )$(if $(filter command line environment,$(origin CLUSTER_PROVIDER)),CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) )bin/cluster-status --full

status-json:
	@$(if $(filter command line environment,$(origin APP_CONTEXT)),APP_CONTEXT=$(APP_CONTEXT) )$(if $(filter command line environment,$(origin CLUSTER_PROVIDER)),CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) )bin/cluster-status --json $(if $(SERVICE),--service "$(SERVICE)",)

## Spin up a vCluster and deploy the full stack via ArgoCD (NAME=<name>; MODE=--auto|--keep, default --auto)
preflight:
	@bin/cluster-preflight "$(NAME)" "$(MODE)"

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
	@kubectl get secret argocd-manager-token -n kube-system --context ubuntu-k3s >/dev/null 2>&1 || { \
	  echo "[argocd-registration] argocd-manager SA/token missing — bootstrapping on ubuntu-k3s..."; \
	  kubectl apply --context ubuntu-k3s -f scripts/etc/argocd-manager.yaml && sleep 5; \
	}
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
	ARGOCD_APP_CLUSTER_PROVIDER="$(CLUSTER_PROVIDER)" \
	ARGOCD_APP_CLUSTER_MANAGED="$(if $(and $(ACG_SANDBOX_ID),$(ACG_SANDBOX_EXPIRES_AT)),true,false)" \
	ARGOCD_APP_CLUSTER_SANDBOX_ID="$(ACG_SANDBOX_ID)" \
	ARGOCD_APP_CLUSTER_EXPIRES_AT="$(ACG_SANDBOX_EXPIRES_AT)" \
	ARGOCD_APP_CLUSTER_RELEASE="$(BRANCH)" \
	  scripts/k3d-manager register_app_cluster && \
	kubectl rollout restart statefulset/argocd-application-controller \
	  -n cicd --context k3d-k3d-cluster && \
	kubectl rollout status statefulset/argocd-application-controller \
	  -n cicd --context k3d-k3d-cluster --timeout=90s

## Sync ArgoCD data-layer and show remote pod status
sync-apps:
	APP_CONTEXT=$(if $(filter k3s-gcp,$(CLUSTER_PROVIDER)),ubuntu-gcp,ubuntu-k3s) bin/cluster-sync-apps

## Point services-git ApplicationSet at BRANCH (default: current branch) and force-refresh apps
## Usage: make sync-branch            — uses current branch
##        make sync-branch BRANCH=k3d-manager-v1.4.12
sync-branch:
	@echo "[make] Patching services-git ApplicationSet → $(BRANCH)"
	@_b='$(BRANCH)'; \
	kubectl patch applicationset services-git -n $(ARGOCD_NS) --context $(INFRA_CONTEXT) \
	  --type=json -p \
	  "[{\"op\":\"replace\",\"path\":\"/spec/generators/0/git/revision\",\"value\":\"$$_b\"},{\"op\":\"replace\",\"path\":\"/spec/template/spec/source/targetRevision\",\"value\":\"$$_b\"}]"
	@for app in shopping-cart-basket shopping-cart-frontend shopping-cart-namespace shopping-cart-order shopping-cart-payment shopping-cart-product-catalog; do \
	  kubectl annotate application "$$app" -n $(ARGOCD_NS) --context $(INFRA_CONTEXT) \
	    argocd.argoproj.io/refresh=normal --overwrite 2>/dev/null || true; \
	done
	@echo "[make] Refresh triggered — run 'make status' in ~30s to verify pods"

## Revert services-git ApplicationSet back to main and force-refresh apps
sync-main:
	@echo "[make] Reverting services-git ApplicationSet → main"
	@kubectl patch applicationset services-git -n $(ARGOCD_NS) --context $(INFRA_CONTEXT) \
	  --type=json -p \
	  '[{"op":"replace","path":"/spec/generators/0/git/revision","value":"main"},{"op":"replace","path":"/spec/template/spec/source/targetRevision","value":"main"}]'
	@for app in shopping-cart-basket shopping-cart-frontend shopping-cart-namespace shopping-cart-order shopping-cart-payment shopping-cart-product-catalog; do \
	  kubectl annotate application "$$app" -n $(ARGOCD_NS) --context $(INFRA_CONTEXT) \
	    argocd.argoproj.io/refresh=normal --overwrite 2>/dev/null || true; \
	done
	@echo "[make] Refresh triggered — run 'make status' to confirm"

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

## Restart the k3dm-webhook LaunchAgent (picks up code changes)
restart-webhook:
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.webhook" 2>/dev/null || true
	launchctl bootstrap "gui/$$(id -u)" "$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook.plist"

## Remove k3d-manager-owned /tmp files
clean-tmp:
	rm -f /tmp/k3d-manager-sudoers.*
	rm -f /tmp/k3dm-gcp-creds.*
	rm -f /tmp/k3d-manager-tunnel.out /tmp/k3d-manager-tunnel.err
	rm -f /tmp/k3d-manager-acg-watch.out /tmp/k3d-manager-acg-watch.err
	rm -f /tmp/k3dm-acg-screenshot-*.png
	rm -f /tmp/k3s-etcd-*.db
	find /tmp -maxdepth 1 -name 'playwright-artifacts-*' -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "clean-tmp: done"

## Rotate webhook bearer token now (updates Keychain + Cloudflare Worker secret + restarts webhook)
rotate-webhook-token:
	bin/rotate-webhook-token

## Install the 6-hour token rotation LaunchAgent (run once; safe to re-run)
install-token-rotator:
	sed \
	  -e "s|{{K3DM_REPO_ROOT}}|$$(pwd)|g" \
	  -e "s|{{HOME}}|$(HOME)|g" \
	  scripts/etc/launchd/com.k3d-manager.webhook-token-rotate.plist.tmpl \
	  > "$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook-token-rotate.plist"
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.webhook-token-rotate" 2>/dev/null || true
	launchctl bootstrap "gui/$$(id -u)" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook-token-rotate.plist"
	@echo "Token rotator installed — fires every 6 hours"

## Install the daily state dir cleanup LaunchAgent (run once; safe to re-run)
install-cleanup:
	sed \
	  -e "s|{{K3DM_REPO_ROOT}}|$$(pwd)|g" \
	  -e "s|{{HOME}}|$(HOME)|g" \
	  scripts/etc/launchd/com.k3d-manager.cleanup.plist.tmpl \
	  > "$(HOME)/Library/LaunchAgents/com.k3d-manager.cleanup.plist"
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.cleanup" 2>/dev/null || true
	launchctl bootstrap "gui/$$(id -u)" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.cleanup.plist"
	@echo "Cleanup agent installed — fires daily at 03:00"

## Install the bounded k3d agent health/recovery watchdog (restarts after 3 failures)
install-node-health-watch:
	sed -e "s|{{REPO_ROOT}}|$$(pwd)|g" -e "s|{{HOME}}|$(HOME)|g" \
	  scripts/etc/launchd/com.k3d-manager.node-health-watch.plist.tmpl \
	  > "$(HOME)/Library/LaunchAgents/com.k3d-manager.node-health-watch.plist"
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.node-health-watch" 2>/dev/null || true
	launchctl bootstrap "gui/$$(id -u)" "$(HOME)/Library/LaunchAgents/com.k3d-manager.node-health-watch.plist"
	@echo "Node health watchdog installed — recovery is bounded to agent-0 with a 5-minute cooldown"

uninstall-node-health-watch:
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.node-health-watch" 2>/dev/null || true
	rm -f "$(HOME)/Library/LaunchAgents/com.k3d-manager.node-health-watch.plist"
	@echo "Node health watchdog removed"

## Install the Vault port-forward LaunchAgent — keeps kubectl port-forward vault-0 18200:8200 alive
install-vault-port-forward:
	sed \
	  -e "s|{{KUBECTL_PATH}}|$$(command -v kubectl)|g" \
	  -e "s|{{HOME}}|$(HOME)|g" \
	  scripts/etc/launchd/com.k3d-manager.vault-port-forward.plist.tmpl \
	  > "$(HOME)/Library/LaunchAgents/com.k3d-manager.vault-port-forward.plist"
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.vault-port-forward" 2>/dev/null || true
	launchctl bootstrap "gui/$$(id -u)" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.vault-port-forward.plist"
	@echo "Vault port-forward agent installed — port 18200 will stay open while k3d-cluster is running"

## Stop and remove the Vault port-forward LaunchAgent
uninstall-vault-port-forward:
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.vault-port-forward" 2>/dev/null || true
	rm -f "$(HOME)/Library/LaunchAgents/com.k3d-manager.vault-port-forward.plist"
	@echo "Vault port-forward agent removed"

install-prometheus-port-forward:
	sed \
	  -e "s|{{KUBECTL_PATH}}|$$(command -v kubectl)|g" \
	  -e "s|{{HOME}}|$(HOME)|g" \
	  scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl \
	  > "$(HOME)/Library/LaunchAgents/com.k3d-manager.prometheus-port-forward.plist"
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.prometheus-port-forward" 2>/dev/null || true
	launchctl bootstrap "gui/$$(id -u)" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.prometheus-port-forward.plist"
	@echo "Prometheus port-forward agent installed — port 19090 will stay open while ubuntu-k3s is reachable"

uninstall-prometheus-port-forward:
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.prometheus-port-forward" 2>/dev/null || true
	rm -f "$(HOME)/Library/LaunchAgents/com.k3d-manager.prometheus-port-forward.plist"
	@echo "Prometheus port-forward agent removed"

install-alertmanager-port-forward:
	sed \
	  -e "s|{{KUBECTL_PATH}}|$$(command -v kubectl)|g" \
	  -e "s|{{HOME}}|$(HOME)|g" \
	  scripts/etc/launchd/com.k3d-manager.alertmanager-port-forward.plist.tmpl \
	  > "$(HOME)/Library/LaunchAgents/com.k3d-manager.alertmanager-port-forward.plist"
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.alertmanager-port-forward" 2>/dev/null || true
	launchctl bootstrap "gui/$$(id -u)" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.alertmanager-port-forward.plist"
	@echo "Alertmanager port-forward agent installed — raw backend now stays open on port 19093"

uninstall-alertmanager-port-forward:
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.alertmanager-port-forward" 2>/dev/null || true
	rm -f "$(HOME)/Library/LaunchAgents/com.k3d-manager.alertmanager-port-forward.plist"
	@echo "Alertmanager port-forward agent removed"

install-alertmanager-auth-proxy:
	sed \
	  -e "s|{{PYTHON3_PATH}}|$$(command -v python3)|g" \
	  -e "s|{{ALERTMANAGER_PROXY_BIN}}|$(CURDIR)/bin/alertmanager-auth-proxy|g" \
	  -e "s|{{ALERTMANAGER_AUTH_FILE}}|$(HOME)/.local/share/k3d-manager/alertmanager-basic-auth.env|g" \
	  -e "s|{{HOME}}|$(HOME)|g" \
	  scripts/etc/launchd/com.k3d-manager.alertmanager-auth-proxy.plist.tmpl \
	  > "$(HOME)/Library/LaunchAgents/com.k3d-manager.alertmanager-auth-proxy.plist"
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.alertmanager-auth-proxy" 2>/dev/null || true
	launchctl bootstrap "gui/$$(id -u)" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.alertmanager-auth-proxy.plist"
	@echo "Alertmanager auth proxy installed — localhost:9093 now requires basic auth"

uninstall-alertmanager-auth-proxy:
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.alertmanager-auth-proxy" 2>/dev/null || true
	rm -f "$(HOME)/Library/LaunchAgents/com.k3d-manager.alertmanager-auth-proxy.plist"
	@echo "Alertmanager auth proxy removed"

## Inject SLACK_BOT_TOKEN and SLACK_CHANNEL_ID into the webhook LaunchAgent plist and restart
update-webhook-slack:
	@[ -n "$(SLACK_BOT_TOKEN)" ] || (echo "ERROR: SLACK_BOT_TOKEN not set — export it first"; exit 1)
	@[ -n "$(SLACK_CHANNEL_ID)" ] || (echo "ERROR: SLACK_CHANNEL_ID not set — export it first"; exit 1)
	/usr/libexec/PlistBuddy -c "Delete :EnvironmentVariables:SLACK_BOT_TOKEN" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook.plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:SLACK_BOT_TOKEN string $(SLACK_BOT_TOKEN)" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook.plist"
	/usr/libexec/PlistBuddy -c "Delete :EnvironmentVariables:SLACK_CHANNEL_ID" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook.plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:SLACK_CHANNEL_ID string $(SLACK_CHANNEL_ID)" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook.plist"
	$(MAKE) restart-webhook
	@echo "SLACK_BOT_TOKEN and SLACK_CHANNEL_ID injected — webhook restarted"

## Store the Slack user→role allowlist in Keychain and restart the webhook
## Example: make update-webhook-slack-roles K3DM_SLACK_ROLE_MAP=U123:admin,U456:operator
update-webhook-slack-roles:
	@[ -n "$(K3DM_SLACK_ROLE_MAP)" ] || (echo "ERROR: K3DM_SLACK_ROLE_MAP not set — use user_id:role[,user_id:role...]"; exit 1)
	@security add-generic-password -U -s k3dm-slack-role-map -a k3dm -w "$(K3DM_SLACK_ROLE_MAP)"
	$(MAKE) restart-webhook
	@echo "K3DM_SLACK_ROLE_MAP stored in Keychain — webhook restarted"

## Inject SLACK_SIGNING_SECRET from Keychain into the webhook LaunchAgent plist and restart
update-webhook-slack-secret:
	@_sig=$$(security find-generic-password -s k3dm-slack-signing-secret -a k3dm -w 2>/dev/null) || \
	  (echo "ERROR: k3dm-slack-signing-secret not in Keychain — run: security add-generic-password -s k3dm-slack-signing-secret -a k3dm -w <secret>"; exit 1); \
	/usr/libexec/PlistBuddy -c "Delete :EnvironmentVariables:SLACK_SIGNING_SECRET" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook.plist" 2>/dev/null || true; \
	/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:SLACK_SIGNING_SECRET string $$_sig" \
	  "$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook.plist"
	$(MAKE) restart-webhook
	@echo "SLACK_SIGNING_SECRET injected from Keychain — webhook restarted"

## Bootstrap Cloudflare Worker + webhook daemon (one-time per environment; safe to re-run)
setup-worker:
	bin/k3dm-webhook-setup
	bin/k3dm-worker-setup

## Re-deploy Cloudflare Worker and sync secrets from Keychain (run after Worker code changes)
deploy-worker:
	@_cf=$$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -w 2>/dev/null) && \
	_tok=$$(security find-generic-password -s k3dm-webhook-token -a k3dm -w 2>/dev/null) && \
	_sig=$$(security find-generic-password -s k3dm-slack-signing-secret -a k3dm -w 2>/dev/null) && \
	[ -n "$$_cf" ] || { echo "ERROR: k3dm-cloudflare-api-token missing from Keychain — run bin/k3dm-worker-setup"; exit 1; } && \
	[ -n "$$_tok" ] || { echo "ERROR: k3dm-webhook-token missing from Keychain — run bin/k3dm-webhook-setup"; exit 1; } && \
	[ -n "$$_sig" ] || { echo "ERROR: k3dm-slack-signing-secret missing from Keychain — run bin/k3dm-worker-setup"; exit 1; } && \
	cd workers/slack-relay && \
	printf '%s' "$$_tok" | CLOUDFLARE_API_TOKEN="$$_cf" npx --yes wrangler secret put WEBHOOK_TOKEN && \
	printf '%s' "$$_sig" | CLOUDFLARE_API_TOKEN="$$_cf" npx --yes wrangler secret put SLACK_SIGNING_SECRET && \
	CLOUDFLARE_API_TOKEN="$$_cf" npx --yes wrangler deploy && \
	_ts=$$(date +%s) && \
	_body='command=%2Fcluster-status&text=&response_url=https%3A%2F%2Fexample.com' && \
	_sig=$$(BODY="$$_body" SECRET="$$_sig" TS="$$_ts" python3 -c 'import hmac,hashlib,os; body=os.environ["BODY"]; secret=os.environ["SECRET"].encode(); ts=os.environ["TS"]; msg=f"v0:{ts}:{body}".encode(); print("v0="+hmac.new(secret, msg, hashlib.sha256).hexdigest())') && \
	_code=$$(curl -sS -o /dev/null -w '%{http_code}' \
	  -X POST 'https://k3dm-slack-relay.k3dm.workers.dev' \
	  -H "X-Slack-Request-Timestamp: $$_ts" \
	  -H "X-Slack-Signature: $$_sig" \
	  --data "$$_body" 2>/dev/null || true) && \
	[ "$$_code" = "200" ]

## Backup Cloudflare tunnel credentials to macOS Keychain + Vault (run after rotating credentials)
cloudflared-backup:
	@_tok=$$(kubectl get secret vault-root -n secrets --context k3d-k3d-cluster \
	  -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d); \
	_creds=$$(cat "$$HOME/.cloudflared/bb7ece59-8680-4310-9437-232f862e2773.json"); \
	_cert=$$(cat "$$HOME/.cloudflared/cert.pem"); \
	security add-generic-password -a cloudflared -s k3d-manager-cloudflared-credentials -w "$$_creds" -U && \
	security add-generic-password -a cloudflared -s k3d-manager-cloudflared-cert -w "$$_cert" -U && \
	echo "[cloudflared-backup] Keychain updated" && \
	curl -sf -X POST \
	  -H "X-Vault-Token: $$_tok" -H "Content-Type: application/json" \
	  "http://127.0.0.1:18200/v1/secret/data/k3d-manager/cloudflared" \
	  -d "$$(CREDS="$$_creds" CERT="$$_cert" python3 -c 'import json,os; print(json.dumps({"data":{"credentials_json":os.environ["CREDS"],"cert_pem":os.environ["CERT"],"tunnel_id":"bb7ece59-8680-4310-9437-232f862e2773","tunnel_name":"k3d-manager"}}))')" >/dev/null && \
	echo "[cloudflared-backup] Vault updated"

## Backup k3s etcd snapshot + kubeconfig to OCI object storage (k3s-oci only)
backup:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager oci_backup ;; \
	  *)       echo "[make] backup only supported for CLUSTER_PROVIDER=k3s-oci" ; exit 1 ;; \
	esac

## Restore k3s etcd snapshot + kubeconfig from OCI object storage (k3s-oci only)
restore:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager oci_restore ;; \
	  *)       echo "[make] restore only supported for CLUSTER_PROVIDER=k3s-oci" ; exit 1 ;; \
	esac

## Show all service login credentials (Hub k3d cluster must be running)
show-service-passwords:
	@echo ""
	@echo "  === Service Credentials ==="
	@echo ""
	@_vault_tok=$$(kubectl get secret vault-root -n secrets \
	  --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' 2>/dev/null | base64 --decode); \
	_vault_hdr=$$(mktemp); printf 'X-Vault-Token: %s\n' "$$_vault_tok" > "$$_vault_hdr"; \
	_argocd=$$(curl -sf -H "@$$_vault_hdr" \
	  "http://127.0.0.1:18200/v1/secret/data/argocd/admin" 2>/dev/null | \
	  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["data"].get("password","N/A"))' 2>/dev/null || true); \
	rm -f "$$_vault_hdr"; \
	echo "  ArgoCD      https://argocd.3ai-talk.org";\
	echo "    user:     admin";\
	echo "    password: $${_argocd:-N/A}";\
	echo ""
	@_vault_tok=$$(kubectl get secret vault-root -n secrets \
	  --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d); \
	_vault_hdr=$$(mktemp); printf 'X-Vault-Token: %s\n' "$$_vault_tok" > "$$_vault_hdr"; \
	_grafana=$$(curl -sf -H "@$$_vault_hdr" \
	  "http://127.0.0.1:18200/v1/secret/data/observability/grafana" 2>/dev/null | \
	  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["data"].get("password","N/A"))' 2>/dev/null || true); \
	rm -f "$$_vault_hdr"; \
	echo "  Grafana     https://grafana.3ai-talk.org";\
	echo "    user:     admin";\
	echo "    password: $${_grafana:-N/A}";\
	echo ""
	@_vault_tok=$$(kubectl get secret vault-root -n secrets \
	  --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d); \
	_vault_hdr=$$(mktemp); printf 'X-Vault-Token: %s\n' "$$_vault_tok" > "$$_vault_hdr"; \
	_prom_creds=$$(curl -sf \
	  -H "@$$_vault_hdr" \
	  "http://127.0.0.1:18200/v1/secret/data/k3d-manager/prometheus-basic-auth" 2>/dev/null \
	  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["data"]; print(d.get("user","admin")+"|"+d.get("password","N/A"))' 2>/dev/null || true); \
	rm -f "$$_vault_hdr"; \
	_prom_user=$${_prom_creds%%|*}; \
	_prom_pass=$${_prom_creds##*|}; \
	echo "  Prometheus  https://prometheus.3ai-talk.org";\
	echo "    user:     $${_prom_user:-admin}";\
	echo "    password: $${_prom_pass:-N/A}";\
	echo ""
	@_am_auth_file="$${HOME}/.local/share/k3d-manager/alertmanager-basic-auth.env"; \
	if [ -r "$$_am_auth_file" ]; then \
	  _am_user=$$(grep -E '^ALERTMANAGER_BASIC_AUTH_USER=' "$$_am_auth_file" | head -1 | cut -d= -f2-); \
	  _am_pass=$$(grep -E '^ALERTMANAGER_BASIC_AUTH_PASSWORD=' "$$_am_auth_file" | head -1 | cut -d= -f2-); \
	else \
	  _am_user="admin"; \
	  _am_pass="N/A"; \
	fi; \
	echo "  Alertmanager https://alertmanager.3ai-talk.org";\
	echo "    user:     $${_am_user:-admin}";\
	echo "    password: $${_am_pass:-N/A}";\
	echo ""
	@_kc=$$(kubectl get secret keycloak-secrets -n identity \
	  --context k3d-k3d-cluster -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' 2>/dev/null | base64 --decode); \
	_realm_admin=$$(./bin/get-keycloak-password admin -q 2>/dev/null || true); \
	_dev=$$(./bin/get-keycloak-password developer -q 2>/dev/null || true); \
	_op=$$(./bin/get-keycloak-password operator -q 2>/dev/null || true); \
	echo "  Frontend    https://frontend.3ai-talk.org  (login via Keycloak SSO)";\
	echo "  Keycloak    https://keycloak.3ai-talk.org";\
	echo "    admin user:     admin / $${_kc:-N/A}";\
	echo "    dev users:      admin / $${_realm_admin:-N/A}  |  developer / $${_dev:-N/A}  |  operator / $${_op:-N/A}";\
	echo ""

## Store Alertmanager credentials in Vault (run once; requires Hub Vault + port-forward)
alertmanager-secret:
	@_tok=$$(kubectl get secret vault-root -n secrets --context k3d-k3d-cluster \
	  -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d); \
	read -r -p "Gmail from address: " _gmail; \
	read -r -s -p "Gmail app password: " _pw; echo; \
	read -r -p "T-Mobile SMS gateway (10digits@tmomail.net): " _sms; \
	curl -sf -X POST \
	  -H "X-Vault-Token: $$_tok" -H "Content-Type: application/json" \
	  "http://127.0.0.1:18200/v1/secret/data/k3d-manager/alertmanager" \
	  -d "$$(GMAIL_FROM="$$_gmail" GMAIL_PW="$$_pw" SMS_GW="$$_sms" python3 -c 'import json,os; print(json.dumps({"data":{"gmail_from":os.environ["GMAIL_FROM"],"gmail_app_pw":os.environ["GMAIL_PW"],"sms_gateway":os.environ["SMS_GW"]}}))')" >/dev/null && \
	echo "[alertmanager-secret] Credentials stored in Vault"

## Deploy observability stack (Prometheus+Grafana+Trivy) to Hub k3d
observability:
	./scripts/k3d-manager deploy_observability --confirm

## Reconcile Hub platform-ops resources (CVE scanner, retry limits, and dashboards)
platform-ops:
	./scripts/k3d-manager deploy_argocd_platform_ops --confirm

## Deploy observability stack (Prometheus+Trivy) to ACG ubuntu-k3s
observability-acg:
	./scripts/k3d-manager deploy_observability_acg --confirm

## Show pod status for monitoring/trivy-system on both clusters
observability-status:
	./scripts/k3d-manager observability_status

## Scale the hub observability stack to zero to reclaim ~1.1 CPU cores
monitoring-pause:
	./scripts/k3d-manager observability_pause

## Restore the hub observability stack paused by monitoring-pause
monitoring-resume:
	./scripts/k3d-manager observability_resume

## Print VulnerabilityReport summary for both clusters
vuln-scan trivy-scan-report:
	./scripts/k3d-manager trivy_scan_report

## ── Agent Fix Targets ────────────────────────────────────────────────────────
## Callable by /ask agents in fix mode. Use 'make fix-list' to discover targets.
## All targets accept CONTEXT (default: ubuntu-k3s) and NS (namespace).

FIX_CONTEXT ?= ubuntu-k3s

fix-list: ## List all fix targets with descriptions
	@grep -E '^fix-[a-z].*:.*##' Makefile | sort | awk -F':.*##' '{printf "  make %-30s %s\n", $$1, $$2}'

## Rollout restart a deployment and wait for rollout (APP=<name> NS=<namespace>)
fix-restart: ## APP and NS are required
	@test -n "$(APP)" || { echo "Usage: make fix-restart APP=<deployment> NS=<namespace>"; exit 1; }
	@test -n "$(NS)"  || { echo "Usage: make fix-restart APP=<deployment> NS=<namespace>"; exit 1; }
	kubectl rollout restart 'deployment/$(APP)' -n '$(NS)' --context '$(FIX_CONTEXT)'
	kubectl rollout status  'deployment/$(APP)' -n '$(NS)' --context '$(FIX_CONTEXT)' --timeout=120s

## Delete all pods matching label app=<APP> (forces pod restart via ReplicaSet)
fix-delete-pod: ## APP and NS are required
	@test -n "$(APP)" || { echo "Usage: make fix-delete-pod APP=<label> NS=<namespace>"; exit 1; }
	@test -n "$(NS)"  || { echo "Usage: make fix-delete-pod APP=<label> NS=<namespace>"; exit 1; }
	kubectl delete pod -l 'app=$(APP)' -n '$(NS)' --context '$(FIX_CONTEXT)' --grace-period=0

## ArgoCD app sync with 120s timeout (APP=<argocd-app-name>)
fix-sync: ## APP is required
	@test -n "$(APP)" || { echo "Usage: make fix-sync APP=<argocd-app-name>"; exit 1; }
	argocd app sync '$(APP)' --timeout 120 --server localhost:8080 --insecure

## ArgoCD force sync — discards local state (APP=<argocd-app-name>)
fix-force-sync: ## APP is required
	@test -n "$(APP)" || { echo "Usage: make fix-force-sync APP=<argocd-app-name>"; exit 1; }
	argocd app sync '$(APP)' --force --timeout 180 --server localhost:8080 --insecure

## Force ESO ClusterSecretStore reconcile (annotates vault-backend to trigger re-sync)
fix-eso-refresh: ## No arguments needed
	kubectl annotate clustersecretstore vault-backend \
	  k3d-manager/reconcile-at="$$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite \
	  --context $(FIX_CONTEXT)

## Print node + pod status for a namespace (NS=<namespace>)
fix-status: ## NS is required
	@test -n "$(NS)" || { echo "Usage: make fix-status NS=<namespace>"; exit 1; }
	kubectl get nodes --context '$(FIX_CONTEXT)' --no-headers
	kubectl get pods -n '$(NS)' --context '$(FIX_CONTEXT)'

file-bug: ## FILE_TITLE and FILE_BODY required — write docs/bugs/<date>-<slug>.md
	@test -n "$(FILE_TITLE)" || { echo "Usage: make file-bug FILE_TITLE=<title> FILE_BODY=<body>"; exit 1; }
	@test -n "$(FILE_BODY)"  || { echo "Usage: make file-bug FILE_TITLE=<title> FILE_BODY=<body>"; exit 1; }
	@slug=$$(echo "$(FILE_TITLE)" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-'); \
	 existing=$$(ls docs/bugs/*-$$slug.md 2>/dev/null | head -1); \
	 if [ -n "$$existing" ]; then echo "already filed: $$existing"; exit 0; fi; \
	 fname="docs/bugs/$$(date +%Y-%m-%d)-$$slug.md"; \
	 printf '# Bug: %s\n\n**Filed:** %s\n**Source:** /ask agent observation\n\n## Description\n\n%s\n' \
	   "$(FILE_TITLE)" "$$(date +%Y-%m-%d)" "$(FILE_BODY)" > "$$fname"; \
	 echo "$$fname"

## Run all BATS test suites
test:
	./scripts/k3d-manager test all

## Run the Tier 1 e2e verification harness (throwaway vCluster + in-cluster Playwright Job). DIGEST=<candidate image digest> optional.
e2e:
	./scripts/k3d-manager e2e_verify_vcluster $(DIGEST)

## Run the Tier 1 e2e harness on a remote runner off the M4 laptop. RUNNER=m2 required, DIGEST=<image digest> optional. No local fallback.
e2e-remote:
	@if [ -z "$(RUNNER)" ]; then echo "usage: make e2e-remote RUNNER=m2 [DIGEST=sha256:...]" >&2; exit 2; fi
	./scripts/k3d-manager e2e_runner_dispatch $(RUNNER) $(DIGEST)

## Report hub health vs remote-runner availability as distinct states (RUNNER=m2 optional; unavailable runner is a warning).
e2e-runner-health:
	./scripts/k3d-manager e2e_runner_health $(RUNNER)

## Bounded, explicit replay of a remote runner's retained publication_pending E2E results. RUNNER=m2 required.
e2e-replay:
	@if [ -z "$(RUNNER)" ]; then echo "usage: make e2e-replay RUNNER=m2" >&2; exit 2; fi
	./scripts/k3d-manager e2e_runner_replay $(RUNNER)

## Clear a STALE remote-runner lock (bounded age + no-live-run checks; never automatic). RUNNER=m2 required.
e2e-runner-unlock:
	@if [ -z "$(RUNNER)" ]; then echo "usage: make e2e-runner-unlock RUNNER=m2" >&2; exit 2; fi
	./scripts/k3d-manager e2e_runner_unlock $(RUNNER)

## Show this help
help:
	@echo ""
	@echo "  k3d-manager — cluster lifecycle"
	@echo ""
	@echo "  Targets (set CLUSTER_PROVIDER=k3s-aws|k3s-gcp|k3s-oci; default: k3s-aws):"
	@echo "    make up            Provision full stack"
	@echo "    make down          Tear down cluster (set KEEP_LOCAL=1 to preserve Hub on k3s-aws/gcp)"
	@echo "    make down ... CLEANUP_STALE=1  Also remove expired managed registrations and stale AWS local state"
	@echo "    make status        Show concise service health (SERVICE=<name> for focused detail)"
	@echo "    make status-full   Show full pod and diagnostic report"
	@echo "    make status-json   Emit concise status as JSON"
	@echo "    make test          Run all BATS test suites"
	@echo "    make e2e           Run Tier 1 e2e harness (vCluster + Playwright Job; DIGEST=<image digest> optional)"
	@echo "    make e2e-remote    Run Tier 1 e2e harness on a remote runner off the M4 (RUNNER=m2 [DIGEST=<image digest>]; no local fallback)"
	@echo "    make e2e-runner-health  Report hub health vs remote-runner availability (RUNNER=m2 optional)"
	@echo "    make e2e-replay    Replay a runner's retained publication_pending E2E results (RUNNER=m2)"
	@echo "    make e2e-runner-unlock  Clear a STALE remote-runner lock, guarded by age + no-live-run (RUNNER=m2)"
	@echo "    make preflight     Spin up a throwaway vCluster + deploy the full stack via ArgoCD (NAME=<name> MODE=--auto|--keep|--reuse, default --auto)"
	@echo ""
	@echo "  k3s-aws / k3s-gcp only:"
	@echo "    make refresh       Refresh credentials and restart tunnel"
	@echo "    make creds         Extract AWS credentials only"
	@echo "    make chrome-cdp    Install Chrome CDP launchd agent (automated credentials)"
	@echo "    make chrome-cdp-stop   Uninstall Chrome CDP launchd agent"
	@echo "    make argocd-registration   Re-register ubuntu-k3s with ArgoCD (after sandbox recreation)"
	@echo "    make cleanup-stale-sandbox  Preview/remove stale AWS sandbox local state (CONFIRM=1 to remove)"
	@echo "    make cleanup-stale-clusters Preview/remove expired managed ArgoCD registrations (CONFIRM=1 to remove)"
	@echo "    make cleanup-stale-resources Run both cleanup paths (CONFIRM=1 to remove)"
	@echo "    make sync-apps             Sync ArgoCD data-layer and show remote pod status"
	@echo "    make sync-branch           Point services-git at BRANCH (default: current branch) and refresh"
	@echo "    make sync-main             Revert services-git to main and refresh"
	@echo "    make ssm                   Ensure session-manager-plugin is installed"
	@echo "    make provision             Provision ACG stack via SSM (depends on ssm)"
	@echo "    make fleet-render          Render count-driven ACG fleet (offline)"
	@echo "    make fleet-validate        Validate rendered ACG fleet with CloudFormation"
	@echo "    make fleet-plan            Create a no-execute ACG fleet change set"
	@echo "    make fleet-up              Provision/join the ACG fleet (node-join rung)"
	@echo "    make install-sudoers       Install passwordless sudo rules (one-time macOS setup)"
	@echo ""
	@echo "  Observability / credentials:"
	@echo "    make observability              Deploy Prometheus+Grafana+Trivy to Hub k3d"
	@echo "    make observability-acg          Deploy Prometheus+Trivy to ACG ubuntu-k3s"
	@echo "    make observability-status       Show monitoring pod status on both clusters"
	@echo "    make monitoring-pause           Scale hub monitoring to zero, keep Grafana up (~1 core back)"
	@echo "    make monitoring-resume          Restore hub monitoring after a pause"
	@echo "    make vuln-scan                  Print VulnerabilityReport summary"
	@echo "    make show-service-passwords     Show all service login credentials"
	@echo "    make alertmanager-secret        Store Alertmanager Gmail+SMS creds in Vault (run once)"
	@echo "    make install-alertmanager-auth-proxy   Install Alertmanager auth proxy LaunchAgent"
	@echo "    make install-alertmanager-port-forward   Install Alertmanager port-forward LaunchAgent"
	@echo "    make cloudflared-backup         Backup Cloudflare tunnel creds to Keychain+Vault"
	@echo ""
	@echo "  Examples:"
	@echo "    make up                                          # k3s-aws (default)"
	@echo "    make up CLUSTER_PROVIDER=k3s-gcp"
	@echo "    make up CLUSTER_PROVIDER=k3s-oci"
	@echo "    make down CLUSTER_PROVIDER=k3s-oci"
	@echo "    make down CLEANUP_STALE=1                 # teardown + guarded stale-resource cleanup"
	@echo "    make up URL=https://app.pluralsight.com/hands-on/playground/cloud-sandboxes/..."
	@echo "    make fleet-render ACG_AGENT_COUNT=4   # offline: render 4 agents / 5 nodes"
	@echo "    make fleet-up ACG_AGENT_COUNT=4       # live node-join rung (k3s-aws only)"
	@echo ""
	@echo "  Default URL: $(URL)"
	@echo ""
