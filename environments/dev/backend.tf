# Backend remoto: state en S3 (versionado + encriptado) con locking via
# DynamoDB. El bucket y la tabla se crean por separado en
# environments/backend-bootstrap/ (no pueden vivir en este mismo config: para
# usarlos como backend ya deben existir de antemano).
terraform {
  backend "s3" {
    bucket         = "cloudshop-tfstate-f195c5ba"
    key            = "cloudshop/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloudshop-tf-lock"
    encrypt        = true
  }
}
