variable "project_id" {
  type        = string
  description = "GCP 프로젝트 ID"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-c"
}

# --- 네트워크 ---
variable "network_name" {
  type    = string
  default = "privatenet"
}

variable "subnet_name" {
  type    = string
  default = "privatenet-us"
}

variable "subnet_cidr" {
  type    = string
  default = "10.130.0.0/20"
}

variable "ssh_source_cidr" {
  type        = string
  default     = "35.235.240.0/20"
  description = "IAP TCP 포워딩이 사용하는 소스 IP 범위"
}

# --- VM ---
variable "vm_name" {
  type    = string
  default = "vm-internal"
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "image" {
  type        = string
  default     = "debian-12"
  description = "Debian GNU/Linux 12 (bookworm) 이미지 패밀리"
}

# --- Storage ---
variable "bucket_name" {
  type        = string
  description = "전역적으로 고유한 버킷 이름 (예: <프로젝트>-lab04-pganat-XXXX)"
}

# --- Cloud NAT ---
variable "nat_router_name" {
  type    = string
  default = "nat-router"
}

variable "nat_gateway_name" {
  type    = string
  default = "nat-config"
}
