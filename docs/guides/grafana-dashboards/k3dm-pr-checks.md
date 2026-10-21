# k3dm PR Checks (`k3dm-pr-checks`) — hub

[← Grafana dashboards index](../grafana-dashboards.md)

Shows every open pull request's GitHub check-run state, overall verdict, and check duration for
the nine selected repos: k3d-manager, lib-foundation, shopping-cart-basket, shopping-cart-e2e-tests,
shopping-cart-frontend, shopping-cart-infra, shopping-cart-order, shopping-cart-payment, and
shopping-cart-product-catalog. Hermes publishes it every five minutes through Pushgateway job
`k3dm-pr-checks`, using one group per repo; the Repo filter is at the top. A Copilot review is not
a check. Merged or closed PRs disappear on the next good poll. With no open PRs the tables read
`No open PRs`; that is normal, and **Last scrape** and **GitHub read** are the panels that show whether
the collector is healthy. `GitHub read = failed` keeps the
last good rows and usually means the Hermes GitHub token expired or was rejected. **GitHub read** is
the minimum across the selected repos; use the Repo filter to find which one failed. A repo whose
reads have always failed is missing from the Repo filter, because the filter is built from
`k3dm_pr_checks_open_prs`. The Hermes GitHub token needs read access to every listed repo.
