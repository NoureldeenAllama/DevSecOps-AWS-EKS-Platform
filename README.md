# DevSecOps-AWS-EKS-Platform

**A production-grade, multi-service Java platform (VProfile) deployed on Amazon EKS with a fully automated, security-first CI/CD pipeline.**

![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.30-326CE5?style=flat-square&logo=kubernetes&logoColor=white)
![eksctl](https://img.shields.io/badge/eksctl-cluster%20provisioning-4285F4?style=flat-square)
![Docker](https://img.shields.io/badge/Docker-containers-2496ED?style=flat-square&logo=docker&logoColor=white)
![Java](https://img.shields.io/badge/Java-11-ED8B00?style=flat-square&logo=openjdk&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?style=flat-square&logo=githubactions&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-charts-0F1689?style=flat-square&logo=helm&logoColor=white)
![Vault](https://img.shields.io/badge/HashiCorp-Vault-000000?style=flat-square&logo=vault&logoColor=white)
![Trivy](https://img.shields.io/badge/Trivy-image%20scanning-1904DA?style=flat-square)
![Prometheus](https://img.shields.io/badge/Prometheus-monitoring-E6522C?style=flat-square&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-dashboards-F46800?style=flat-square&logo=grafana&logoColor=white)
![Velero](https://img.shields.io/badge/Velero-backup%20%2F%20DR-4C9CD6?style=flat-square)
![Region](https://img.shields.io/badge/region-eu--north--1-orange?style=flat-square)
![Status](https://img.shields.io/badge/status-capstone--complete-success?style=flat-square)

---

## Project Overview

VProfile is a 3-tier Java Spring application (Tomcat, MySQL, RabbitMQ, Memcached, Elasticsearch, nginx) that historically ran on flat, self-managed infrastructure with no image scanning, no centralized secrets, and no automated release path. This repository re-platforms it as a **microservices deployment on Amazon EKS**, closing four specific DevSecOps gaps in that original design:

- **Manual provisioning → declarative infrastructure.** The EKS control plane, node groups, and cluster add-ons are defined in a single `eksctl` manifest and provisioned as code, not clicked together in the console.
- **Unscanned images → gated registry.** Every container is pulled/built, scanned with **Trivy** for `HIGH`/`CRITICAL` CVEs, and only pushed to a private **Amazon ECR** repository if it passes.
- **Static credentials → dynamic secrets.** Database and broker credentials are never committed, never base64'd into a `Secret`, and never touch a GitHub Actions log — they're pulled from **HashiCorp Vault** at pod startup via the Agent Injector.
- **No release automation → path-based, OIDC-authenticated CI/CD.** GitHub Actions builds, quality-gates (SonarQube), scans, and deploys — using short-lived AWS credentials via **OIDC**, with zero long-lived access keys stored anywhere.

The result is a self-healing, observable, backed-up EKS platform with default-deny network segmentation between application tiers — built and owned across a 6-engineer team following a phased (P1–P9) delivery plan.

> Built as the capstone project for the **EFE (Education for Employment – Egypt) DevOps Engineering Scholarship**.

---

## Architecture & Workflow

<img width="1024" height="682" alt="image" src="https://github.com/user-attachments/assets/ac40e20f-8404-4b0d-a02a-b76ad41cf6e7" />


The platform follows a strict phase dependency chain — the cluster (**P1**) must exist before anything else can deploy; images, pipeline, and secrets (**P2 / P3 / P4**) build in parallel; deployment (**P5**) requires all three; everything downstream (**P6–P8**) layers on top of a running application; **Go-Live** (**P9**) requires every phase closed out.

````text
P1 EKS Cluster ──┐
P2 ECR + Trivy ───┼──► P5 Helm Deploy ──► P6 NetworkPolicy ──┐
P3 GitHub Actions ┤                    ──► P7 Monitoring ────┼──► P9 Go-Live
P4 Vault Secrets ─┘                    ──► P8 Velero Backup ─┘
````

**Request flow in production:** `Internet → Route 53 → AWS ALB (Ingress) → vproweb (nginx, tier:frontend) → app01 (Tomcat, tier:backend) → db01 / mc01 / rmq01 / vprosearch01 (tier:data)`, with Vault Agent sidecars injecting credentials into `app01` and NetworkPolicies enforcing that only the adjacent tier may talk to the next.

| Phase | Deliverable | Owner |
|---|---|---|
| **P1** | EKS cluster (3 workers, managed control plane) + LB Controller + EBS CSI | Infra / Cluster Lead |
| **P2** | 5 container images, Trivy-scanned, pushed to private ECR | Containers / Registry |
| **P3** | GitHub Actions pipeline, OIDC auth, SonarQube gate | CI/CD |
| **P4** | HashiCorp Vault, KV v2 secrets, Kubernetes auth | Security |
| **P5** | Helm chart, 6 templated workloads, ALB Ingress | App / Helm |
| **P6** | Default-deny NetworkPolicies, tier isolation | Security |
| **P7** | kube-prometheus-stack (Prometheus, Grafana, Alertmanager) | Observability / Backup |
| **P8** | Velero scheduled backups → S3, tested restore | Observability / Backup |
| **P9** | TLS (ACM), Route 53 → ALB, smoke tests, rollback plan | Full team |

---

## Tech Stack

| Category | Tools |
|---|---|
| **Infrastructure Provisioning** | `eksctl` (declarative `ClusterConfig`), AWS Console, `kubectl` — **no Terraform**; the control plane, VPC, and subnets are provisioned by `eksctl` across 3 AZs |
| **Container Orchestration** | Amazon EKS (managed control plane), managed node groups (`t3.medium`, 3–5 nodes, private networking) |
| **Container Registry / Build** | Docker, Amazon ECR (private), Trivy (CVE scanning, `HIGH,CRITICAL` gate) |
| **CI/CD** | GitHub Actions (hosted runners), OIDC federation to AWS (no static access keys), `dorny/paths-filter` for path-based conditional jobs |
| **Code Quality** | SonarQube / SonarCloud quality gate on every `src/**` change |
| **Packaging / Deployment** | Helm 3 (single chart, 6 templated microservices) |
| **Secrets Management** | HashiCorp Vault (KV v2), Vault Agent Injector, Kubernetes auth method |
| **Networking / Security** | Kubernetes `NetworkPolicy` (default-deny + explicit tier allows), AWS Load Balancer Controller (ALB Ingress, IRSA), ACM (TLS) |
| **Observability** | kube-prometheus-stack — Prometheus, Grafana, Alertmanager, `ServiceMonitor` |
| **Backup / Disaster Recovery** | Velero, Amazon S3, EBS volume snapshots, scheduled + on-demand backup/restore |
| **Application Runtime** | Java 11, Apache Tomcat, MySQL, RabbitMQ, Memcached, Elasticsearch 7.17, nginx |
| **DNS / TLS** | Route 53 (public), AWS Certificate Manager |

---

## Prerequisites

Install locally (or on a shared bastion/EC2) before deploying:

````bash
# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscli.zip
unzip awscli.zip && sudo ./aws/install

# eksctl
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# kubectl
curl -LO "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# docker + trivy (image builds and local scanning)
sudo apt-get install -y docker.io
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin

# velero CLI (backup/restore operations)
curl -sL https://github.com/vmware-tanzu/velero/releases/latest/download/velero-linux-amd64.tar.gz | tar xz
sudo mv velero-*/velero /usr/local/bin
````

AWS-side requirements:

- One AWS account, IAM users per engineer (never root), region pinned to `eu-north-1`.
- IAM permissions covering: EKS, EC2, ECR, IAM, S3, ELB, VPC.

````bash
aws configure                                  # access key / secret / eu-north-1 / json
aws sts get-caller-identity                    # confirm identity
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REGION=eu-north-1
export ECR=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
````

---

## Step-by-Step Deployment

<details>
<summary><strong>P1 — Cluster Provisioning (EKS via eksctl)</strong></summary>

`eksctl/cluster.yaml`:

````yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: vprofile-eks
  region: eu-north-1
  version: "1.30"
iam:
  withOIDC: true              # enables the OIDC provider (required for IRSA)
managedNodeGroups:
  - name: ng-workers
    instanceType: t3.medium
    desiredCapacity: 3
    minSize: 3
    maxSize: 5
    volumeSize: 30
    privateNetworking: true
    labels: { role: worker }
addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver
````

````bash
eksctl create cluster -f eksctl/cluster.yaml   # ~15-20 min: VPC + subnets across 3 AZs + control plane + nodes

aws eks update-kubeconfig --name vprofile-eks --region eu-north-1
kubectl get nodes                              # expect 3 nodes Ready
kubectl get pods -A                             # coredns / aws-node / kube-proxy running
````

Install the AWS Load Balancer Controller (required for ALB Ingress in P5):

````bash
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json

eksctl create iamserviceaccount --cluster vprofile-eks \
  --namespace kube-system --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=vprofile-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
````

**Definition of Done:** `kubectl get nodes` shows 3 `Ready` nodes, the LB Controller and EBS CSI driver are running, OIDC is enabled.

</details>

<details>
<summary><strong>P2 — Container Images, ECR & Trivy</strong></summary>

````bash
for r in vprofile-app vprofile-db vprofile-mc vprofile-rmq vprofile-web; do
  aws ecr create-repository --repository-name $r --region $REGION
done
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR
````

Pull, scan, and push the four pre-built service images:

````bash
for i in app db mc rmq; do
  docker pull alnaqib/vprofile-$i:1.0
  docker tag  alnaqib/vprofile-$i:1.0 $ECR/vprofile-$i:1.0

  trivy image --severity HIGH,CRITICAL --exit-code 1 $ECR/vprofile-$i:1.0

  docker push $ECR/vprofile-$i:1.0
done
````

Build the nginx frontend image:

````dockerfile
# docker/web/Dockerfile
FROM nginx:1.27-alpine
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/vproapp.conf
````

````bash
docker build -t $ECR/vprofile-web:1.0 docker/web/
trivy image --severity HIGH,CRITICAL --exit-code 0 $ECR/vprofile-web:1.0
docker push $ECR/vprofile-web:1.0
````

| Service | ECR Image | Source |
|---|---|---|
| app (Tomcat) | `$ECR/vprofile-app:1.0` | `alnaqib/vprofile-app` |
| db (MySQL) | `$ECR/vprofile-db:1.0` | `alnaqib/vprofile-db` |
| mc (Memcached) | `$ECR/vprofile-mc:1.0` | `alnaqib/vprofile-mc` |
| rmq (RabbitMQ) | `$ECR/vprofile-rmq:1.0` | `alnaqib/vprofile-rmq` |
| web (nginx) | `$ECR/vprofile-web:1.0` | `nginx:alpine` + custom conf |
| search (Elasticsearch) | `elasticsearch:7.17.0` | official image, used as-is |

**Definition of Done:** All 5 repos exist on ECR, populated and Trivy-scanned.

</details>

<details>
<summary><strong>P3 — CI/CD Pipeline (GitHub Actions + OIDC)</strong></summary>

AWS trusts GitHub via an OIDC identity provider (`IAM → Identity providers → Add provider → OpenID Connect`, provider URL `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`), backing a role scoped to this repo only:

````json
{
  "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
    "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:OWNER/DevSecOps-AWS-EKS-Platform:*" }
  }
}
````

Configure GitHub → `Settings → Secrets and variables → Actions`:

| Type | Name | Value |
|---|---|---|
| Variable | `AWS_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/github-actions-role` |
| Variable | `AWS_REGION` | `eu-north-1` |
| Variable | `ECR_REGISTRY` | `ACCOUNT_ID.dkr.ecr.eu-north-1.amazonaws.com` |
| Secret | `SONAR_TOKEN` | SonarCloud/SonarQube token |

No AWS access keys are stored — OIDC issues short-lived, per-run credentials.

`.github/workflows/ci-cd.yml` (conditional, path-filtered):

````yaml
name: vprofile-ci-cd
on: { push: { branches: [ main ] } }
permissions:
  id-token: write        # required for OIDC
  contents: read
env:
  AWS_REGION: eu-north-1
  ECR: ${{ vars.ECR_REGISTRY }}

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs: { src: '${{ steps.f.outputs.src }}', docker: '${{ steps.f.outputs.docker }}', helm: '${{ steps.f.outputs.helm }}' }
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: f
        with:
          filters: |
            src:    'src/**'
            docker: [ 'src/**', 'docker/**' ]
            helm:   [ 'src/**', 'helm/**' ]

  build:
    needs: changes
    if: needs.changes.outputs.src == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '11' }
      - run: mvn -B clean package
      - run: mvn sonar:sonar -Dsonar.login=${{ secrets.SONAR_TOKEN }}

  docker:
    needs: changes
    if: needs.changes.outputs.docker == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with: { role-to-assume: '${{ vars.AWS_ROLE_ARN }}', aws-region: '${{ env.AWS_REGION }}' }
      - uses: aws-actions/amazon-ecr-login@v2
      - run: docker build -t $ECR/vprofile-app:${{ github.run_number }} -f docker/app/Dockerfile .
      - uses: aquasecurity/trivy-action@master
        with: { image-ref: '${{ env.ECR }}/vprofile-app:${{ github.run_number }}', severity: 'HIGH,CRITICAL', exit-code: '1' }
      - run: docker push $ECR/vprofile-app:${{ github.run_number }}

  deploy:
    needs: [ changes, docker ]
    if: needs.changes.outputs.helm == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with: { role-to-assume: '${{ vars.AWS_ROLE_ARN }}', aws-region: '${{ env.AWS_REGION }}' }
      - uses: azure/setup-helm@v4
      - run: |
          aws eks update-kubeconfig --name vprofile-eks --region $AWS_REGION
          helm upgrade --install vprofile ./helm/vprofile -n vprofile --create-namespace \
            --set app.image.tag=${{ github.run_number }}
````

| Change detected in | Jobs triggered |
|---|---|
| `src/**` | `build` (+Sonar) → `docker` (+Trivy+push) → `deploy` |
| `docker/**` | `docker` → `deploy` (build/Sonar skipped) |
| `helm/**` | `deploy` only (`helm upgrade`) |

**Definition of Done:** A push to `main` triggers the workflow, jobs run under the correct conditions, OIDC authenticates without static keys, and the image reaches ECR followed by a successful `helm upgrade`.

</details>

<details>
<summary><strong>P4 — Secrets Management (HashiCorp Vault)</strong></summary>

````bash
helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update
helm install vault hashicorp/vault -n vault --create-namespace \
  --set "injector.enabled=true"
kubectl -n vault get pods    # vault-0 + vault-agent-injector
````

> Installed in **dev mode** (auto-unseal) for this lab build. Production Vault requires manual `init` + `unseal` with the unseal keys stored outside the cluster — see [Known Limitations](#known-limitations--production-hardening).

Enable the KV v2 secrets engine and store credentials:

````bash
kubectl -n vault exec -it vault-0 -- sh

vault secrets enable -path=secret kv-v2
vault kv put secret/vprofile/db  password="vprodbpass" username="root"
vault kv put secret/vprofile/rmq username="guest"      password="guest"
````

Enable Kubernetes auth and scope a read-only policy to the app's service account:

````bash
vault auth enable kubernetes
vault write auth/kubernetes/config \
   kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

vault policy write vprofile - <<EOF
path "secret/data/vprofile/*" { capabilities = ["read"] }
EOF

vault write auth/kubernetes/role/vprofile \
   bound_service_account_names=vprofile-app \
   bound_service_account_namespaces=vprofile \
   policies=vprofile ttl=1h
````

Secrets are injected into the app pod at `/vault/secrets/db` via annotations on the Helm deployment template (see P5).

**Definition of Done:** Secrets exist in Vault; the app's ServiceAccount is bound to the `vprofile` policy.

</details>

<details>
<summary><strong>P5 — Helm Chart & Microservices Deployment</strong></summary>

Service names are a **fixed contract** — the app's `application.properties` resolves these hostnames via DNS, so renaming any of them breaks connectivity:

| Tier | Service Name | Port |
|---|---|---|
| Data (MySQL) | `db01` | 3306 |
| Data (Memcached) | `mc01` | 11211 |
| Data (RabbitMQ) | `rmq01` | 5672 |
| Data (Elasticsearch) | `vprosearch01` | 9300 |
| Backend (Tomcat) | `app01` | 8080 |
| Frontend (nginx) | `vproweb` | 80 |

````text
helm/vprofile/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _namespace.yaml
    ├── web-configmap.yaml         # nginx.conf
    ├── web-deploy.yaml            # frontend (nginx)
    ├── web-svc.yaml               # vproweb
    ├── app-deploy.yaml            # backend (Tomcat) + Vault annotations
    ├── app-svc.yaml                # app01
    ├── db-statefulset.yaml        # MySQL + PVC
    ├── db-svc.yaml                 # db01
    ├── mc-deploy.yaml + mc-svc.yaml       # mc01
    ├── rmq-statefulset.yaml + rmq-svc.yaml # rmq01
    ├── es-statefulset.yaml + es-svc.yaml   # vprosearch01
    ├── ingress.yaml                # ALB
    ├── servicemonitor.yaml         # Prometheus (P7)
    └── networkpolicies.yaml        # tier isolation (P6)
````

Backend deployment with Vault injection (`templates/app-deploy.yaml`):

````yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: app01, namespace: {{ .Values.namespace }} }
spec:
  replicas: {{ .Values.app.replicas }}
  selector: { matchLabels: { app: app01 } }
  template:
    metadata:
      labels: { app: app01, tier: backend }          # required for NetworkPolicy
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "vprofile"
        vault.hashicorp.com/agent-inject-secret-db: "secret/data/vprofile/db"
    spec:
      serviceAccountName: vprofile-app
      containers:
        - name: app01
          image: "{{ .Values.ecr }}/{{ .Values.app.image.repo }}:{{ .Values.app.image.tag }}"
          ports: [{ containerPort: 8080 }]
          readinessProbe: { httpGet: { path: /login, port: 8080 } }   # root "/" 302s under Spring Security
````

Deploy:

````bash
helm upgrade --install vprofile ./helm/vprofile -n vprofile --create-namespace
kubectl -n vprofile get pods,svc,ingress          # wait for ADDRESS on the ingress (ALB DNS)
````

**Definition of Done:** All pods `Running`, services carry the exact required names, ALB is provisioned, and the app reaches its backing services.

</details>

<details>
<summary><strong>P6 — Network Policies (Tier Isolation)</strong></summary>

Default-deny baseline, then explicit tier-to-tier allows:

````yaml
# templates/networkpolicies.yaml — default-deny
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: vprofile }
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
````

````yaml
# Allow: Ingress → Frontend (:80)
kind: NetworkPolicy
metadata: { name: allow-ingress-to-web, namespace: vprofile }
spec:
  podSelector: { matchLabels: { tier: frontend } }
  ingress:
    - from: [{ namespaceSelector: { matchLabels: { name: ingress-nginx } } }]
      ports: [{ port: 80 }]
````

````yaml
# Allow: Frontend → Backend (:8080)
kind: NetworkPolicy
metadata: { name: allow-web-to-app, namespace: vprofile }
spec:
  podSelector: { matchLabels: { tier: backend } }
  ingress:
    - from: [{ podSelector: { matchLabels: { tier: frontend } } }]
      ports: [{ port: 8080 }]
````

````yaml
# Allow: Backend → Data + DNS
kind: NetworkPolicy
metadata: { name: allow-app-to-data, namespace: vprofile }
spec:
  podSelector: { matchLabels: { tier: backend } }
  policyTypes: [Egress]
  egress:
    - to: [{ podSelector: { matchLabels: { tier: data } } }]
      ports: [{ port: 3306 },{ port: 11211 },{ port: 5672 },{ port: 9300 }]
    - to: [{ namespaceSelector: {} }]          # DNS (kube-dns)
      ports: [{ port: 53, protocol: UDP }]
````

**Test:** from a frontend pod, `nc -zv db01 3306` must **fail**; from a backend pod, the same command must **succeed**.

**Definition of Done:** Direct Ingress → Backend/Data traffic is blocked; only the declared paths are allowed.

</details>

<details>
<summary><strong>P7 — Monitoring (kube-prometheus-stack)</strong></summary>

````bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set grafana.ingress.enabled=true \
  --set prometheus.prometheusSpec.retention=15d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi
````

`templates/servicemonitor.yaml` — scrape the VProfile app:

````yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vprofile-app
  namespace: monitoring
  labels: { release: monitoring }
spec:
  namespaceSelector: { matchNames: [vprofile] }
  selector: { matchLabels: { app: app01 } }
  endpoints: [{ port: web, interval: 30s }]
````

````bash
kubectl -n monitoring get secret monitoring-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
# Import dashboards by ID: 315 (K8s cluster), 1860 (Node Exporter)
````

**Definition of Done:** Prometheus scrapes nodes and the app, Grafana renders dashboards, and at least one Alertmanager rule is active.

</details>

<details>
<summary><strong>P8 — Backup / Disaster Recovery (Velero → S3)</strong></summary>

````bash
aws s3 mb s3://vprofile-velero-backups --region eu-north-1

eksctl create iamserviceaccount --cluster vprofile-eks \
  --namespace velero --name velero \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/VeleroS3Policy --approve

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket vprofile-velero-backups \
  --backup-location-config region=eu-north-1 \
  --snapshot-location-config region=eu-north-1 \
  --service-account-name velero --no-secret
````

````bash
# Daily backup at 02:00, 7-day retention
velero schedule create vprofile-daily \
  --schedule="0 2 * * *" --include-namespaces vprofile --ttl 168h0m0s

# On-demand backup
velero backup create vprofile-now --include-namespaces vprofile

# Restore
velero restore create --from-backup vprofile-now
````

**Definition of Done:** Backups land in S3 on schedule, and a namespace restore has been tested end-to-end.

</details>

<details>
<summary><strong>P9 — Go-Live & Validation</strong></summary>

````bash
# TLS — request an ACM certificate for your domain, validate via DNS, then:
helm upgrade vprofile ./helm/vprofile -n vprofile --set ingress.certArn=<ACM_ARN>

# DNS — point Route 53 at the ALB
kubectl -n vprofile get ingress vprofile-ingress    # grab the ALB DNS from ADDRESS
# Route 53: create an Alias (A) record → ALB DNS

# Smoke tests
curl -I https://vprofile.example.com/login          # expect 200 OK
kubectl -n vprofile get pods                          # all Running/Ready
kubectl -n vprofile logs deploy/app01 | tail          # no DB/RMQ errors
````

Rollback path if validation fails:

````bash
helm history vprofile -n vprofile
helm rollback vprofile <REVISION> -n vprofile
# Worst case: velero restore from the last known-good backup
````

**Definition of Done:** Domain resolves over HTTPS, login succeeds, and all backing services (DB / cache / MQ / search) are reachable.

</details>

---

## Security & Disaster Recovery

### HashiCorp Vault — Secrets Management

Plain Kubernetes `Secret` objects are **base64-encoded, not encrypted** — anyone with cluster read access can recover the plaintext with `base64 -d`. This platform stores every credential in Vault's **KV v2** engine instead:

- Secrets never appear in Helm values, manifests, or CI/CD logs.
- The `vprofile-app` ServiceAccount authenticates to Vault via the **Kubernetes auth method**, scoped by namespace and a read-only policy on `secret/data/vprofile/*`.
- The **Vault Agent Injector** mounts secrets as files inside the pod (e.g. `/vault/secrets/db`) at startup — no application code changes required to consume them.
- Leases are time-boxed (`ttl=1h`), limiting the blast radius of a compromised token.

### Velero — Backup & Disaster Recovery

- Both Kubernetes object state and EBS volume snapshots are captured to **Amazon S3** on a schedule, authenticated via **IRSA** (no static AWS keys for the backup agent either).
- Backups run on a **daily cron** with a 7-day retention window, plus on-demand backups before risky changes.
- Restore is a single command (`velero restore create --from-backup <name>`) and is treated as the documented worst-case rollback path — validated during P8, not just assumed to work.

### Defense in Depth

- **Trivy** gates every image at build time — `HIGH`/`CRITICAL` CVEs block the push to ECR (in production; lab runs may relax `--exit-code` — see below).
- **NetworkPolicies** enforce default-deny with explicit tier-to-tier allows, so a compromised frontend pod cannot reach the data tier directly.
- **OIDC federation** means the CI/CD pipeline never holds long-lived AWS credentials.
- **SonarQube** blocks merges below the quality gate threshold, catching vulnerabilities and code smells before they reach a container image.

---

## Repository Structure

````text
DevSecOps-AWS-EKS-Platform/
├── src/                          # VProfile application source
├── docker/                       # Dockerfiles per service
│   ├── app/Dockerfile
│   └── web/{Dockerfile, nginx.conf}
├── helm/
│   └── vprofile/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/            # all Kubernetes manifests (Deployments, StatefulSets,
│                                  # Services, Ingress, NetworkPolicies, ServiceMonitor)
├── k8s/                          # standalone NetworkPolicies / ServiceMonitors (if not chart-embedded)
├── eksctl/
│   └── cluster.yaml               # declarative EKS cluster definition
└── .github/
    └── workflows/
        └── ci-cd.yml               # path-based, OIDC-authenticated pipeline
````

---

## Known Limitations & Production Hardening

Documented deliberately rather than glossed over — these are the gaps between "capstone-complete" and "production-ready":

- **Vault is installed in dev mode** (auto-unseal). Production requires manual `vault operator init` + `unseal`, with unseal keys distributed and stored outside the cluster (e.g. AWS KMS auto-unseal).
- **Trivy's `--exit-code`** was relaxed to `0` for the nginx image during the lab build to avoid blocking on base-image CVEs; production should enforce `1` uniformly and patch the base image instead.
- **Elasticsearch runs a single StatefulSet replica** — no cluster quorum, acceptable for a lab environment but a single point of failure in production.
- **Trivy scan results are consumed via CI logs**, not exported to a central vulnerability dashboard — worth wiring into GitHub's Security tab (SARIF upload) for longer-term tracking.

---

## Acknowledgments

Delivered as the final capstone project of the **EFE DevOps Engineering Scholarship**, by a team of 6 engineers working across Infrastructure, Containers, CI/CD, Application/Helm, Security, and Observability domains under a formal RACI ownership model — supervised by **Eng. Gamal Mohamed** and **Eng. Abdelrahman Ahmed**.
````
````
