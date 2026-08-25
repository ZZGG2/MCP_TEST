# ==================================================================
# Task 1. 외부 IP가 없는 VM 인스턴스
# ==================================================================
resource "google_compute_instance" "vm_internal" {
  name         = var.vm_name
  zone         = var.zone
  machine_type = var.machine_type

  boot_disk {
    initialize_params {
      image = var.image # Debian GNU/Linux 12 (bookworm)
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.privatenet_us.name
    # access_config 블록이 없으면 외부 IP 없음 (--no-address 와 동일)
  }

  # gcloud create 시 기본으로 부착되는 서비스 계정/스코프와 동일하게 유지
  # (import 후 불필요한 변경 감지를 방지)
  service_account {
    email = "73022286315-compute@developer.gserviceaccount.com" # 기본 Compute SA
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/pubsub",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }
}
