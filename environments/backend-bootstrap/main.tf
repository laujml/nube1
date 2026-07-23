# Bootstrap del backend remoto (S3 + DynamoDB lock) para environments/dev.
#
# Este config se aplica UNA SOLA VEZ, por separado, con su propio state LOCAL
# (no puede usar el backend S3 que el mismo esta creando: seria un ciclo).
# Una vez aplicado, environments/dev/backend.tf apunta a estos recursos.
#
# No se destruye ni se vuelve a aplicar como parte del ciclo normal de
# environments/dev.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # Evita borrar el bucket (y perder el state) por accidente con un
  # terraform destroy corrido en el directorio equivocado.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project     = var.project_name
    Purpose     = "terraform-remote-state"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project = var.project_name
    Purpose = "terraform-state-lock"
  }
}
