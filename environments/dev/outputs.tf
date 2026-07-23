# URL de invocacion de la API Gateway
output "api_url" {
  value = aws_api_gateway_stage.main.invoke_url
}

# API Key (marcala como sensible para que no se vea en los logs)
output "api_key_value" {
  value     = module.apigateway.api_key_value
  sensitive = true
}

# Dominio de CloudFront
output "cloudfront_domain_name" {
  value = module.cloudfront.cloudfront_domain_name
}

# --- Auth Module ---
output "auth_lambda_function_name" {
  value = module.auth.auth_lambda_function_name
}

output "auth_dynamodb_table_name" {
  value = module.auth.dynamodb_table_name
}

output "jwt_secret_arn" {
  value     = module.auth.jwt_secret_arn
  sensitive = true
}

# --- Catalog Module ---
output "catalog_lambda_function_name" {
  value = module.catalog.catalog_lambda_function_name
}

output "stores_table_name" {
  value = module.catalog.stores_table_name
}

output "products_table_name" {
  value = module.catalog.products_table_name
}

output "cart_table_name" {
  value = module.catalog.cart_table_name
}

# --- Orders Module ---
output "orders_lambda_function_name" {
  value = module.orders.orders_lambda_function_name
}

output "orders_table_name" {
  value = module.orders.orders_table_name
}

# eventing
output "event_bus_name" {
  value = module.eventing.event_bus_name
}

output "audit_table_name" {
  value = module.eventing.audit_table_name
}

output "eventing_lambda_function_names" {
  value = module.eventing.lambda_function_names
}

output "ses_sender_identity_arn" {
  value = module.eventing.ses_sender_identity_arn
}

output "event_target_dlq_name" {
  value = module.eventing.event_target_dlq_name
}

# --- Reports Module ---
output "reports_lambda_function_name" {
  value = module.reports.reports_lambda_function_name
}

# --- Monitoring Module ---
output "alarms_sns_topic_arn" {
  value = module.monitoring.alarms_sns_topic_arn
}

output "dashboard_name" {
  value = module.monitoring.dashboard_name
}
