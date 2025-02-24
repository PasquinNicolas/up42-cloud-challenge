### Deploy External Secrets Operator

The External Secrets Operator will fetch credentials from Vault and create Kubernetes secrets.

1. Install the External Secrets Operator:

```bash
# Add External Secrets Operator helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Create namespace for External Secrets
kubectl create namespace external-secrets

# Install External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --set installCRDs=true
```

2. Create a service account in the file-server namespace:

```bash
# Create the namespace if it doesn't exist
kubectl create namespace file-server --dry-run=client -o yaml | kubectl apply -f -

# Create a service account for the file-server application
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: file-server
  namespace: file-server
EOF
```

3. Configure the SecretStore to connect to Vault:

```bash
# Create a SecretStore that connects to Vault
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: file-server
spec:
  provider:
    vault:
      server: "http://vault.default:8200"
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

4. Create an ExternalSecret that fetches MinIO credentials:

```bash
# Create an ExternalSecret that fetches MinIO credentials
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

> [!NOTE]
> The ExternalSecret will create a Kubernetes Secret named `file-server-minio-secret` with `access-key` and `secret-key` data fields. Our Helm chart is configured to use this secret.

### Verify the Setup

To verify that the entire setup is working correctly:

1. Check that External Secrets has created the Kubernetes Secret:

```bash
kubectl get secret file-server-minio-secret -n file-server -o yaml
```

2. Deploy the application using Terraform:

```bash
cd terraform/environments/local
terraform apply
```

3. Verify the pods are running:

```bash
kubectl get pods -n file-server
```

4. Check that the MinIO bucket has been created and the document uploaded:

```bash
# Port forward the MinIO service
kubectl port-forward -n file-server svc/file-server-minio 9000:api

# In another terminal, configure the MinIO client (mc)
mc alias set myminio http://localhost:9000 minioadmin minioadmin

# List buckets
mc ls myminio/

# Check the contents of the up42-storage bucket
mc ls myminio/up42-storage/
```

5. Access the served document:

```bash
# Port forward the s3www service
kubectl port-forward -n file-server svc/file-server-s3www 8080:http

# In another terminal or browser, access the document
curl http://localhost:8080/document.gif -o test.gif
```

## Disaster Recovery

In case of a disaster, you can follow these steps to restore the system:

### Vault Recovery

If Vault needs to be restored:

1. Reinstall Vault:

```bash
helm install vault hashicorp/vault --values vault-values.yaml
```

2. Unseal Vault using the saved unseal keys:

```bash
# Use the saved unseal key
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)

# Unseal Vault
kubectl exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY
```

> [!DANGER]
> In a production environment, the unseal keys should be securely stored and never in plain text. Loss of all unseal keys means all data in Vault is permanently lost.

### Application Recovery

To recover the application components:

1. Reinstall the External Secrets Operator:

```bash
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --set installCRDs=true
```

2. Recreate the service account, SecretStore, and ExternalSecret resources.

3. Use Terraform to redeploy the application:

```bash
cd terraform/environments/local  # or production
terraform apply
```

## Maintenance Operations

### Rotating MinIO Credentials

To rotate the MinIO credentials:

1. Store new credentials in Vault:

```bash
# Generate new credentials
NEW_ACCESS_KEY=$(openssl rand -hex 8)
NEW_SECRET_KEY=$(openssl rand -hex 16)

# Store new credentials in Vault
kubectl exec -it vault-0 -- vault kv put secret/file-server/minio \
  access_key=$NEW_ACCESS_KEY \
  secret_key=$NEW_SECRET_KEY
```

2. The External Secrets Operator will automatically update the Kubernetes Secret. By default, it refreshes every 15 minutes, but you can trigger an immediate refresh:

```bash
kubectl delete secret file-server-minio-secret -n file-server
```

3. Restart the pods to pick up the new credentials:

```bash
kubectl rollout restart deployment -n file-server
```

### Upgrading Components

To upgrade the Helm charts or Terraform modules:

1. Update the chart version or configuration:

```bash
# Edit values.yaml with new configurations
nano charts/up42-file-server/values.yaml
```

2. Apply the changes using Terraform:

```bash
cd terraform/environments/local  # or production
terraform apply
```

## Production Considerations

For production deployments, consider these additional steps:

1. **Secure Communication**:
   - Enable TLS for all services
   - Configure mutual TLS (mTLS) between services
   - Use network policies to restrict traffic

2. **High Availability**:
   - Use multiple replicas for all components
   - Configure proper affinity/anti-affinity rules
   - Set up pod disruption budgets

3. **Monitoring and Alerting**:
   - Set up Prometheus for metrics collection
   - Configure Grafana dashboards
   - Set up alerts for critical conditions

4. **Backup and Recovery**:
   - Regular backups of Vault data
   - Regular backups of MinIO data
   - Test recovery procedures

5. **Security Hardening**:
   - Regularly rotate all credentials
   - Use Pod Security Policies
   - Run security scans on container images

## Conclusion

This documentation has guided you through the complete setup of a secure file serving infrastructure using MinIO and s3www on Kubernetes. The solution includes:

- A Helm chart for deploying both services
- Terraform code for infrastructure as code
- HashiCorp Vault integration for secure credentials management
- External Secrets Operator for Kubernetes integration
- Production-ready configurations for scaling and security

By following this guide, you have deployed a solution that meets all the requirements specified in the UP42 Cloud Engineering challenge.

## Troubleshooting

### Common Issues

#### MinIO Pod Not Starting

If the MinIO pod is stuck in Pending state:

```bash
# Check the pod status
kubectl describe pod -n file-server -l app=minio
```

Possible causes:
- PVC not binding (check storage class)
- Resource constraints (check node capacity)

#### Initialization Job Failing

If the init job fails:

```bash
# Check the job logs
kubectl logs -n file-server -l job-name=file-server-minio-init
```

Possible causes:
- MinIO not ready (increase wait time)
- Credentials issue (check secret exists and has correct keys)

#### External Secrets Not Working

If External Secrets is not creating the secret:

```bash
# Check the ExternalSecret status
kubectl get externalsecret -n file-server
kubectl describe externalsecret minio-credentials -n file-server
```

Possible causes:
- Vault connection issues
- Authentication problems
- Incorrect path or property names

#### Document Not Accessible

If the document is not accessible through s3www:

```bash
# Check if document exists in MinIO
kubectl port-forward -n file-server svc/file-server-minio 9000:api
mc ls myminio/up42-storage/

# Check s3www logs
kubectl logs -n file-server -l app=s3www
```

Possible causes:
- Document not uploaded to bucket
- s3www configuration issue
- Network connectivity problems# UP42 Cloud Engineering Challenge Documentation

## Overview

This documentation provides a comprehensive guide for deploying a secure file serving infrastructure on Kubernetes. The solution consists of MinIO (S3-compatible object storage) and s3www (a Go-based web server) to serve static files.

## Repository Structure

```
up42-cloud-challenge/
├── .github/
│   └── workflows/             # CI/CD workflow definitions
├── charts/
│   └── up42-file-server/      # Helm chart for both services
│       ├── Chart.yaml         # Chart metadata
│       ├── values.yaml        # Production values
│       ├── values-local.yaml  # Local development values
│       ├── templates/
│       │   ├── configmap.yaml # Init script and file data
│       │   ├── minio/
│       │   │   ├── deployment.yaml
│       │   │   ├── service.yaml
│       │   │   ├── pvc.yaml
│       │   │   └── init-job.yaml
│       │   ├── s3www/
│       │   │   ├── deployment.yaml
│       │   │   ├── service.yaml
│       │   │   └── ingress.yaml
│       │   └── servicemonitor.yaml
│       └── files/
│           └── document.gif   # The file to be served
├── terraform/
│   ├── environments/
│   │   ├── local/            # Local environment config
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── terraform.tfvars
│   │   │   └── providers.tf
│   │   └── production/       # Production environment config
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── terraform.tfvars
│   │       └── providers.tf
│   └── modules/
│       └── file-server/      # Reusable Terraform module
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
└── vault/                    # Vault configuration
    └── vault-values.yaml


## Step 1: Helm Chart Implementation

The Helm chart deploys both MinIO for S3-compatible storage and s3www for serving files stored in MinIO.

### Repository Structure

```
up42-cloud-challenge/
├── charts/
│   └── up42-file-server/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── templates/
│       │   ├── configmap.yaml
│       │   ├── minio/
│       │   │   ├── deployment.yaml
│       │   │   ├── service.yaml
│       │   │   ├── pvc.yaml
│       │   │   └── init-job.yaml
│       │   ├── s3www/
│       │   │   ├── deployment.yaml
│       │   │   ├── service.yaml
│       │   │   └── ingress.yaml
│       │   └── servicemonitor.yaml
│       └── files/
│           └── document.gif
```

### Setup the Repository Structure

1. Create the repository structure using the setup script:

```bash
#!/bin/bash

# Script: setup-repository.sh
# Description: Creates the directory structure for the UP42 cloud challenge project
# Usage: ./setup-repository.sh [target_directory]

set -euo pipefail

# Function to create directory and echo status
create_dir() {
    mkdir -p "$1"
    echo "Created directory: $1"
}

# Function to create file with initial content
create_file() {
    local file_path="$1"
    local content="$2"
    echo -e "$content" > "$file_path"
    echo "Created file: $file_path"
}

# Set target directory (use argument if provided, otherwise use current directory)
TARGET_DIR="${1:-up42-cloud-challenge}"

# Create main project directory
create_dir "$TARGET_DIR"
cd "$TARGET_DIR"

# Create directory structure
create_dir ".github/workflows"
create_dir "charts/up42-file-server/templates/minio"
create_dir "charts/up42-file-server/templates/s3www"
create_dir "charts/up42-file-server/files"
create_dir "terraform/environments/local"
create_dir "terraform/environments/production"
create_dir "terraform/modules"
create_dir "scripts/setup"
create_dir "docs/assets"
create_dir "docs/guides"

# Create essential files with basic content
create_file "README.md" "# UP42 Cloud Engineering Challenge\n\nThis repository contains the solution for the UP42 Cloud Engineering challenge.\n\n## Overview\n\nTBD\n\n## Prerequisites\n\nTBD\n\n## Installation\n\nTBD\n\n## Usage\n\nTBD"

create_file "CHALLENGE.md" "# Challenge Implementation Thoughts\n\n## Design Decisions\n\nTBD\n\n## Concerns and Considerations\n\nTBD\n\n## Future Improvements\n\nTBD"

create_file ".gitignore" "# Terraform
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl

# Helm
charts/*/charts
charts/*/Chart.lock

# IDE
.idea/
.vscode/

# OS
.DS_Store
Thumbs.db"

create_file "LICENSE" "Apache License, Version 2.0\nTBD - Full license text to be added"

# Create initial Helm chart files
create_file "charts/up42-file-server/Chart.yaml" "apiVersion: v2
name: up42-file-server
description: A Helm chart for deploying MinIO and s3www services for UP42
version: 0.1.0
type: application"

create_file "charts/up42-file-server/values.yaml" "# Default values for up42-file-server
# This is a YAML-formatted file.

global:
  environment: local  # Can be 'local' or 'production'

# Add other default values here"

create_file "charts/up42-file-server/templates/_helpers.tpl" "{{/*
Expand the name of the chart.
*/}}
{{- define \"up42-file-server.name\" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix \"-\" }}
{{- end }}"

# Create .helmignore file
create_file "charts/up42-file-server/.helmignore" "# Patterns to ignore when building packages.
.DS_Store
# Common VCS dirs
.git/
.gitignore
.bzr/
.bzrignore
.hg/
.hgignore
.svn/
# Common backup files
*.swp
*.bak
*.tmp
*.orig
*~
# Various IDEs
.project
.idea/
*.tmproj
.vscode/"

echo "Repository structure has been created successfully in: $TARGET_DIR"
```

2. Make the script executable and run it:

```bash
chmod +x setup-repository.sh
./setup-repository.sh
```

### Chart Configuration

1. Create the `values.yaml` file:

```yaml
# charts/up42-file-server/values.yaml
global:
  environment: production

minio:
  enabled: true
  persistence:
    enabled: true
    size: 50Gi
    storageClass: "standard"
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
  service:
    type: ClusterIP
  credentials:
    existingSecret: "file-server-minio-secret"
    accessKeyKey: "access-key"
    secretKeyKey: "secret-key"
  bucket:
    name: "up42-storage"
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      namespace: monitoring
      interval: 30s
      labels:
        release: prometheus

s3www:
  enabled: true
  replicaCount: 2
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "400m"
  service:
    type: LoadBalancer
    port: 8080
    annotations: {}
  ingress:
    enabled: false
    className: "nginx"
    annotations:
      kubernetes.io/ingress.class: nginx
    hosts:
      - host: file-server.example.com
        paths:
          - path: /
            pathType: Prefix
    tls: []
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      namespace: monitoring
      interval: 30s
      labels:
        release: prometheus

podDisruptionBudget:
  enabled: true
  minAvailable: 1

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - s3www
        topologyKey: "kubernetes.io/hostname"
```

2. Create a local values file for development:

```yaml
# charts/up42-file-server/values-local.yaml
minio:
  enabled: true
  persistence:
    enabled: true
    size: 1Gi
    storageClass: standard
  service:
    type: ClusterIP
  credentials:
    existingSecret: "file-server-minio-secret"
    accessKeyKey: "access-key"
    secretKeyKey: "secret-key"
  bucket:
    name: "up42-storage"

s3www:
  enabled: true
  service:
    type: NodePort
    port: 8080
```

3. Create the MinIO deployment template:

```yaml
# charts/up42-file-server/templates/minio/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-minio
  labels:
    app: minio
spec:
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
        - name: minio
          image: minio/minio:RELEASE.2024-02-14T21-19-51Z
          args:
            - server
            - /data
          env:
            - name: MINIO_ROOT_USER
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.minio.credentials.existingSecret }}
                  key: {{ .Values.minio.credentials.accessKeyKey }}
            - name: MINIO_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.minio.credentials.existingSecret }}
                  key: {{ .Values.minio.credentials.secretKeyKey }}
          ports:
            - containerPort: 9000
              name: api
            - containerPort: 9001
              name: console
          volumeMounts:
            - name: data
              mountPath: "/data"
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: {{ .Release.Name }}-minio-pvc
```

4. Create the MinIO PVC:

```yaml
# charts/up42-file-server/templates/minio/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Release.Name }}-minio-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {{ .Values.minio.persistence.size }}
  storageClassName: {{ .Values.minio.persistence.storageClass }}
```

5. Create the MinIO service:

```yaml
# charts/up42-file-server/templates/minio/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-minio
  labels:
    app: minio
spec:
  type: ClusterIP
  ports:
    - port: 9000
      targetPort: api
      protocol: TCP
      name: api
    - port: 9001
      targetPort: console
      protocol: TCP
      name: console
  selector:
    app: minio
```

6. Create the s3www deployment template:

```yaml
# charts/up42-file-server/templates/s3www/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-s3www
  labels:
    app: s3www
spec:
  replicas: {{ .Values.s3www.replicaCount }}
  selector:
    matchLabels:
      app: s3www
  template:
    metadata:
      labels:
        app: s3www
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
        - name: s3www
          image: y4m4/s3www:latest
          args:
            - -endpoint
            - "http://{{ .Release.Name }}-minio:9000"
            - -accessKey
            - "$(MINIO_ACCESS_KEY)"
            - -secretKey
            - "$(MINIO_SECRET_KEY)"
            - -bucket
            - "{{ .Values.minio.bucket.name }}"
          env:
            - name: MINIO_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.minio.credentials.existingSecret }}
                  key: {{ .Values.minio.credentials.accessKeyKey }}
            - name: MINIO_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.minio.credentials.existingSecret }}
                  key: {{ .Values.minio.credentials.secretKeyKey }}
          ports:
            - containerPort: 8080
              name: http
          resources:
            {{- toYaml .Values.s3www.resources | nindent 12 }}
```

7. Create the s3www service:

```yaml
# charts/up42-file-server/templates/s3www/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-s3www
spec:
  type: {{ .Values.s3www.service.type }}
  ports:
    - port: {{ .Values.s3www.service.port }}
      targetPort: http
      name: http
  selector:
    app: s3www
```

8. Create the ingress template:

```yaml
# charts/up42-file-server/templates/s3www/ingress.yaml
{{- if .Values.s3www.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}-s3www
  labels:
    app: s3www
  {{- with .Values.s3www.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  ingressClassName: {{ .Values.s3www.ingress.className }}
  rules:
    {{- range .Values.s3www.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ $.Release.Name }}-s3www
                port:
                  number: {{ $.Values.s3www.service.port }}
          {{- end }}
    {{- end }}
  {{- if .Values.s3www.ingress.tls }}
  tls:
    {{- range .Values.s3www.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
{{- end }}
```

9. Create the service monitor for Prometheus:

```yaml
# charts/up42-file-server/templates/servicemonitor.yaml
{{- if and .Values.s3www.metrics.enabled .Values.s3www.metrics.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ .Release.Name }}-s3www
  {{- if .Values.s3www.metrics.serviceMonitor.namespace }}
  namespace: {{ .Values.s3www.metrics.serviceMonitor.namespace }}
  {{- end }}
  labels:
    app: s3www
    {{- with .Values.s3www.metrics.serviceMonitor.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  endpoints:
    - port: http
      path: /metrics
      interval: {{ .Values.s3www.metrics.serviceMonitor.interval }}
  selector:
    matchLabels:
      app: s3www
  namespaceSelector:
    matchNames:
      - {{ .Release.Namespace }}
{{- end }}

{{- if and .Values.minio.metrics.enabled .Values.minio.metrics.serviceMonitor.enabled }}
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ .Release.Name }}-minio
  {{- if .Values.minio.metrics.serviceMonitor.namespace }}
  namespace: {{ .Values.minio.metrics.serviceMonitor.namespace }}
  {{- end }}
  labels:
    app: minio
    {{- with .Values.minio.metrics.serviceMonitor.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  endpoints:
    - port: api
      path: /minio/v2/metrics/cluster
      interval: {{ .Values.minio.metrics.serviceMonitor.interval }}
  selector:
    matchLabels:
      app: minio
  namespaceSelector:
    matchNames:
      - {{ .Release.Namespace }}
{{- end }}
```

10. Create the configmap for the initialization script:

```yaml
# charts/up42-file-server/templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-init
data:
  init.sh: |
    #!/bin/sh
    
    # Exit on any error
    set -e
    
    echo "Configuring MinIO client..."
    # Add retry mechanism for mc config
    for i in $(seq 1 5); do
      if mc config host add myminio http://{{ .Release.Name }}-minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} --quiet; then
        break
      fi
      echo "Failed to configure MinIO client, attempt $i/5"
      sleep 5
    done
    
    echo "Creating bucket..."
    # Create bucket with error handling
    if ! mc mb --ignore-existing myminio/{{ .Values.minio.bucket.name }}; then
      echo "Failed to create bucket, checking if it exists..."
      mc ls myminio/{{ .Values.minio.bucket.name }} || exit 1
    fi
    
    echo "Copying document.gif to bucket..."
    # Copy file with verification
    if ! mc cp /files/document.gif myminio/{{ .Values.minio.bucket.name }}/; then
      echo "Failed to copy document.gif"
      exit 1
    fi
    
    echo "Setting bucket policy..."
    # Set bucket policy with verification
    if ! mc policy set download myminio/{{ .Values.minio.bucket.name }}; then
      echo "Failed to set bucket policy"
      exit 1
    fi
    
    echo "Initialization completed successfully"

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-files
binaryData:
  document.gif: {{ .Files.Get "files/document.gif" | b64enc }}
```

11. Create the initialization job:

```yaml
# charts/up42-file-server/templates/minio/init-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-minio-init
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  backoffLimit: 10
  template:
    spec:
      initContainers:
        - name: wait-for-minio
          image: busybox
          command:
            - sh
            - -c
            - |
              echo "Waiting 50 seconds for MinIO to be ready..."
              sleep 50
              echo "Proceeding with initialization..."
      containers:
        - name: mc
          image: minio/mc:latest
          command:
            - sh
            - -c
            - |
              echo "Starting MinIO initialization..."
              
              echo "Configuring MinIO client..."
              mc config host add myminio http://{{ .Release.Name }}-minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} --quiet
              
              echo "Creating bucket..."
              mc mb --ignore-existing myminio/{{ .Values.minio.bucket.name }} || echo "Bucket might already exist"
              
              echo "Copying document.gif to bucket..."
              mc cp /files/document.gif myminio/{{ .Values.minio.bucket.name }}/
              
              echo "Setting bucket policy..."
              mc policy set download myminio/{{ .Values.minio.bucket.name }}
              
              echo "Verifying setup..."
              mc ls myminio/{{ .Values.minio.bucket.name }}/document.gif
              
              echo "Initialization completed successfully"
          env:
            - name: MINIO_ROOT_USER
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.minio.credentials.existingSecret }}
                  key: {{ .Values.minio.credentials.accessKeyKey }}
            - name: MINIO_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.minio.credentials.existingSecret }}
                  key: {{ .Values.minio.credentials.secretKeyKey }}
          volumeMounts:
            - name: document
              mountPath: /files
      volumes:
        - name: document
          configMap:
            name: {{ .Release.Name }}-files
      restartPolicy: OnFailure
```

12. Prepare the document.gif file:
   - Copy the document.gif file to the `charts/up42-file-server/files/` directory.

> [!NOTE]
> Make sure your document.gif file exists in the `charts/up42-file-server/files/` directory before deploying. The chart will base64 encode and embed this file in a ConfigMap.

## Step 2: Terraform Implementation

Terraform is used to deploy the Helm chart to the Kubernetes cluster in a reusable and maintainable way.

### 2.1 Terraform Module Structure

Set up the Terraform module structure:

1. Create the file-server module:

```terraform
# terraform/modules/file-server/variables.tf
variable "namespace" {
  description = "The namespace to deploy the file server into"
  type        = string
}

variable "helm_chart_path" {
  description = "Path to the Helm chart"
  type        = string
}

variable "release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "file-server"
}

variable "values_file" {
  description = "Path to the values file"
  type        = string
}

variable "create_namespace" {
  description = "Whether to create the namespace"
  type        = bool
  default     = true
}

variable "max_history" {
  description = "Maximum number of release versions stored per release"
  type        = number
  default     = 5
}

variable "timeout_seconds" {
  description = "Time in seconds to wait for any individual kubernetes operation"
  type        = number
  default     = 300
}

variable "linkerd_enabled" {
  description = "Whether to enable Linkerd injection"
  type        = bool
  default     = true
}
```

```terraform
# terraform/modules/file-server/main.tf
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

# Create ServiceAccount for External Secrets
resource "kubernetes_service_account_v1" "file_server" {
  metadata {
    name      = "file-server"
    namespace = var.namespace
  }

  depends_on = [
    kubernetes_namespace.this
  ]
}

# Create SecretStore
resource "kubernetes_manifest" "secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "SecretStore"
    metadata = {
      name      = "vault-backend"
      namespace = var.namespace
    }
    spec = {
      provider = {
        vault = {
          server  = "http://vault.default:8200"
          path    = "secret"
          version = "v2"
          auth = {
            kubernetes = {
              mountPath = "kubernetes"
              role      = "file-server"
              serviceAccountRef = {
                name = "file-server"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account_v1.file_server
  ]
}

# Create ExternalSecret
resource "kubernetes_manifest" "external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "minio-credentials"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "15m"
      secretStoreRef = {
        name = "vault-backend"
        kind = "SecretStore"
      }
      target = {
        name           = "file-server-minio-secret"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "access-key"
          remoteRef = {
            key      = "file-server/minio"
            property = "access_key"
          }
        },
        {
          secretKey = "secret-key"
          remoteRef = {
            key      = "file-server/minio"
            property = "secret_key"
          }
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.secret_store
  ]
}

# Enable Linkerd injection for the namespace
resource "null_resource" "namespace_linkerd_injection" {
  count = var.linkerd_enabled ? 1 : 0

  provisioner "local-exec" {
    command = "kubectl label namespace ${var.namespace} linkerd.io/inject=enabled --overwrite"
  }

  depends_on = [
    kubernetes_namespace.this
  ]
}

resource "helm_release" "file_server" {
  name       = var.release_name
  chart      = var.helm_chart_path
  namespace  = var.namespace
  max_history = var.max_history
  timeout    = var.timeout_seconds

  values = [
    file(var.values_file)
  ]

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_manifest.external_secret,
    null_resource.namespace_linkerd_injection
  ]
}
```

```terraform
# terraform/modules/file-server/outputs.tf
output "namespace" {
  description = "The namespace where the file server is deployed"
  value       = var.namespace
}

output "release_name" {
  description = "The name of the Helm release"
  value       = helm_release.file_server.name
}

output "release_status" {
  description = "Status of the release"
  value       = helm_release.file_server.status
}
```

2. Create the local environment configuration:

```terraform
# terraform/environments/local/providers.tf
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}
```

```terraform
# terraform/environments/local/variables.tf
variable "namespace" {
  description = "The namespace to deploy the file server into"
  type        = string
  default     = "file-server"
}

variable "helm_chart_path" {
  description = "Path to the Helm chart"
  type        = string
}

variable "values_file" {
  description = "Path to the values file"
  type        = string
}

variable "linkerd_enabled" {
  description = "Whether to enable Linkerd injection"
  type        = bool
  default     = true
}
```

```terraform
# terraform/environments/local/main.tf
module "file_server" {
  source = "../../modules/file-server"

  namespace       = var.namespace
  helm_chart_path = var.helm_chart_path
  values_file     = var.values_file
  create_namespace = true
  linkerd_enabled = var.linkerd_enabled
}
```

```terraform
# terraform/environments/local/terraform.tfvars
namespace = "file-server"
helm_chart_path = "../../charts/up42-file-server"
values_file = "../../charts/up42-file-server/values-local.yaml"
linkerd_enabled = true
```

3. Create the production environment configuration:

```terraform
# terraform/environments/production/providers.tf
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }

  # In production, you would typically use a remote backend
  # backend "s3" {
  #   bucket         = "terraform-state"
  #   key            = "file-server/prod/terraform.tfstate"
  #   region         = "eu-central-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-lock"
  # }
}

provider "kubernetes" {
  # In production, you would typically use cluster credentials
  # host                   = var.cluster_endpoint
  # cluster_ca_certificate = base64decode(var.cluster_ca_cert)
  # token                  = var.cluster_token
}

provider "helm" {
  kubernetes {
    # Same as kubernetes provider configuration
  }
}
```

```terraform
# terraform/environments/production/variables.tf
variable "namespace" {
  description = "The namespace to deploy the file server into"
  type        = string
  default     = "file-server"
}

variable "helm_chart_path" {
  description = "Path to the Helm chart"
  type        = string
}

variable "values_file" {
  description = "Path to the values file"
  type        = string
}

variable "linkerd_enabled" {
  description = "Whether to enable Linkerd injection"
  type        = bool
  default     = true
}

# Add any production-specific variables here
variable "cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  type        = string
}

variable "cluster_ca_cert" {
  description = "Kubernetes cluster CA certificate"
  type        = string
}

variable "cluster_token" {
  description = "Kubernetes cluster token"
  type        = string
}
```

```terraform
# terraform/environments/production/main.tf
module "file_server" {
  source = "../../modules/file-server"

  namespace       = var.namespace
  helm_chart_path = var.helm_chart_path
  values_file     = var.values_file
  create_namespace = true
  linkerd_enabled = var.linkerd_enabled
  
  # Add any production-specific configurations here
  timeout_seconds = 600
  max_history    = 10
}
```

```terraform
# terraform/environments/production/terraform.tfvars
namespace = "file-server"
helm_chart_path = "../../charts/up42-file-server"
values_file = "../../charts/up42-file-server/values.yaml"
linkerd_enabled = true
```

### 2.2 Deploy with Terraform

To deploy the solution using Terraform:

```bash
# Initialize Terraform
cd terraform/environments/local
terraform init

# Plan the deployment
terraform plan

# Apply the deployment
terraform apply
```

> [!IMPORTANT]
> For production deployments, you need to configure the Kubernetes provider with the appropriate authentication credentials for your production cluster.

## Step 3: Security Implementation with HashiCorp Vault

To enhance security, we'll use HashiCorp Vault to manage sensitive credentials and the External Secrets Operator to securely fetch them.

### 3.1 Deploy HashiCorp Vault

1. Create a values file for Vault:

```yaml
# vault/vault-values.yaml
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
```

2. Install Vault:

```bash
# Add HashiCorp helm repository
helm repo add hashicorp https://helm.releases.hashicorp.io
helm repo update

# Install Vault
helm install vault hashicorp/vault --values vault/vault-values.yaml
```

3. Initialize Vault:

```bash
# Initialize Vault
kubectl exec vault-0 -- vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > cluster-keys.json

# Get the unseal key
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)

# Unseal the first Vault instance
kubectl exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
```

4. Join and unseal the other Vault instances:

```bash
# Join the second Vault instance to the cluster
kubectl exec -ti vault-1 -- vault operator raft join http://vault-0.vault-internal:8200

# Join the third Vault instance to the cluster
kubectl exec -ti vault-2 -- vault operator raft join http://vault-0.vault-internal:8200

# Unseal the second Vault instance
kubectl exec -ti vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY

# Unseal the third Vault instance
kubectl exec -ti vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY
```

5. Configure Vault:

```bash
# Get the root token
export VAULT_TOKEN=$(jq -r ".root_token" cluster-keys.json)

# Log into the Vault instance
kubectl exec -it vault-0 -- /bin/sh

# Inside the Vault pod, set the token environment variable
export VAULT_TOKEN="<your-root-token>"  # Replace with your actual root token

# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Store MinIO credentials
vault kv put secret/file-server/minio access_key=minioadmin secret_key=minioadmin

# Enable Kubernetes authentication
vault auth enable kubernetes

# Configure Kubernetes authentication
vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local:443" \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_ca_cert="$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)" \
    issuer="https://kubernetes.default.svc.cluster.local"

# Create policy for file-server
vault policy write file-server - <<EOF
path "secret/data/file-server/minio" {
  capabilities = ["read"]
}
EOF

# Create Kubernetes auth role
vault write auth/kubernetes/role/file-server \
    bound_service_account_names=file-server \
    bound_service_account_namespaces=file-server \
    policies=file-server \
    ttl=1h

# Exit the Vault pod
exit
```

> [!WARNING]
> In a production environment, you should never store the unseal keys or root token in plain text files. Use a secure secret management system or hardware security modules (HSMs) to store these critical credentials.

### 3.2 Deploy External Secrets Operator

The External Secrets Operator will fetch credentials from Vault and create Kubernetes secrets.

1. Install the External Secrets Operator:

```bash
# Add External Secrets Operator helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Create namespace for External Secrets
kubectl create namespace external-secrets

# Install External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --set installCRDs=true
```

After installing External Secrets Operator, the resources defined in the Terraform configuration will:
1. Create a service account in the file-server namespace
2. Set up a SecretStore to connect to Vault
3. Configure an ExternalSecret to fetch the MinIO credentials

You don't need to manually create these resources as they are now managed by Terraform.

## Step 4: Service Mesh Implementation with Linkerd

To implement secure service-to-service communication, we'll use Linkerd service mesh.

### 4.1 Install Linkerd

1. Install the Linkerd CLI:

```bash
# Download and install the Linkerd CLI
curl -sL run.linkerd.io/install | sh

# Add the Linkerd CLI to your path
export PATH=$PATH:$HOME/.linkerd2/bin

# Check prerequisites
linkerd check --pre
```

2. Install Linkerd CRDs and core components:

```bash
# Install Linkerd CRDs
linkerd install --crds | kubectl apply -f -

# Install Linkerd with runAsRoot enabled for Docker environments
linkerd install --set proxyInit.runAsRoot=true | kubectl apply -f -

# Verify the installation
linkerd check
```

### 4.2 Update Helm Chart for Linkerd Integration

Modify your values.yaml and values-local.yaml files to include Linkerd configuration:

```yaml
# charts/up42-file-server/values.yaml (and values-local.yaml)
linkerd:
  enabled: true

# Rest of your configuration...
```

Update your deployment templates to include Linkerd annotations:

```yaml
# charts/up42-file-server/templates/minio/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-minio
  labels:
    app: minio
spec:
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
      annotations:
        {{- if .Values.linkerd.enabled }}
        linkerd.io/inject: "enabled"
        config.linkerd.io/proxy-enable-gateway: "false"
        {{- end }}
      # Rest of metadata...
    # Rest of spec...
```

```yaml
# charts/up42-file-server/templates/s3www/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-s3www
  labels:
    app: s3www
spec:
  replicas: {{ .Values.s3www.replicaCount }}
  selector:
    matchLabels:
      app: s3www
  template:
    metadata:
      labels:
        app: s3www
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        {{- if .Values.linkerd.enabled }}
        linkerd.io/inject: "enabled"
        config.linkerd.io/proxy-enable-gateway: "false"
        {{- end }}
      # Rest of metadata...
    # Rest of spec...
```

### 4.3 Verify Linkerd Installation

After deployment, verify that Linkerd is properly working:

```bash
# Check that all deployments are injected with Linkerd
kubectl get pods -n file-server

# Check the mTLS status
linkerd edges -n file-server

# View detailed stats in the Linkerd dashboard
linkerd viz dashboard
```

## Complete Deployment Process

Here's the complete step-by-step process to deploy the entire solution:

1. Setup the repository structure:
```bash
./setup-repository.sh
```

2. Copy document.gif to the chart directory:
```bash
cp document.gif charts/up42-file-server/files/
```

3. Install HashiCorp Vault:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.io
helm repo update
helm install vault hashicorp/vault --values vault/vault-values.yaml
```

4. Initialize and configure Vault:
```bash
# Initialize Vault and save keys
kubectl exec vault-0 -- vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > cluster-keys.json

# Extract keys and unseal Vault instances
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)
kubectl exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -ti vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -ti vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -ti vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -ti vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY

# Configure Vault (inside vault-0 pod)
export VAULT_TOKEN=$(jq -r ".root_token" cluster-keys.json)
kubectl exec -it vault-0 -- /bin/sh
# Run the Vault configuration commands from Section 3.1 step 5
```

5. Install External Secrets Operator:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
kubectl create namespace external-secrets
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --set installCRDs=true
```

6. Install Linkerd:
```bash
curl -sL run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin
linkerd check --pre
linkerd install --crds | kubectl apply -f -
linkerd install --set proxyInit.runAsRoot=true | kubectl apply -f -
linkerd check
```

7. Deploy with Terraform:
```bash
cd terraform/environments/local
terraform init
terraform apply
```

This completes the deployment of the entire solution with all security enhancements.

## Disaster Recovery
vault policy write file-server - <<EOF
path "secret/data/file-server/minio" {
  capabilities = ["read"]
}
EOF

# Create Kubernetes auth role
vault write auth/kubernetes/role/file-server \
    bound_service_account_names=file-server \
    bound_service_account_namespaces=file-server \
    policies=file-server \
    ttl=1h

# Exit the Vault pod
exit
```

> [!WARNING]
> In a production environment, you should never store the unseal keys or root token in plain text files. Use a secure secret management system or hardware security modules (HSMs) to store these critical credentials.
