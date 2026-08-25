output "instance_internal_ip" {
  description = "vm-internal의 내부 IP"
  value       = google_compute_instance.vm_internal.network_interface[0].network_ip
}

output "bucket_url" {
  description = "실습 버킷 URL"
  value       = google_storage_bucket.lab_bucket.url
}

output "nat_gateway" {
  description = "NAT 게이트웨이 이름"
  value       = google_compute_router_nat.nat_config.name
}

output "ssh_command" {
  description = "IAP 터널로 VM 접속하는 명령어"
  value       = "gcloud compute ssh ${var.vm_name} --zone=${var.zone} --tunnel-through-iap"
}
