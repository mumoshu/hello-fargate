# NOTE: No custom Batch service role needed.
# AWS Batch automatically uses the service-linked role (AWSServiceRoleForBatch)
# when service_role is omitted from the compute environment.
# The service-linked role has the latest permissions for Fargate compute.

# Execution Role (pulls images, writes logs)
resource "aws_iam_role" "batch_execution_role" {
  name = "hello-fargate-batchjobs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Project = "hello-fargate-batchjobs"
  }
}

resource "aws_iam_role_policy_attachment" "batch_execution_policy" {
  role       = aws_iam_role.batch_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Job Role (for app to access AWS APIs - optional)
# Uncomment if your batch job needs to access S3, DynamoDB, etc.
#
# resource "aws_iam_role" "batch_job_role" {
#   name = "hello-fargate-batchjobs-job-role"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = {
#         Service = "ecs-tasks.amazonaws.com"
#       }
#     }]
#   })
#
#   tags = {
#     Project = "hello-fargate-batchjobs"
#   }
# }
#
# # Example: S3 access policy for job role
# resource "aws_iam_role_policy" "batch_job_s3_policy" {
#   name = "hello-fargate-batchjobs-s3-policy"
#   role = aws_iam_role.batch_job_role.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Action = [
#         "s3:GetObject",
#         "s3:PutObject",
#         "s3:ListBucket"
#       ]
#       Resource = [
#         "arn:aws:s3:::your-bucket-name",
#         "arn:aws:s3:::your-bucket-name/*"
#       ]
#     }]
#   })
# }
