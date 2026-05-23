# Plan: MinIO In-Cluster Object Store + Product Image Pipeline

**Date:** 2026-05-23
**Repos:**
- `shopping-cart-infra` — branch `docs/next-improvements-2` (MinIO data layer + image upload)
- `shopping-cart-frontend` — branch `docs/next-improvements` (nginx proxy for /minio/)

**Architecture doc:** `shopping-cart-infra/docs/minio-image-pipeline.md`

## Before You Start

1. `git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-infra pull origin docs/next-improvements-2`
2. `git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend pull origin docs/next-improvements`
3. Read `shopping-cart-infra/docs/minio-image-pipeline.md` in full — it defines the architecture
4. Read `shopping-cart-infra/data-layer/postgresql/products/statefulset.yaml` — follow this pattern for the MinIO StatefulSet
5. Read `shopping-cart-infra/data-layer/secrets/postgres-products-externalsecret.yaml` — follow this pattern for the ESO ExternalSecret
6. Confirm `shopping-cart-infra/argocd/applications/data-layer.yaml` has `directory.recurse: true` — no Application manifest update needed

## Task

Create MinIO as a data-layer service in `shopping-cart-infra`, following existing StatefulSet/ESO patterns exactly. Add nginx proxy in `shopping-cart-frontend` so image URLs are browser-portable.

---

## File 1: `data-layer/minio/secret.yaml` (new, shopping-cart-infra)

ESO ExternalSecret pulling MinIO credentials from Vault. Follow the postgres-products-externalsecret.yaml pattern exactly.

```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: minio-credentials
  namespace: shopping-cart-data
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  labels:
    app.kubernetes.io/name: external-secret
    app.kubernetes.io/instance: minio-credentials
    app.kubernetes.io/component: object-store-credentials
    app.kubernetes.io/part-of: shopping-cart
spec:
  refreshInterval: 24h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: minio-credentials
    creationPolicy: Owner
    template:
      type: Opaque
      metadata:
        labels:
          app.kubernetes.io/name: minio-credentials
          app.kubernetes.io/component: object-store-credentials
      data:
        MINIO_ROOT_USER: "{{ .root-user }}"
        MINIO_ROOT_PASSWORD: "{{ .root-password }}"
  data:
    - secretKey: root-user
      remoteRef:
        key: secret/data/minio/credentials
        property: root-user
    - secretKey: root-password
      remoteRef:
        key: secret/data/minio/credentials
        property: root-password
```

## File 2: `data-layer/minio/statefulset.yaml` (new, shopping-cart-infra)

Follow the postgresql-products statefulset.yaml pattern. MinIO runs as UID 1000.

```yaml
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: shopping-cart-data
  annotations:
    argocd.argoproj.io/sync-wave: "1"
  labels:
    app.kubernetes.io/name: minio
    app.kubernetes.io/instance: product-images
    app.kubernetes.io/component: object-store
    app.kubernetes.io/part-of: shopping-cart
spec:
  serviceName: minio
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: minio
      app.kubernetes.io/instance: product-images
  template:
    metadata:
      labels:
        app.kubernetes.io/name: minio
        app.kubernetes.io/instance: product-images
        app.kubernetes.io/component: object-store
        app.kubernetes.io/part-of: shopping-cart
    spec:
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
        runAsNonRoot: true
      containers:
        - name: minio
          image: quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z
          imagePullPolicy: IfNotPresent
          args:
            - server
            - /data
            - --console-address
            - ":9001"
          ports:
            - name: api
              containerPort: 9000
              protocol: TCP
            - name: console
              containerPort: 9001
              protocol: TCP
          envFrom:
            - secretRef:
                name: minio-credentials
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /minio/health/live
              port: api
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /minio/health/ready
              port: api
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          volumeMounts:
            - name: data
              mountPath: /data
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false
            capabilities:
              drop:
                - ALL
  volumeClaimTemplates:
    - metadata:
        name: data
        labels:
          app.kubernetes.io/name: minio
          app.kubernetes.io/instance: product-images
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
```

Note: `readOnlyRootFilesystem: false` — MinIO writes to `/data` and needs `/tmp`; PVC handles the data volume but MinIO also needs to write internal temp files to the root FS.

## File 3: `data-layer/minio/service.yaml` (new, shopping-cart-infra)

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: shopping-cart-data
  labels:
    app.kubernetes.io/name: minio
    app.kubernetes.io/instance: product-images
    app.kubernetes.io/component: object-store
    app.kubernetes.io/part-of: shopping-cart
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: minio
    app.kubernetes.io/instance: product-images
  ports:
    - name: api
      port: 9000
      targetPort: api
      protocol: TCP
    - name: console
      port: 9001
      targetPort: console
      protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: minio-nodeport
  namespace: shopping-cart-data
  labels:
    app.kubernetes.io/name: minio
    app.kubernetes.io/instance: product-images
    app.kubernetes.io/component: object-store
    app.kubernetes.io/part-of: shopping-cart
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: minio
    app.kubernetes.io/instance: product-images
  ports:
    - name: api
      port: 9000
      targetPort: api
      nodePort: 30900
      protocol: TCP
    - name: console
      port: 9001
      targetPort: console
      nodePort: 30901
      protocol: TCP
```

## File 4: `data-layer/minio/bucket-init-job.yaml` (new, shopping-cart-infra)

PostSync Job: creates the `product-images` bucket and sets anonymous read policy.

```yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-bucket-init
  namespace: shopping-cart-data
  labels:
    app.kubernetes.io/name: minio
    app.kubernetes.io/component: bucket-init
    app.kubernetes.io/part-of: shopping-cart
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 5
  template:
    metadata:
      labels:
        app.kubernetes.io/name: minio
        app.kubernetes.io/component: bucket-init
        app.kubernetes.io/part-of: shopping-cart
    spec:
      restartPolicy: OnFailure
      containers:
        - name: mc
          image: quay.io/minio/mc:RELEASE.2024-11-07T00-52-20Z
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
              until mc alias set local http://minio.shopping-cart-data.svc.cluster.local:9000 \
                "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"; do
                echo "Waiting for MinIO..."; sleep 5
              done
              mc mb --ignore-existing local/product-images
              mc anonymous set download local/product-images
              echo "Bucket product-images ready."
          envFrom:
            - secretRef:
                name: minio-credentials
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false
            capabilities:
              drop:
                - ALL
```

Note: `readOnlyRootFilesystem: false` — `mc` writes config to `~/.mc/` inside the container.

## File 5: `data-layer/minio/image-upload-job.yaml` (new, shopping-cart-infra)

PostSync Job: generates 20 category placeholder images using **Python + Pillow** and
uploads to `product-images` bucket.

**Why Pillow, not Picsum/external URLs:**
- Zero IP or ToS exposure — all images are generated in-cluster, not downloaded from
  any third-party service
- No external network dependency — works on air-gapped clusters
- Fully deterministic — same slug always produces the same image
- Each image is a clean 800×600 PNG with a category-appropriate background color and
  a centered white label

Category color palette (HSL-based, one hue per category group):

| Category | Color |
|----------|-------|
| Electronics | #1a73e8 (blue) |
| Peripherals | #188038 (green) |
| Monitors | #9334e6 (purple) |
| Accessories | #e37400 (amber) |

```yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-image-upload
  namespace: shopping-cart-data
  labels:
    app.kubernetes.io/name: minio
    app.kubernetes.io/component: image-upload
    app.kubernetes.io/part-of: shopping-cart
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 3
  template:
    metadata:
      labels:
        app.kubernetes.io/name: minio
        app.kubernetes.io/component: image-upload
        app.kubernetes.io/part-of: shopping-cart
    spec:
      restartPolicy: OnFailure
      initContainers:
        - name: install-mc
          image: alpine:3.19
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
              apk add --no-cache curl ca-certificates
              curl -sSL https://dl.min.io/client/mc/release/linux-amd64/mc \
                -o /shared/mc
              chmod +x /shared/mc
          volumeMounts:
            - name: shared
              mountPath: /shared
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
      containers:
        - name: uploader
          image: python:3.12-alpine
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
              pip install --quiet Pillow
              python3 /scripts/generate-and-upload.py
          env:
            - name: MC_BIN
              value: /shared/mc
            - name: MINIO_ENDPOINT
              value: http://minio.shopping-cart-data.svc.cluster.local:9000
            - name: MINIO_BUCKET
              value: product-images
          envFrom:
            - secretRef:
                name: minio-credentials
          volumeMounts:
            - name: shared
              mountPath: /shared
            - name: scripts
              mountPath: /scripts
            - name: tmp
              mountPath: /tmp
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false
            capabilities:
              drop: [ALL]
      volumes:
        - name: shared
          emptyDir: {}
        - name: tmp
          emptyDir: {}
        - name: scripts
          configMap:
            name: minio-image-upload-script
```

## File 5b: `data-layer/minio/image-upload-configmap.yaml` (new, shopping-cart-infra)

ConfigMap containing the Python image generation script.

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: minio-image-upload-script
  namespace: shopping-cart-data
  labels:
    app.kubernetes.io/name: minio
    app.kubernetes.io/component: image-upload
    app.kubernetes.io/part-of: shopping-cart
data:
  generate-and-upload.py: |
    #!/usr/bin/env python3
    """Generate product placeholder images and upload to MinIO.

    Images are generated in-cluster using Pillow — no external downloads,
    no IP or ToS exposure.
    """
    import os
    import subprocess
    import sys
    import tempfile
    from pathlib import Path

    from PIL import Image, ImageDraw, ImageFont

    IMAGES = [
        # (slug, label, bg_color)
        ("laptop",     "Laptop",           "#1a73e8"),
        ("phone",      "Smartphone",       "#1a73e8"),
        ("headphones", "Headphones",       "#1a73e8"),
        ("tablet",     "Tablet",           "#1a73e8"),
        ("speaker",    "Speaker",          "#1a73e8"),
        ("keyboard",   "Keyboard",         "#188038"),
        ("mouse",      "Mouse",            "#188038"),
        ("webcam",     "Webcam",           "#188038"),
        ("hub",        "USB Hub",          "#188038"),
        ("monitor-24", "Monitor 24\"",     "#9334e6"),
        ("monitor-27", "Monitor 27\"",     "#9334e6"),
        ("ultrawide",  "Ultrawide",        "#9334e6"),
        ("curved",     "Curved Monitor",   "#9334e6"),
        ("deskpad",    "Desk Mat",         "#e37400"),
        ("stand",      "Monitor Stand",    "#e37400"),
        ("bag",        "Laptop Bag",       "#e37400"),
        ("charger",    "GaN Charger",      "#e37400"),
        ("cable",      "USB-C Cable",      "#e37400"),
        ("light",      "Key Light",        "#e37400"),
        ("hub-desk",   "Desktop Hub",      "#e37400"),
    ]

    MC = os.environ["MC_BIN"]
    ENDPOINT = os.environ["MINIO_ENDPOINT"]
    BUCKET = os.environ["MINIO_BUCKET"]
    ROOT_USER = os.environ["MINIO_ROOT_USER"]
    ROOT_PASSWORD = os.environ["MINIO_ROOT_PASSWORD"]
    ALIAS = "local"
    WIDTH, HEIGHT = 800, 600


    def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
        h = hex_color.lstrip("#")
        return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


    def generate_image(slug: str, label: str, bg_color: str) -> Path:
        img = Image.new("RGB", (WIDTH, HEIGHT), hex_to_rgb(bg_color))
        draw = ImageDraw.Draw(img)

        # Lighter inner rectangle for visual depth
        inner_color = tuple(min(255, c + 40) for c in hex_to_rgb(bg_color))
        margin = 40
        draw.rectangle(
            [margin, margin, WIDTH - margin, HEIGHT - margin],
            fill=inner_color,
        )

        # Centered label — use default font (always available in alpine)
        font = ImageFont.load_default(size=48)
        bbox = draw.textbbox((0, 0), label, font=font)
        text_w = bbox[2] - bbox[0]
        text_h = bbox[3] - bbox[1]
        x = (WIDTH - text_w) // 2
        y = (HEIGHT - text_h) // 2
        draw.text((x, y), label, fill="white", font=font)

        # Subtle bottom tag
        tag_font = ImageFont.load_default(size=24)
        draw.text((margin + 10, HEIGHT - margin - 30), slug, fill="white", font=tag_font)

        path = Path(tempfile.gettempdir()) / f"{slug}.jpg"
        img.save(str(path), "JPEG", quality=85)
        return path


    def mc(*args: str) -> None:
        result = subprocess.run([MC, *args], capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            raise RuntimeError(f"mc {' '.join(args)} failed")
        print(result.stdout.strip())


    def wait_for_minio() -> None:
        import time
        for attempt in range(30):
            result = subprocess.run(
                [MC, "alias", "set", ALIAS, ENDPOINT, ROOT_USER, ROOT_PASSWORD],
                capture_output=True,
            )
            if result.returncode == 0:
                return
            print(f"Waiting for MinIO (attempt {attempt + 1}/30)...")
            time.sleep(5)
        raise RuntimeError("MinIO did not become ready in time")


    def image_exists(slug: str) -> bool:
        result = subprocess.run(
            [MC, "stat", f"{ALIAS}/{BUCKET}/{slug}.jpg"],
            capture_output=True,
        )
        return result.returncode == 0


    def main() -> None:
        wait_for_minio()
        for slug, label, bg_color in IMAGES:
            dest = f"{ALIAS}/{BUCKET}/{slug}.jpg"
            if image_exists(slug):
                print(f"Already exists: {slug}.jpg — skipping")
                continue
            print(f"Generating {slug}...")
            path = generate_image(slug, label, bg_color)
            mc("cp", str(path), dest)
            path.unlink()
            print(f"Uploaded {slug}.jpg")
        print("Image upload complete.")


    if __name__ == "__main__":
        main()
```

## File 6: frontend nginx proxy (shopping-cart-frontend)

Find the nginx ConfigMap or nginx.conf in the frontend k8s manifests. Add a `location /minio/` block that proxies to MinIO.

First read all files under `k8s/` in shopping-cart-frontend to find the nginx config location. Then add:

```nginx
location /minio/ {
    proxy_pass http://minio.shopping-cart-data.svc.cluster.local:9000/;
    proxy_set_header Host minio.shopping-cart-data.svc.cluster.local;
}
```

If no nginx ConfigMap exists and nginx config is baked into the image, add a ConfigMap + volumeMount to inject the proxy config. Follow existing patterns in the frontend k8s directory.

## Definition of Done

### shopping-cart-infra (branch: `docs/next-improvements-2`)
- [ ] `data-layer/minio/secret.yaml` created
- [ ] `data-layer/minio/statefulset.yaml` created
- [ ] `data-layer/minio/service.yaml` created (ClusterIP + NodePort)
- [ ] `data-layer/minio/bucket-init-job.yaml` created
- [ ] `data-layer/minio/image-upload-job.yaml` created
- [ ] `kubectl apply --dry-run=client -f data-layer/minio/` passes
- [ ] Committed with message: `feat(data-layer): add MinIO object store with product image pipeline`
- [ ] Pushed to `origin docs/next-improvements-2`

### shopping-cart-frontend (branch: `docs/next-improvements`)
- [ ] nginx config updated with `/minio/` proxy location
- [ ] `kubectl apply --dry-run=client -k k8s/base/` or equivalent passes
- [ ] Committed with message: `feat(nginx): proxy /minio/ to MinIO for product images`
- [ ] Pushed to `origin docs/next-improvements`

### Both
- [ ] Tag Copilot on PRs after creation
- [ ] Report commit SHAs for all repos

## What NOT to Do

- Do NOT commit to `main` — work on the specified branches per repo
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the listed targets
- Do NOT change the MinIO image tag — use `RELEASE.2024-11-07T00-52-20Z` exactly
- Do NOT use `latest` for any image tag
- Do NOT add `readOnlyRootFilesystem: true` to MinIO or mc containers — both need writable FS
- Do NOT hardcode MinIO credentials — all credentials come from the `minio-credentials` Secret
- Do NOT update the ArgoCD data-layer Application — `directory.recurse: true` picks up new files automatically
