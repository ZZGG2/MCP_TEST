# ==================================================================
# Task 1. VPC 네트워크 / 서브넷 / 방화벽 규칙
# ==================================================================

# 커스텀 서브넷 모드 VPC
resource "google_compute_network" "privatenet" {
  name                    = var.network_name
  auto_create_subnetworks = false # 서브넷 생성 모드: Custom
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "privatenet_us" {
  name          = var.subnet_name
  region        = var.region
  network       = google_compute_network.privatenet.id
  ip_cidr_range = var.subnet_cidr

  # Task 2: Private Google Access 활성화
  private_ip_google_access = true

  depends_on = [google_compute_network.privatenet]
}

# IAP 터널(35.235.240.0/20)에서 오는 SSH만 허용
resource "google_compute_firewall" "allow_ssh_iap" {
  name          = "${var.network_name}-allow-ssh"
  network       = google_compute_network.privatenet.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.ssh_source_cidr]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
