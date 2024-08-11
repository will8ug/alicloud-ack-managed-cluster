provider "alicloud" {
  region = "cn-shenzhen"
  #请与variable.tf 配置文件中得地域保持一致
}
variable "k8s_name_prefix" {
  description = "The name prefix used to create managed kubernetes cluster."
  default     = "tf-ack-shenzhen"
}

resource "random_uuid" "this" {}

locals {
  k8s_name_terway         = substr(join("-", [var.k8s_name_prefix, "terway"]), 0, 63)
  k8s_name_flannel        = substr(join("-", [var.k8s_name_prefix, "flannel"]), 0, 63)
  k8s_name_ask            = substr(join("-", [var.k8s_name_prefix, "ask"]), 0, 63)
  new_vpc_name            = "tf-vpc-172-16"
  new_vsw_name_azD        = "tf-vswitch-azD-172-16-0"
  new_vsw_name_azE        = "tf-vswitch-azE-172-16-2"
  new_vsw_name_azF        = "tf-vswitch-azF-172-16-4"
  nodepool_name           = "default-nodepool"
  managed_nodepool_name   = "managed-node-pool"
  autoscale_nodepool_name = "autoscale-node-pool"
  log_project_name        = "log-for-${local.k8s_name_terway}"
}

data "alicloud_instance_types" "default" {
  cpu_core_count       = 8
  memory_size          = 32
  availability_zone    = var.availability_zone[0]
  kubernetes_node_role = "Worker"
}

data "alicloud_zones" "default" {
  available_instance_type = data.alicloud_instance_types.default.instance_types[0].id
}

resource "alicloud_vpc" "default" {
  vpc_name   = local.new_vpc_name
  cidr_block = "172.16.0.0/12"
}

resource "alicloud_vswitch" "vswitches" {
  count      = length(var.node_vswitch_ids) > 0 ? 0 : length(var.node_vswitch_cidrs)
  vpc_id     = alicloud_vpc.default.id
  cidr_block = element(var.node_vswitch_cidrs, count.index)
  zone_id    = element(var.availability_zone, count.index)
}

resource "alicloud_vswitch" "terway_vswitches" {
  count      = length(var.terway_vswitch_ids) > 0 ? 0 : length(var.terway_vswitch_cidrs)
  vpc_id     = alicloud_vpc.default.id
  cidr_block = element(var.terway_vswitch_cidrs, count.index)
  zone_id    = element(var.availability_zone, count.index)
}

resource "alicloud_cs_managed_kubernetes" "default" {
  name = local.k8s_name_terway
  cluster_spec = "ack.pro.small"
  version      = "1.28.9-aliyun.1"
  worker_vswitch_ids = split(",", join(",", alicloud_vswitch.vswitches.*.id))

  pod_vswitch_ids = split(",", join(",", alicloud_vswitch.terway_vswitches.*.id))

  new_nat_gateway = true
  # pod_cidr                  = "10.10.0.0/16"
  service_cidr = "10.11.0.0/16"
  slb_internet_enabled = true

  enable_rrsa = true

  control_plane_log_components = ["apiserver", "kcm", "scheduler", "ccm"]

  dynamic "addons" {
    for_each = var.cluster_addons
    content {
      name   = lookup(addons.value, "name", var.cluster_addons)
      config = lookup(addons.value, "config", var.cluster_addons)
    }
  }
}

resource "alicloud_cs_kubernetes_node_pool" "default" {
  cluster_id = alicloud_cs_managed_kubernetes.default.id
  node_pool_name = local.nodepool_name
  vswitch_ids = split(",", join(",", alicloud_vswitch.vswitches.*.id))

  # Worker ECS Type and ChargeType
  instance_types       = var.worker_instance_types
  instance_charge_type = "PostPaid"

  # customize worker instance name
  # node_name_mode      = "customized,ack-terway-shenzhen,ip,default"

  desired_size = 2
  password = var.password

  install_cloud_monitor = true

  system_disk_category = "cloud_efficiency"
  system_disk_size     = 40

  data_disks {
    category = "cloud_ssd"
    size = 100
  }
}
