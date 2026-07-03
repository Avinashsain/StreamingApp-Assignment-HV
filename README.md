# StreamingApp — Orchestration & Scaling on AWS

> **Graded Project:** End-to-end DevOps pipeline for a MERN microservices streaming platform
> **Author:** Avinash Sain · **Fork of:** [UnpredictablePrashant/StreamingApp](https://github.com/UnpredictablePrashant/StreamingApp)

A collaborative video streaming platform (React + 4 Node.js microservices + MongoDB) deployed with a fully automated CI/CD pipeline:

**GitHub → Jenkins (webhook via ngrok) → Docker → Amazon ECR → Helm → Amazon EKS → CloudWatch → SNS ChatOps**

---

## Table of Contents

1. [Architecture](#architecture)
2. [Tech Stack](#tech-stack)
3. [Microservices](#microservices)
4. [Repository Structure](#repository-structure)
5. [Phase 1 — Version Control](#phase-1--version-control-with-git)
6. [Phase 2 — Local Setup & Containerization](#phase-2--local-setup--containerization)
7. [Phase 3 — AWS Environment (ECR + S3)](#phase-3--aws-environment-ecr--s3)
8. [Phase 4 — CI with Jenkins + ngrok](#phase-4--ci-with-jenkins--ngrok-webhook)
9. [Phase 5 — EKS Deployment via Helm](#phase-5--kubernetes-deployment-eks--helm)
10. [Phase 6 — Monitoring & Logging (CloudWatch)](#phase-6--monitoring--logging-cloudwatch)
11. [Phase 7 — ChatOps (SNS)](#phase-7--chatops-sns-notifications-bonus)
12. [Final Validation](#final-validation)
13. [Troubleshooting Journal](#troubleshooting-journal-real-issues-i-solved)
14. [Scaling & Self-Healing](#scaling--self-healing)
15. [Cost Management & Teardown](#cost-management--teardown)

---

## Architecture

```mermaid
flowchart LR
  Dev[Developer] -->|git push| GH[GitHub Fork]
  GH -->|webhook via ngrok| J[Jenkins - local]
  J -->|build & push 5 images<br/>linux/amd64| ECR[(Amazon ECR<br/>us-east-1)]
  J -->|helm upgrade| EKS[Amazon EKS<br/>streamingapp-eks]
  subgraph EKS Cluster - 2x t3.medium
    FE[frontend :80]
    AU[auth :3001]
    ST[streaming :3002]
    AD[admin :3003]
    CH[chat :3004]
    M[(MongoDB<br/>StatefulSet + EBS)]
    AU & ST & AD & CH --> M
  end
  ST --> S3[(S3 media bucket<br/>us-west-2)]
  AD --> S3
  EKS --> CW[CloudWatch<br/>Container Insights + Logs]
  CW -->|alarm| SNS[SNS streamingapp-alerts]
  J -->|deploy success/failure| SNS
  SNS --> Email[Email Notifications]
  User((Users)) -->|5x ELB| FE & AU & ST & AD & CH
```
---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | React (served by nginx) |
| Backend | Node.js + Express (4 microservices) |
| Realtime | Socket.IO (chat service) |
| Database | MongoDB 6 (StatefulSet + EBS persistent volume) |
| Object Storage | Amazon S3 (video + thumbnail storage) |
| Containerization | Docker (multi-stage builds, `linux/amd64`) |
| Registry | Amazon ECR (5 repositories) |
| CI/CD | Jenkins (local, Docker socket) + GitHub webhook via ngrok |
| Orchestration | Amazon EKS (Kubernetes 1.34, managed nodegroup) |
| Packaging | Helm 3 |
| Autoscaling | HorizontalPodAutoscaler + metrics-server |
| Monitoring | CloudWatch Container Insights + Fluent Bit |
| ChatOps | Amazon SNS → Email |

---

## Microservices

| Service | Port | Responsibility | ECR Repository |
|---|---|---|---|
| frontend | 80 | React SPA, login/catalogue/player UI | `streamingapp/frontend` |
| authService | 3001 | Registration, login, JWT issuance, roles | `streamingapp/auth` |
| streamingService | 3002 | Video catalogue, S3 streaming endpoints | `streamingapp/streaming` |
| adminService | 3003 | Video upload & asset management (admin role) | `streamingapp/admin` |
| chatService | 3004 | Live chat via websockets | `streamingapp/chat` |
| MongoDB | 27017 | Shared database (internal only, no ELB) | — (in-cluster) |

**Docker build contexts** (important — they differ per service):

| Image | Build context | Dockerfile |
|---|---|---|
| frontend | `./frontend` | `frontend/Dockerfile` |
| auth | `./backend/authService` | `Dockerfile` (in context) |
| streaming / admin / chat | `./backend` | `-f backend/<service>/Dockerfile` |

---

## Repository Structure

```
StreamingApp-Assignment-HV/
├── Jenkinsfile                     # CI/CD pipeline (build → ECR → helm deploy → SNS)
├── docker-compose.yml              # Local development
├── frontend/                       # React app + multi-stage Dockerfile
├── backend/
│   ├── authService/                # each service: Dockerfile, controllers, routes, models
│   ├── streamingService/
│   ├── adminService/
│   └── chatService/
├── helm/streamingapp/              # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/                  # deployments, services, mongo, hpa, secrets
├── scripts/
│   ├── create-ecr-repos.sh         # idempotent ECR repo creation
│   ├── build-and-push-ecr.sh       # manual build+push (mirrors Jenkinsfile)
│   ├── deploy-eks.sh               # manual helm deploy
│   ├── get-service-urls.sh         # prints ELB URLs + ready-made FE_* exports
│   └── cleanup.sh                  # safe teardown (helm → PVC → cluster)
└── docs/                           # architecture + deployment documentation
```

---

## Phase 1 — Version Control with Git

Forked the upstream repository and configured syncing:

```bash
git clone https://github.com/Avinashsain/StreamingApp-Assignment-HV.git
cd StreamingApp-Assignment-HV
git remote add upstream https://github.com/UnpredictablePrashant/StreamingApp.git

# Sync with upstream whenever needed:
git fetch upstream && git checkout main && git merge upstream/main && git push origin main
```

**Security hygiene:** all `.env` files are git-ignored (`.env`, `**/.env`) and excluded from Docker images via `.dockerignore`. Secrets reach the cluster only through Kubernetes Secrets injected at deploy time (`--set` from Jenkins credentials).

![git remote -v output](./screenshots/git-remote-v.png)

---

## Phase 2 — Local Setup & Containerization

The entire stack runs locally with one command:

```bash
cp .env.example .env        # fill in local values (never committed)
docker-compose up --build
```

**Local endpoints:**

| Service | URL |
|---|---|
| Frontend | http://localhost:3000 |
| Auth API | http://localhost:3001 |
| Streaming API | http://localhost:3002 |
| Admin API | http://localhost:3003 |
| Chat API | http://localhost:3004 |
| MongoDB | mongodb://localhost:27017 |

> Inside containers, services reach the database as `mongodb://mongo:27017/streamingapp` (Docker network DNS, not localhost).

![docker ps showing all 6 containers running](./screenshots/local-service/docker-ps/running-containers.png)
![App login page at http://localhost:3000](./screenshots/local-service/page-1.png)
![App running locally — catalogue](./screenshots/local-service/page-2.png)
![App running locally — video playback](./screenshots/local-service/page-3.png)
![App running locally — chat](./screenshots/local-service/page-4.png)

---

## Phase 3 — AWS Environment (ECR + S3)

```bash
aws configure                       # IAM user credentials, region us-east-1
./scripts/create-ecr-repos.sh       # creates 5 repos (idempotent)
```

Created ECR repositories:

```
251478238405.dkr.ecr.us-east-1.amazonaws.com/streamingapp/{frontend,auth,streaming,admin,chat}
```

S3 bucket for media: `streamingappbucketb15` (**us-west-2**). Because the bucket region differs from the deployment region, the app's `AWS_REGION` env var is set to `us-west-2` (used only by the S3 SDK client and URL builder) while ECR/EKS/SNS run in `us-east-1`.

![ECR console with 5 repositories](./screenshots/ecr-console-with-5-repositories/repositories.png)
![S3 bucket — uploaded thumbnails](./screenshots/s3-bucket-with-uploaded-videos-and-thumbnails/thumbnails-1.png)
![S3 bucket — uploaded videos](./screenshots/s3-bucket-with-uploaded-videos-and-thumbnails/thumbnails-2.png)
![S3 bucket — object details](./screenshots/s3-bucket-with-uploaded-videos-and-thumbnails/thumbnails-3.png)

---

## Phase 4 — CI with Jenkins + ngrok Webhook

Jenkins runs **locally** (zero EC2 cost) with Docker socket access; GitHub reaches it through an ngrok static domain:

```bash
ngrok http 8080 --domain=<static-domain>.ngrok-free.dev
# GitHub webhook payload URL: https://<static-domain>.ngrok-free.dev/github-webhook/
```

**AWS auth:** Jenkins stores an *AWS Credentials* entry (`aws-jenkins`) consumed via `withCredentials` — no keys in source control, masked in logs.

**Pipeline stages** (see [Jenkinsfile](Jenkinsfile)):

1. **Checkout** — sets `IMAGE_TAG` = 12-char git commit SHA (every image traceable to a commit)
2. **AWS Login** — ECR docker login
3. **Build Backend Images** — loop over 4 services with correct contexts, `--platform linux/amd64`
4. **Build Frontend Image** — production ELB URLs injected as build args (React bakes URLs at build time)
5. **Deploy to EKS** — `helm upgrade --install`, S3 keys injected via `--set` from credentials
6. **post** — SNS publish on success/failure (wrapped in `withCredentials`)

![Jenkins pipeline stage view — all green](./screenshots/jenkins-pipeline-stage-view/jenkins-1.png)
![Jenkins build history](./screenshots/jenkins-pipeline-stage-view/jenkins-2.png)
![Jenkins console output — successful deploy](./screenshots/jenkins-pipeline-stage-view/jenkins-3.png)
![GitHub webhook Recent Deliveries — 200 responses](./screenshots/github-webhook-recent-deliveries/webhook-1.png)
![GitHub webhook configuration](./screenshots/github-webhook-recent-deliveries/webhook-2.png)
![ECR image list with git-SHA tags — frontend](./screenshots/ecr-image-list-with-git-sha-tags/screenshot-1.png)
![ECR image list with git-SHA tags — auth](./screenshots/ecr-image-list-with-git-sha-tags/screenshot-2.png)
![ECR image list with git-SHA tags — streaming](./screenshots/ecr-image-list-with-git-sha-tags/screenshot-3.png)
![ECR image list with git-SHA tags — admin](./screenshots/ecr-image-list-with-git-sha-tags/screenshot-4.png)
![ECR image list with git-SHA tags — chat](./screenshots/ecr-image-list-with-git-sha-tags/screenshot-5.png)
![ECR image tags traceable to commits](./screenshots/ecr-image-list-with-git-sha-tags/screenshot-6.png)

---

## Phase 5 — Kubernetes Deployment (EKS + Helm)

```bash
eksctl create cluster --name streamingapp-eks --region us-east-1 \
  --nodegroup-name workers --node-type t3.medium \
  --nodes 2 --nodes-min 2 --nodes-max 3 --managed
```

![EKS console — cluster overview](./screenshots/eks-console-cluster/eks-console-cluster-1.png)
![EKS console — compute / nodegroup](./screenshots/eks-console-cluster/eks-console-cluster-2.png)
![EKS console — workloads](./screenshots/eks-console-cluster/eks-console-cluster-3.png)
![EKS console — resources](./screenshots/eks-console-cluster/eks-console-cluster-4.png)
![EKS console — add-ons](./screenshots/eks-console-cluster/eks-console-cluster-5.png)
![EKS console — networking](./screenshots/eks-console-cluster/eks-console-cluster-6.png)

Cluster: Kubernetes **1.34**, 2× t3.medium managed nodes, metrics-server installed as EKS addon. Additionally installed the **EBS CSI driver addon** (required for MongoDB's persistent volume on K8s 1.34) and set `gp2` as the default StorageClass.

**Helm chart highlights** ([helm/streamingapp](helm/streamingapp)):
- Single templated loop renders all 4 backend Deployments + Services from `values.yaml`
- MongoDB StatefulSet with a 5Gi EBS-backed PVC (`storageClassName: gp2`) and TCP-socket health probes
- Kubernetes Secret for `JWT_SECRET` and AWS keys (values injected at deploy, never committed)
- LoadBalancer Services expose frontend + 4 backends publicly; MongoDB stays ClusterIP-internal
- HPA per backend (CPU 70%, max 4) — deployments intentionally omit `replicas` so the HPA owns scaling

**Two-run deployment flow** (because React bakes API URLs at build time):
1. **Run 1:** deploy with placeholder URLs → backends get their ELB DNS names
2. `./scripts/get-service-urls.sh` prints the real URLs + ready-to-paste values
3. **Run 2:** commit real ELB hostnames into the Jenkinsfile + CORS origin (`clientUrls`) into values.yaml → push → frontend rebuilt with production URLs

![kubectl get nodes — 2 Ready nodes](./screenshots/kubectl/screenshot-1.png)
![kubectl -n streamingapp get pods — all Running](./screenshots/kubectl/screenshot-2.png)
![kubectl -n streamingapp get svc — 5 EXTERNAL-IPs](./screenshots/kubectl/screenshot-3.png)
![App live at the frontend ELB — login](./screenshots/app-live-frontend-elb-url/screenshot-1.png)
![App live at the frontend ELB — home](./screenshots/app-live-frontend-elb-url/screenshot-2.png)
![App live at the frontend ELB — catalogue](./screenshots/app-live-frontend-elb-url/screenshot-3.png)
![App live at the frontend ELB — admin dashboard](./screenshots/app-live-frontend-elb-url/screenshot-4.png)
![App live at the frontend ELB — video playback](./screenshots/app-live-frontend-elb-url/screenshot-5.png)
![App live at the frontend ELB — chat](./screenshots/app-live-frontend-elb-url/screenshot-6.png)

---

## Phase 6 — Monitoring & Logging (CloudWatch)

Installed **Container Insights** (CloudWatch agent DaemonSet) + **Fluent Bit** (log shipping DaemonSet) after attaching `CloudWatchAgentServerPolicy` to the nodegroup role.

- **Metrics:** per-pod/per-node CPU, memory, network → CloudWatch → Container Insights
- **Centralized logs:** all container stdout/stderr → log group `/aws/containerinsights/streamingapp-eks/application`
- **Alarm:** `streamingapp-high-cpu` — average pod CPU > 80% for 10 min → SNS topic

![Container Insights performance dashboard](./screenshots/cloudwatch/screenshot-2.png)
![Application log group with live pod logs](./screenshots/cloudwatch/screenshot-1.png)
![CloudWatch alarm streamingapp-high-cpu](./screenshots/cloudwatch/screenshot-3.png)

---

## Phase 7 — ChatOps (SNS Notifications, Bonus)

- SNS topic `streamingapp-alerts` with a confirmed email subscription
- Jenkins `post {}` block publishes **Deploy SUCCESS / Deploy FAILED** on every build (with build number + image tag)
- The CloudWatch high-CPU alarm targets the same topic

Every git push now produces an email notification within seconds of deployment — full ChatOps loop: **push → webhook → build → deploy → SNS → email**.

![SNS subscription confirmation email](./screenshots/sns-notifications/screenshot-1.png)
![SNS topic + confirmed subscription in console](./screenshots/sns-notifications/screenshot-3.png)
!["Deploy SUCCESS" email received in Gmail](./screenshots/sns-notifications/screenshot-2.png)

---

## Final Validation

| # | Check | Proof |
|---|---|---|
| 1 | All pods Running, 0 restarts steady-state | `kubectl -n streamingapp get pods` |
| 2 | Register + login via frontend ELB (frontend↔auth↔Mongo↔JWT) | login page + logged-in home |
| 3 | Admin role granted, admin dashboard accessible | admin dashboard |
| 4 | Video upload via admin → stored in S3 (cross-region us-west-2) | upload success + S3 object |
| 5 | Video playback (S3 streaming path) | player mid-playback |
| 6 | Live chat across two browser tabs (websockets) | both tabs with messages |
| 7 | Push commit → webhook → auto build → auto deploy | Jenkins triggered "Started by GitHub push" |
| 8 | Self-healing: deleted a pod → recreated automatically | `kubectl -n streamingapp get pods -w` |
| 9 | HPA active on all backends | `kubectl -n streamingapp get hpa` |
| 10 | Deploy notification email received | SNS email |

![All pods Running, 0 restarts steady-state](./screenshots/hpa/get-pods.png)
![Self-healing: deleted a pod, recreated automatically](./screenshots/hpa/get-pods-w.png)
![HPA active on all backends](./screenshots/hpa/get-hpa.png)

![MongoDB users collection via mongosh — data layer proof](./screenshots/mongosh/screenshot-1.png)
![MongoDB videos collection via mongosh](./screenshots/mongosh/screenshot-2.png)

---

## Troubleshooting Journal (Real Issues I Solved)

Documenting these was half the learning. Every issue below actually occurred during this deployment:

| # | Symptom | Root Cause | Fix |
|---|---|---|---|
| 1 | `ImagePullBackOff` — `no match for platform in manifest` | Images built on Apple Silicon (arm64); EKS nodes are x86_64 | `docker build --platform linux/amd64` everywhere (Jenkinsfile + scripts) |
| 2 | `mongo-0` Pending 40+ min — `unbound PersistentVolumeClaims` | K8s 1.34 ships no EBS CSI driver; `gp2` StorageClass existed but was not default, so the PVC had no class | Installed `aws-ebs-csi-driver` addon + attached `AmazonEBSCSIDriverPolicy` + patched gp2 as default + recreated the PVC |
| 3 | All backends `CrashLoopBackOff` | Domino effect: services exit when MongoDB is unreachable | Resolved automatically once mongo was healthy |
| 4 | Helm `UPGRADE FAILED: StatefulSet spec forbidden` | `volumeClaimTemplates` is immutable after creation | `kubectl delete statefulset mongo --cascade=orphan` (pod + data survive), helm recreates it |
| 5 | Helm conflict: `.spec.replicas` owned by kube-controller-manager | HPA had scaled deployments; Helm's server-side apply fought over `replicas` | Removed `replicas` from deployment templates — HPA owns scaling |
| 6 | Mongo crash-looping after adding health probes | `mongosh` exec probe exceeded default 1s timeout → liveness kills | Switched to lightweight `tcpSocket` probes with `timeoutSeconds: 5` |
| 7 | Frontend API calls hit `PASTE-...-HOSTNAME` placeholders | Real ELB URLs never actually committed (verified with `git show HEAD:Jenkinsfile`) | Committed real hostnames; added a pre-push `grep` verification habit |
| 8 | `{"success":false,"message":"Admin privileges required"}` after DB role update | JWT carries the role from login time; old token still said `user` | Log out / clear localStorage → fresh login mints an admin token |
| 9 | Thumbnails pointed at `http://localhost:3002/...` | `STREAMING_PUBLIC_URL` env var unset; code defaults to localhost (`util/s3.js`) | Added `STREAMING_PUBLIC_URL` to Helm values/env pointing at the streaming ELB |
| 10 | SNS publish failed: `NoCredentials` in post-actions | Jenkins `post {}` runs outside stage `withCredentials` scope | Wrapped SNS publishes in their own `withCredentials` block |
| 11 | Browser `ERR_TIMED_OUT` while `curl` returned 200 | Chrome silently upgraded http→https; ELB listens on 80 only | Explicit `http://` in incognito window |

---

## Scaling & Self-Healing

- **HorizontalPodAutoscaler** on every backend: CPU target 70%, min 1 → max 4 replicas (observed live during a crash-storm: HPA scaled auth/streaming to 2)
- **Managed nodegroup** scales 2 → 3 nodes
- **Self-healing** verified: deleting a pod triggers immediate recreation; MongoDB data survives restarts on its EBS PersistentVolume
- **Health probes** on MongoDB prevent traffic before the DB is ready

![kubectl -n streamingapp get hpa output](./screenshots/hpa/get-hpa.png)

---

## Cost Management & Teardown

Total project cost ≈ **$2–4** by design: Jenkins local ($0), cluster created and destroyed same-day, screenshots taken before teardown.

```bash
./scripts/cleanup.sh
# 1. helm uninstall  → removes app + all 5 ELBs + mongo PVC
# 2. eksctl delete cluster → removes control plane, nodes, VPC
# 3-5. optional: log groups, alarm + SNS topic, ECR repositories
# Ends with an executed verification that nothing is left billing
```
![cleanup-3](./screenshots/cleanup/Screenshot-3.png)
![cleanup-4](./screenshots/cleanup/Screenshot-4.png)

---

## Documentation

- [docs/architecture.md](docs/architecture.md) — system design, components, decisions
- [docs/deployment.md](docs/deployment.md) — full step-by-step deployment record with screenshots

---

## Author

**Avinash Sain**
Graded Project — Orchestration and Scaling (Hero Vired)