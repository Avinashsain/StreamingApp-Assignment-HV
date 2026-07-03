# StreamingApp — Orchestration & Scaling (Graded Project)

Collaborative video streaming platform (MERN, 5 microservices) deployed end-to-end on AWS:
**Docker → Amazon ECR → Jenkins CI/CD (GitHub webhook) → Amazon EKS via Helm → CloudWatch monitoring/logging → SNS ChatOps.**

## Quick links
- 📐 [Architecture](docs/architecture.md) — diagram, components, design decisions
- 🚀 [Deployment process](docs/deployment.md) — step-by-step with screenshots
- ⚙️ [Jenkinsfile](Jenkinsfile) — CI/CD pipeline
- ⛵ [Helm chart](helm/streamingapp/) — Kubernetes manifests
- 🔧 [Scripts](scripts/) — reproducible automation outside CI

## Stack
React · Node.js/Express · MongoDB · Socket.IO · Docker · Jenkins · Amazon ECR · Amazon EKS (Kubernetes) · Helm · CloudWatch · SNS · S3

## Services
| Service | Port | Purpose |
|---|---|---|
| frontend | 80 | React SPA (nginx) |
| authService | 3001 | Auth, JWT |
| streamingService | 3002 | Catalogue, S3 playback |
| adminService | 3003 | Uploads, asset management |
| chatService | 3004 | Live chat (websockets) |
| MongoDB | 27017 | Shared database (in-cluster StatefulSet) |

## Run locally
```bash
cp .env.example .env   # fill values
docker-compose up --build
# frontend: http://localhost:3000
```

## Deploy to AWS
See [docs/deployment.md](docs/deployment.md). Summary:
`scripts/create-ecr-repos.sh` → `eksctl create cluster` → push to main (Jenkins Run 1) → `scripts/get-service-urls.sh` → update FE_* URLs → push (Run 2) → validate → `scripts/cleanup.sh`.
