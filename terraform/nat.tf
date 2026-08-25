# ==================================================================
# Task 3. Cloud Router / NAT 게이트웨이
# Task 4. Cloud NAT 로깅
# ==================================================================

resource "google_compute_router" "nat_router" {
  name    = var.nat_router_name
  region  = var.region
  network = google_compute_network.privatenet.name
}

resource "google_compute_router_nat" "nat_config" {
  name   = var.nat_gateway_name
  router = google_compute_router.nat_router.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"                  # 외부 IP 자동 할당
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES" # 모든 서브넷의 모든 IP 범위

  # 참고: Cloud NAT는 아웃바운드 NAT만 지원 (인바운드는 불가)

  # Task 4: 로깅 활성화 (콘솔의 'Translation and errors' = ALL)
  log_config {
    enable = true
    filter = "ALL"
  }
}
