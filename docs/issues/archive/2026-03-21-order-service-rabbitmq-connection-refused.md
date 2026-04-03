# Issue: order-service RabbitMQ Connection Refused

**Date:** 2026-03-21
**Status:** OPEN
**Component:** `shopping-cart-order`

## Symptoms

`order-service` pod is in `CrashLoopBackOff`. Logs show:
```
Caused by: java.net.ConnectException: Connection refused
        at java.base/sun.nio.ch.Net.pollConnect(Native Method) ~[na:na]
        ...
        at com.rabbitmq.client.impl.SocketFrameHandlerFactory.create(SocketFrameHandlerFactory.java:61) ~[amqp-client-5.19.0.jar:5.19.0]
```

## Root Cause

The application is unable to establish a TCP connection to the RabbitMQ service (`rabbitmq.shopping-cart-data.svc.cluster.local:5672`). 
Note: 
- PostgreSQL authentication and schema issues have been resolved.
- `VAULT_ENABLED` and `SPRING_CLOUD_VAULT_ENABLED` were set to `false` to rule out Vault connectivity issues.
- Connectivity tests from other pods in the same namespace to RabbitMQ management port (15672) timed out.

## Mitigation

- Verified RabbitMQ service and pods are Running in `shopping-cart-data`.
- NetworkPolicies were updated to allow egress, but connection refusal persists.
- Further investigation into node-level networking or Istio sidecar proxy behavior is required.
