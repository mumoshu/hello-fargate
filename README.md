# Hello Fargate!

This project envisions to be a getting-started guide for Fargate that covers my recommended use-cases for Fargate including:

- One-off tasks
- Web services behind ALB + Cognito User Pool
- API-only Web services behind ALB JWT auth
- Internal-only backend services using Service Connect
- Background jobs using SQS
- Scheduled jobs using Event Bridge + Step Function
- Batch jobs using AWS Batch

## Prerequisites

*   AWS CLI instaleld and configured: Ensure at least `aws sts get-caller-identity` works
*   Docker: Ensure at least `docker ps` works
*   [Terraform](https://developer.hashicorp.com/terraform/install) 1.14.0 or greater: Ensure `terraform version` works
*   Go 1.25 or greater

## Getting Started

The project is composed of the following directories:

- `infra/terraform` contains Terraform projects for deploying the common infrastructure like ECR repositories and ECS cluster, Cfn coming
- `usecases/$name` contains various use-case-specific code

Each use-case is designed to be independently consumable as much as possible.
Once the infrastructured is provisioned using `infra`, you can head over to any use-case in any order.

To learners:

If you're an independent self-learner, please refer to [infra/README](./infra/README.md) for setting up the infra first, and then the [usecases/README](./usecases/README.md) to find use-cases you are interested in!

To coachs:

If you're a technical coach, a platform engineer or anyone who wants your friends to learn from this project, please follow [infra/README](./infra/README.md) for setting up the infra, pass the necessary information to each participant along with the
[usecases/README](./usecases/README.md).
