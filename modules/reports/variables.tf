variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "api_gateway_id" {
  type = string
}

variable "v1_resource_id" {
  type        = string
  description = "ID del recurso /v1 (modulo apigateway), padre de /v1/reports"
}

variable "authorizer_id" {
  type        = string
  description = "ID del Lambda Authorizer JWT (modulo auth), para proteger todas las rutas de reportes"
}

variable "orders_table_name" {
  type        = string
  description = "Nombre de la tabla Orders (modulo orders), para el reporte de ventas"
}

variable "orders_table_arn" {
  type        = string
  description = "ARN de la tabla Orders (modulo orders), para el rol dedicado de solo lectura"
}

variable "products_table_name" {
  type        = string
  description = "Nombre de la tabla Products (modulo catalog), para el reporte de inventario"
}

variable "products_table_arn" {
  type        = string
  description = "ARN de la tabla Products (modulo catalog), para el rol dedicado de solo lectura"
}

variable "audit_table_name" {
  type        = string
  description = "Nombre de la tabla Audit (modulo eventing), para el reporte de auditoria"
}

variable "audit_table_arn" {
  type        = string
  description = "ARN de la tabla Audit (modulo eventing), para el rol dedicado de solo lectura"
}

variable "low_stock_threshold" {
  type        = number
  default     = 10
  description = "Stock igual o menor a este valor se reporta como bajo en /v1/reports/inventory"
}
