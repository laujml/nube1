variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "lambda_function_names" {
  type        = map(string)
  description = "Mapa clave logica -> nombre real de funcion Lambda, para log groups/alarmas/dashboard de todas las Lambdas del proyecto"
}

variable "event_bus_name" {
  type        = string
  description = "Nombre del bus de EventBridge (modulo eventing), para las metricas de exito/fallo del dashboard"
}

variable "dlq_name" {
  type        = string
  description = "Nombre de la cola SQS de DLQ (modulo eventing), para la metrica de mensajes en el dashboard"
}

variable "log_retention_days" {
  type    = number
  default = 14
}
