# Log group explicito por Lambda, con el nombre exacto que Lambda usa por
# convencion (/aws/lambda/<function_name>) para que AWS lo reutilice en vez
# de crear uno sin retention por su cuenta en el primer invoke.
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = var.lambda_function_names

  name              = "/aws/lambda/${each.value}"
  retention_in_days = var.log_retention_days

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-${var.environment}-alarms"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.lambda_function_names

  alarm_name          = "${var.project_name}-${var.environment}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods   = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "Errores en ${each.value} en los ultimos 5 minutos"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    FunctionName = each.value
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = var.lambda_function_names

  alarm_name          = "${var.project_name}-${var.environment}-${each.key}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods   = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "Throttles en ${each.value} en los ultimos 5 minutos"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    FunctionName = each.value
  }
}

locals {
  invocations_metrics = [
    for k, v in var.lambda_function_names :
    ["AWS/Lambda", "Invocations", "FunctionName", v, { label = k }]
  ]
  errors_metrics = [
    for k, v in var.lambda_function_names :
    ["AWS/Lambda", "Errors", "FunctionName", v, { label = k }]
  ]
  duration_metrics = [
    for k, v in var.lambda_function_names :
    ["AWS/Lambda", "Duration", "FunctionName", v, { label = k, stat = "Average" }]
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${var.project_name}-${var.environment} — Lambdas, EventBridge y DLQ"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "Invocaciones por Lambda"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = local.invocations_metrics
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "Errores por Lambda"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = local.errors_metrics
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Duracion promedio por Lambda (ms)"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          metrics = local.duration_metrics
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "EventBridge: invocaciones exitosas vs fallidas"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          # AWS/Events solo publica Invocations/FailedInvocations con las
          # dimensiones EventBusName + RuleName juntas (confirmado con
          # list-metrics real): un metric fijo con solo EventBusName no
          # devuelve datos. SEARCH() suma automaticamente todas las reglas
          # del bus sin necesitar conocer sus nombres de antemano.
          metrics = [
            [
              {
                expression = "SEARCH('{AWS/Events,EventBusName,RuleName} EventBusName=\"${var.event_bus_name}\" MetricName=\"Invocations\"', 'Sum', 300)",
                label      = "Exitosas (todas las reglas)",
                id         = "e1"
              }
            ],
            [
              {
                expression = "SEARCH('{AWS/Events,EventBusName,RuleName} EventBusName=\"${var.event_bus_name}\" MetricName=\"FailedInvocations\"', 'Sum', 300)",
                label      = "Fallidas (todas las reglas)",
                id         = "e2"
              }
            ],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "Mensajes en la DLQ (eventos que agotaron reintentos)"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          stat   = "Maximum"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.dlq_name],
          ]
        }
      },
    ]
  })
}

