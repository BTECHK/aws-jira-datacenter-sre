terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random" }
    http = { source = "hashicorp/http", version = "~> 3.0" }
  }
}
provider "aws" {
  region = var.region
  default_tags { tags = { Project = "mds-tools", Environment = "prod", ManagedBy = "terraform" } }
}
variable "region" { default = "us-east-1" }
data "http" "myip" {
  url = "https://ipv4.icanhazip.com"   # v4-ONLY host — dodges the exact IPv6 trap we hit with curl
}
locals {
  my_cidr = "${chomp(data.http.myip.response_body)}/32"
}