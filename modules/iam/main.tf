# Rol para todas las Lambdas (se puede usar uno solo, pero luego se pueden crear roles separados)
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.environment}-lambda-role"
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
}

# Política base para logs
resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Politica para DynamoDB (todas las tablas base, en un solo policy attachment).
# NOTA: AWS permite max 10 managed policies por rol. Al usar un rol
# compartido para todas las Lambdas, cada modulo (auth, catalog, orders...)
# suma sus propias policies a ese mismo limite. Este policy unico (en vez de
# uno por tabla) deja mas margen, pero sigue sin ser minimo privilegio real:
# la forma correcta es un rol por Lambda, scoped a lo que esa Lambda usa.
#
# Los nombres de tabla siguen el mismo patron "${project_name}-${environment}-X"
# que usan todos los modulos (auth, catalog, orders, eventing) al crear sus
# tablas. Idealmente estos ARNs vendrian como output de esos modulos en vez de
# reconstruirse aqui, pero eso crearia una dependencia circular: catalog/orders
# ya reciben lambda_role_arn/lambda_role_name DESDE este modulo iam, asi que
# iam no puede a su vez depender de sus outputs sin romper el grafo. Mientras
# ese refactor de dependencias no se decida en equipo, se mantiene la
# reconstruccion del nombre pero con el patron correcto.
locals {
  tables = ["Products", "Stores", "Orders", "Cart", "Users"]
}

resource "aws_iam_policy" "dynamodb" {
  name = "${var.project_name}-${var.environment}-dynamodb-base-tables"
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
        Resource = flatten([
          for t in local.tables : [
            "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.project_name}-${var.environment}-${t}",
            "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.project_name}-${var.environment}-${t}/index/*"
          ]
        ])
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dynamodb_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.dynamodb.arn
}

# Política para EventBridge (put events). Solo orders (via boto3 "events"
# en modules/orders/lambda/events.py) usa esto desde el rol compartido.
# Igual que con DynamoDB arriba: pasar el ARN real del bus desde modules/eventing
# crearia un ciclo (catalog depende de iam -> iam dependeria de eventing ->
# eventing depende de catalog), asi que se reconstruye con el mismo patron de
# nombre que usa aws_cloudwatch_event_bus.orders en modules/eventing/main.tf.
resource "aws_iam_policy" "eventbridge" {
  name = "${var.project_name}-${var.environment}-eventbridge-put"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "events:PutEvents"
        Resource = "arn:aws:events:${var.aws_region}:${var.account_id}:event-bus/${var.project_name}-${var.environment}-orders"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.eventbridge.arn
}

# NOTA: la policy de ses:SendEmail que compartia este rol se elimino porque
# ninguna Lambda que use el rol compartido (auth, catalog, orders) llama a
# SES. El unico consumidor real es notification_email en modules/eventing,
# que ya tiene su propio rol dedicado con permiso ses:SendEmail/SendRawEmail
# scoped al ARN de la identidad SES (ver aws_iam_role_policy.notification_email
# en modules/eventing/main.tf).