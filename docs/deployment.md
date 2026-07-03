# StreamingApp — Deployment Process

> Region: **us-east-1** · CI: **Jenkins (local Docker) + ngrok webhook** · Orchestration: **Amazon EKS + Helm**
> Insert your own screenshot after each phase where marked 📸.

## Phase 1 — Version control

Forked `UnpredictablePrashant/StreamingApp`, added the original as `upstream` for syncing:

```bash
git clone https://github.com/<YOUR_USERNAME>/StreamingApp.git
git remote add upstream https://github.com/UnpredictablePrashant/StreamingApp.git
# sync when needed:
git fetch upstream && git merge upstream/main && git push origin main
```
📸 *Screenshot: `git remote -v` output and fork page.*

## Phase 2 — Containerization

The app ships Dockerfiles for all five components. Build contexts differ per service (streaming/admin/chat share `backend/` as context). Verified locally with `docker-compose up --build` — frontend on :3000, services on :3001–:3004, MongoDB on :27017.
📸 *Screenshot: `docker ps` with all containers, app login page on localhost.*

## Phase 3 — AWS environment

```bash
aws configure          # IAM user keys, region us-east-1
aws sts get-caller-identity
./scripts/create-ecr-repos.sh          # 5 repos: streamingapp/{frontend,auth,streaming,admin,chat}
aws s3 mb s3://streamingapp-media-<name> --region us-east-1   # video storage
```
📸 *Screenshot: ECR console showing the 5 repositories.*

## Phase 4 — CI with Jenkins

Jenkins runs in Docker locally with the host Docker socket mounted, plus AWS CLI/kubectl/helm installed inside the container. AWS access uses a Jenkins credential (`aws-jenkins`, type AWS Credentials) consumed via `withCredentials` — no keys in source control.

GitHub → Jenkins connectivity uses an ngrok static domain:

```bash
ngrok http 8080 --domain=<name>.ngrok-free.app
# GitHub webhook payload URL: https://<name>.ngrok-free.app/github-webhook/
```

Pipeline job: *Pipeline script from SCM* → this repo → `Jenkinsfile`, trigger: *GitHub hook trigger for GITScm polling*.

Pipeline stages: **Checkout** (sets IMAGE_TAG = git SHA) → **AWS Login** (ECR docker login) → **Build Backend Images** (loop over 4 services with correct contexts) → **Build Frontend Image** (production URLs as build args) → **Deploy to EKS** (helm upgrade) → **post**: SNS success/failure notification.

📸 *Screenshots: green pipeline stage view; GitHub webhook Recent Deliveries 200; ECR image list with SHA tags.*

## Phase 5 — EKS + Helm

```bash
eksctl create cluster --name streamingapp-eks --region us-east-1 \
  --nodegroup-name workers --node-type t3.medium --nodes 2 --nodes-min 2 --nodes-max 3 --managed
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

The Helm chart (`helm/streamingapp/`) templates: 4 backend Deployments + Services rendered from a single loop over `values.yaml`, frontend Deployment + Service, MongoDB StatefulSet with 5Gi PVC, Secret for JWT/AWS keys, and HPAs for all services.

**Two-run deployment (frontend URLs are build-time):**

- **Run 1:** push chart + Jenkinsfile → Jenkins builds everything (frontend with placeholder URLs) and deploys. Backends receive ELB DNS names.
- **Run 2:** `./scripts/get-service-urls.sh` prints the ELB URLs and ready-made `FE_*` values → paste into the Jenkinsfile, set `env.clientUrls` (CORS) in values.yaml to the frontend ELB → push → Jenkins rebuilds the frontend with real URLs and redeploys.

📸 *Screenshots: `kubectl get pods -n streamingapp` all Running; `kubectl get svc` with EXTERNAL-IPs; app served from the frontend ELB URL.*

## Phase 6 — Monitoring & logging

Attached `CloudWatchAgentServerPolicy` to the nodegroup role, then installed the Container Insights quickstart (CloudWatch agent + Fluent Bit DaemonSets). Result:

- Metrics: CloudWatch → Container Insights → per-pod CPU/memory for the cluster.
- Logs: log group `/aws/containerinsights/streamingapp-eks/application` centralizes all pod logs.
- Alarm: `streamingapp-high-cpu` (pod CPU > 80% for 10 min) → SNS.

📸 *Screenshots: Container Insights dashboard; application log group with entries; alarm in OK state.*

## Phase 7 — ChatOps (bonus)

SNS topic `streamingapp-alerts` with an email subscription (and Slack via AWS Chatbot). The Jenkins `post{}` block publishes on every success/failure, and the CloudWatch alarm targets the same topic.
📸 *Screenshot: deployment notification received in email/Slack.*

## Phase 8 — Validation performed

| Check | Result |
|---|---|
| All pods Running, HPAs active | ✅ |
| Register + login via frontend ELB (frontend↔auth↔Mongo) | ✅ |
| Video upload via admin + playback (S3 integration) | ✅ |
| Live chat across two browser tabs (websockets) | ✅ |
| Commit push → webhook → auto build → auto deploy | ✅ |
| Deleted a pod → recreated automatically (self-healing) | ✅ |
| SNS notification received on deploy | ✅ |

## Scaling behaviour

Each service runs under an HPA (CPU 70%, max 4 replicas); the managed nodegroup scales 2→3 nodes. Load-tested by looping requests against the streaming service and observing `kubectl get hpa -w` scale replicas up and back down.
📸 *Screenshot: HPA scaled above minReplicas during load.*

## Teardown

```bash
./scripts/cleanup.sh    # helm uninstall (removes ELBs + PVC) → eksctl delete cluster
```
Verified no leftover load balancers or unattached EBS volumes after deletion.

## Troubleshooting encountered / notes

| Issue | Resolution |
|---|---|
| Frontend API calls failed after first deploy | Expected — Run 1 uses placeholder URLs; fixed by Run 2 rebuild with ELB URLs |
| CORS errors in browser console | Set `env.clientUrls` in values.yaml to the frontend ELB URL and `helm upgrade` |
| Mongo PVC Pending | Installed EBS CSI addon: `eksctl create addon --name aws-ebs-csi-driver ...` |
| ngrok URL changed after restart | Switched to the free static domain so the GitHub webhook stays valid |
