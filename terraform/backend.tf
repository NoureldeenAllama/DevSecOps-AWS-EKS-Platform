terraform {
  backend "s3" {
    bucket       = "my-eks-terraform-state-bucket-484056256277"
    key          = "eks-terraform/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
