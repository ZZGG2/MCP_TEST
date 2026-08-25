# ==================================================================
# Task 2. Cloud Storage 버킷 및 이미지 파일
# ==================================================================

resource "google_storage_bucket" "lab_bucket" {
  name          = var.bucket_name
  location      = "US" # 멀티 리전
  force_destroy = true

  uniform_bucket_level_access = true
}

# 공개 버킷(google training)에서 복사해온 이미지 파일
resource "google_storage_bucket_object" "access_svg" {
  name   = "access.svg"
  bucket = google_storage_bucket.lab_bucket.name
  source = "${path.module}/files/access.svg"
}
