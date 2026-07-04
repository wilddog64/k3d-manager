#!/usr/bin/env bats

@test "services-git ApplicationSet ignores kustomize image overrides via jqPathExpressions" {
  run grep -nF 'jqPathExpressions' scripts/etc/argocd/applicationsets/services-git.yaml
  [ "$status" -eq 0 ]

  run grep -nF '.spec.source.kustomize.images' scripts/etc/argocd/applicationsets/services-git.yaml
  [ "$status" -eq 0 ]

  run grep -nF '/spec/source/kustomize/images' scripts/etc/argocd/applicationsets/services-git.yaml
  [ "$status" -ne 0 ]
}

@test "product-catalog kustomization declares an image override anchor" {
  run grep -nE '^images:' services/shopping-cart-product-catalog/kustomization.yaml
  [ "$status" -eq 0 ]

  run grep -nF 'ghcr.io/wilddog64/shopping-cart-product-catalog' services/shopping-cart-product-catalog/kustomization.yaml
  [ "$status" -eq 0 ]
}
