# Collaboration Notes: Fargate Scheduled Workflow Project

This document captures key takeaways and successful collaboration patterns observed during the development of the `fargate-scheduled-workflow` project. The aim is to leverage these learnings for future projects.

## Key Takeaways for Future Projects

1.  **Start with a Clear Vision:** Having a concise overview (like the `README.md`'s "Overview" section) outlining the high-level goal, the core technologies (Step Functions, Fargate, EventBridge, Go app, Terraform), and the basic workflow is crucial. This sets the direction early.
2.  **Component-Based Breakdown:** Thinking in terms of distinct components (`app/`, `terraform/`, `scripts/`, `test-runner/`) makes the project manageable. We could tackle each part somewhat independently before integrating.
3.  **Define the "Interface" Early:** Specifying how components interact is important. For instance, knowing the Go app needed to output JSON with `parallelItems` for the Step Function Map state helps shape the application code from the start.
4.  **Infrastructure as Code is Foundational:** Using Terraform (`terraform/`) from the beginning ensures infrastructure is repeatable, version-controlled, and easier to manage. Defining outputs (like `state_machine_arn`) makes connecting components easier.
5.  **Automate Repetitive Tasks:** Creating helper scripts (`scripts/`) for common actions like building Docker images (`build.sh`), setting environment variables (`set-tf-vars.sh`), or running end-to-end tests (`run-e2e.sh`) saves significant time and reduces errors.
6.  **Context is Crucial for AI:** When asking for code or configuration, providing context (like existing files, desired inputs/outputs, specific AWS service requirements) dramatically improves the quality and relevance of the AI's suggestions. Attaching the `README.md` or relevant code snippets helps immensely.
7.  **Iterative Refinement:** Don't expect perfection on the first try. Build a basic version, test it, and then refine. For example, start with the core Terraform, then add IAM permissions, then refine security groups.
8.  **Explicit Configuration:** Clearly defining necessary environment variables (`AWS_ACCOUNT_ID`, `TF_SUBNET_IDS`, etc.) and providing guidance on how to obtain them (like the "Finding Subnet IDs" section) prevents configuration headaches.
9.  **Testing Strategy:** Incorporating a way to test the workflow (like the `test-runner/` or the `run-e2e.sh` script) is essential for verifying functionality after deployment or changes.
10. **Documentation Matters:** Maintaining a `README.md` with setup, deployment, testing, and cleanup instructions makes the project accessible to others (and your future self!).

## Why This Kind of Collaboration Goes Well (Prompting & Interaction Patterns)

*   **Clear Goal Definition:** Starting prompts that clearly state the objective (e.g., "Create a Fargate task definition for a Go app," "Set up a Step Function to run a task," "Write a script to build and push a Docker image to ECR").
*   **Providing Specific Requirements:** Prompts that include details like required IAM permissions, input/output formats, resource names, or specific AWS service features lead to more accurate results.
*   **Supplying Context:** Attaching existing code files (`app/main.go`, `terraform/main.tf`) or the `README.md` when asking for related changes or additions allows the AI to understand the existing structure and conventions.
*   **Iterative Prompting:** Instead of one giant prompt, breaking down the request into smaller steps (e.g., "First, create the ECR repository," "Next, add the task definition," "Now, create the Step Function state machine that uses this task").
*   **Requesting Explanations:** Asking "Why?" or "Explain this code" helps ensure understanding and allows for correction if the AI's approach isn't quite right.
*   **User Review and Guidance:** The user actively reviews the AI's suggestions, catches logical errors or misconceptions, and provides corrective feedback or alternative approaches. The AI assists, but the user directs.
*   **Leveraging AI for Boilerplate:** Using prompts like "Generate the basic Terraform structure for a VPC," "Create a simple Go HTTP server," or "Write a Dockerfile for a Go application" speeds up development significantly. 