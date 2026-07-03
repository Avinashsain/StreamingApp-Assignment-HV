# StreamingApp — Deployment Process

> Region: **us-east-1** (S3 media bucket in **us-west-2**) · CI: **Jenkins (local, native) + ngrok webhook** · Orchestration: **Amazon EKS + Helm**

## Phase 1 — Version control

Forked `UnpredictablePrashant/StreamingApp`, added the original as `upstream` for syncing:

```bash
git clone https://github.com/Avinashsain/StreamingApp-Assignment-HVC.git
git remote add upstream https://github.com/UnpredictablePrashant/StreamingApp.git
# sync when needed:
git fetch upstream && git merge upstream/main && git push origin main
```

![git remote -v output](../screenshots/git-remote-v.png)

## Phase 2 — Containerization

The app ships Dockerfiles for all five components. Build contexts differ per service (streaming/admin/chat share `backend/` as context; auth uses `backend/authService`). Verified locally with `docker-compose up --build` — frontend on :3000, services on :3001–:3004, MongoDB on :27017.

![docker ps with all containers running](../screenshots/local-service/docker-ps/running-containers.png)
![App login page on localhost](../screenshots/local-service/page-1.png)
![App running locally — catalogue](../screenshots/local-service/page-2.png)
![App running locally — video playback](../screenshots/local-service/page-3.png)
![App running locally — chat](../screenshots/local-service/page-4.png)

## Phase 3 — AWS environment

```bash
aws configure          # IAM user keys, region us-east-1
aws sts get-caller-identity
./scripts/create-ecr-repos.sh          # 5 repos: streamingapp/{frontend,auth,streaming,admin,chat}
```

Media storage uses the pre-existing S3 bucket `streamingappbucketb15` in **us-west-2**; the app's `AWS_REGION` env var points at the bucket region while all other infrastructure runs in us-east-1.

![ECR console showing the 5 repositories](../screenshots/ecr-console-with-5-repositories/repositories.png)
![S3 bucket — uploaded thumbnails](../screenshots/s3-bucket-with-uploaded-videos-and-thumbnails/thumbnails-1.png)
![S3 bucket — uploaded videos](../screenshots/s3-bucket-with-uploaded-videos-and-thumbnails/thumbnails-2.png)
![S3 bucket — object details](../screenshots/s3-bucket-with-uploaded-videos-and-thumbnails/thumbnails-3.png)

## Phase 4 — CI with Jenkins

Jenkins runs **natively on the local machine** (zero EC2 cost) with Docker Desktop, AWS CLI, kubectl and helm available on the host. AWS access uses a Jenkins credential (`aws-jenkins`, type AWS Credentials) consumed via `withCredentials` — no keys in source control, masked in build logs.

GitHub → Jenkins connectivity uses an ngrok static domain:

```bash
ngrok http 8080 --domain=<static-domain>.ngrok-free.dev
# GitHub webhook payload URL: https://<static-domain>.ngrok-free.dev/github-webhook/
```

Pipeline job: *Pipeline script from SCM* → this repo → `Jenkinsfile`, trigger: *GitHub hook trigger for GITScm polling*.

Pipeline stages: **Checkout** (sets IMAGE_TAG = 12-char git SHA) → **AWS Login** (ECR docker login) → **Build Backend Images** (loop over 4 services with correct contexts, `--platform linux/amd64`) → **Build Frontend Image** (production ELB URLs as build args) → **Deploy to EKS** (helm upgrade with S3 keys injected via `--set`) → **post**: SNS success/failure notification (wrapped in `withCredentials`).

![Jenkins pipeline stage view — all green](../screenshots/jenkins-pipeline-stage-view/jenkins-1.png)
![Jenkins build history](../screenshots/jenkins-pipeline-stage-view/jenkins-2.png)
![Jenkins console output — successful deploy](../screenshots/jenkins-pipeline-stage-view/jenkins-3.png)
![GitHub webhook Recent Deliveries — 200 responses](../screenshots/github-webhook-recent-deliveries/webhook-1.png)
![GitHub webhook configuration](../screenshots/github-webhook-recent-deliveries/webhook-2.png)
![ECR image list with git-SHA tags — frontend](../screenshots/ecr-image-list-with-git-sha-tags/screenshot-1.png)
![ECR image list with git-SHA tags — auth](../screenshots/ecr-image-list-with-git-sha-tags/screenshot-2.png)
![ECR image list with git-SHA tags — streaming](../screenshots/ecr-image-list-with-git-sha-tags/screenshot-3.png)
![ECR image list with git-SHA tags — admin](../screenshots/ecr-image-list-with-git-sha-tags/screenshot-4.png)
![ECR image list with git-SHA tags — chat](../screenshots/ecr-image-list-with-git-sha-tags/screenshot-5.png)
![ECR image tags traceable to commits](../screenshots/ecr-image-list-with-git-sha-tags/screenshot-6.png)

## Phase 5 — EKS + Helm

```bash
eksctl create cluster --name streamingapp-eks --region us-east-1 \
  --nodegroup-name workers --node-type t3.medium --nodes 2 --nodes-min 2 --nodes-max 3 --managed
```

Kubernetes **1.34** with metrics-server as an EKS addon. Additionally required for this version: the **EBS CSI driver addon** (`eksctl create addon --name aws-ebs-csi-driver ...` plus `AmazonEBSCSIDriverPolicy` on the node role) and patching `gp2` as the **default StorageClass** — without both, the MongoDB PVC stays Pending forever.

The Helm chart (`helm/streamingapp/`) templates: 4 backend Deployments + Services rendered from a single loop over `values.yaml`, frontend Deployment + Service, MongoDB StatefulSet with a 5Gi gp2 PVC and TCP-socket health probes, Secret for JWT/AWS keys, and HPAs for all backends (deployments intentionally omit `replicas` so the HPA owns scaling).

**Two-run deployment (frontend URLs are build-time):**

- **Run 1:** push chart + Jenkinsfile → Jenkins builds everything (frontend with placeholder URLs) and deploys. Backends receive ELB DNS names.
- **Run 2:** `./scripts/get-service-urls.sh` prints the ELB URLs and ready-made `FE_*` values → paste into the Jenkinsfile, set `env.clientUrls` (CORS) in values.yaml to the frontend ELB → push → Jenkins rebuilds the frontend with real URLs and redeploys.

![EKS console — cluster overview](../screenshots/eks-console-cluster/eks-console-cluster-1.png)
![EKS console — compute / nodegroup](../screenshots/eks-console-cluster/eks-console-cluster-2.png)
![EKS console — workloads](../screenshots/eks-console-cluster/eks-console-cluster-3.png)
![EKS console — resources](../screenshots/eks-console-cluster/eks-console-cluster-4.png)
![EKS console — add-ons](../screenshots/eks-console-cluster/eks-console-cluster-5.png)
![EKS console — networking](../screenshots/eks-console-cluster/eks-console-cluster-6.png)
![kubectl get nodes — 2 Ready nodes](../screenshots/kubectl/screenshot-1.png)
![kubectl -n streamingapp get pods — all Running](../screenshots/kubectl/screenshot-2.png)
![kubectl -n streamingapp get svc — 5 EXTERNAL-IPs](../screenshots/kubectl/screenshot-3.png)
![App live at the frontend ELB — login](../screenshots/app-live-frontend-elb-url/screenshot-1.png)
![App live at the frontend ELB — home](../screenshots/app-live-frontend-elb-url/screenshot-2.png)
![App live at the frontend ELB — catalogue](../screenshots/app-live-frontend-elb-url/screenshot-3.png)
![App live at the frontend ELB — admin dashboard](../screenshots/app-live-frontend-elb-url/screenshot-4.png)
![App live at the frontend ELB — video playback](../screenshots/app-live-frontend-elb-url/screenshot-5.png)
![App live at the frontend ELB — chat](../screenshots/app-live-frontend-elb-url/screenshot-6.png)

## Phase 6 — Monitoring & logging

Attached `CloudWatchAgentServerPolicy` to the nodegroup role, then installed the Container Insights quickstart (CloudWatch agent + Fluent Bit DaemonSets). Result:

- Metrics: CloudWatch → Container Insights → per-pod CPU/memory for the cluster.
- Logs: log group `/aws/containerinsights/streamingapp-eks/application` centralizes all pod logs.
- Alarm: `streamingapp-high-cpu` (pod CPU > 80% for 10 min) → SNS.

![Container Insights performance dashboard](../screenshots/cloudwatch/screenshot-2.png)
![Application log group with live pod logs](../screenshots/cloudwatch/screenshot-1.png)
![CloudWatch alarm streamingapp-high-cpu](../screenshots/cloudwatch/screenshot-3.png)

## Phase 7 — ChatOps (bonus)

SNS topic `streamingapp-alerts` with a confirmed email subscription. The Jenkins `post{}` block publishes on every success/failure, and the CloudWatch alarm targets the same topic. Full loop: **push → webhook → build → deploy → SNS → email**.

![SNS subscription confirmation email](../screenshots/sns-notifications/screenshot-1.png)
![SNS topic + confirmed subscription in console](../screenshots/sns-notifications/screenshot-3.png)
!["Deploy SUCCESS" email received in Gmail](../screenshots/sns-notifications/screenshot-2.png)

## Phase 8 — Validation performed

| Check | Result |
|---|---|
| All pods Running, HPAs active | ✅ |
| Register + login via frontend ELB (frontend↔auth↔Mongo) | ✅ |
| Admin role + video upload via admin + playback (S3 integration) | ✅ |
| Live chat across two browser tabs (websockets) | ✅ |
| Commit push → webhook → auto build → auto deploy | ✅ |
| Deleted a pod → recreated automatically (self-healing) | ✅ |
| SNS notification received on deploy | ✅ |

![All pods Running, 0 restarts steady-state](../screenshots/hpa/get-pods.png)
![Self-healing: deleted a pod, recreated automatically](../screenshots/hpa/get-pods-w.png)
![MongoDB users collection via mongosh — data layer proof](../screenshots/mongosh/screenshot-1.png)
![MongoDB videos collection via mongosh](../screenshots/mongosh/screenshot-2.png)

## Scaling behaviour

Each backend runs under an HPA (CPU 70%, max 4 replicas); the managed nodegroup scales 2→3 nodes. Scaling was observed live: during a MongoDB outage, crash-looping services burned CPU and the HPA scaled auth/streaming to 2 replicas, then scaled back down after stabilization.

![HPA active on all backends](../screenshots/hpa/get-hpa.png)

## Teardown

```bash
./scripts/cleanup.sh
# 1. helm uninstall (removes ELBs + PVC)
# 2. eksctl delete cluster
# 3-5. optional: log groups, alarm + SNS topic, ECR repositories
# Ends with an executed verification (clusters, ELBs, volumes, instances, log groups all empty)
```

Verified no leftover load balancers or unattached EBS volumes after deletion.

## Troubleshooting encountered / notes

The full 11-issue journal (with root causes) is in the [README](../README.md#troubleshooting-journal-real-issues-i-solved). Highlights:

| Issue | Resolution |
|---|---|
| `ImagePullBackOff` — platform mismatch (Apple Silicon arm64 vs x86 nodes) | `docker build --platform linux/amd64` in Jenkinsfile and scripts |
| Mongo PVC Pending forever | EBS CSI addon + node-role policy + gp2 set as default StorageClass + PVC recreated |
| Helm StatefulSet "spec forbidden" on upgrade | `kubectl delete statefulset mongo --cascade=orphan`, helm recreates it |
| Helm vs HPA conflict over `.spec.replicas` | Removed `replicas` from deployment templates |
| Frontend API calls hit placeholder URLs | Run 2 rebuild with real ELB URLs (verified with `git show HEAD:Jenkinsfile`) |
| CORS errors in browser console | Set `env.clientUrls` in values.yaml to the frontend ELB URL |
| Thumbnails pointed at localhost:3002 | `STREAMING_PUBLIC_URL` env var added to Helm values |
| SNS publish `NoCredentials` in post-actions | Wrapped publishes in `withCredentials` inside `post{}` |
