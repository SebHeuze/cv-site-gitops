# CV-Site GitOps Repository

Complete Kubernetes infrastructure using GitOps with **Flux CD**, **Traefik**, **Authelia**, and **HashiCorp Vault**.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Flux CD (GitOps)                                 │
│                                                                               │
│  ┌────────────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │ Infrastructure │  │Databases │  │   Apps   │  │Monitoring│  │  Vault   │ │
│  │  Controllers   │  │          │  │          │  │          │  │          │ │
│  └───────┬────────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘ │
└──────────┼────────────────┼─────────────┼────────────┼──────────────┼───────┘
           │                │             │            │              │
           ▼                ▼             ▼            ▼              ▼
     ┌──────────┐     ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
     │ Traefik  │     │CloudNPG  │  │ Frontend │  │Prometheus│  │ External │
     │cert-mgr  │     │PostgreSQL│  │ Backend  │  │ Grafana  │  │ Secrets  │
     │ Strimzi  │     │  Kafka   │  │ Ingester │  │  AKHQ    │  │          │
     └──────────┘     └──────────┘  └──────────┘  └──────────┘  └──────────┘
```

## Directory Structure

```
cv-site-gitops/
├── clusters/                    # Flux sync points per cluster
│   ├── local/                   # Local development cluster
│   │   ├── infrastructure.yaml  # Flux Kustomization
│   │   ├── databases.yaml
│   │   ├── apps.yaml
│   │   └── monitoring.yaml
│   └── production/              # Production cluster
│       └── (same structure)
├── infrastructure/
│   ├── controllers/             # HelmReleases for operators
│   │   ├── base/                # cert-manager, traefik, strimzi, vault, etc.
│   │   ├── local/
│   │   └── production/
│   └── configs/                 # ClusterIssuers, middlewares, etc.
│       ├── base/
│       ├── local/               # IngressRoutes for *.k8s.local
│       └── production/          # IngressRoutes for *.sebastien.sh
├── databases/
│   ├── base/                    # CloudNativePG + Kafka clusters
│   ├── local/                   # Single-node for dev
│   └── production/              # Multi-node HA
├── apps/
│   ├── base/                    # cv-site + akhq
│   ├── local/
│   └── production/
├── monitoring/
│   └── controllers/             # Prometheus, Grafana
│       ├── base/
│       ├── local/
│       └── production/
└── README.md
```

## Prerequisites

1. **Kubernetes Cluster** (K3s, Kind, or managed cluster)
2. **Flux CLI**:
   ```bash
   curl -s https://fluxcd.io/install.sh | sudo bash
   ```
3. **GitHub Personal Access Token** with repo permissions

## Quick Start

### 1. Bootstrap Flux (Production)

```bash
flux bootstrap github \
  --owner=sebheuze \
  --repository=cv-site-gitops \
  --branch=main \
  --path=clusters/production \
  --personal
```

### 2. Bootstrap Flux (Local Development)

```bash
flux bootstrap github \
  --owner=sebheuze \
  --repository=cv-site-gitops \
  --branch=main \
  --path=clusters/local \
  --personal
```

### 3. Initialize HashiCorp Vault

After Flux deploys Vault, initialize and unseal it:

```bash
# Initialize Vault
kubectl exec -it vault-0 -n vault -- vault operator init

# Save the unseal keys and root token!

# Unseal with 3 of 5 keys
kubectl exec -it vault-0 -n vault -- vault operator unseal <key1>
kubectl exec -it vault-0 -n vault -- vault operator unseal <key2>
kubectl exec -it vault-0 -n vault -- vault operator unseal <key3>

# Enable KV secrets engine
kubectl exec -it vault-0 -n vault -- vault login
kubectl exec -it vault-0 -n vault -- vault secrets enable -path=secret kv-v2

# Enable Kubernetes auth
kubectl exec -it vault-0 -n vault -- vault auth enable kubernetes
```

### 4. Add Secrets to Vault

```bash
# GHCR credentials
vault kv put secret/cv-site/ghcr \
  username=sebheuze \
  password=<github-pat>

# PostgreSQL credentials
vault kv put secret/cv-site/postgres \
  username=cvuser \
  password=<secure-password>

# Authelia secrets
vault kv put secret/cv-site/authelia \
  jwt-secret=$(openssl rand -hex 32) \
  session-secret=$(openssl rand -hex 32) \
  storage-encryption-key=$(openssl rand -hex 32)
```

## Dependency Chain

Flux Kustomizations deploy in this order using `dependsOn`:

```
1. infra-controllers → Traefik, cert-manager, Strimzi, CNPG, ESO, Vault
          │
          ▼
2. infra-configs → Namespaces, ClusterIssuers, middlewares, ClusterSecretStore
          │
          ├──────────────────────────────┐
          ▼                              ▼
3. databases → PostgreSQL, Kafka    4. monitoring → Prometheus, Grafana
          │
          ▼
5. apps → cv-site (frontend, trading-simulator, binance-ingester), AKHQ
```

## Access URLs

### Production (*.sebastien.sh)

| Service | URL | Auth |
|---------|-----|------|
| Frontend | https://cv.sebastien.sh | Public |
| API | https://api.sebastien.sh | Public |
| Authelia | https://auth.sebastien.sh | - |
| Grafana | https://grafana.sebastien.sh | Authelia (2FA) |
| AKHQ | https://akhq.sebastien.sh | Authelia (2FA) |
| Prometheus | https://prometheus.sebastien.sh | Authelia (2FA) |

### Local (*.k8s.local)

| Service | URL | Auth |
|---------|-----|------|
| Frontend | https://cv.k8s.local | Public |
| API | https://api.k8s.local | Public |
| Authelia | https://auth.k8s.local | - |
| Grafana | https://grafana.k8s.local | Authelia (1FA) |
| Traefik | https://traefik.k8s.local | Authelia (1FA) |

## Flux Commands

```bash
# Check Flux status
flux get all

# Reconcile immediately
flux reconcile kustomization apps --with-source

# View HelmRelease status
flux get helmreleases -A

# Suspend reconciliation (for debugging)
flux suspend kustomization apps

# Resume reconciliation
flux resume kustomization apps

# Check logs
flux logs --level=error

# Export current config
flux export source git flux-system > backup.yaml
```

## Key Components

### CloudNativePG PostgreSQL
- Operator-managed PostgreSQL cluster
- 3 instances in production, 1 in local
- Automatic failover and backup

### Strimzi Kafka (KRaft mode)
- Zookeeper-less Kafka cluster
- 3 controllers + 3 brokers in production
- Topics: binance-btcusdc-trades, trading-events, analytics-results

### External Secrets Operator
- Syncs secrets from HashiCorp Vault
- 1-hour refresh interval
- ClusterSecretStore for cluster-wide access

### Authelia
- Single Sign-On (SSO)
- Two-Factor Authentication (TOTP)
- File-based user database
- Protects: Grafana, AKHQ, Prometheus

## Troubleshooting

```bash
# Check Kustomization status
kubectl get kustomizations -n flux-system

# Check HelmRelease status
kubectl get helmreleases -A

# View events
kubectl get events --sort-by='.lastTimestamp' -A

# Check Vault status
kubectl exec -it vault-0 -n vault -- vault status

# Check External Secrets
kubectl get externalsecrets -A
kubectl get clustersecretstores

# Check CNPG cluster
kubectl get clusters -n cv-site-prd
kubectl cnpg status trading-db -n cv-site-prd
```

## Migration from ArgoCD

If migrating from ArgoCD:

1. Backup any manual changes
2. Uninstall ArgoCD: `kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
3. Remove ArgoCD namespace: `kubectl delete namespace argocd`
4. Bootstrap Flux as described above
