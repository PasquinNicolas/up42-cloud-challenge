# External Secrets Operator Setup

This document details the steps to install and configure External Secrets Operator to integrate Kubernetes with external secret management systems like HashiCorp Vault.

## Prerequisites

- Kubernetes cluster running
- Helm installed
- kubectl configured to access the cluster
- HashiCorp Vault installed and configured

## Installation Process

### 1. Add External Secrets Helm Repository

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
```

### 2. Create Namespace for External Secrets

```bash
kubectl create namespace external-secrets
```

### 3. Install External Secrets Operator

```bash
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --set installCRDs=true
```

### 4. Verify Installation

```bash
kubectl get pods -n external-secrets
```

## Configuring External Secrets with Vault

### 1. Create ServiceAccount in Application Namespace

```bash
kubectl create namespace file-server --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: file-server
  namespace: file-server
EOF
```

### 2. Create SecretStore

Create a SecretStore resource to connect to Vault:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: file-server
spec:
  provider:
    vault:
      server: "http://vault.vault:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "file-server"
          serviceAccountRef:
            name: "file-server"
EOF
```

### 3. Create ExternalSecret

Create an ExternalSecret resource to fetch MinIO credentials from Vault:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: minio-credentials
  namespace: file-server
spec:
  refreshInterval: "15m"
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: file-server-minio-secret
    creationPolicy: Owner
  data:
  - secretKey: access-key
    remoteRef:
      key: file-server/minio
      property: access_key
  - secretKey: secret-key
    remoteRef:
      key: file-server/minio
      property: secret_key
EOF
```

### 4. Verify Secret Creation

Check if the Kubernetes Secret has been created:

```bash
kubectl get secret file-server-minio-secret -n file-server
```

## Troubleshooting

### Checking External Secrets Logs

If secrets aren't being created properly, check the External Secrets logs:

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Checking SecretStore Status

Check the status of the SecretStore resource:

```bash
kubectl get secretstore -n file-server
kubectl describe secretstore vault-backend -n file-server
```

### Checking ExternalSecret Status

Check the status of the ExternalSecret resource:

```bash
kubectl get externalsecret -n file-server
kubectl describe externalsecret minio-credentials -n file-server
```

## Updating Secrets

When you need to update secrets in Vault, those changes will automatically be synchronized to Kubernetes based on the `refreshInterval` specified in the ExternalSecret resource.
