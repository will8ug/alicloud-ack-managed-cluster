terraform {
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~>1.227"
    }
  }
}

provider "alicloud" {
  region = "cn-shenzhen"
}
