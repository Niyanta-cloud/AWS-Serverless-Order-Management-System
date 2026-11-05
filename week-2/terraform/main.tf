data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/orderflow-lambda.zip"
}

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

resource "aws_iam_role" "lambda" {
  for_each = toset(["create", "read", "update", "delete"])
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

resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = toset(["create", "read", "update", "delete"])
  name              = "/aws/lambda/${var.project_name}-${each.key}"
  retention_in_days = var.log_retention_days
  tags              = { Project = var.project_name }
}

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

resource "aws_iam_role_policy" "lambda_dynamodb" {
  for_each = aws_iam_role.lambda
  name     = "${var.project_name}-${each.key}-dynamodb"
  role     = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = each.key == "create" ? ["dynamodb:PutItem"] : each.key == "read" ? ["dynamodb:GetItem", "dynamodb:Query"] : each.key == "update" ? ["dynamodb:UpdateItem", "dynamodb:GetItem"] : ["dynamodb:DeleteItem"]
      Resource = each.key == "read" ? [aws_dynamodb_table.orders.arn, "${aws_dynamodb_table.orders.arn}/index/CustomerCreatedIndex"] : [aws_dynamodb_table.orders.arn]
    }]
  })
}

locals {
  functions = {
    create = { handler = "order_api.create_handler.handler", timeout = 10 }
    read   = { handler = "order_api.read_handler.handler", timeout = 10 }
    update = { handler = "order_api.update_handler.handler", timeout = 10 }
    delete = { handler = "order_api.delete_handler.handler", timeout = 10 }
  }
}

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
  environment { variables = { ORDERS_TABLE = aws_dynamodb_table.orders.name } }
  depends_on = [aws_iam_role_policy.lambda_logs, aws_iam_role_policy.lambda_dynamodb, aws_cloudwatch_log_group.lambda]
  tags       = { Project = var.project_name }
}

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
  tags                = { Project = var.project_name }
}

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
  tags                = { Project = var.project_name }
}

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
  tags                = { Project = var.project_name }
}

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
  tags                = { Project = var.project_name }
}

resource "aws_api_gateway_rest_api" "orders" {
  name        = "${var.project_name}-api"
  description = "IAM-authorized serverless order management API"
  endpoint_configuration { types = ["REGIONAL"] }
  tags = { Project = var.project_name }
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

locals {
  api_routes = {
    create = { resource_id = aws_api_gateway_resource.orders.id, method = "POST", function = "create" }
    list   = { resource_id = aws_api_gateway_resource.orders.id, method = "GET", function = "read" }
    get    = { resource_id = aws_api_gateway_resource.order_id.id, method = "GET", function = "read" }
    update = { resource_id = aws_api_gateway_resource.status.id, method = "PATCH", function = "update" }
    delete = { resource_id = aws_api_gateway_resource.order_id.id, method = "DELETE", function = "delete" }
  }
}

resource "aws_api_gateway_method" "routes" {
  for_each      = local.api_routes
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  resource_id   = each.value.resource_id
  http_method   = each.value.method
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "routes" {
  for_each                = local.api_routes
  rest_api_id             = aws_api_gateway_rest_api.orders.id
  resource_id             = aws_api_gateway_method.routes[each.key].resource_id
  http_method             = aws_api_gateway_method.routes[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.orders[each.value.function].invoke_arn
}

resource "aws_lambda_permission" "api_gateway" {
  for_each      = local.api_routes
  statement_id  = "AllowApiGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orders[each.value.function].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.orders.execution_arn}/*/${each.value.method}/orders*"
}

resource "aws_api_gateway_deployment" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.routes,
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

locals {
  caller_policy = {
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["execute-api:Invoke"]
      Resource = [
        "${aws_api_gateway_rest_api.orders.execution_arn}/${aws_api_gateway_stage.orders.stage_name}/POST/orders",
        "${aws_api_gateway_rest_api.orders.execution_arn}/${aws_api_gateway_stage.orders.stage_name}/GET/orders",
        "${aws_api_gateway_rest_api.orders.execution_arn}/${aws_api_gateway_stage.orders.stage_name}/GET/orders/*",
        "${aws_api_gateway_rest_api.orders.execution_arn}/${aws_api_gateway_stage.orders.stage_name}/PATCH/orders/*/status",
        "${aws_api_gateway_rest_api.orders.execution_arn}/${aws_api_gateway_stage.orders.stage_name}/DELETE/orders/*"
      ]
    }]
  }
}
