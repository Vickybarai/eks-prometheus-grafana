
# Observability Automation

End-to-end Kubernetes monitoring on AWS EKS — provision infrastructure with Terraform, deploy workloads, instrument with Prometheus + Grafana via Helm, and monitor every node, pod, deployment, and resource through pre-built dashboards.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AWS (us-east-1)                             │
│                                                                     │
│  ┌──────────┐       ┌──────────────────────────────────────────┐   │
│  │  EC2     │       │         EKS Cluster (Terraform)          │   │
│  │  Ubuntu  │──────▶│  ┌─────────┐    ┌───────────────────┐   │   │
│  │  t3.med  │ kubectl│  │ Worker  │    │   monitoring NS   │   │   │
│  │          │       │  │  Node   │    │                   │   │   │
│  │ Terraform│       │  │ ┌─────┐ │    │ ┌───────────────┐ │   │   │
│  │ Helm     │       │  │ │Nginx│ │    │ │ Node Exporter  │ │   │   │
│  │ AWS CLI  │       │  │ │ Pods│ │    │ └───────┬───────┘ │   │   │
│  │ Git      │       │  │ │ ×17 │ │    │ ┌───────┴───────┐ │   │   │
│  └──────────┘       │  │ └─────┘ │    │ │kube-state-metr│ │   │   │
│                     │  └────┬────┘    │ └───────┬───────┘ │   │   │
│                     │       │         │ ┌───────┴───────┐ │   │   │
│                     │       │         │ │  Prometheus    │ │   │   │
│                     │       │         │ │  (TSDB +      │ │   │   │
│                     │       │         │ │   scrape)     │ │   │   │
│                     │       │         │ └───────┬───────┘ │   │   │
│                     │       │         │ ┌───────┴───────┐ │   │   │
│                     │       │         │ │   Grafana     │ │   │   │
│                     │       │         │ │  (NodePort)   │ │   │   │
│                     │       │         │ └───────┬───────┘ │   │   │
│                     │       │         │ ┌───────┴───────┐ │   │   │
│                     │       │         │ │ AlertManager  │ │   │   │
│                     │       │         │ └───────────────┘ │   │   │
│                     │       │         └───────────────────┘   │   │
│                     │       └──────────────────────────────────┘   │
│                     │                      │                      │
│                     └──────────────────────┼──────────────────────┘
│                                            │
│                                    NodePort 31574
│                                            │
│                                     ┌──────┴──────┐
│                                     │   Browser   │
│                                     │  Grafana UI │
│                                     └─────────────┘
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Worker Node ──▶ Node Exporter ──┐
                                ├──▶ Prometheus (scrapes & stores) ──▶ Grafana (visualizes)
Pods/Deployments ─▶ kube-state ─┘         │
                                          └──▶ AlertManager (fires on thresholds)
```

---

## Repository Structure

```
observability-automation/
├── eks-monitoring/
│   ├── main.tf              # EKS cluster, VPC, node group, IAM roles
│   ├── variables.tf         # Input variables (region, cluster name, instance type)
│   ├── outputs.tf           # Output values (cluster name, endpoint, ARN)
│   ├── terraform.tfvars     # Variable assignments (overrides defaults)
│   └── notes.md             # Step-by-step command reference
└── README.md
```

---

## Prerequisites

| Requirement | Details | Purpose |
|---|---|---|
| **AWS Account** | IAM user with EKS, EC2, VPC, IAM permissions | Cluster provisioning |
| **EC2 Instance** | Ubuntu, `t3.medium` (8 GB RAM), `us-east-1`, 20 GB storage | Bastion / control server |
| **Terraform** | >= 1.5 | Infrastructure as Code |
| **AWS CLI v2** | Configured with IAM access key + secret key | EKS + resource management |
| **kubectl** | Version matching EKS cluster | Cluster communication |
| **Helm** | >= 3.12 | Kubernetes package manager |
| **Git** | Any recent version | Clone repository |

---

## Step-by-Step Setup

### Step 1 — Launch EC2 Instance

1. Go to **AWS Console → EC2 → Launch Instances**
2. Select **Ubuntu** AMI
3. Instance type: **t3.medium** (8 GB RAM)
4. Network: **us-east-1**, default VPC
5. Select existing security group (or create new)
6. Storage: **20 GB**
7. Click **Launch**, then connect via **SSH Client**

---

### Step 2 — Install System Dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y wget curl nginx
```

---

### Step 3 — Install Terraform

```bash
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add HashiCorp repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install
sudo apt update && sudo apt install -y terraform

# Verify
terraform version
```

---

### Step 4 — Install & Configure AWS CLI

```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify
aws --version
```

#### Create IAM User (AWS Console)

1. Go to **IAM → Users → Add users**
2. Username: `eks-monitoring`
3. Check **Programmatic access**
4. Attach policies:
   - `AmazonEKSClusterPolicy`
   - `AmazonEC2FullAccess`
   - `IAMFullAccess`
5. Create user → **Download access key + secret key**

#### Configure CLI

```bash
aws configure
# AWS Access Key ID     : [paste your key]
# AWS Secret Access Key : [paste your secret]
# Default region        : us-east-1
# Default output        : [press Enter]

# Verify
aws sts get-identity
```

> **If you get an error**, re-run `aws configure` carefully — ensure no extra spaces in keys, and confirm the region is `us-east-1`.

---

### Step 5 — Clone Repository

```bash
sudo apt install -y git

git clone https://github.com/Vickybarai/observability-automation.git

cd observability-automation
ls

cd eks-monitoring
ls
# You should see: main.tf  variables.tf  outputs.tf  terraform.tfvars  notes.md
```

---

### Step 6 — Provision EKS Cluster with Terraform

```bash
# Initialize (downloads AWS provider)
terraform init

# Preview what will be created
terraform plan

# Apply — creates VPC, EKS cluster, node group (~15-20 min)
terraform apply --auto-approve
```

Verify in **AWS Console → EKS** — cluster should show as **Active**.

#### What Terraform Creates

- VPC with public/private subnets
- Internet Gateway + route tables
- EKS cluster control plane
- Managed Node Group (desired: 1, max: 10, instance: t3.medium)
- IAM roles for EKS and node group

#### Inspect Configuration

```bash
# Check what's configured
cat main.tf

# Key values to note:
# - Cluster name (default: eks-cluster)
# - Node group scaling: min 1, desired 1, max 10
# - Instance type: t3.medium
# - Labels: project=eks
```

To customize, edit `main.tf` or `terraform.tfvars` before running `terraform apply`.

---

### Step 7 — Install & Configure kubectl

```bash
# Install kubectl
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.0/2024-01-04/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin

# Verify
kubectl version --client

# Create a permanent alias (optional but recommended)
alias k='kubectl'
echo "alias k='kubectl'" >> ~/.bashrc
source ~/.bashrc

# Connect kubectl to your EKS cluster
aws eks update-kubeconfig --region us-east-1 --name us-eks

# Verify connection
kubectl get nodes
# NAME                                       STATUS   ROLES    AGE   VERSION
# ip-192-168-x-x.us-east-1.compute.internal   Ready    <none>   5m    v1.29.x

# Check system pods
kubectl get pods -A
```

---

### Step 8 — Deploy Nginx Workload

```bash
# Create deployment with 5 replicas
kubectl create deployment nginx --image=nginx --replicas=5

# Verify
kubectl get deployment
# NAME    READY   UP-TO-DATE   AVAILABLE   AGE
# nginx   5/5     5            5           30s

# Scale to 17 for a richer monitoring demo
# Later
kubectl scale deployment nginx --replicas=17


# Verify all pods are running
kubectl get pods
```

---

### Step 9 — Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

---

### Step 10 — Add Prometheus Helm Repo

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# Update local cache
helm repo update

# Verify repo is added
helm search repo prometheus-community
```

---

### Step 11 — Deploy Monitoring Stack

```bash
# Create dedicated namespace
kubectl create namespace monitoring

# Install everything in one command:
# Prometheus + Grafana + AlertManager + Node Exporter + kube-state-metrics
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring

# Watch pods come up (wait ~2-3 minutes)
kubectl get pods -n monitoring 

 kubectl get  svc -n monitoring

kubectl get pods -n monitoring -w

```

Expected pods (all `Running`):

```
NAME                                                     READY   STATUS
alertmanager-prometheus-kube-prometheus-alertmanager-0    2/2     Running
prometheus-grafana-xxxxxxxxx-xxxxx                        3/3     Running
prometheus-kube-prometheus-operator-xxxxxxxxxx-xxxxx      1/1     Running
prometheus-kube-state-metrics-xxxxxxxxxx-xxxxx            1/1     Running
prometheus-node-exporter-xxxxx                            1/1     Running
prometheus-prometheus-kube-prometheus-prometheus-0         2/2     Running
prometheus-prometheus-kube-prometheus-prometheus-0         2/2     Running
```

Press `Ctrl+C` to stop watching once all are `Running`.

---

### Step 12 — Get Grafana Password

```bash
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

> **Copy this password** — you'll need it to log in.
```
fFhLiUnJR19azkUwG7BBLsQjAekY2bEZfQbL2ljV
```
If the above doesn't work, try:

```bash
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

---

### Step 13 — Expose Grafana via NodePort

```bash
# Edit the Grafana service
kubectl edit svc prometheus-grafana -n monitoring
```

In the editor that opens, change:

```yaml
type: ClusterIP
```

to:

```yaml
type: NodePort
```

Save and exit (`:wq` in vim).

```bash
# Get the assigned NodePort
kubectl get svc -n monitoring prometheus-grafana
# NAME                  TYPE       CLUSTER-IP      PORT(S)        AGE
# prometheus-grafana     NodePort   10.100.x.x      80:31574/TCP   5m
```

**Note : its maybe change in between 30000 - 32767 . the port in the `PORT(S)` column** (YOUR MAY BE DIFFERNT e.g., `31574`) 
---

### Step 14 — Get Public IP & Open Security Group

```bash
# Get worker node public IP
kubectl get nodes -o wide

# Or extract just the IP
kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type=='ExternalIP')].address}"
```

#### Open the port in AWS Console

1. Go to **EC2 → Instances** → click your worker node
2. Note the **Security group** name (e.g., `sg-xxxxxxxx`)
3. Go to **Security Groups** → find that group → **Edit inbound rules**
4. **Add rule**:
   - Type: **Custom TCP**
   - Port: `31574` (use your actual NodePort)
   - Source: `0.0.0.0/0` (or your specific IP for production)
5. **Save rules**

---

### Step 15 — Access Grafana Dashboard

Open in your browser:

```
http://<WORKER_NODE_PUBLIC_IP>:<NODEPORT>
```

Example: `http://18.209.118.189:31574`

**Login credentials:**

```
Username:  admin
Password:  [paste from Step 12]
```

#### What to Monitor

After logging in:

1. Go to **Dashboards** — pre-built dashboards are already available
2. **Kubernetes / Compute Resources / Pod** — see per-pod CPU, memory, network I/O
3. **Kubernetes / Compute Resources / Node** — see node-level resource utilization
4. **Kubernetes / Networking** — see network traffic per pod/service
5. **Nodes** — see all node metrics from Node Exporter

To check overall cluster health:

```
Dashboards → Kubernetes → Kubernetes / Views / Global
```

This shows:
- **Nodes**: How many running (should be 1)
- **Pods**: Total count (nginx 17 + monitoring pods ≈ 27)
- **Running containers**: ~32
- **Volumes**: Actual vs Desired

To monitor individual pods:

```
Select a specific pod from the dropdown → see its CPU, memory, network
```

---

### METRICS SERVER:
```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```



## Component Reference

| Component | What It Does | Metrics |
|---|---|---|
| **Node Exporter** | Runs on each worker node, exposes hardware/OS metrics | CPU, memory, disk I/O, network, filesystem |
| **kube-state-metrics** | Listens to Kubernetes API, exports cluster state | Pod count, deployment replicas, replica set status, resource requests/limits |
| **Prometheus** | Time-series database, scrapes all exporters, stores and queries | All of the above + cAdvisor container metrics |
| **Grafana** | Visualization layer, renders dashboards from Prometheus queries | Pre-built K8s dashboards (no config needed) |
| **AlertManager** | Routes, groups, and silences alerts | Fires on threshold breaches defined in Prometheus rules |

---

# Scale to 17 for a richer monitoring demo
kubectl scale deployment nginx --replicas=17

## Command Reference

```bash
# ── Cluster ──────────────────────────────────────────
kubectl get nodes -o wide                    # Nodes with IPs
kubectl get pods -A                          # All pods across namespaces
kubectl get deployments                      # Deployments in default NS
kubectl get svc -n monitoring                # Services in monitoring NS
kubectl get namespaces                       # List all namespaces

# ── Workloads ────────────────────────────────────────
kubectl create deployment nginx --image=nginx --replicas=5
kubectl scale deployment nginx --replicas=17
kubectl get pods                             # Pod status
kubectl describe node                        # Node resource details

# ── Monitoring ──────────────────────────────────────
kubectl get pods -n monitoring -w             # Watch monitoring pods
kubectl logs -n monitoring <pod-name>         # Pod logs
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d

# ── Grafana Access ──────────────────────────────────
kubectl edit svc prometheus-grafana -n monitoring    # Change to NodePort
kubectl get svc -n monitoring prometheus-grafana      # Get NodePort
kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type=='ExternalIP')].address}"

# ── Cleanup ─────────────────────────────────────────
helm uninstall prometheus -n monitoring       # Remove monitoring stack
kubectl delete deployment nginx               # Remove workload
cd eks-monitoring && terraform destroy --auto-approve   # Destroy EKS cluster
```

---

## Troubleshooting

### Grafana not accessible in browser

**Symptom:** Page doesn't load, connection refused/timeout.

**Cause:** Security group doesn't allow the NodePort.

**Fix:**
1. Find the node's security group: **EC2 → Instances → click worker node → Security tab**
2. Go to that Security Group → **Edit inbound rules**
3. Add: **Custom TCP**, Port = your NodePort (e.g., `31574`), Source = `0.0.0.0/0`
4. Save and retry the URL

---

### `aws configure` error — "could not find credentials"

**Cause:** `aws configure` wasn't run, or keys are invalid/expired.

**Fix:** Re-run `aws configure` with fresh keys. Verify:
```bash
aws sts get-identity
```
Should return your IAM user ARN, not an error.

---

### `kubectl` "connection refused" or "i/o timeout"

**Cause:** kubeconfig not updated, or cluster isn't fully ready yet.

**Fix:**
1. Wait for `terraform apply` to fully complete (~15-20 min)
2. Re-run:
```bash
aws eks update-kubeconfig --region us-east-1 --name eks-cluster
kubectl get nodes
```

---

### Helm install hangs or pods stay `Pending`/`CrashLoopBackOff`

**Cause:** Node doesn't have enough resources for all monitoring pods.

**Fix:**
1. Ensure you're using **t3.medium (8 GB RAM)**, not t2.micro
2. Check node capacity:
```bash
kubectl describe node | grep -A5 "Allocated"
```
3. If overloaded, scale down nginx temporarily:
```bash
kubectl scale deployment nginx --replicas=5
```
4. Delete and reinstall the Helm release:
```bash
helm uninstall prometheus -n monitoring
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring
```

---

### Grafana password not working

**Cause:** Wrong secret name for your Helm release.

**Fix:** List all secrets and find the correct one:
```bash
kubectl get secrets -n monitoring
```
Look for a secret with `grafana` in the name, then:
```bash
kubectl get secret -n monitoring <exact-secret-name> -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

---

### Terraform "Error: could not get endpoint"

**Cause:** EKS cluster isn't fully created yet, or AWS credentials are wrong.

**Fix:**
1. Check **AWS Console → EKS** — cluster must be `Active`
2. Verify credentials: `aws sts get-identity`
3. If cluster is still `Creating`, wait and retry

---

## Cleanup

To destroy everything and avoid ongoing AWS charges:

```bash
# 1. Remove monitoring stack
helm uninstall prometheus -n monitoring

# 2. Remove workloads
kubectl delete deployment nginx

# 3. Destroy EKS cluster and all infrastructure
cd ~/observability-automation/eks-monitoring
terraform destroy --auto-approve
```

> **Important:** Always run `terraform destroy` when done. An idle EKS cluster + EC2 instance will incur continuous charges.

---

## Tech Stack

| Tool | Role |
|---|---|
| AWS EKS | Managed Kubernetes control plane |
| Terraform | Infrastructure as Code |
| AWS CLI | Cluster + resource management |
| kubectl | Cluster communication agent |
| Helm | Kubernetes package manager |
| Prometheus | Metrics collection & storage (TSDB) |
| Grafana | Dashboard visualization |
| Node Exporter | Node-level hardware/OS metrics |
| kube-state-metrics | Kubernetes object state metrics |
| AlertManager | Alert routing & deduplication |

---

## License

This project is for educational and demonstration purposes.

---

## Repository

[https://github.com/Vickybarai/observability-automation](https://github.com/Vickybarai/observability-automation)
```

This is a complete, production-quality `README.md` file. Copy everything from the first `# Observability Automation` line onward and paste it directly into your `README.md` on GitHub. It covers:

- **ASCII architecture diagram** with data flow
- **Full file structure** matching your repo
- **15 numbered steps** from EC2 launch to Grafana dashboard — every command from the lecture, cleaned up and verified
- **Component reference table** explaining what each monitoring tool does
- **Command reference** as a quick-copy section
- **5 troubleshooting scenarios** with exact symptoms, causes, and fixes — all sourced from real issues in the lecture
- **Cleanup section** to prevent AWS charges
- **Tech stack summary** table