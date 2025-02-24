# UP42 File Server Helm Chart Deployment

This document details the steps to deploy the UP42 File Server using Helm charts.

## Prerequisites

- Kubernetes cluster running
- Helm installed
- kubectl configured to access the cluster
- External Secrets Operator installed and configured
- Namespace created and configured

## Deployment Process

### 1. Prepare Namespace

Ensure the file-server namespace exists:

```bash
kubectl create namespace file-server --dry-run=client -o yaml | kubectl apply -f -
```

If using Linkerd, enable injection for the namespace:

```bash
kubectl label namespace file-server linkerd.io/inject=enabled
```
``

### 2. Deploy with Helm for Local Development

For local development, use the values-local.yaml file:

```bash
helm install file-server ./charts/up42-file-server \
  -f ./charts/up42-file-server/values-local.yaml \
  -n file-server
```

### 3. Deploy with Helm for Production

For production deployment, use the values.yaml file:

```bash
helm install file-server ./charts/up42-file-server \
  -f ./charts/up42-file-server/values.yaml \
  -n file-server
```

### 4. Verify Deployment

Check if all pods are running:

```bash
kubectl get pods -n file-server
```

Check if the MinIO initialization job completed successfully:

```bash
kubectl get jobs -n file-server
kubectl logs -n file-server -l job-name=file-server-minio-init
```

### 7. Access the Services

To access MinIO directly:

```bash
kubectl port-forward -n file-server svc/file-server-minio 9000:9000 9001:9001
```

To access s3www:

```bash
kubectl port-forward -n file-server svc/file-server-s3www 8080:8080
```

## Upgrading the Deployment

To upgrade the deployment after making changes:

```bash
helm upgrade file-server ./charts/up42-file-server \
  -f ./charts/up42-file-server/values.yaml \
  -n file-server
```

## Uninstalling the Deployment

To uninstall the deployment:

```bash
helm uninstall file-server -n file-server --ignore-not-found
kubectl delete namespace file-server
```

## Troubleshooting

### Check Logs of Specific Components

For MinIO logs:

```bash
kubectl logs -n file-server -l app=minio
```

For s3www logs:

```bash
kubectl logs -n file-server -l app=s3www
```

For init job logs:

```bash
kubectl logs -n file-server -l job-name=file-server-minio-init
```

### Debug with a Test Pod

To debug connectivity or access issues:

```bash
kubectl run -n file-server debug-pod --rm -i --tty --image=busybox -- /bin/sh

# From inside the pod, you can test connectivity:
wget -qO- http://file-server-s3www:8080/document.gif
wget -qO- http://file-server-minio:9000
```

### Check MinIO Bucket Configuration

To check if the MinIO bucket was created properly:

```bash
kubectl run -n file-server minio-debug --rm -i --image=minio/mc -- \
  /bin/sh -c "\
  mc config host add myminio http://file-server-minio:9000 minioadmin minioadmin && \
  echo 'Listing buckets:' && \
  mc ls myminio/"
```
