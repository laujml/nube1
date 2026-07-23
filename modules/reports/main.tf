# Rol dedicado para la Lambda de reportes (no el rol compartido de modules/iam):
# solo lectura sobre Orders, Products y Audit, nada de escritura. Mismo patron
# de rol-por-Lambda que ya usa modules/eventing para sus processors.

resource "aws_iam_role" "reports" {
  name = "${var.project_name}-${var.environment}-reports-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "reports_logs" {
  role       = aws_iam_role.reports.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "reports_readonly" {
  name = "${var.project_name}-${var.environment}-reports-readonly"
  role = aws_iam_role.reports.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOrdersProducts"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          var.orders_table_arn,
          "${var.orders_table_arn}/index/*",
          var.products_table_arn,
          "${var.products_table_arn}/index/*",
        ]
      },
      {
        Sid    = "ReadAudit"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          var.audit_table_arn,
        ]
      }
    ]
  })
}

# --- Lambda ---

data "archive_file" "reports_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "reports" {
  function_name    = "${var.project_name}-${var.environment}-reports"
  role             = aws_iam_role.reports.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.reports_lambda.output_path
  source_code_hash = data.archive_file.reports_lambda.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      ORDERS_TABLE        = var.orders_table_name
      PRODUCTS_TABLE      = var.products_table_name
      AUDIT_TABLE         = var.audit_table_name
      LOW_STOCK_THRESHOLD = var.low_stock_threshold
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_lambda_permission" "apigateway_reports" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reports.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${var.account_id}:${var.api_gateway_id}/*"
}

# --- API Gateway: /v1/reports/sales, /v1/reports/inventory, /v1/reports/audit ---

resource "aws_api_gateway_resource" "reports" {
  rest_api_id = var.api_gateway_id
  parent_id   = var.v1_resource_id
  path_part   = "reports"
}

resource "aws_api_gateway_resource" "reports_sales" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.reports.id
  path_part   = "sales"
}

resource "aws_api_gateway_resource" "reports_inventory" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.reports.id
  path_part   = "inventory"
}

resource "aws_api_gateway_resource" "reports_audit" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.reports.id
  path_part   = "audit"
}

# Todas las rutas de reportes exigen el mismo Lambda Authorizer JWT que el
# resto del API; la restriccion a roles admin/operator (nada de customer) se
# resuelve dentro de la Lambda via auth_context.require_role, mismo patron
# que P3/P4.
locals {
  routes = {
    sales     = { resource_id = aws_api_gateway_resource.reports_sales.id }
    inventory = { resource_id = aws_api_gateway_resource.reports_inventory.id }
    audit     = { resource_id = aws_api_gateway_resource.reports_audit.id }
  }
}

resource "aws_api_gateway_method" "routes" {
  for_each      = local.routes
  rest_api_id   = var.api_gateway_id
  resource_id   = each.value.resource_id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = var.authorizer_id
}

resource "aws_api_gateway_integration" "routes" {
  for_each                = local.routes
  rest_api_id              = var.api_gateway_id
  resource_id              = each.value.resource_id
  http_method              = aws_api_gateway_method.routes[each.key].http_method
  integration_http_method  = "POST"
  type                     = "AWS_PROXY"
  uri                      = aws_lambda_function.reports.invoke_arn
}

# --- CORS preflight (OPTIONS, integracion MOCK, sin pasar por la Lambda) ---
# Necesario porque el frontend (P6) llama a esta API desde otro origen
# (CloudFront/S3) y el header Authorization dispara preflight en el browser.
resource "aws_api_gateway_method" "cors_options" {
  for_each      = local.routes
  rest_api_id   = var.api_gateway_id
  resource_id   = each.value.resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cors_options" {
  for_each    = local.routes
  rest_api_id = var.api_gateway_id
  resource_id = each.value.resource_id
  http_method = aws_api_gateway_method.cors_options[each.key].http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "cors_options" {
  for_each    = local.routes
  rest_api_id = var.api_gateway_id
  resource_id = each.value.resource_id
  http_method = aws_api_gateway_method.cors_options[each.key].http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "cors_options" {
  for_each    = local.routes
  rest_api_id = var.api_gateway_id
  resource_id = each.value.resource_id
  http_method = aws_api_gateway_method.cors_options[each.key].http_method
  status_code = aws_api_gateway_method_response.cors_options[each.key].status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.cors_options]
}
