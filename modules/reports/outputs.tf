output "reports_lambda_function_name" {
  value = aws_lambda_function.reports.function_name
}

output "reports_lambda_arn" {
  value = aws_lambda_function.reports.arn
}

output "reports_role_name" {
  value = aws_iam_role.reports.name
}

output "reports_role_arn" {
  value = aws_iam_role.reports.arn
}
