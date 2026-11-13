# LAMBDA PACKAGE
# Zip the Python source folder so Terraform can upload the handlers to AWS Lambda.
data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/orderflow-lambda.zip"
}

# DYNAMODB TABLE
# Store order items. orderId is the table primary key; the GSI supports customer history.
resource "aws_dynamodb_table" "orders" {
  name         = "${var.project_name}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }
  attribute {
    name = "customerId"
    type = "S"
  }
  attribute {
    name = "createdAtOrder"
    type = "S"
  }

  global_secondary_index {
    name            = "CustomerCreatedIndex"
    hash_key        = "customerId"
    range_key       = "createdAtOrder"
    projection_type = "ALL"
  }

  server_side_encryption { enabled = true }
  point_in_time_recovery { enabled = false }
  tags = { Project = var.project_name }

  lifecycle {
    precondition {
      condition = terraform.workspace == "aws"
      #condition     = contains(["aws", "localstack", "default"], terraform.workspace)
      error_message = "Select the 'aws' Terraform workspace before managing AWS resources."
    }
  }
}

# CREATE EVENT DEAD-LETTER QUEUE
# Hold create events that the worker cannot process after the configured retries.
resource "aws_sqs_queue" "create_events_dlq" {
  name                      = "${var.project_name}-create-events-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = { Project = var.project_name }
}

# CREATE EVENT QUEUE
# Buffer post-create work independently from the synchronous order creation response.
resource "aws_sqs_queue" "create_events" {
  name                       = "${var.project_name}-create-events"
  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.create_events_dlq.arn
    maxReceiveCount     = 5
  })
  tags = { Project = var.project_name }
}

# LAMBDA EXECUTION ROLES
# Each function assumes its own role to access only the AWS services it needs.
resource "aws_iam_role" "lambda" {
  for_each = toset(["create", "read", "update", "delete", "create-event-worker"])
  name     = "${var.project_name}-${each.key}-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# CLOUDWATCH LOG GROUPS
# Create a log destination with retention for each Lambda function.
resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = toset(["create", "read", "update", "delete", "create-event-worker"])
  name              = "/aws/lambda/${var.project_name}-${each.key}"
  retention_in_days = var.log_retention_days
  tags              = { Project = var.project_name }
}

# LAMBDA LOGGING POLICIES
# Let each function write logs only to its own CloudWatch log group.
resource "aws_iam_role_policy" "lambda_logs" {
  for_each = aws_iam_role.lambda
  name     = "${var.project_name}-${each.key}-logs"
  role     = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.lambda[each.key].arn}:*"
    }]
  })
}

# LAMBDA DATABASE POLICIES
# Give create/read/update/delete functions operation-specific DynamoDB permissions.
resource "aws_iam_role_policy" "lambda_dynamodb" {
  for_each = toset(["create", "read", "update", "delete"])
  name     = "${var.project_name}-${each.key}-dynamodb"
  role     = aws_iam_role.lambda[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = each.key == "create" ? ["dynamodb:PutItem"] : each.key == "read" ? ["dynamodb:GetItem", "dynamodb:Query"] : each.key == "update" ? ["dynamodb:UpdateItem", "dynamodb:GetItem"] : ["dynamodb:DeleteItem"]
      Resource = each.key == "read" ? [aws_dynamodb_table.orders.arn, "${aws_dynamodb_table.orders.arn}/index/CustomerCreatedIndex"] : [aws_dynamodb_table.orders.arn]
    }]
  })
}

# SQS PERMISSIONS
# Create publishes events; the worker consumes them. Other Lambdas get no SQS access.
resource "aws_iam_role_policy" "create_event_sqs" {
  for_each = toset(["create", "create-event-worker"])
  name     = "${var.project_name}-${each.key}-sqs"
  role     = aws_iam_role.lambda[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = each.key == "create" ? ["sqs:SendMessage"] : [
        "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"
      ]
      Resource = aws_sqs_queue.create_events.arn
    }]
  })
}

# FUNCTION HANDLERS
# Map each operation to its Python entry point and timeout.
locals {
  functions = {
    create              = { handler = "order_api.create_handler.handler", timeout = 10 }
    read                = { handler = "order_api.read_handler.handler", timeout = 10 }
    update              = { handler = "order_api.update_handler.handler", timeout = 10 }
    delete              = { handler = "order_api.delete_handler.handler", timeout = 10 }
    create-event-worker = { handler = "order_api.create_event_worker.handler", timeout = 30 }
  }
}

# LAMBDA FUNCTIONS
# Deploy the four handlers with their own roles and the orders-table name.
resource "aws_lambda_function" "orders" {
  for_each         = local.functions
  function_name    = "${var.project_name}-${each.key}"
  role             = aws_iam_role.lambda[each.key].arn
  runtime          = "python3.12"
  handler          = each.value.handler
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  timeout          = each.value.timeout
  memory_size      = 128
  environment {
    variables = merge(
      { ORDERS_TABLE = aws_dynamodb_table.orders.name },
      each.key == "create" ? { CREATE_EVENTS_QUEUE_URL = aws_sqs_queue.create_events.id } : {}
    )
  }
  depends_on = [aws_iam_role_policy.lambda_logs, aws_iam_role_policy.lambda_dynamodb, aws_iam_role_policy.create_event_sqs, aws_cloudwatch_log_group.lambda]
  tags       = { Project = var.project_name }
}

# SQS EVENT SOURCE
# Invoke the background worker with one message at a time; failures are retried.
resource "aws_lambda_event_source_mapping" "create_events" {
  event_source_arn        = aws_sqs_queue.create_events.arn
  function_name           = aws_lambda_function.orders["create-event-worker"].arn
  batch_size              = 1
  function_response_types = ["ReportBatchItemFailures"]
  depends_on              = [aws_iam_role_policy.create_event_sqs]
}

# LAMBDA ERROR ALARMS
# Alert in CloudWatch when any order Lambda reports an invocation error.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each            = aws_lambda_function.orders
  alarm_name          = "${each.value.function_name}-errors"
  alarm_description   = "One or more OrderFlow Lambda invocations failed in the evaluation period."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = var.project_name }
}

# LAMBDA DURATION ALARMS
# Monitor when a Lambda invocation approaches its timeout.
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each            = aws_lambda_function.orders
  alarm_name          = "${each.value.function_name}-duration"
  alarm_description   = "Maximum duration approaches the Lambda timeout."
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  dimensions          = { FunctionName = each.value.function_name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 8000
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = var.project_name }
}

# API GATEWAY ALARM
# Monitor server-side (5xx) API responses.
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name        = "${var.project_name}-api-5xx"
  alarm_description = "One or more API Gateway requests returned a server-side error in the evaluation period."
  namespace         = "AWS/ApiGateway"
  metric_name       = "5XXError"
  dimensions = {
    ApiName = aws_api_gateway_rest_api.orders.name
    Stage   = aws_api_gateway_stage.orders.stage_name
  }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = var.project_name }
}

# DYNAMODB THROTTLE ALARMS
# Detect read/write requests throttled for the orders table.
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  for_each = toset(["ReadThrottleEvents", "WriteThrottleEvents"])

  alarm_name          = "${var.project_name}-orders-${each.key}"
  alarm_description   = "DynamoDB reported one or more ${each.key} for the orders table."
  namespace           = "AWS/DynamoDB"
  metric_name         = each.key
  dimensions          = { TableName = aws_dynamodb_table.orders.name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = var.project_name }
}

# DLQ ALARM
# Notify through SNS when a create event has exhausted its retry allowance.
resource "aws_cloudwatch_metric_alarm" "create_events_dlq_messages" {
  alarm_name          = "${var.project_name}-create-events-dlq-messages"
  alarm_description   = "One or more order-created events are waiting in the DLQ."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.create_events_dlq.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = var.project_name }
}

# CREATE EVENT PUBLISH FAILURE METRIC
# Turn the recognizable create-handler log message into a CloudWatch metric/alarm.
resource "aws_cloudwatch_log_metric_filter" "create_event_publish_failures" {
  name           = "${var.project_name}-create-event-publish-failures"
  log_group_name = aws_cloudwatch_log_group.lambda["create"].name
  pattern        = "create_event_publish_failed"
  metric_transformation {
    name      = "CreateEventPublishFailures"
    namespace = "${var.project_name}/CreateEvents"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "create_event_publish_failures" {
  alarm_name          = "${var.project_name}-create-event-publish-failures"
  alarm_description   = "An order was saved but its background event could not be published to SQS."
  namespace           = "${var.project_name}/CreateEvents"
  metric_name         = "CreateEventPublishFailures"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = var.project_name }
}

# COGNITO CUSTOMER USER POOL
# Customers sign in here; their immutable Cognito sub becomes the order customerId.
resource "aws_cognito_user_pool" "customers" {
  name                     = "${var.project_name}-customers"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  tags = { Project = var.project_name }
}

# COGNITO APP CLIENT
# Enable CLI demo sign-in. The app client has no embedded client secret.
resource "aws_cognito_user_pool_client" "customers" {
  name                          = "${var.project_name}-cli-client"
  user_pool_id                  = aws_cognito_user_pool.customers.id
  generate_secret               = false
  explicit_auth_flows           = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
  access_token_validity         = 60
  id_token_validity             = 60
  refresh_token_validity        = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

# SNS ALERT TOPIC
# CloudWatch publishes alarm state changes to this topic.
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = { Project = var.project_name }
}

# EMAIL SUBSCRIPTION
# AWS sends a confirmation message; the recipient must confirm before email alerts arrive.
resource "aws_sns_topic_subscription" "alarm_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}


# API GATEWAY REST API
# HTTPS entry point; methods below require a valid Cognito user-pool token.
resource "aws_api_gateway_rest_api" "orders" {
  name        = "${var.project_name}-api"
  description = "Cognito-authenticated serverless order management API"
  endpoint_configuration { types = ["REGIONAL"] }
  tags = { Project = var.project_name }
}

# COGNITO API AUTHORIZER
# API Gateway validates the customer JWT before invoking any route Lambda.
resource "aws_api_gateway_authorizer" "customers" {
  name                           = "${var.project_name}-cognito-authorizer"
  rest_api_id                    = aws_api_gateway_rest_api.orders.id
  type                           = "COGNITO_USER_POOLS"
  provider_arns                  = [aws_cognito_user_pool.customers.arn]
  identity_source                = "method.request.header.Authorization"
  identity_validation_expression = "^${aws_cognito_user_pool_client.customers.id}$"
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  parent_id   = aws_api_gateway_rest_api.orders.root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_resource" "order_id" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  parent_id   = aws_api_gateway_resource.orders.id
  path_part   = "{orderId}"
}

resource "aws_api_gateway_resource" "status" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  parent_id   = aws_api_gateway_resource.order_id.id
  path_part   = "status"
}

# API ROUTES
# Connect each HTTP method/path to the matching Lambda operation.
locals {
  api_routes = {
    create = { resource_id = aws_api_gateway_resource.orders.id, method = "POST", function = "create" }
    list   = { resource_id = aws_api_gateway_resource.orders.id, method = "GET", function = "read" }
    get    = { resource_id = aws_api_gateway_resource.order_id.id, method = "GET", function = "read" }
    update = { resource_id = aws_api_gateway_resource.status.id, method = "PATCH", function = "update" }
    delete = { resource_id = aws_api_gateway_resource.order_id.id, method = "DELETE", function = "delete" }
  }
}

# AUTHENTICATED API METHODS
# Require API Gateway to validate a Cognito user-pool token for every operation.
resource "aws_api_gateway_method" "routes" {
  for_each      = local.api_routes
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  resource_id   = each.value.resource_id
  http_method   = each.value.method
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.customers.id
}

# API-TO-LAMBDA INTEGRATIONS
# Forward API requests to Lambda using proxy integration.
resource "aws_api_gateway_integration" "routes" {
  for_each                = local.api_routes
  rest_api_id             = aws_api_gateway_rest_api.orders.id
  resource_id             = aws_api_gateway_method.routes[each.key].resource_id
  http_method             = aws_api_gateway_method.routes[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.orders[each.value.function].invoke_arn
}

# LAMBDA INVOKE PERMISSIONS
# Allow API Gateway to invoke only the function used by each route.
resource "aws_lambda_permission" "api_gateway" {
  for_each      = local.api_routes
  statement_id  = "AllowApiGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orders[each.value.function].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.orders.execution_arn}/*/${each.value.method}/orders*"
}

# API DEPLOYMENT AND STAGE
# Publish the configured routes under the v1 URL stage.
resource "aws_api_gateway_deployment" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.routes,
      aws_api_gateway_authorizer.customers,
      aws_api_gateway_integration.routes,
      aws_lambda_permission.api_gateway
    ]))
  }
  lifecycle { create_before_destroy = true }
  depends_on = [aws_api_gateway_integration.routes]
}

resource "aws_api_gateway_stage" "orders" {
  deployment_id = aws_api_gateway_deployment.orders.id
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  stage_name    = "v1"
  tags          = { Project = var.project_name }
}
