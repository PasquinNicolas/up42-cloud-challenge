# UP42 Cloud Engineering Challenge Documentation

## Overview

This documentation provides a comprehensive guide for deploying a secure file serving infrastructure on Kubernetes. The solution consists of MinIO (S3-compatible object storage) and s3www (a Go-based web server) to serve static files.

## Requirements

### Infrastructure Components
- **s3www**: A Go-based web server that serves static files from S3-compatible storage
- **MinIO**: Local S3-compatible object storage solution
- **Static file**: A document (document.gif) to be served by the application

### Core Requirements
1. **Helm Chart Requirements**:
   - Chart for deploying both s3www and MinIO services
   - Automatic file loading into MinIO bucket during pod startup
   - Prometheus metrics discovery
   - Production-ready configurations
   - External access via LoadBalancer or Ingress
   - Reusable for production deployment

2. **Terraform Requirements**:
   - Deploy the Helm chart to Kubernetes
   - Production-ready configuration
   - Reusable code

3. **Documentation Requirements**:
   - Production-grade documentation
   - Implementation thoughts and concerns

### Technical Considerations
1. **Architecture**:
   - MinIO as S3-compatible backend
   - s3www as frontend web server
   - Secure communication between components
   - Prometheus monitoring

2. **Security**:
   - Secure communication between services
   - Proper credentials management
   - Production-ready security configurations

3. **Scalability**:
   - High availability
   - Resource management
   - Scaling capabilities

4. **Operational**:
   - Metrics collection and monitoring
   - Easy deployment and maintenance
   - Clear documentation

## Prerequisites

Before you begin, ensure you have the following tools installed:

- Kubernetes cluster (Minikube for local development)
- kubectl (v1.20+)
- Helm (v3.5+)
- Terraform (v1.0+)
- jq
- mc (Minio Clicent cli)

# Complete Installation Order and Integration Guide

This document outlines the proper installation order for all components needed to deploy the UP42 File Server infrastructure. Follow this sequence to ensure all dependencies are properly set up.

## Installation Sequence

### 1. Kubernetes Cluster Setup

Start with a Kubernetes cluster:

```bash
minikube start \
  --cpus 4 \
  --memory 8192 \
  --disk-size 80g \
  --driver docker \
  --addons metallb \
  --addons ingress \
  --addons metrics-server \
  --addons registry
```

Verify cluster is running:

```bash
kubectl get nodes
kubectl get pods -A
```

Configure MetalLB (if using minikube):

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.49.100-192.168.49.200
EOF
```

### 2. Linkerd Service Mesh

Install Linkerd service mesh for secure communication:

```bash
# Check compatibility
linkerd check --pre

# Install CRDs
linkerd install --crds | kubectl apply -f -

# Install control plane
linkerd install | kubectl apply -f -

# Install visualization components
linkerd viz install | kubectl apply -f -

# Verify installation
linkerd check
```

### 3. cert-manager

Install cert-manager for certificate management:

```bash
# Add Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

# Create a ClusterIssuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
```

### 4. Prometheus Stack

Install Prometheus for monitoring:

```bash
# Add Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace monitoring

# Install Prometheus stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

### 5. HashiCorp Vault

Install Vault for secret management:

```bash
# Add Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Create namespace
kubectl create namespace vault

# Create Vault values file
cat > vault-values.yaml << EOF
server:
   affinity: ""
   ha:
      enabled: true
      raft: 
         enabled: true
         setNodeId: true
         config: |
            cluster_name = "vault-integrated-storage"
            storage "raft" {
               path    = "/vault/data/"
            }

            listener "tcp" {
               address = "[::]:8200"
               cluster_address = "[::]:8201"
               tls_disable = "true"
            }
            service_registration "kubernetes" {}
EOF

# Install Vault
helm install vault hashicorp/vault --values vault-values.yaml -n vault

# Initialize Vault
kubectl exec vault-0 -n vault -- vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > cluster-keys.json

# Unseal Vault
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)
kubectl exec vault-0 -n vault -- vault operator unseal $VAULT_UNSEAL_KEY

# Configure Vault
export ROOT_TOKEN=$(jq -r ".root_token" cluster-keys.json)
kubectl port-forward svc/vault 8200:8200 -n vault &

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$ROOT_TOKEN
vault login $VAULT_TOKEN

# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Store MinIO credentials
vault kv put secret/file-server/minio \
    access_key=minioadmin \
    secret_key=minioadmin

# Enable Kubernetes authentication
vault auth enable kubernetes
vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    issuer="https://kubernetes.default.svc.cluster.local" \
    disable_iss_validation=true

# Create policy and role for file-server
vault policy write file-server - <<EOF
path "secret/data/file-server/*" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/file-server \
    bound_service_account_names=file-server \
    bound_service_account_namespaces=file-server \
    policies=file-server \
    ttl=1h
```

### 6. External Secrets Operator

Install External Secrets to integrate with Vault:

```bash
# Add Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Create namespace
kubectl create namespace external-secrets

# Install External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --set installCRDs=true
```

### 7. File Server Namespace and Service Account

Create the namespace and service account:

```bash
# Create namespace
kubectl create namespace file-server

# Enable Linkerd injection
kubectl label namespace file-server linkerd.io/inject=enabled

# Create service account
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: file-server
  namespace: file-server
EOF
```

### 8. SecretStore and ExternalSecret Configuration

Configure External Secrets to fetch from Vault:

```bash
# Create SecretStore
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

# Create ExternalSecret
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

### 9. Generate TLS Certificates (Optional)

Create TLS certificates for services:

```bash
# Certificate for MinIO
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

# Certificate for s3www
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

### 10. Deploy with Helm Charts (Manual Method)

Deploy using Helm charts directly:

```bash
# For local development
helm install file-server ./charts/up42-file-server \
  -f ./charts/up42-file-server/values-local.yaml \
  -n file-server

# Or for production
helm install file-server ./charts/up42-file-server \
  -f ./charts/up42-file-server/values.yaml \
  -n file-server
```

### 11. Deploy with Terraform (Automated Method)

Initialize and apply Terraform configuration:

```bash
# Set environment variables
export TF_STATE_NAME=live-up42-s3www-production
export GITLAB_ACCESS_TOKEN=your_gitlab_access_token

# Navigate to the appropriate directory
cd terraform/environments/production

# Initialize Terraform
terraform init \
    -backend-config="address=https://gitlab.example.com/api/v4/projects/14/terraform/state/$TF_STATE_NAME" \
    -backend-config="lock_address=https://gitlab.example.com/api/v4/projects/14/terraform/state/$TF_STATE_NAME/lock" \
    -backend-config="unlock_address=https://gitlab.example.com/api/v4/projects/14/terraform/state/$TF_STATE_NAME/lock" \
    -backend-config="username=username" \
    -backend-config="password=$GITLAB_ACCESS_TOKEN" \
    -backend-config="lock_method=POST" \
    -backend-config="unlock_method=DELETE" \
    -backend-config="retry_wait_min=5"

# Apply configuration
terraform apply --auto-approve
```

## Testing and Verification

### Verify Pods and Services

```bash
kubectl get pods -n file-server
kubectl get svc -n file-server
```

### Check MinIO Access

```bash
kubectl port-forward -n file-server svc/file-server-minio 9000:9000 9001:9001
```

Access MinIO at http://localhost:9000 with credentials from Vault or directly:

```bash
kubectl get secret --namespace file-server file-server-minio-secret -o jsonpath="{.data.access-key}" | base64 --decode
```

### Check s3www Access

```bash
kubectl port-forward -n file-server svc/file-server-s3www 8080:8080
```

Access s3www at http://localhost:8080/document.gif

### Verify Prometheus Metrics

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Access Prometheus at http://localhost:9090

## Integration Summary

1. **Kubernetes Cluster** - Base infrastructure
2. **Linkerd** - Service mesh for secure communication
3. **cert-manager** - Certificate management
4. **Prometheus** - Monitoring and metrics
5. **Vault** - Secret management
6. **External Secrets** - Connect Kubernetes with Vault
7. **UP42 File Server** - Application deployment (via Helm or Terraform)

The components integrate as follows:

- Linkerd provides secure mTLS communication between services
- cert-manager provides TLS certificates for secure endpoints
- Vault stores sensitive credentials
- External Secrets fetches credentials from Vault
- Prometheus monitors all components
- Helm/Terraform automates the deployment process

This integration provides a secure, observable, and automated deployment process for the UP42 File Server.
