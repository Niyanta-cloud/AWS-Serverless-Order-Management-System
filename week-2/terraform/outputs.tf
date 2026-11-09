# TERRAFORM OUTPUTS
# Print useful values after apply: API URL, table name, caller policy, and Lambda names.
output "api_url" {
  description = "Base URL for the deployed AWS API stage."
  value       = "https://${aws_api_gateway_rest_api.orders.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.orders.stage_name}"
}

output "orders_table_name" {
  description = "DynamoDB table created for orders."
  value       = aws_dynamodb_table.orders.name
}

output "caller_policy_json" {
  description = "Attach this invoke-only policy to the trusted API caller identity."
  value       = jsonencode(local.caller_policy)
}

output "lambda_names" {
  description = "Lambda function names for log inspection."
  value       = { for name, function in aws_lambda_function.orders : name => function.function_name }
}
