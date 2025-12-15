# Secrets Management Guide

## Overview

This document explains how to manage secrets in the GitOps repository.

## Current Implementation

Secrets are defined in `charts/infrastructure/templates/secrets.yaml` and configured via values files.

**Note**: Base64-encoded secrets in Git are NOT secure for production. This is a starter implementation.

## Production Recommendations

### Option 1: Sealed Secrets

1. Install Sealed Secrets controller:
```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system
```

2. Seal secrets:
```bash
kubeseal --format yaml < secret.yaml > sealed-secret.yaml
```

3. Commit sealed secrets to Git

### Option 2: External Secrets Operator

1. Install ESO:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
```

2. Create SecretStore pointing to your vault
3. Create ExternalSecret resources

### Option 3: SOPS + Age

1. Install SOPS and Age
2. Encrypt values files:
```bash
sops -e environments/production/infrastructure-values.yaml > environments/production/infrastructure-values.enc.yaml
```

3. Configure Argo CD to decrypt

## Required Secrets

### 1. GitHub Container Registry (GHCR)

```bash
# Generate dockerconfigjson
GITHUB_USER="your-username"
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"

echo -n '{"auths":{"ghcr.io":{"auth":"'$(echo -n "$GITHUB_USER:$GITHUB_TOKEN" | base64)'"}}}' | base64
```

Update `environments/production/infrastructure-values.yaml`:
```yaml
secrets:
  ghcr:
    enabled: true
    dockerConfigJson: "<base64-encoded-docker-config>"
```

### 2. PostgreSQL Password

```bash
# Generate secure password
openssl rand -base64 32

# Base64 encode
echo -n "your-secure-password" | base64
```

Update `environments/production/infrastructure-values.yaml`:
```yaml
secrets:
  postgres:
    password: "<base64-encoded-password>"
```

### 3. Authelia Secrets

```bash
# Generate JWT secret
openssl rand -base64 64

# Generate session secret
openssl rand -base64 64

# Generate storage encryption key
openssl rand -base64 64
```

### 4. Authelia User Passwords

Generate argon2id hash:
```bash
docker run authelia/authelia:latest authelia crypto hash generate argon2 --password 'your-password'
```

Update `environments/production/ingress-values.yaml`:
```yaml
authelia:
  users:
    - username: admin
      password: "$argon2id$v=19$m=65536,t=3,p=4$..."
```

## Rotating Secrets

### PostgreSQL Password

1. Update secret in values
2. Restart PostgreSQL pod
3. Update application connection strings if needed

### Authelia Secrets

1. Update secrets in values
2. Restart Authelia pod
3. Users may need to re-authenticate

### GHCR Token

1. Generate new GitHub token
2. Update dockerConfigJson
3. Delete and recreate ghcr-secret
4. Restart pods using the secret

## Validating Secrets

```bash
# Check if secret exists
kubectl get secret postgres-secret -n cv-site-prd

# Decode and verify (be careful with output)
kubectl get secret postgres-secret -n cv-site-prd -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```

## Security Checklist

- [ ] Changed default PostgreSQL password
- [ ] Changed default Grafana admin password
- [ ] Generated secure Authelia JWT secret
- [ ] Generated secure Authelia session secret
- [ ] Created strong Authelia user passwords
- [ ] Configured GHCR authentication
- [ ] Implemented secrets encryption (Sealed Secrets/ESO)
- [ ] Enabled audit logging
- [ ] Restricted RBAC permissions
