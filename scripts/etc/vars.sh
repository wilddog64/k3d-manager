# Shared cross-plugin configuration — override via the environment.
#
# CF_DOMAIN is the public DNS suffix fronted by the Cloudflare tunnel. Every public hostname
# (argocd, frontend, keycloak, grafana, prometheus, alertmanager, webhook) is CF_DOMAIN-suffixed,
# and the monitoring manifests in scripts/etc/prometheus/rules/ are rendered against it.
export CF_DOMAIN="${CF_DOMAIN:-3ai-talk.org}"
