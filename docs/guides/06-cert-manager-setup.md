# cert-manager Setup

This document details the steps to install and configure cert-manager for certificate management in the Kubernetes cluster.

## Prerequisites

- Kubernetes cluster running
- Helm installed
- kubectl configured to access the cluster

## Installation Process

### 1. Add Jetstack Helm Repository

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

### 2. Install cert-manager

Install cert-manager with its Custom Resource Definitions (CRDs):

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

### 3. Verify Installation

Check that all cert-manager pods are running:

```bash
kubectl get pods -n cert-manager
```

## Configure Certificate Issuers

### 1. Create Self-Signed ClusterIssuer

For testing environments, create a self-signed ClusterIssuer:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
```

### 2. Create Let's Encrypt ClusterIssuer (for Production)

For production environments, create a Let's Encrypt ClusterIssuer:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: admin@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

## Generate TLS Certificates

### 1. Create Certificate for MinIO

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: minio-tls
  namespace: file-server
spec:
  secretName: minio-tls-secret
  duration: 8760h # 1 year
  renewBefore: 720h # 30 days
  subject:
    organizations:
      - UP42
  isCA: false
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  usages:
    - server auth
    - client auth
  dnsNames:
    - file-server-minio
    - file-server-minio.file-server
    - file-server-minio.file-server.svc
    - file-server-minio.file-server.svc.cluster.local
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
EOF
```

### 2. Create Certificate for s3www

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: s3www-tls
  namespace: file-server
spec:
  secretName: s3www-tls-secret
  duration: 8760h
  renewBefore: 720h
  subject:
    organizations:
      - UP42
  isCA: false
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  usages:
    - server auth
  dnsNames:
    - file-server-s3www
    - file-server-s3www.file-server
    - file-server-s3www.file-server.svc
    - file-server-s3www.file-server.svc.cluster.local
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
EOF
```

## Verify Certificate Creation

Check if certificates have been created properly:

```bash
kubectl get certificates -n file-server
kubectl describe certificate minio-tls -n file-server
kubectl describe certificate s3www-tls -n file-server
```

Check the status of the created TLS secrets:

```bash
kubectl get secrets -n file-server minio-tls-secret s3www-tls-secret
```

## Configure Services to Use TLS

Update your service configurations to use the generated TLS certificates. For example, in Helm values for MinIO:

```yaml
tls:
  enabled: true
  secretName: minio-tls-secret
```

For Ingress resources:

```yaml
tls:
  - hosts:
      - file-server-s3www.example.com
    secretName: s3www-tls-secret
```

## Troubleshooting

If certificates aren't being issued properly, check the cert-manager logs:

```bash
kubectl logs -n cert-manager -l app=cert-manager
```

Check the status of Certificate resources:

```bash
kubectl get challenges -n file-server
```
