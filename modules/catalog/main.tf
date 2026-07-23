# --- DynamoDB ---

resource "aws_dynamodb_table" "stores" {
  name         = "${var.project_name}-${var.environment}-Stores"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "store_id"

  attribute {
    name = "store_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_dynamodb_table" "products" {
  name         = "${var.project_name}-${var.environment}-Products"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "product_id"

  attribute {
    name = "product_id"
    type = "S"
  }

  attribute {
    name = "store_id"
    type = "S"
  }

  global_secondary_index {
    name            = "store_id-index"
    hash_key        = "store_id"
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

resource "aws_dynamodb_table" "cart" {
  name         = "${var.project_name}-${var.environment}-Cart"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"
  range_key    = "product_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "product_id"
    type = "S"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# --- IAM (scoped solo a las tablas de este modulo) ---

resource "aws_iam_policy" "catalog_dynamodb" {
  name = "${var.project_name}-${var.environment}-catalog-dynamodb"
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
          aws_dynamodb_table.stores.arn,
          "${aws_dynamodb_table.stores.arn}/index/*",
          aws_dynamodb_table.products.arn,
          "${aws_dynamodb_table.products.arn}/index/*",
          aws_dynamodb_table.cart.arn,
          "${aws_dynamodb_table.cart.arn}/index/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "catalog_dynamodb_attach" {
  role       = var.lambda_role_name
  policy_arn = aws_iam_policy.catalog_dynamodb.arn
}

# --- Lambda ---

data "archive_file" "catalog_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "catalog" {
  function_name    = "${var.project_name}-${var.environment}-catalog"
  role             = var.lambda_role_arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.catalog_lambda.output_path
  source_code_hash = data.archive_file.catalog_lambda.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      STORES_TABLE   = aws_dynamodb_table.stores.name
      PRODUCTS_TABLE = aws_dynamodb_table.products.name
      CART_TABLE     = aws_dynamodb_table.cart.name
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_lambda_permission" "apigateway_catalog" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.catalog.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${var.account_id}:${var.api_gateway_id}/*"
}

# --- API Gateway: /v1/stores, /v1/products, /v1/cart ---

resource "aws_api_gateway_resource" "stores" {
  rest_api_id = var.api_gateway_id
  parent_id   = var.v1_resource_id
  path_part   = "stores"
}

resource "aws_api_gateway_resource" "stores_id" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.stores.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "products" {
  rest_api_id = var.api_gateway_id
  parent_id   = var.v1_resource_id
  path_part   = "products"
}

resource "aws_api_gateway_resource" "products_id" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.products.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "cart" {
  rest_api_id = var.api_gateway_id
  parent_id   = var.v1_resource_id
  path_part   = "cart"
}

resource "aws_api_gateway_resource" "cart_id" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.cart.id
  path_part   = "{productId}"
}

# Lectura de catalogo (stores/products) publica; mutaciones y todo el
# carrito exigen el Lambda Authorizer JWT (roles Admin/Operador/Cliente
# se validan dentro de la Lambda via auth_context.require_role).
locals {
  routes = {
    stores_list   = { resource_id = aws_api_gateway_resource.stores.id, method = "GET", protected = false }
    stores_create = { resource_id = aws_api_gateway_resource.stores.id, method = "POST", protected = true }
    stores_get    = { resource_id = aws_api_gateway_resource.stores_id.id, method = "GET", protected = false }
    stores_update = { resource_id = aws_api_gateway_resource.stores_id.id, method = "PUT", protected = true }
    stores_delete = { resource_id = aws_api_gateway_resource.stores_id.id, method = "DELETE", protected = true }

    products_list   = { resource_id = aws_api_gateway_resource.products.id, method = "GET", protected = false }
    products_create = { resource_id = aws_api_gateway_resource.products.id, method = "POST", protected = true }
    products_get    = { resource_id = aws_api_gateway_resource.products_id.id, method = "GET", protected = false }
    products_update = { resource_id = aws_api_gateway_resource.products_id.id, method = "PUT", protected = true }
    products_delete = { resource_id = aws_api_gateway_resource.products_id.id, method = "DELETE", protected = true }

    cart_get    = { resource_id = aws_api_gateway_resource.cart.id, method = "GET", protected = true }
    cart_add    = { resource_id = aws_api_gateway_resource.cart.id, method = "POST", protected = true }
    cart_update = { resource_id = aws_api_gateway_resource.cart_id.id, method = "PUT", protected = true }
    cart_remove = { resource_id = aws_api_gateway_resource.cart_id.id, method = "DELETE", protected = true }
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
  uri                     = aws_lambda_function.catalog.invoke_arn
}

# --- CORS preflight (OPTIONS, integracion MOCK, sin pasar por la Lambda) ---
# Necesario porque el frontend (P6) llama a esta API desde otro origen
# (CloudFront/S3) y el header Authorization dispara preflight en el browser.
locals {
  cors_resources = {
    stores      = aws_api_gateway_resource.stores.id
    stores_id   = aws_api_gateway_resource.stores_id.id
    products    = aws_api_gateway_resource.products.id
    products_id = aws_api_gateway_resource.products_id.id
    cart        = aws_api_gateway_resource.cart.id
    cart_id     = aws_api_gateway_resource.cart_id.id
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
