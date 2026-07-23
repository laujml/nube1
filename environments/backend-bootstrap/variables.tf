variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "cloudshop"
}

variable "state_bucket_name" {
  type        = string
  description = "Nombre del bucket S3 para el remote state (unico globalmente)"
}

variable "lock_table_name" {
  type        = string
  default     = "cloudshop-tf-lock"
  description = "Nombre de la tabla DynamoDB para el state lock"
}
