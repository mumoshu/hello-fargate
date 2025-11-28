# Hello Fargate Use Cases Collection

Each use-case-specific project `usecases/$name/` is composed of:

- `apps/` contains the source code for the applications deployed to Fargate, in mostly Go, more language coming
- `scripts/` shell scripts that serve as entrypoints to various tasks including running end-to-end tests
- `infra/terraform/` contains Terraform projects for deploying AWS resources specific to the use-case
- `tests/` contains the source code for various automated tests against the deployed apps and infra

Please refer to each use-case directory for more details:

- `oneoff/`: One-off tasks
- `webapp/`: Web services behind ALB + Cognito User Pool
- `webapi/`: API-only Web services behind ALB JWT auth
- `backend/`: Internal-only backend services using Service Connect
- `backgroundjob/`: Background jobs using SQS
- `scheduledjob/`: Scheduled jobs using Event Bridge + Step Function
- `batchjob/`: Batch jobs using AWS Batch
