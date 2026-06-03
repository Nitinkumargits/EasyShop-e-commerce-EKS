# 📘 EasyShop — Project Guide

> A practical, end-to-end walkthrough of the **EasyShop 3-Tier Production-Ready DevOps Project on AWS EKS**.
> This guide explains _what_ the project is, _how_ every piece fits together, and _the exact order_ in which things are built and deployed.

---

## 1. What This Project Is

EasyShop is a **full-stack e-commerce web application** (Next.js + MongoDB) that is packaged, provisioned, deployed, monitored, and logged using a **complete production-grade DevOps toolchain on AWS**.

There are really **two projects in one repo**:

| Layer            | What it is                             | Key tech                                                             |
| ---------------- | -------------------------------------- | -------------------------------------------------------------------- |
| **The App**      | A 3-tier e-commerce site               | Next.js 14, TypeScript, MongoDB, Redux, Tailwind                     |
| **The Platform** | The infra + pipelines that run the app | Terraform, AWS EKS, Docker, Jenkins, ArgoCD, Prometheus/Grafana, ELK |

The "3-Tier" in the name refers to the **application architecture** (Presentation → Application → Data), while the bulk of the engineering value here is the **DevOps platform** around it.

---

## 2. The Application (3-Tier Architecture)

```
┌──────────────────────────────────────────────────────────┐
│ 1. PRESENTATION TIER  (Frontend)                          │
│    Next.js React components · Redux store · Tailwind CSS  │
└───────────────────────────┬──────────────────────────────┘
                            │ HTTP
┌───────────────────────────▼──────────────────────────────┐
│ 2. APPLICATION TIER  (Backend)                            │
│    Next.js API routes · Auth middleware · Business logic  │
└───────────────────────────┬──────────────────────────────┘
                            │ Mongoose ODM
┌───────────────────────────▼──────────────────────────────┐
│ 3. DATA TIER  (Database)                                  │
│    MongoDB · Mongoose models · CRUD                       │
└──────────────────────────────────────────────────────────┘
```

**Source layout** ([src/](src/)):

| Path                                               | Purpose                                                                                                      |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| [src/app/](src/app/)                               | Next.js App Router — pages + API routes (`api/`, `products/`, `checkout/`, `(auth)/`, `profile/`, `orders/`) |
| [src/components/](src/components/)                 | Reusable React UI components                                                                                 |
| [src/lib/](src/lib/)                               | Auth logic, DB config, Redux feature slices                                                                  |
| [src/middleware.ts](src/middleware.ts)             | Request/auth middleware                                                                                      |
| [src/types/](src/types/)                           | TypeScript type definitions                                                                                  |
| [scripts/migrate-data.ts](scripts/migrate-data.ts) | Seeds MongoDB with initial product data                                                                      |

Key dependencies (from [package.json](package.json)): `next@14.1.0`, `mongoose`, `next-auth`, `@reduxjs/toolkit`, `jsonwebtoken`, `bcryptjs`, `zod`, `tailwindcss`.

---

## 3. The DevOps Platform — Big Picture

```
 Developer push
      │
      ▼
 ┌─────────┐  webhook   ┌──────────────┐   build+scan+push   ┌────────────┐
 │ GitHub  │ ─────────► │   Jenkins    │ ──────────────────► │ Docker Hub │
 └─────────┘            │  (CI)        │                     └────────────┘
                        └──────┬───────┘
                               │ updates image tag in k8s manifests (git commit)
                               ▼
                        ┌──────────────┐    syncs manifests    ┌──────────────┐
                        │   GitHub     │ ◄──── watches ─────── │   ArgoCD     │ (CD / GitOps)
                        │  (manifests) │                       └──────┬───────┘
                        └──────────────┘                              │ kubectl apply
                                                                      ▼
   ┌──────────────────────── AWS EKS Cluster ──────────────────────────────────┐
   │  easyshop pods (x2) + HPA   ·   MongoDB StatefulSet   ·   migration Job     │
   │  ALB Ingress Controller → ALB → easyshop.nitinkdevs.com                     │
   │  Monitoring: kube-prometheus-stack (Prometheus + Grafana + Alertmanager)    │
   │  Logging:    Elasticsearch + Filebeat (DaemonSet) + Kibana                  │
   └─────────────────────────────────────────────────────────────────────────────┘
            ▲ provisioned by Terraform (VPC, EKS, Bastion, addons)
```

---

## 4. Infrastructure as Code — Terraform

Located in [terraform/](terraform/). Provisions the entire AWS foundation.

**State backend** ([terraform/terraform.tf](terraform/terraform.tf)): S3 bucket `terraform-s3-backend-tws-hackathon` with native state locking (`use_lockfile`).

| File                                                                                                              | Provisions                                                                                                                                            |
| ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| [terraform/vpc.tf](terraform/vpc.tf)                                                                              | VPC with public + private subnets, single NAT gateway, ELB subnet tags                                                                                |
| [terraform/eks.tf](terraform/eks.tf)                                                                              | EKS cluster `tws-eks-cluster` (v1.31), **private endpoint**, SPOT `t3.large` managed node group (min 1 / max 3), addons: CoreDNS, kube-proxy, VPC-CNI |
| [terraform/bastion_ec2.tf](terraform/bastion_ec2.tf)                                                              | Bastion host in public subnet (since the EKS API is private-only, you reach the cluster through this)                                                 |
| [terraform/ec2.tf](terraform/ec2.tf)                                                                              | Additional EC2 (e.g. Jenkins host)                                                                                                                    |
| [terraform/bastion_user_data.sh](terraform/bastion_user_data.sh) / [install_tools.sh](terraform/install_tools.sh) | Bootstrap tooling (kubectl, aws-cli, helm, etc.)                                                                                                      |
| [terraform/outputs.tf](terraform/outputs.tf)                                                                      | Cluster name, endpoints, IPs                                                                                                                          |

**Cluster add-ons via Terraform** ([terraform/apps/](terraform/apps/)) — an alternative to installing by hand:

- [alb_controller.tf](terraform/apps/alb_controller.tf) — AWS Load Balancer Controller
- [ebs_csi_driver.tf](terraform/apps/ebs_csi_driver.tf) — EBS CSI driver (needed for Elasticsearch volumes)
- [argocd.tf](terraform/apps/argocd.tf) — ArgoCD
- [kube-prom-stack.tf](terraform/apps/kube-prom-stack.tf) — Prometheus/Grafana stack
- [storageclass.tf](terraform/apps/storageclass.tf) — default EBS StorageClass

> ⚠️ **Region note:** `variables.tf` defaults to `ap-south-1`, the README's `update-kubeconfig` examples use `ap-south-1`, and the Ingress cert ARN is in `ap-south-1`. Pick **one** region and make these consistent before applying.

---

## 5. Containerization — Docker

| File                                                         | Role                                                                                                                       |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| [Dockerfile](Dockerfile)                                     | **Multi-stage** build: `node:18-alpine` builder → slim `runner` running Next.js standalone (`node server.js`) on port 3000 |
| [scripts/Dockerfile.migration](scripts/Dockerfile.migration) | Builds the DB migration/seed image                                                                                         |
| [docker-compose.yml](docker-compose.yml)                     | Local dev stack: `mongodb` → `migration` (runs once) → `app`, wired with healthchecks + dependency ordering                |

**Run locally with Docker:**

```bash
# create .env.local first (see README "Step 1: Environment Setup")
docker compose up -d
docker compose logs -f
# visit http://localhost:3000
```

---

## 6. Continuous Integration — Jenkins

Pipeline defined in [Jenkinsfile](Jenkinsfile); setup steps in [JENKINS.md](JENKINS.md).

**Pipeline stages:**

1. **Cleanup Workspace** — `clean_ws()`
2. **Clone Repository** — pulls `master`
3. **Build Docker Images** (parallel) — main app image + migration image
4. **Run Unit Tests** — `run_tests()`
5. **Security Scan** — `trivy_scan()` (image vulnerability scanning)
6. **Push Docker Images** (parallel) — pushes both to Docker Hub
7. **Update Kubernetes Manifests** — bumps the image tag in [kubernetes/](kubernetes/) and **commits back to git** → this is what triggers ArgoCD

The pipeline relies on a **Jenkins Shared Library** (`@Library('Shared')`) providing `clean_ws`, `clone`, `docker_build`, `run_tests`, `trivy_scan`, `docker_push`, `update_k8s_manifests`.

> 🔧 **Before running:** update `DOCKER_IMAGE_NAME` / `DOCKER_MIGRATION_IMAGE_NAME` in the Jenkinsfile and the repo URLs to your own Docker Hub + GitHub accounts. Configure `github-credentials` and `docker-hub-credentials` in Jenkins.

---

## 7. Kubernetes Manifests

In [kubernetes/](kubernetes/) — numbered so they apply in order:

| File                                                                                                                                  | Resource                                                                                            |
| ------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| [01-namespace.yaml](kubernetes/01-namespace.yaml)                                                                                     | `easyshop` namespace                                                                                |
| [02-mongodb-pv.yaml](kubernetes/02-mongodb-pv.yaml) / [03-mongodb-pvc.yaml](kubernetes/03-mongodb-pvc.yaml)                           | MongoDB persistent storage                                                                          |
| [04-configmap.yaml](kubernetes/04-configmap.yaml)                                                                                     | Non-secret env (`NEXTAUTH_URL`, API URL, Mongo URI)                                                 |
| [05-secrets.yaml](kubernetes/05-secrets.yaml)                                                                                         | `NEXTAUTH_SECRET`, `JWT_SECRET`                                                                     |
| [06-mongodb-service.yaml](kubernetes/06-mongodb-service.yaml) / [07-mongodb-statefulset.yaml](kubernetes/07-mongodb-statefulset.yaml) | MongoDB (StatefulSet + headless service)                                                            |
| [08-easyshop-deployment.yaml](kubernetes/08-easyshop-deployment.yaml)                                                                 | App Deployment — **2 replicas**, startup/readiness/liveness probes on `/`, resource requests/limits |
| [09-easyshop-service.yaml](kubernetes/09-easyshop-service.yaml)                                                                       | App Service (port 80 → 3000)                                                                        |
| [10-ingress.yaml](kubernetes/10-ingress.yaml)                                                                                         | ALB Ingress → `easyshop.nitinkdevs.com` (HTTP→HTTPS redirect, ACM cert)                             |
| [11-hpa.yaml](kubernetes/11-hpa.yaml)                                                                                                 | Horizontal Pod Autoscaler (needs metrics-server)                                                    |
| [12-migration-job.yaml](kubernetes/12-migration-job.yaml)                                                                             | One-off DB seed Job                                                                                 |

> 🔧 Update the image (`nitinkdocker18/easyshop-app`), the Ingress `host`, and the `certificate-arn` to your own values before deploying.

---

## 8. Continuous Deployment — ArgoCD (GitOps)

ArgoCD watches the `kubernetes/` path in the git repo. When Jenkins commits a new image tag, ArgoCD **automatically syncs** the change to the cluster.

**Setup summary** (full steps in [README.md](README.md)):

1. `kubectl create namespace argocd`
2. `helm install my-argo-cd argo/argo-cd` then customize values ([helm-values/argocd-values.yaml](helm-values/argocd-values.yaml)) for ALB ingress on `argocd.nitinkdevs.com`
3. Add a Route53 record → ALB DNS
4. Retrieve admin password from the `argocd-initial-admin-secret`
5. Create an App: Source = repo `kubernetes/` path, Destination = `https://kubernetes.default.svc` / namespace `easyshop`, Sync = **Automatic**

---

## 9. Observability

### Monitoring — kube-prometheus-stack

- Namespace `monitoring`, installed via Helm; values in [helm-values/kube-prom-stack.yaml](helm-values/kube-prom-stack.yaml)
- Exposes **Grafana**, **Prometheus**, **Alertmanager** behind ALB ingress (`grafana.` / `prometheus.` / `alertmanager.nitinkdevs.com`)
- **Alerting to Slack**: Alertmanager routes `severity=critical` alerts to a Slack incoming webhook (`#alerts` channel)
- Requires **metrics-server** (also powers the HPA)

### Logging — ELK + Filebeat

- Namespace `logging`; uses the **EBS CSI driver + a default StorageClass** ([helm-values/storageclass.yaml](helm-values/storageclass.yaml)) so Elasticsearch can dynamically provision EBS volumes
- **Elasticsearch** — log store ([helm-values/elasticsearch.yaml](helm-values/elasticsearch.yaml))
- **Filebeat** — DaemonSet shipping container logs ([helm-values/filebeat.yaml](helm-values/filebeat.yaml)); configured to tail `/var/log/containers/*easyshop*.log`
- **Kibana** — visualization behind ALB (`logs-kibana.nitinkdevs.com`) ([helm-values/kibana.yaml](helm-values/kibana.yaml))

---

## 10. End-to-End Deployment Order (Cheat Sheet)

1. **Provision infra** — `terraform init && terraform apply` in [terraform/](terraform/) → VPC, EKS, Bastion
2. **Connect** — SSH to Bastion, `aws configure`, then `aws eks update-kubeconfig --region <region> --name tws-eks-cluster`; verify `kubectl get nodes`
3. **Cluster add-ons** — install **AWS Load Balancer Controller** + **EBS CSI driver** (Helm or [terraform/apps/](terraform/apps/))
4. **Set up Jenkins** — install plugins, add Docker/GitHub credentials, configure the Shared Library, create the pipeline ([JENKINS.md](JENKINS.md))
5. **CI run** — push code → Jenkins builds, scans (Trivy), pushes images, and commits new tags to `kubernetes/`
6. **Install ArgoCD** — point it at the repo's `kubernetes/` path with Automatic sync → app deploys (incl. MongoDB + migration Job)
7. **DNS** — add Route53 records mapping each hostname to the ALB DNS name
8. **metrics-server** — install (enables HPA + `kubectl top`)
9. **Monitoring** — install kube-prometheus-stack, wire Slack alerts
10. **Logging** — install Elasticsearch → Filebeat → Kibana; confirm `*easyshop*` logs stream into Kibana

---

## 11. Quick Reference — Where Things Live

| I want to…                               | Look at                                                                                |
| ---------------------------------------- | -------------------------------------------------------------------------------------- |
| Run the app locally                      | [docker-compose.yml](docker-compose.yml), [README.md](README.md) §Getting Started      |
| Change the app image build               | [Dockerfile](Dockerfile)                                                               |
| Edit the CI pipeline                     | [Jenkinsfile](Jenkinsfile), [JENKINS.md](JENKINS.md)                                   |
| Change cluster size / region / node type | [terraform/eks.tf](terraform/eks.tf), [terraform/variables.tf](terraform/variables.tf) |
| Change app replicas / probes / resources | [kubernetes/08-easyshop-deployment.yaml](kubernetes/08-easyshop-deployment.yaml)       |
| Change the public domain / TLS cert      | [kubernetes/10-ingress.yaml](kubernetes/10-ingress.yaml)                               |
| Tune Grafana/Prometheus/alerts           | [helm-values/kube-prom-stack.yaml](helm-values/kube-prom-stack.yaml)                   |
| Tune logging                             | [helm-values/](helm-values/) (elasticsearch/filebeat/kibana)                           |
| Full setup walkthrough w/ screenshots    | [README.md](README.md)                                                                 |

---

## 12. Things to Customize Before You Deploy

- [ ] **AWS region** — make `terraform/variables.tf`, kubeconfig commands, and ACM cert ARNs all agree
- [ ] **Docker Hub repo names** — [Jenkinsfile](Jenkinsfile) + [kubernetes/08-easyshop-deployment.yaml](kubernetes/08-easyshop-deployment.yaml)
- [ ] **Git repo URLs** — Jenkinsfile clone + shared-library + ArgoCD source
- [ ] **Domain names** — every Ingress `host` and the matching Route53 records
- [ ] **ACM certificate ARN** — Ingress annotations
- [ ] **Secrets** — generate real `NEXTAUTH_SECRET` / `JWT_SECRET` (`openssl rand`), don't commit them
- [ ] **Terraform S3 backend** — point to a bucket you own ([terraform/terraform.tf](terraform/terraform.tf))

---

_Generated as a navigation/onboarding guide. For the detailed step-by-step commands and screenshots, see [README.md](README.md)._
