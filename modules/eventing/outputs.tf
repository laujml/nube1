output "event_bus_name" {
  value = aws_cloudwatch_event_bus.orders.name
}

output "event_bus_arn" {
  value = aws_cloudwatch_event_bus.orders.arn
}

output "audit_table_name" {
  value = aws_dynamodb_table.audit.name
}

output "audit_table_arn" {
  value = aws_dynamodb_table.audit.arn
}

output "lambda_function_names" {
  value = {
    for name, function in aws_lambda_function.processor : name => function.function_name
  }
}

output "ses_sender_identity_arn" {
  value = aws_ses_email_identity.sender.arn
}

output "event_target_dlq_name" {
  value = aws_sqs_queue.event_target_dlq.name
}

output "event_target_dlq_arn" {
  value = aws_sqs_queue.event_target_dlq.arn
}
