# Installing HashiCorp Vault on Proxmox

This guide explains how to install and configure HashiCorp Vault as a standalone VM on Proxmox for use with the cv-site-gitops Kubernetes cluster.

## Prerequisites

- Proxmox VE 9.x
- Network access between Kubernetes nodes and the Vault VM
- Ubuntu 24.04 LTS ISO (or Debian 12)

## 1. Create the VM in Proxmox

### Via Proxmox Web UI

1. Click **Create VM**
2. **General**:
   - Node: Select your node
   - VM ID: e.g., `200`
   - Name: `vault`
3. **OS**:
   - ISO Image: `ubuntu-24.04-live-server-amd64.iso`
4. **System**:
   - Machine: `q35`
   - BIOS: `OVMF (UEFI)` or `SeaBIOS`
   - Add EFI Disk if using UEFI
5. **Disks**:
   - Storage: local-lvm
   - Disk size: `20 GB` (minimum)
6. **CPU**:
   - Cores: `2`
7. **Memory**:
   - Memory: `2048 MB`
8. **Network**:
   - Bridge: `vmbr0` (or your network bridge)
   - Model: `VirtIO`

### Via CLI

```bash
qm create 200 --name vault --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:20 \
  --ide2 local:iso/ubuntu-24.04-live-server-amd64.iso,media=cdrom \
  --boot order=scsi0;ide2
```

## 2. Install Ubuntu Server

1. Start the VM and open the console
2. Follow Ubuntu Server installation:
   - Language: English
   - Keyboard: Your layout
   - Network: Configure static IP (recommended)
   - Storage: Use entire disk
   - Profile: Create user (e.g., `vault`)
   - SSH: Install OpenSSH server
3. Reboot and remove ISO

### Configure Static IP (recommended)

Edit `/etc/netplan/00-installer-config.yaml`:

```yaml
network:
  version: 2
  ethernets:
    ens18:  # Your interface name
      addresses:
        - 192.168.1.50/24  # Your desired IP
      routes:
        - to: default
          via: 192.168.1.1  # Your gateway
      nameservers:
        addresses:
          - 192.168.1.1
          - 8.8.8.8
```

Apply:
```bash
sudo netplan apply
```

## 3. Install HashiCorp Vault

### Add HashiCorp Repository

```bash
# Install prerequisites
sudo apt update && sudo apt install -y gpg wget

# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install Vault
sudo apt update && sudo apt install -y vault
```

### Verify Installation

```bash
vault --version
# vault v1.x.x
```

## 4. Configure Vault

### Create Configuration File

```bash
sudo mkdir -p /etc/vault.d
sudo mkdir -p /opt/vault/data
sudo chown -R vault:vault /opt/vault
```

Create `/etc/vault.d/vault.hcl`:

```bash
sudo tee /etc/vault.d/vault.hcl << 'EOF'
# Vault configuration for cv-site-gitops

ui = true
disable_mlock = true

storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true  # Enable TLS in production!
}

api_addr = "http://192.168.1.50:8200"  # Update with your VM IP
cluster_addr = "http://192.168.1.50:8201"
EOF
```

### For Production with TLS

```bash
# Generate self-signed certificate (or use Let's Encrypt)
sudo mkdir -p /etc/vault.d/tls
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/vault.d/tls/vault.key \
  -out /etc/vault.d/tls/vault.crt \
  -subj "/CN=vault.internal"

sudo chown -R vault:vault /etc/vault.d
```

Update `vault.hcl` for TLS:
```hcl
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault.d/tls/vault.crt"
  tls_key_file  = "/etc/vault.d/tls/vault.key"
}
```

## 5. Configure Systemd Service

The Vault package creates a systemd service automatically. Verify:

```bash
sudo systemctl status vault
```

If not present, create `/etc/systemd/system/vault.service`:

```bash
sudo tee /etc/systemd/system/vault.service << 'EOF'
[Unit]
Description=HashiCorp Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl

[Service]
User=vault
Group=vault
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF
```

### Start Vault

```bash
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault
sudo systemctl status vault
```

## 6. Initialize Vault

```bash
export VAULT_ADDR='http://192.168.1.50:8200'  # Your VM IP

# Initialize Vault
vault operator init

# OUTPUT - SAVE THESE SECURELY!
# Unseal Key 1: xxxxx
# Unseal Key 2: xxxxx
# Unseal Key 3: xxxxx
# Unseal Key 4: xxxxx
# Unseal Key 5: xxxxx
# Initial Root Token: hvs.xxxxx
```

**IMPORTANT**: Save the unseal keys and root token securely! You need 3 of 5 keys to unseal Vault.

### Unseal Vault

```bash
vault operator unseal  # Enter key 1
vault operator unseal  # Enter key 2
vault operator unseal  # Enter key 3

# Check status
vault status
```

## 7. Configure Vault for cv-site-gitops

### Login with Root Token

```bash
export VAULT_ADDR='http://192.168.1.50:8200'
vault login  # Enter root token
```

### Enable KV Secrets Engine

```bash
vault secrets enable -path=secret kv-v2
```

### Create Secrets for cv-site-gitops

```bash
# GHCR (GitHub Container Registry) credentials
vault kv put secret/cv-site/ghcr \
  username="sebheuze" \
  password="ghp_your_github_pat"

# PostgreSQL credentials
vault kv put secret/cv-site/postgres \
  username="cvuser" \
  password="your_secure_password"

# Authelia secrets
vault kv put secret/cv-site/authelia \
  jwt-secret="$(openssl rand -hex 32)" \
  session-secret="$(openssl rand -hex 32)" \
  storage-encryption-key="$(openssl rand -hex 32)"
```

### Create Policy for External Secrets

```bash
vault policy write external-secrets - << 'EOF'
path "secret/data/cv-site/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/cv-site/*" {
  capabilities = ["read", "list"]
}
EOF
```

### Create Token for Kubernetes

```bash
# Create a token for External Secrets Operator
vault token create \
  -policy=external-secrets \
  -period=720h \
  -display-name="kubernetes-external-secrets"

# OUTPUT:
# Key                  Value
# ---                  -----
# token                hvs.xxxxx  <-- Use this in Kubernetes
# token_accessor       xxxxx
# token_duration       720h
# token_renewable      true
# token_policies       ["default" "external-secrets"]
```

## 8. Configure Kubernetes to Use External Vault

### Update ClusterSecretStore

Edit `infrastructure/configs/base/external-secrets/cluster-secret-store.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://192.168.1.50:8200"  # Your Vault VM IP
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
          namespace: external-secrets
```

### Create Vault Token Secret in Kubernetes

```bash
kubectl create secret generic vault-token \
  -n external-secrets \
  --from-literal=token=hvs.xxxxx  # Your token from step 7
```

## 9. DNS Configuration (Optional but Recommended)

Add DNS entry for Vault in your network's DNS server or in CoreDNS:

### Option A: /etc/hosts on Kubernetes nodes

```bash
# On each Kubernetes node
echo "192.168.1.50 vault.internal" | sudo tee -a /etc/hosts
```

### Option B: CoreDNS ConfigMap

```bash
kubectl edit configmap coredns -n kube-system
```

Add to Corefile:
```
hosts {
    192.168.1.50 vault.internal
    fallthrough
}
```

## 10. Firewall Configuration

If using UFW:

```bash
sudo ufw allow 8200/tcp comment "Vault API"
sudo ufw allow 8201/tcp comment "Vault Cluster"
sudo ufw enable
```

## 11. Auto-Unseal (Production)

For production, consider auto-unseal using:
- **Transit Auto-Unseal** (another Vault)
- **Cloud KMS** (AWS KMS, GCP KMS, Azure Key Vault)
- **HSM** (Hardware Security Module)

Example with Transit (if you have another Vault):

```hcl
seal "transit" {
  address         = "https://vault-primary.internal:8200"
  token           = "s.xxxxx"
  disable_renewal = false
  key_name        = "autounseal"
  mount_path      = "transit/"
}
```

## 12. Backup Strategy

### Backup Vault Data

```bash
# Stop Vault
sudo systemctl stop vault

# Backup data directory
sudo tar -czvf vault-backup-$(date +%Y%m%d).tar.gz /opt/vault/data

# Start Vault
sudo systemctl start vault
```

### Backup with Raft Snapshots (if using Raft storage)

```bash
vault operator raft snapshot save backup.snap
```

## Verification Checklist

- [ ] Vault VM is running on Proxmox
- [ ] Vault is initialized and unsealed
- [ ] KV secrets engine enabled at `secret/`
- [ ] Secrets created under `secret/cv-site/`
- [ ] Policy `external-secrets` created
- [ ] Token created for Kubernetes
- [ ] Kubernetes can reach Vault (network/firewall)
- [ ] `vault-token` secret created in `external-secrets` namespace
- [ ] ClusterSecretStore pointing to Vault VM IP
- [ ] ExternalSecrets syncing successfully

## Troubleshooting

### Check Vault Status
```bash
vault status
```

### Check Vault Logs
```bash
sudo journalctl -u vault -f
```

### Test Connection from Kubernetes
```bash
kubectl run test-vault --rm -it --image=curlimages/curl -- \
  curl -s http://192.168.1.50:8200/v1/sys/health
```

### Check External Secrets
```bash
kubectl get clustersecretstores
kubectl get externalsecrets -A
kubectl describe externalsecret <name> -n <namespace>
```

## Security Recommendations

1. **Enable TLS** - Never run Vault without TLS in production
2. **Rotate Root Token** - Revoke root token after initial setup
3. **Use Policies** - Principle of least privilege
4. **Enable Audit Logging** - `vault audit enable file file_path=/var/log/vault/audit.log`
5. **Regular Backups** - Automate backup of Vault data
6. **Network Segmentation** - Vault should be in a secure network segment
7. **Auto-Unseal** - Use cloud KMS or transit for auto-unseal
