# AWS Terraform deployment

See `../docs/aws-only-run-guide.md` for the AWS deployment and Console walkthrough. This module builds one Lambda ZIP and deploys the DynamoDB table/index, four Python 3.12 functions, per-function IAM roles/policies, IAM-authorized API Gateway REST routes, CloudWatch log groups, eight Lambda metric alarms, two DynamoDB throttle alarms, and one API Gateway 5xx alarm.

Use the dedicated `aws` workspace and `aws.tfvars.example` for every plan, apply, or destroy. This protects the existing `default` workspace state from being used accidentally. Review the AWS account, region, and full plan before applying; real AWS resources can incur charges.
