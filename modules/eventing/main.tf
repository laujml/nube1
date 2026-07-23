locals {
  processors = {
    update_inventory   = "actualiza el inventario cuando se crea un pedido"
    audit_logger       = "guarda los eventos importantes en dynamodb"
    notification_email = "manda el correo de confirmacion con ses"
  }

  lambda_environment = {
    update_inventory = {
      PRODUCTS_TABLE = var.products_table_name
      AUDIT_TABLE    = aws_dynamodb_table.audit.name
    }
    audit_logger = {
      AUDIT_TABLE = aws_dynamodb_table.audit.name
    }
    notification_email = {
      SES_FROM_EMAIL = aws_ses_email_identity.sender.email
    }
  }
}

resource "aws_cloudwatch_event_bus" "orders" {
  name = "${var.project_name}-${var.environment}-orders"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# DLQ compartida para los targets de EventBridge: si una invocacion a un
# processor agota sus reintentos (maximum_retry_attempts / maximum_event_age_in_seconds
# en aws_cloudwatch_event_target de abajo), el evento cae aqui en vez de perderse.
resource "aws_sqs_queue" "event_target_dlq" {
  name                      = "${var.project_name}-${var.environment}-event-target-dlq"
  message_retention_seconds = 1209600 # 14 dias, maximo permitido

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_sqs_queue_policy" "event_target_dlq" {
  queue_url = aws_sqs_queue.event_target_dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeDLQ"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.event_target_dlq.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [
              aws_cloudwatch_event_rule.order_created.arn,
              aws_cloudwatch_event_rule.order_audit.arn,
            ]
          }
        }
      }
    ]
  })
}

resource "aws_dynamodb_table" "audit" {
  name         = "${var.project_name}-${var.environment}-Audit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "audit_id"

  attribute {
    name = "audit_id"
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

resource "aws_ses_email_identity" "sender" {
  email = var.ses_sender_email
}

resource "aws_iam_role" "processor" {
  for_each = local.processors

  name = "${var.project_name}-${var.environment}-${replace(each.key, "_", "-")}-role"
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

resource "aws_iam_role_policy_attachment" "logs" {
  for_each = local.processors

  role       = aws_iam_role.processor[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "update_inventory" {
  name = "update-products"
  role = aws_iam_role.processor["update_inventory"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UpdateProducts"
        Effect   = "Allow"
        Action   = "dynamodb:UpdateItem"
        Resource = var.products_table_arn
      },
      {
        Sid      = "WriteInventoryAudit"
        Effect   = "Allow"
        Action   = "dynamodb:PutItem"
        Resource = aws_dynamodb_table.audit.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "audit_logger" {
  name = "write-audit-records"
  role = aws_iam_role.processor["audit_logger"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "dynamodb:PutItem"
        Resource = aws_dynamodb_table.audit.arn
      }
    ]
  })
}

# Mientras la cuenta este en SES sandbox, cada destinatario (ademas del
# remitente) tambien debe estar verificado, y SES evalua el permiso IAM de
# ses:SendEmail contra la identidad del DESTINATARIO ademas de la del
# remitente (confirmado en pruebas reales: AccessDenied citando el ARN del
# destinatario aunque el codigo solo use SES_FROM_EMAIL como Source). Por
# eso el Resource no puede quedar scoped solo a la identidad del remitente;
# se amplia a todas las identidades SES de la cuenta (no un Resource "*"
# total) hasta salir de sandbox, donde ya no aplicaria esta restriccion.
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "notification_email" {
  name = "send-order-emails"
  role = aws_iam_role.processor["notification_email"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "arn:aws:ses:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:identity/*"
      }
    ]
  })
}

data "archive_file" "processor" {
  for_each = local.processors

  type        = "zip"
  source_dir  = "${path.module}/lambda/${each.key}"
  output_path = "${path.module}/${each.key}.zip"
}

resource "aws_lambda_function" "processor" {
  for_each = local.processors

  function_name    = "${var.project_name}-${var.environment}-${replace(each.key, "_", "-")}"
  description      = each.value
  role             = aws_iam_role.processor[each.key].arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.processor[each.key].output_path
  source_code_hash = data.archive_file.processor[each.key].output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = local.lambda_environment[each.key]
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_rule" "order_created" {
  name           = "${var.project_name}-${var.environment}-order-created"
  description    = "procesa un pedido nuevo"
  event_bus_name = aws_cloudwatch_event_bus.orders.name
  event_pattern = jsonencode({
    source        = ["cloudshop.orders"]
    "detail-type" = ["OrderCreated"]
  })
}

resource "aws_cloudwatch_event_rule" "order_audit" {
  name           = "${var.project_name}-${var.environment}-order-audit"
  description    = "audita la creacion y los cambios de estado"
  event_bus_name = aws_cloudwatch_event_bus.orders.name
  event_pattern = jsonencode({
    source        = ["cloudshop.orders"]
    "detail-type" = ["OrderCreated", "OrderStatusChanged"]
  })
}

locals {
  event_targets = {
    update_inventory = {
      rule_name   = aws_cloudwatch_event_rule.order_created.name
      rule_arn    = aws_cloudwatch_event_rule.order_created.arn
      function_id = "update_inventory"
    }
    audit_orders = {
      rule_name   = aws_cloudwatch_event_rule.order_audit.name
      rule_arn    = aws_cloudwatch_event_rule.order_audit.arn
      function_id = "audit_logger"
    }
    notify_customer = {
      rule_name   = aws_cloudwatch_event_rule.order_created.name
      rule_arn    = aws_cloudwatch_event_rule.order_created.arn
      function_id = "notification_email"
    }
  }
}

resource "aws_cloudwatch_event_target" "processor" {
  for_each = local.event_targets

  event_bus_name = aws_cloudwatch_event_bus.orders.name
  rule           = each.value.rule_name
  target_id      = replace(each.key, "_", "-")
  arn            = aws_lambda_function.processor[each.value.function_id].arn

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 2
  }

  dead_letter_config {
    arn = aws_sqs_queue.event_target_dlq.arn
  }
}

resource "aws_lambda_permission" "eventbridge" {
  for_each = local.event_targets

  statement_id  = "allow-eventbridge-${replace(each.key, "_", "-")}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor[each.value.function_id].function_name
  principal     = "events.amazonaws.com"
  source_arn    = each.value.rule_arn
}
