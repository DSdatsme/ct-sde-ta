terraform {
  backend "s3" {
    bucket         = "mybucket-tfstate-prod"
    key            = "prod/ap-south-1/network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "mybucket-tflock-prod"
    encrypt        = true
  }
}
