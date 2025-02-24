# Prometheus Monitoring Setup

This document details the steps to install and configure Prometheus for monitoring in the Kubernetes cluster.

## Prerequisites

- Kubernetes cluster running
- Helm installed
- kubectl configured to access the cluster

## Installation Process

### 1. Add Prometheus Community Helm Repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### 2. Create Monitoring Namespace

```bash
kubectl create namespace monitoring
```

### 3. Install Prometheus Stack

Install the kube-prometheus-stack, which includes Prometheus, Alertmanager, Node Exporter, and Grafana:

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

The `serviceMonitorSelectorNilUsesHelmValues=false` option allows Prometheus to discover ServiceMonitor resources across all namespaces.

### 4. Verify Installation

Check that all Prometheus components are running:

```bash
kubectl get pods -n monitoring
```

## Accessing Prometheus UI

To access the Prometheus web interface:

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Then visit http://localhost:9090 in your browser.

## Configuring Service Monitoring

### Creating ServiceMonitor for MinIO

To monitor MinIO with Prometheus, create a ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: file-server-minio
  namespace: monitoring
  labels:
    release: prometheus
spec:
  endpoints:
    - port: api
      path: /minio/v2/metrics/cluster
      interval: 30s
  selector:
    matchLabels:
      app: minio
  namespaceSelector:
    matchNames:
      - file-server
```

### Creating ServiceMonitor for s3www

To monitor s3www with Prometheus, create a ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: file-server-s3www
  namespace: monitoring
  labels:
    release: prometheus
spec:
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
  selector:
    matchLabels:
      app: s3www
  namespaceSelector:
    matchNames:
      - file-server
```

### Creating ServiceMonitor for Linkerd-Injected Services

For services with Linkerd proxies, create a ServiceMonitor for the Linkerd metrics:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: file-server-s3www-linkerd
  namespace: monitoring
  labels:
    release: prometheus
spec:
  endpoints:
    - targetPort: linkerd-metrics
      path: /metrics
      interval: 30s
  selector:
    matchLabels:
      app: s3www
  namespaceSelector:
    matchNames:
      - file-server
```

## Verifying Service Monitors

To check if ServiceMonitor resources are properly configured:

```bash
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor file-server-minio -n monitoring
kubectl describe servicemonitor file-server-s3www -n monitoring
```

## Adding Grafana Dashboard (Optional)

If you need to install Grafana separately:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana -n grafana --create-namespace grafana/grafana
```

To access Grafana:

```bash
kubectl port-forward -n grafana service/grafana 3000:80
```

Get the admin password:

```bash
kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

Then visit http://localhost:3000 and login with username `admin` and the password from the previous command.
