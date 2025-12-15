# Quick Start Guide

Deploy the complete CV-Site infrastructure in under 10 minutes.

## Prerequisites

1. **Kubernetes cluster** (K3s recommended)
2. **kubectl** configured
3. **helm** installed (v3+)

## One-Command Deployment

### Linux/macOS
```bash
./scripts/deploy.sh
```

### Windows
```cmd
scripts\deploy.bat
```

## Manual Deployment

### Step 1: Install cert-manager
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
```

### Step 2: Install Strimzi Operator
```bash
kubectl create namespace kafka-prd
kubectl apply -f "https://strimzi.io/install/latest?namespace=kafka-prd" -n kafka-prd
kubectl wait --for=condition=available --timeout=300s deployment/strimzi-cluster-operator -n kafka-prd
```

### Step 3: Install Argo CD
```bash
kubectl apply -f bootstrap/argocd-namespace.yaml
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
```

### Step 4: Get Argo CD Password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 5: Deploy App of Apps
```bash
kubectl apply -f bootstrap/app-of-apps.yaml
```

### Step 6: Access Argo CD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080

## What Gets Deployed

| Wave | Component | Description |
|------|-----------|-------------|
| 0 | Infrastructure | Namespaces, PVCs, Secrets |
| 1 | Kafka | Strimzi cluster (3 brokers, KRaft mode) |
| 2 | CV-Site | PostgreSQL, Backend services, Frontend |
| 3 | Monitoring | Prometheus, Grafana, AKHQ |
| 4 | Ingress | Traefik routes, Authelia SSO |

## Verify Deployment

```bash
# Check all applications
argocd app list

# Check pods
kubectl get pods -A | grep -E "(kafka|cv-site|monitoring|authelia)"

# Check services
kubectl get svc -A | grep -E "(kafka|cv-site|monitoring|authelia)"
```

## Access Services

| Service | URL | Auth |
|---------|-----|------|
| Frontend | https://cv.sebastien.sh | Public |
| API | https://api.sebastien.sh | Public |
| Grafana | https://grafana.sebastien.sh | Authelia 2FA |
| AKHQ | https://akhq.sebastien.sh | Authelia 2FA |
| Prometheus | https://prometheus.sebastien.sh | Authelia 2FA |
| Argo CD | https://argocd.sebastien.sh | Authelia 2FA |
| Auth Portal | https://auth.sebastien.sh | - |

## Troubleshooting

### Application not syncing
```bash
argocd app get <app-name> --show-operation
```

### Pods not starting
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Kafka issues
```bash
kubectl get kafka -n kafka-prd
kubectl get kafkatopics -n kafka-prd
```

## Next Steps

1. Configure DNS records for your domain
2. Update secrets in `environments/production/`
3. Configure GHCR authentication
4. Set up Authelia users and passwords
