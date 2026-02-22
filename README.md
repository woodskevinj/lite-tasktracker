# lite-tasktracker

A standalone application repository for a full-stack task management app. Create projects, track tasks within them.

**Infrastructure is managed separately** in the `lite-infra` repo, which provisions all AWS resources (VPC, RDS, ECS Fargate, ECR, ALB) as the `LiteInfraStack` CloudFormation stack. This repo owns only the application code and Docker containers.

## Tech Stack

| Layer    | Technology                          |
|----------|-------------------------------------|
| Frontend | React (Vite) + Tailwind CSS         |
| Backend  | Express.js + PostgreSQL via `pg`    |
| Compute  | AWS ECS Fargate (via lite-infra)    |
| Testing  | Vitest (frontend), Jest (backend)   |

## Project Structure

```
lite-tasktracker/
├── frontend/      # React SPA (Vite + Tailwind CSS)
├── backend/       # Express.js API server
├── deploy.sh      # Build, push, and deploy to ECS
└── teardown.sh    # Stop the ECS service gracefully
```

## Local Development

### Prerequisites

- Node.js v18+
- Docker (for building and deploying)
- AWS CLI configured with valid credentials (for deploy/teardown)
- `jq` (for the deploy and teardown scripts)

### Run the app locally

```bash
# Terminal 1 — Backend (port 3001)
cd backend
npm install
node server.js

# Terminal 2 — Frontend (port 5173, proxies /api to backend)
cd frontend
npm install
npm run dev
```

The frontend dev server automatically proxies all `/api/*` requests to the backend at `http://localhost:3001`.

## Run All Tests

```bash
# Backend — 16 tests (Jest + Supertest)
cd backend && npm install && npm test

# Frontend — 17 tests (Vitest + React Testing Library)
cd frontend && npm install && npx vitest run
```

Neither suite requires a database connection or AWS credentials — all external dependencies are mocked.

## Deploy to AWS

Infrastructure must already be deployed via the `lite-infra` repo before running this script.

```bash
./deploy.sh
```

The script requires only valid AWS credentials. It will:

1. Query `LiteInfraStack` outputs for the ECS cluster name, service name, ECR repository URIs, and ALB DNS
2. Authenticate Docker with ECR
3. Build and push the frontend and backend Docker images to their ECR repositories
4. Register a new ECS task definition revision with the updated image URIs
5. Trigger an ECS service update with `--force-new-deployment`
6. Print the application URL and a monitoring command

## Stop the ECS Service

To gracefully stop all running containers without destroying infrastructure:

```bash
./teardown.sh
```

This scales the ECS service to 0, then waits for all tasks to drain and stop before exiting.

To fully tear down all AWS infrastructure (VPC, RDS, ECR, ALB, ECS), run `cdk destroy` in the `lite-infra` repo.

## Known Limitations

- **Database integration is not yet fully implemented.** The backend connects to RDS PostgreSQL via environment variables injected by ECS, but does not currently run migrations or persist data. All API responses are served from in-memory state. Full CRUD operations backed by PostgreSQL are planned.
