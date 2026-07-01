# Makefile — k3d-manager cluster lifecycle (provider-aware)
# Usage: make [target] [CLUSTER_PROVIDER=k3s-aws|k3s-az|k3s-gcp|k3s-oci] [URL=https://...]

.DEFAULT_GOAL := help

CLUSTER_PROVIDER ?= k3s-aws
URL ?= https://app.pluralsight.com/cloud-playground/cloud-sandboxes
GHCR_PAT ?=
KEEP_LOCAL    ?= 0
BRANCH        ?= $(shell git rev-parse --abbrev-ref HEAD)
INFRA_CONTEXT ?= k3d-k3d-cluster
ARGOCD_NS     ?= cicd

.PHONY: up down refresh status preflight creds chrome-cdp chrome-cdp-stop argocd-registration sync-apps sync-branch sync-main ssm provision install-sudoers setup-worker deploy-worker cloudflared-backup alertmanager-secret backup restore test help observability observability-acg observability-status vuln-scan trivy-scan-report show-service-passwords update-webhook-slack update-webhook-slack-secret install-vault-port-forward uninstall-vault-port-forward install-prometheus-port-forward uninstall-prometheus-port-forward install-alertmanager-port-forward uninstall-alertmanager-port-forward clean-tmp

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

## Tear down cluster (k3s-oci → destroy_cluster; others → bin/cluster-down)
## Set KEEP_LOCAL=1 to preserve the local Hub cluster (k3s-aws/k3s-gcp only)
down:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager destroy_cluster ;; \
	  k3s-hostinger) CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager destroy_cluster --confirm ;; \
	  *)       bin/cluster-down --confirm $(if $(filter 1,$(KEEP_LOCAL)),--keep-hub,) ;; \
	esac

## Refresh credentials and restart tunnel (provider-aware)
refresh:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-hostinger) CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager refresh_cluster ;; \
	  *)       $(if $(filter command line environment,$(origin CLUSTER_PROVIDER)),CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) )bin/cluster-refresh "$(URL)" ;; \
	esac

## Show cluster nodes, pods, endpoint + ESO health (provider-aware)
status:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) CLUSTER_PROVIDER=k3s-oci KUBECONFIG=$(HOME)/.kube/k3s-oci.yaml \
	             kubectl get nodes,pods -A --no-headers 2>/dev/null \
	             || echo "OCI cluster unreachable" ;; \
	  *)       $(if $(filter command line environment,$(origin APP_CONTEXT)),APP_CONTEXT=$(APP_CONTEXT) )$(if $(filter command line environment,$(origin CLUSTER_PROVIDER)),CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) )bin/cluster-status ;; \
	esac

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
	@echo "Alertmanager port-forward agent installed — port 9093 will stay open while k3d-cluster is reachable"

uninstall-alertmanager-port-forward:
	launchctl bootout "gui/$$(id -u)/com.k3d-manager.alertmanager-port-forward" 2>/dev/null || true
	rm -f "$(HOME)/Library/LaunchAgents/com.k3d-manager.alertmanager-port-forward.plist"
	@echo "Alertmanager port-forward agent removed"

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
	cd workers/slack-relay && \
	printf '%s' "$$_tok" | CLOUDFLARE_API_TOKEN="$$_cf" npx --yes wrangler secret put WEBHOOK_TOKEN && \
	printf '%s' "$$_sig" | CLOUDFLARE_API_TOKEN="$$_cf" npx --yes wrangler secret put SLACK_SIGNING_SECRET && \
	CLOUDFLARE_API_TOKEN="$$_cf" npx --yes wrangler deploy

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
	@_argocd=$$(kubectl get secret argocd-initial-admin-secret -n cicd \
	  --context k3d-k3d-cluster -o jsonpath='{.data.password}' 2>/dev/null | base64 -d); \
	echo "  ArgoCD      https://argocd.3ai-talk.org";\
	echo "    user:     admin";\
	echo "    password: $${_argocd:-N/A}";\
	echo ""
	@_grafana=$$(kubectl get secret kube-prometheus-stack-grafana -n monitoring \
	  --context k3d-k3d-cluster -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d); \
	echo "  Grafana     https://grafana.3ai-talk.org";\
	echo "    user:     admin";\
	echo "    password: $${_grafana:-N/A}";\
	echo ""
	@_vault_tok=$$(kubectl get secret vault-root -n secrets \
	  --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d); \
	_prom_creds=$$(curl -sf \
	  -H "X-Vault-Token: $$_vault_tok" \
	  "http://127.0.0.1:18200/v1/secret/data/k3d-manager/prometheus-basic-auth" 2>/dev/null \
	  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["data"]; print(d.get("user","admin")+"|"+d.get("password","N/A"))' 2>/dev/null || true); \
	_prom_user=$${_prom_creds%%|*}; \
	_prom_pass=$${_prom_creds##*|}; \
	echo "  Prometheus  https://prometheus.3ai-talk.org";\
	echo "    user:     $${_prom_user:-admin}";\
	echo "    password: $${_prom_pass:-N/A}";\
	echo ""
	@_kc=$$(kubectl get secret keycloak-secrets -n identity \
	  --context k3d-k3d-cluster -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' 2>/dev/null | base64 -d); \
	echo "  Frontend    https://frontend.3ai-talk.org  (login via Keycloak SSO)";\
	echo "  Keycloak    https://keycloak.3ai-talk.org";\
	echo "    admin user:     admin / $${_kc:-N/A}";\
	echo "    dev users:      alice / test1234  |  developer / test1234  |  operator / test1234";\
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

## Deploy observability stack (Prometheus+Trivy) to ACG ubuntu-k3s
observability-acg:
	./scripts/k3d-manager deploy_observability_acg --confirm

## Show pod status for monitoring/trivy-system on both clusters
observability-status:
	./scripts/k3d-manager observability_status

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
	@echo "    make preflight     Spin up a throwaway vCluster + deploy the full stack via ArgoCD (NAME=<name> MODE=--auto|--keep|--reuse, default --auto)"
	@echo ""
	@echo "  k3s-aws / k3s-gcp only:"
	@echo "    make refresh       Refresh credentials and restart tunnel"
	@echo "    make creds         Extract AWS credentials only"
	@echo "    make chrome-cdp    Install Chrome CDP launchd agent (automated credentials)"
	@echo "    make chrome-cdp-stop   Uninstall Chrome CDP launchd agent"
	@echo "    make argocd-registration   Re-register ubuntu-k3s with ArgoCD (after sandbox recreation)"
	@echo "    make sync-apps             Sync ArgoCD data-layer and show remote pod status"
	@echo "    make sync-branch           Point services-git at BRANCH (default: current branch) and refresh"
	@echo "    make sync-main             Revert services-git to main and refresh"
	@echo "    make ssm                   Ensure session-manager-plugin is installed"
	@echo "    make provision             Provision ACG stack via SSM (depends on ssm)"
	@echo "    make install-sudoers       Install passwordless sudo rules (one-time macOS setup)"
	@echo ""
	@echo "  Observability / credentials:"
	@echo "    make observability              Deploy Prometheus+Grafana+Trivy to Hub k3d"
	@echo "    make observability-acg          Deploy Prometheus+Trivy to ACG ubuntu-k3s"
	@echo "    make observability-status       Show monitoring pod status on both clusters"
	@echo "    make vuln-scan                  Print VulnerabilityReport summary"
	@echo "    make show-service-passwords     Show all service login credentials"
	@echo "    make alertmanager-secret        Store Alertmanager Gmail+SMS creds in Vault (run once)"
	@echo "    make install-alertmanager-port-forward   Install Alertmanager port-forward LaunchAgent"
	@echo "    make cloudflared-backup         Backup Cloudflare tunnel creds to Keychain+Vault"
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
