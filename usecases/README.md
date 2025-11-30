# Hello Fargate Use Cases Collection

This collection demonstrates different subsystems of a typical production system, all running on AWS Fargate.

A typical production system consists of multiple layers: external-facing services that handle user and API traffic, internal services that encapsulate business logic, asynchronous workers that process messages and scheduled tasks, and utility tasks for operations like database migrations. Each use case in this collection maps to one of these architectural roles.

## System Architecture

```
                              ┌──────────────────────────────────────────────────────────────────┐
                              │                        TYPICAL SYSTEM                            │
                              └──────────────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
    │                                    EXTERNAL ACCESS LAYER                                         │
    │                                                                                                  │
    │    ┌─────────────────────────┐                        ┌─────────────────────────┐               │
    │    │       webapp            │                        │        webapi           │               │
    │    │  ┌─────────────────┐    │                        │  ┌─────────────────┐    │               │
    │    │  │  Browser/User   │    │                        │  │   API Client    │    │               │
    │    │  └────────┬────────┘    │                        │  │   (M2M/CLI)     │    │               │
    │    │           │             │                        │  └────────┬────────┘    │               │
    │    │           ▼             │                        │           │             │               │
    │    │  ┌─────────────────┐    │                        │           ▼             │               │
    │    │  │      ALB        │    │                        │  ┌─────────────────┐    │               │
    │    │  │ authenticate-   │    │                        │  │      ALB        │    │               │
    │    │  │    cognito      │    │                        │  │ jwt-validation  │    │               │
    │    │  │ (session cookie)│    │                        │  │ (Bearer token)  │    │               │
    │    │  └────────┬────────┘    │                        │  └────────┬────────┘    │               │
    │    │           │             │                        │           │             │               │
    │    │           ▼             │                        │           ▼             │               │
    │    │  ┌─────────────────┐    │                        │  ┌─────────────────┐    │               │
    │    │  │   ECS Service   │    │                        │  │   ECS Service   │    │               │
    │    │  │   (Web App)     │    │                        │  │   (API Server)  │    │               │
    │    │  └─────────────────┘    │                        │  └─────────────────┘    │               │
    │    └─────────────────────────┘                        └─────────────────────────┘               │
    │              │                                                    │                              │
    └──────────────┼────────────────────────────────────────────────────┼──────────────────────────────┘
                   │                                                    │
                   └────────────────────────┬───────────────────────────┘
                                            │
                                            ▼
    ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
    │                                    INTERNAL SERVICE LAYER                                        │
    │                                                                                                  │
    │                              ┌─────────────────────────┐                                         │
    │                              │        backend          │                                         │
    │                              │  ┌─────────────────┐    │                                         │
    │                              │  │   Cloud Map     │    │                                         │
    │                              │  │   Namespace     │    │                                         │
    │                              │  └────────┬────────┘    │                                         │
    │                              │           │             │                                         │
    │                              │           ▼             │                                         │
    │                              │  ┌─────────────────┐    │                                         │
    │                              │  │ Service Connect │    │                                         │
    │                              │  │ (Envoy Proxy)   │    │                                         │
    │                              │  └────────┬────────┘    │                                         │
    │                              │           │             │                                         │
    │                              │     ┌─────┴─────┐       │                                         │
    │                              │     ▼           ▼       │                                         │
    │                              │ ┌───────┐  ┌───────┐    │                                         │
    │                              │ │Backend│  │Backend│    │                                         │
    │                              │ │  #1   │  │  #2   │    │                                         │
    │                              │ └───────┘  └───────┘    │                                         │
    │                              └─────────────────────────┘                                         │
    │                                                                                                  │
    └──────────────────────────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            │ (internal calls, events, messages)
                                            ▼
    ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
    │                                    ASYNC PROCESSING LAYER                                        │
    │                                                                                                  │
    │   ┌─────────────────────────┐   ┌─────────────────────────┐   ┌─────────────────────────┐       │
    │   │     backgroundjobs      │   │     scheduledjobs       │   │       batchjobs         │       │
    │   │                         │   │                         │   │                         │       │
    │   │  ┌─────────────────┐    │   │  ┌─────────────────┐    │   │  ┌─────────────────┐    │       │
    │   │  │      SQS        │    │   │  │  EventBridge    │    │   │  │   AWS Batch     │    │       │
    │   │  │ (with DLQ)      │    │   │  │  (Schedule)     │    │   │  │   Job Queue     │    │       │
    │   │  └────────┬────────┘    │   │  └────────┬────────┘    │   │  └────────┬────────┘    │       │
    │   │           │             │   │           │             │   │           │             │       │
    │   │           ▼             │   │           ▼             │   │           ▼             │       │
    │   │  ┌─────────────────┐    │   │  ┌─────────────────┐    │   │  ┌─────────────────┐    │       │
    │   │  │  ECS Service    │    │   │  │ Step Functions  │    │   │  │ Fargate Compute │    │       │
    │   │  │ (Long-running   │    │   │  │ State Machine   │    │   │  │  Environment    │    │       │
    │   │  │  SQS poller)    │    │   │  └────────┬────────┘    │   │  └────────┬────────┘    │       │
    │   │  └─────────────────┘    │   │           │             │   │           │             │       │
    │   │                         │   │           ▼             │   │           ▼             │       │
    │   │                         │   │  ┌─────────────────┐    │   │  ┌─────────────────┐    │       │
    │   │                         │   │  │  ECS RunTask    │    │   │  │  Array Jobs     │    │       │
    │   │                         │   │  │  (per step)     │    │   │  │  (parallel)     │    │       │
    │   │                         │   │  └─────────────────┘    │   │  └─────────────────┘    │       │
    │   └─────────────────────────┘   └─────────────────────────┘   └─────────────────────────┘       │
    │                                                                                                  │
    └──────────────────────────────────────────────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
    │                                    UTILITY / AD-HOC LAYER                                        │
    │                                                                                                  │
    │                              ┌─────────────────────────┐                                         │
    │                              │         oneoff          │                                         │
    │                              │                         │                                         │
    │                              │  ┌─────────────────┐    │                                         │
    │                              │  │  ECS RunTask    │    │                                         │
    │                              │  │  (single run,   │    │                                         │
    │                              │  │   exits when    │    │                                         │
    │                              │  │   done)         │    │                                         │
    │                              │  └─────────────────┘    │                                         │
    │                              │                         │                                         │
    │                              │  Use: DB migrations,    │                                         │
    │                              │  data imports, etc.     │                                         │
    │                              └─────────────────────────┘                                         │
    │                                                                                                  │
    └──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

Each use-case-specific project `usecases/$name/` is composed of:

- `apps/` contains the source code for the applications deployed to Fargate, in mostly Go, more language coming
- `scripts/` shell scripts that serve as entrypoints to various tasks including running end-to-end tests
- `infra/terraform/` contains Terraform projects for deploying AWS resources specific to the use-case
- `tests/` contains the source code for various automated tests against the deployed apps and infra

## Use Cases

Please refer to each use-case directory for more details:

- `oneoff/`: One-off tasks
- `webapp/`: Web services behind ALB + Cognito User Pool
- `webapi/`: API-only Web services behind ALB JWT auth
- `backend/`: Internal-only backend services using Service Connect
- `backgroundjobs/`: Background jobs using SQS
- `scheduledjobs/`: Scheduled jobs using Event Bridge + Step Function
- `batchjob/`: Batch jobs using AWS Batch

## Implementation Guide

For detailed implementation patterns including directory structure, Terraform templates, script patterns, and naming conventions, see [IMPLEMENTATION.md](IMPLEMENTATION.md)
