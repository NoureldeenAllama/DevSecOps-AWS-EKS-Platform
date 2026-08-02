# EKS Cluster on AWS with Terraform

This project provisions a production-style **Amazon EKS (Elastic Kubernetes Service)** cluster
using Terraform, including:

- A dedicated **VPC** with public and private subnets across 3 Availability Zones
- An **EKS cluster** (control plane) with a **managed node group** (worker nodes)
- **IRSA** (IAM Roles for Service Accounts) via an OIDC provider
- The **AWS Load Balancer Controller** (installed via Helm) so Kubernetes Ingress objects
  automatically create real AWS Application Load Balancers (ALBs)
- An **ECR (Elastic Container Registry)** repository to store your application's Docker images
- A remote **S3 backend with DynamoDB state locking** for safe team collaboration

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites — Install Tools (Linux)](#prerequisites--install-tools-linux)
3. [Step 1: Configure AWS CLI](#step-1-configure-aws-cli)
4. [Step 2: Create the Backend (S3) via AWS CLI](#step-2-create-the-backend-s3--via-aws-cli)
5. [Step 3: Deploy the EKS Cluster](#step-3-deploy-the-eks-cluster)
6. [Step 4: Connect kubectl to the Cluster](#step-4-connect-kubectl-to-the-cluster)
7. [Step 5: Verify the AWS Load Balancer Controller](#step-5-verify-the-aws-load-balancer-controller)
8. [Step 6: Push an Image to ECR and Deploy It](#step-6-push-an-image-to-ecr-and-deploy-it)
9. [EKS Components Explained in Detail](#eks-components-explained-in-detail)
10. [AWS Load Balancer Controller — Deep Dive](#aws-load-balancer-controller--deep-dive)
11. [What AWS Is Responsible For vs. What You Are Responsible For](#what-aws-is-responsible-for-vs-what-you-are-responsible-for)
12. [Destroying Everything](#destroying-everything)
13. [File Structure](#file-structure)
14. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
                                          Internet
                                             │
                                      ┌──────▼──────┐
                                      │  ALB (public) │  <- created automatically by the
                                      └──────┬──────┘     AWS Load Balancer Controller
                                             │  (listeners: 80/443, target group per Service)
   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │                                     VPC (10.0.0.0/16)                            │
   │                                                                                    │
   │   ┌───────────────────────┐              ┌───────────────────────┐               │
   │   │   Public Subnet AZ-a   │              │   Public Subnet AZ-b   │               │
   │   │   10.0.101.0/24        │              │   10.0.102.0/24        │              │
   │   │   [ALB ENI] [NAT GW]   │              │   [ALB ENI]            │              │
   │   └───────────┬───────────┘              └───────────┬───────────┘               │
   │               │  route via NAT (outbound only)        │                           │
   │   ┌───────────▼───────────┐              ┌───────────▼───────────┐               │
   │   │  Private Subnet AZ-a   │              │  Private Subnet AZ-b   │              │
   │   │  10.0.1.0/24           │              │  10.0.2.0/24           │              │
   │   │                        │              │                        │              │
   │   │  EC2 MANAGED NODE GROUP│              │  EC2 MANAGED NODE GROUP│              │
   │   │  ┌──────┐              │              │  ┌──────┐              │              │
   │   │  │Node 1│              │              │  │Node 2│              │              │
   │   │  │ pod  │              │              │  │ pod  │              │              │
   │   │  │ pod  │              │              │  │ pod  │              │              │
   │   │  └──────┘              │              │  └──────┘              │              │
   │   │  (scales up to 2 nodes │              │  (scales up to 2 nodes │              │
   │   │   here at max_size=4)  │              │   here at max_size=4)  │              │
   │   └────────────────────────┘              └────────────────────────┘              │
   │                                                                                    │
   └────────────────────────────────────────────────────────────────────────────────────┘

   Outside your VPC, in an AWS-owned account:
   ┌─────────────────────────────────────────────────────────┐
   │  EKS CONTROL PLANE (fully managed by AWS)                 │
   │  API Server  │  etcd  │  Scheduler  │  Controller Manager  │
   │  Reaches into your VPC via cross-account ENIs to talk to   │
   │  nodes/kubelets; exposes a public and/or private endpoint  │
   │  for kubectl / Terraform.                                   │
   └─────────────────────────────────────────────────────────┘

   ECR (regional, outside your VPC by default, reached over the
   AWS network / optionally a VPC endpoint) — stores the Docker
   images your EC2 nodes pull to run containers.
```

This project's defaults are tuned for a **2-AZ, 2-node** setup (matching
`azs = ["us-east-1a", "us-east-1b"]` in `variables.tf`):

| Setting | Value | Meaning |
|---|---|---|
| `node_desired_size` | `2` | The Auto Scaling Group starts with 2 nodes — the ASG spreads them evenly, so effectively **1 node per AZ** at steady state. |
| `node_min_size` | `2` | The ASG will never scale below 2 nodes — so you always keep at least 1 node per AZ, avoiding a single point of failure. |
| `node_max_size` | `4` | Under load (or if the Cluster Autoscaler is added later), the ASG can grow up to 4 nodes — 2 per AZ, matching the diagram's original 4-node illustration. |
| `azs` | 2 AZs | Only `us-east-1a` and `us-east-1b` are used — drop or add entries here (and matching CIDRs in `private_subnets`/`public_subnets`) to change AZ count. |

> If you want true multi-AZ resilience under normal (non-scaled) conditions, keep
> `node_min_size` at 2 or higher with 2 AZs, so a single AZ outage never takes your
> whole node group down to zero.

### How a request actually flows, end to end

1. A client hits your domain (e.g. `app.example.com`), which resolves via Route 53 to
   the **ALB's** public DNS name.
2. The **ALB**, sitting in the public subnets, terminates the connection (and TLS, if
   you've attached an ACM cert) and evaluates its listener rules — created and kept in
   sync by the **AWS Load Balancer Controller** based on your Kubernetes `Ingress` objects.
3. The ALB forwards the request to a **target group**. With `target-type: ip` (the
   recommended mode), targets are pod IP addresses *directly* — traffic goes straight
   from the ALB's elastic network interface into the private subnet to the pod, bypassing
   `kube-proxy`/`iptables` entirely for a shorter, faster path. With `target-type:
   instance`, the ALB instead targets the EC2 node's `NodePort`, and `kube-proxy` on that
   node forwards the packet on to the right pod (possibly on a different node).
4. The receiving pod runs on one of the **EC2 worker nodes** in the managed node group —
   a real EC2 instance you're billed for hourly, typically packed with several pods to
   maximize utilization (bin-packing). The **VPC CNI** add-on is what gives that pod a
   real, routable IP address out of the private subnet's CIDR block, which is exactly
   what lets the ALB target it directly.
5. If the pod needs to pull its container image, the **kubelet** on that node pulls it
   from **ECR**, authenticating using the node's IAM instance role (which already has
   `AmazonEC2ContainerRegistryReadOnly` attached).
6. If the pod needs outbound internet access (e.g., calling a third-party API), private
   subnet traffic routes out through the **NAT Gateway** sitting in the public subnet —
   the node itself has no public IP.
7. Throughout all of this, the **EKS control plane** — living outside your VPC in an
   AWS-managed account — is the source of truth: it's what the scheduler consults to
   decide which node a pod lands on, what `kube-proxy` watches to program iptables/IPVS
   rules, and what `kubectl get pods` is actually querying.

### Where each Terraform file fits in this architecture

- `vpc.tf` → the whole rectangle (VPC, public/private subnets, NAT Gateway, route tables)
- `eks.tf` → the control plane (top box) + the EC2 managed node group
- `alb-controller.tf` → the controller pod that creates/manages the ALB at the top
- `ecr.tf` → the image registry your nodes pull from
- `backend.tf` → not part of the runtime architecture at all — it's where Terraform's
  own state file lives (S3 + DynamoDB), completely separate from the EKS cluster itself

---

## Prerequisites — Install Tools (Linux — Rocky Linux / RHEL / CentOS)

Run these commands on **Rocky Linux** (also works on RHEL/AlmaLinux/CentOS Stream —
they all share `dnf`). Rocky ships `dnf` by default; `yum` is kept as an alias if you
prefer it.

```bash
sudo dnf update -y
sudo dnf install -y curl unzip tar gzip which git shadow-utils
```

### 1. AWS CLI v2

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
rm -rf awscliv2.zip aws/
```

### 2. Terraform (via HashiCorp's official `dnf` repo)

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo dnf install -y terraform
terraform -version
```

### 3. kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

### 4. Helm (used by Terraform's helm provider, and useful for manual debugging)

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### 5. eksctl (optional, handy for quick manual checks/debugging)

```bash
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version
```

### 6. Docker (to build and push images to ECR)

```bash
sudo dnf remove -y docker docker-client docker-client-latest docker-common \
  docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null

sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker $USER   # log out/in (or `newgrp docker`) for this to take effect
docker --version
```

### 7. SELinux note

Rocky Linux enforces SELinux by default. If Docker or other tools report
permission-denied errors on volume mounts, check `sudo sestatus` and either add
proper SELinux contexts (`chcon`) or, for local dev only, set the mode to
permissive:

```bash
sudo setenforce 0                 # temporary, until reboot
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config   # persistent
```

### 8. Firewall note

Rocky Linux runs `firewalld` by default. It doesn't block outbound calls to the AWS
API (which is all this project needs), so no changes are required unless you're also
running something locally (like a webhook receiver) that needs an inbound port opened:

```bash
sudo firewall-cmd --permanent --add-port=8080/tcp   # example only, if ever needed
sudo firewall-cmd --reload
```

---

## Step 1: Configure AWS CLI

```bash
aws configure
# AWS Access Key ID: <your key>
# AWS Secret Access Key: <your secret>
# Default region name: us-east-1
# Default output format: json

# Verify it works:
aws sts get-caller-identity
```

Your IAM user/role needs permissions for EKS, EC2, VPC, IAM, ECR, S3, and DynamoDB
(`AdministratorAccess` is simplest while learning; scope it down for production).

---

## Step 2: Create the Backend (S3) via AWS CLI

Terraform state must live somewhere durable and shared so your whole team (and CI/CD)
works off the same state file, with locking so two people can't `apply` at once.
**You must create this backend manually, once, before `terraform init`** — Terraform
can't create the S3 bucket it needs in order to store its own state.

```bash
# Set variables (customize the bucket name — it must be globally unique across all of AWS)
export AWS_REGION="us-east-1"
export BUCKET_NAME="my-eks-terraform-state-bucket-$(aws sts get-caller-identity --query Account --output text)"
export DYNAMODB_TABLE="terraform-locks"

# 1. Create the S3 bucket for state storage
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION"
# NOTE: for any region other than us-east-1 you must add:
# --create-bucket-configuration LocationConstraint=$AWS_REGION

# 2. Enable versioning (lets you recover/rollback previous state files)
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# 3. Enable default encryption at rest (AES256)
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

# 4. Block all public access to the state bucket (state files can contain secrets)
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 5. Wait until the table is active
echo "Bucket: $BUCKET_NAME"
```

Now open **`backend.tf`** and replace the placeholder `bucket` value with your real
`$BUCKET_NAME`.

---

## Step 3: Deploy the EKS Cluster

```bash
# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars   # set cluster_name, region, sizes, etc.

# Initialize (downloads providers/modules, connects to the S3 backend)
terraform init

# Review the plan
terraform plan

# Apply (this takes ~15-20 minutes — EKS control plane provisioning is slow)
terraform apply
```

---

## Step 4: Connect kubectl to the Cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name my-eks-cluster

# Verify
kubectl get nodes
kubectl get pods -A
```

---

## Step 5: Verify the AWS Load Balancer Controller

Terraform already installed it via Helm, but confirm it's healthy:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

To actually get an ALB provisioned, deploy an Ingress resource, e.g.:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: demo-service
                port:
                  number: 80
```

```bash
kubectl apply -f demo-ingress.yaml
kubectl get ingress demo-ingress   # ADDRESS column will show the ALB's public DNS name after ~2 min
```

---

## Step 6: Push an Image to ECR and Deploy It

```bash
# Get the repo URL from Terraform output
ECR_URL=$(terraform output -raw ecr_repository_url)

# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR_URL"

# Build, tag, and push
docker build -t my-app .
docker tag my-app:latest "$ECR_URL:latest"
docker push "$ECR_URL:latest"
```

Reference the image in a Kubernetes Deployment: `image: <ECR_URL>:latest`. Nodes pull it
automatically — the managed node group's IAM role already includes ECR read permissions.

---

## EKS Components Explained in Detail

### 1. Control Plane
The Kubernetes "brain": the API server, `etcd` (cluster state database), scheduler, and
controller-manager. **AWS fully manages and hosts this for you** — it runs in an
AWS-owned account, is automatically made highly available across multiple AZs, patched,
and upgraded (with your approval on version bumps). You never SSH into it or see its
underlying servers. You interact with it only through the Kubernetes API (`kubectl`,
Terraform's `kubernetes`/`helm` providers, etc.).

### 2. Data Plane (Worker Nodes)
The EC2 instances that actually run your containers. In this project they're an
**EKS Managed Node Group** (`eks.tf`) — AWS handles provisioning the EC2 instances,
joining them to the cluster, and rolling updates, but *you* own the underlying EC2
instances (you pay for them directly, and they show up in your EC2 console, and you
choose the instance types via `node_instance_types`). Pods are packed onto nodes by
the Kubernetes scheduler based on each pod's resource requests, so a single node
typically runs several pods — this "bin-packing" is what makes EC2 nodes cost-efficient
at scale compared to one-VM-per-pod models. An alternative not used in this project is
a **self-managed node group**, where you control the Auto Scaling Group and launch
template directly yourself for maximum flexibility at the cost of more operational
burden (you'd be responsible for wiring up the EKS bootstrap script, AMI selection,
and scaling logic by hand).

### 3. VPC and Networking
EKS nodes and pods need IP addresses from your VPC. The **VPC CNI plugin** (an EKS
add-on) assigns each pod a real IP address from your VPC's subnet ranges — this is why
pod density per node is limited by the number of ENI slots/IPs an instance type
supports, and why subnet sizing matters. Private subnets host nodes/pods (no direct
inbound internet access); public subnets host the NAT Gateway (outbound internet for
nodes) and the ALB (inbound internet for your app).

### 4. IAM & IRSA (IAM Roles for Service Accounts)
Kubernetes pods often need to call AWS APIs (e.g., read from S3, write to DynamoDB, or,
as in this project, create ALBs). Rather than giving every node broad IAM permissions
(which any pod on that node could then abuse), **IRSA** lets you attach an IAM role to
a specific Kubernetes ServiceAccount. EKS runs an **OIDC (OpenID Connect) identity
provider** tied to your cluster; pods using that ServiceAccount get temporary AWS
credentials scoped to exactly the IAM policy you attached — nothing more. This project
uses IRSA for the AWS Load Balancer Controller.

### 5. Add-ons
Small but critical pieces of cluster plumbing, managed as **EKS Add-ons** so AWS can
patch/version them for you:
- **CoreDNS** — in-cluster DNS, so pods can resolve service names like `my-service.default.svc.cluster.local`.
- **kube-proxy** — implements Kubernetes Service networking (routes traffic to the correct pod) on every node.
- **VPC CNI** — gives pods real VPC IP addresses (see above).
- **EBS CSI driver** — lets pods request persistent block storage (EBS volumes) via `PersistentVolumeClaim`.

### 6. Node Groups — Scaling
`min_size` / `max_size` / `desired_size` define an Auto Scaling Group behind the
scenes. Pairing this with the **Kubernetes Cluster Autoscaler** or **Karpenter** (not
included in this base project, but a common next step) lets the number of nodes grow
and shrink automatically based on pending pod resource requests.

### 7. Security Groups
EKS automatically creates a **cluster security group** shared by the control plane and
nodes for control-plane-to-node communication, plus node-level security groups for
you to layer on additional rules (e.g., allow ALB → node traffic on the app port).

---

## AWS Load Balancer Controller — Deep Dive

The **AWS Load Balancer Controller** is a Kubernetes controller (just a pod running in
your cluster, in the `kube-system` namespace) that watches the Kubernetes API for:

- **Ingress** objects with `ingress.class: alb` → provisions an **Application Load
  Balancer (ALB)** — Layer 7, HTTP/HTTPS routing, path/host-based rules, ideal for web apps and REST APIs.
- **Service** objects of `type: LoadBalancer` with the right annotation → provisions a
  **Network Load Balancer (NLB)** — Layer 4, ideal for raw TCP/UDP, extreme performance, static IPs.

**How it works end to end:**
1. You `kubectl apply` an Ingress resource.
2. The controller (running as a pod, using its IRSA-granted IAM role) calls the AWS
   ELBv2 API to create an ALB, target group(s), and listener rules matching your Ingress spec.
3. It registers your pod IPs (if `target-type: ip`) or node instance IDs (if
   `target-type: instance`) as ALB targets.
4. It continuously reconciles: if you scale pods up/down, add routing rules, or delete
   the Ingress, the controller updates or tears down the real AWS ALB to match.
5. The ALB's DNS name appears in `kubectl get ingress` under `ADDRESS` — point your
   domain's Route 53 record (a CNAME or an ALIAS record) at it.

**Why IRSA matters here:** the controller needs IAM permissions like
`elasticloadbalancing:CreateLoadBalancer`, `ec2:DescribeSubnets`, etc. This project
grants those permissions *only* to the specific `aws-load-balancer-controller`
ServiceAccount via the IAM role defined in `alb-controller.tf` — no other pod in the
cluster can use those permissions.

**Common annotations you'll use on Ingress objects:**
| Annotation | Purpose |
|---|---|
| `alb.ingress.kubernetes.io/scheme` | `internet-facing` or `internal` |
| `alb.ingress.kubernetes.io/target-type` | `ip` (route directly to pod IPs, recommended) or `instance` |
| `alb.ingress.kubernetes.io/certificate-arn` | ACM certificate ARN for HTTPS |
| `alb.ingress.kubernetes.io/listen-ports` | e.g. `'[{"HTTP": 80}, {"HTTPS": 443}]'` |
| `alb.ingress.kubernetes.io/healthcheck-path` | Custom health check path |

---

## What AWS Is Responsible For vs. What You Are Responsible For

EKS follows the AWS **Shared Responsibility Model**, adapted for managed Kubernetes:

### AWS is responsible for:
- Running, patching, and securing the **Kubernetes control plane** (API server, etcd, scheduler) — including its underlying host OS and hypervisor.
- **High availability of the control plane** across multiple AZs automatically.
- **etcd backups and control plane disaster recovery.**
- Making **control-plane Kubernetes version upgrades** available (you approve and trigger them, AWS performs the mechanics).
- The physical security and infrastructure of AWS data centers (hardware, networking backbone, power).
- Managing the lifecycle of **EKS Add-ons** you opt into (CoreDNS, kube-proxy, VPC CNI, EBS CSI) if configured for auto-update.
- Isolating each customer's control plane (you never share a control plane with another AWS account).

### You are responsible for:
- **Worker node OS patching** — even with managed node groups, you choose the AMI and trigger/approve updates; AWS builds the node, but you own its lifecycle.
- **Kubernetes application-layer security**: RBAC rules, Pod Security Standards, network policies, secrets management.
- **VPC design**: subnetting, route tables, NAT Gateways, security groups.
- **IAM configuration**: least-privilege roles for nodes, IRSA roles for pods, who can `kubectl` in via `aws-auth`/access entries.
- **Container image security**: what you build and push to ECR, scanning results, base image CVEs.
- **Application code and configuration**: your Deployments, Services, Ingress rules, ConfigMaps, Secrets.
- **Scaling decisions**: sizing node groups, configuring Cluster Autoscaler/Karpenter, setting pod resource requests/limits.
- **Cost management**: instance types, Spot vs On-Demand, right-sizing.
- **Data**: backups of anything stateful (EBS snapshots, database backups) — Kubernetes/EKS doesn't back up your application data for you.
- **Monitoring and logging**: enabling CloudWatch Container Insights, setting up alerts, log retention.

In short: **AWS guarantees the control plane exists, runs, and is reachable. You are
responsible for everything you put inside the cluster and how you've wired your AWS
account around it — including, with EC2 managed nodes, the OS running on those
instances.**

---

## Destroying Everything

```bash
# Delete Kubernetes-created AWS resources FIRST (e.g. any ALBs from Ingress objects) -
# Terraform doesn't know about resources the ALB controller created dynamically.
kubectl delete ingress --all -A
kubectl delete svc --all -A --field-selector spec.type=LoadBalancer

# Then destroy the Terraform-managed infrastructure
terraform destroy
```

If you also want to remove the backend itself (only after all team members are done with it):

```bash
aws s3 rb "s3://$BUCKET_NAME" --force
aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION"
```

---

## File Structure

```
eks-terraform-project/
├── backend.tf                 # S3 + DynamoDB remote state configuration
├── providers.tf                # AWS, Kubernetes, Helm, HTTP provider setup
├── variables.tf                 # All input variables
├── vpc.tf                        # VPC, public/private subnets, NAT Gateway
├── eks.tf                         # EKS cluster + managed node group + add-ons
├── ecr.tf                          # ECR repository + lifecycle policy
├── alb-controller.tf                # IRSA IAM role + Helm install of ALB controller
├── outputs.tf                        # Useful outputs (endpoints, ARNs, ECR URL...)
├── terraform.tfvars.example           # Copy to terraform.tfvars and customize
└── README.md                           # You are here
```

---

## Troubleshooting

- **`terraform init` fails to find the S3 bucket** → You skipped Step 2, or the bucket
  name in `backend.tf` doesn't match what you created.
- **`kubectl` gets "Unauthorized"** → Re-run `aws eks update-kubeconfig`, and confirm
  your IAM principal has an EKS access entry (or is in `aws-auth` ConfigMap for older clusters).
- **ALB never appears / Ingress ADDRESS stays empty** → Check controller logs
  (`kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller`).
  Common causes: subnets missing the `kubernetes.io/role/elb` tag, or the IRSA role
  missing permissions.
- **Nodes stuck in `NotReady`** → Usually a networking issue (VPC CNI can't assign
  IPs — subnet too small) or the node's IAM role is missing required managed policies.
- **`terraform apply` times out on EKS creation** → This is normal for the first
  apply; the control plane alone can take 10-15 minutes. Just let it run.
- **Nodes stuck `NotReady` or pods stuck `Pending`** → Check
  `kubectl describe node <node>` for resource pressure, and confirm the node group's
  `desired_size` is actually large enough for your workloads' combined resource
  requests. Also check the node IAM role has all four required managed policies
  attached (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`,
  `AmazonEC2ContainerRegistryReadOnly`, and SSM if you use it).
