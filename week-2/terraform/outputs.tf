# TERRAFORM OUTPUTS
# Print useful values after apply: API URL, Cognito sign-in IDs, table, and Lambdas.
output "api_url" {
  description = "Base URL for the deployed AWS API stage."
  value       = "https://${aws_api_gateway_rest_api.orders.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.orders.stage_name}"
}

output "orders_table_name" {
  description = "DynamoDB table created for orders."
  value       = aws_dynamodb_table.orders.name
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID for customer sign-up and authentication."
  value       = aws_cognito_user_pool.customers.id
}

output "cognito_app_client_id" {
  description = "Public Cognito app client ID used by the CLI sign-in flow."
  value       = aws_cognito_user_pool_client.customers.id
}

output "lambda_names" {
  description = "Lambda function names for log inspection."
  value       = { for name, function in aws_lambda_function.orders : name => function.function_name }
}

output "create_event_queue_name" {
  description = "SQS queue for post-create background events."
  value       = aws_sqs_queue.create_events.name
}

output "create_event_dlq_name" {
  description = "Dead-letter queue for failed post-create events."
  value       = aws_sqs_queue.create_events_dlq.name
}
