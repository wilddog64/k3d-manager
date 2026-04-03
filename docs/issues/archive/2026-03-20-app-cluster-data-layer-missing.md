# Issue: Microservices CrashLoopBackOff due to Missing Data Layer

**Date:** 2026-03-20
**Status:** OPEN
**Component:** `order-service`, `product-catalog`

## Symptoms

Pods are in `CrashLoopBackOff`. Logs show:
```
Caused by: java.net.UnknownHostException: postgresql-orders.shopping-cart-data.svc.cluster.local
```

## Root Cause

The app cluster (Ubuntu k3s) was rebuilt from scratch, and while the application services were synced via ArgoCD, the underlying data layer (PostgreSQL databases) has not yet been deployed to the new cluster.

## Mitigation

Deploy the required PostgreSQL instances to the `shopping-cart-data` namespace on the app cluster.
