# --- DynamoDB ---

resource "aws_dynamodb_table" "orders" {
  name         = "${var.project_name}-${var.environment}-Orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  global_secondary_index {
    name            = "user_id-index"
    hash_key        = "user_id"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# --- IAM (scoped solo a la tabla de este modulo) ---
# El acceso a Cart/Products (para armar el checkout) ya lo otorga la policy
# base compartida del modulo iam; aqui solo se agrega lo propio de Orders,
# igual que hace el modulo catalog con sus tablas.

resource "aws_iam_policy" "orders_dynamodb" {
  name = "${var.project_name}-${var.environment}-orders-dynamodb"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.orders.arn,
          "${aws_dynamodb_table.orders.arn}/index/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "orders_dynamodb_attach" {
  role       = var.lambda_role_name
  policy_arn = aws_iam_policy.orders_dynamodb.arn
}

# --- Lambda ---

data "archive_file" "orders_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "orders" {
  function_name    = "${var.project_name}-${var.environment}-orders"
  role             = var.lambda_role_arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.orders_lambda.output_path
  source_code_hash = data.archive_file.orders_lambda.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      ORDERS_TABLE   = aws_dynamodb_table.orders.name
      CART_TABLE     = var.cart_table_name
      PRODUCTS_TABLE = var.products_table_name
      EVENT_BUS_NAME = var.event_bus_name
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_lambda_permission" "apigateway_orders" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orders.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${var.account_id}:${var.api_gateway_id}/*"
}

# --- API Gateway: /v1/orders, /v1/orders/{id}, /v1/orders/{id}/status ---

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = var.api_gateway_id
  parent_id   = var.v1_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_resource" "orders_id" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.orders.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "orders_id_status" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.orders_id.id
  path_part   = "status"
}

# Todas las rutas de pedidos exigen el Lambda Authorizer JWT; la
# distincion de permisos por rol (Admin/Operador/Cliente) y la
# verificacion de dueno del pedido se resuelven dentro de la Lambda
# via auth_context.require_role (mismo patron que P3).
locals {
  routes = {
    orders_create        = { resource_id = aws_api_gateway_resource.orders.id, method = "POST", protected = true }
    orders_list          = { resource_id = aws_api_gateway_resource.orders.id, method = "GET", protected = true }
    orders_get           = { resource_id = aws_api_gateway_resource.orders_id.id, method = "GET", protected = true }
    orders_status_update = { resource_id = aws_api_gateway_resource.orders_id_status.id, method = "PUT", protected = true }
  }
}

resource "aws_api_gateway_method" "routes" {
  for_each      = local.routes
  rest_api_id   = var.api_gateway_id
  resource_id   = each.value.resource_id
  http_method   = each.value.method
  authorization = each.value.protected ? "CUSTOM" : "NONE"
  authorizer_id = each.value.protected ? var.authorizer_id : null
}

resource "aws_api_gateway_integration" "routes" {
  for_each                = local.routes
  rest_api_id             = var.api_gateway_id
  resource_id             = each.value.resource_id
  http_method             = aws_api_gateway_method.routes[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.orders.invoke_arn
}

# --- CORS preflight (OPTIONS, integracion MOCK, sin pasar por la Lambda) ---
# Necesario porque el frontend (P6) llama a esta API desde otro origen
# (CloudFront/S3) y el header Authorization dispara preflight en el browser.
locals {
  cors_resources = {
    orders        = aws_api_gateway_resource.orders.id
    orders_id     = aws_api_gateway_resource.orders_id.id
    orders_status = aws_api_gateway_resource.orders_id_status.id
  }
}

resource "aws_api_gateway_method" "cors_options" {
  for_each      = local.cors_resources
  rest_api_id   = var.api_gateway_id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cors_options" {
  for_each    = local.cors_resources
  rest_api_id = var.api_gateway_id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors_options[each.key].http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "cors_options" {
  for_each    = local.cors_resources
  rest_api_id = var.api_gateway_id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors_options[each.key].http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "cors_options" {
  for_each    = local.cors_resources
  rest_api_id = var.api_gateway_id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors_options[each.key].http_method
  status_code = aws_api_gateway_method_response.cors_options[each.key].status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.cors_options]
}
