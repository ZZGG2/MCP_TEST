# 📚 GCP 네트워킹 실습 정리 (Google Cloud Skills Boost KR)

Google Cloud Skills Boost 실습 문서(한국어)를 학습하며 수행한 내용을 정리한 저장소입니다.
**Lab 04 (Private Google Access & Cloud NAT)** 는 실제 GCP 프로젝트에 리소스를 생성하고,
체크포인트 검증 스크립트와 Terraform(IaC) 코드까지 완료했습니다.

## 📂 폴더 구조

```
GCP_Lab/
├── 01 ~ 15 *.md                  # 실습 가이드 문서 (한국어 번역본)
├── check_lab04.sh                # Lab 04 체크포인트 검증 스크립트 (17개 항목)
├── lab04_bucket.txt              # Lab 04에서 생성한 버킷 이름
└── terraform/                    # Lab 04의 Terraform 코드 (README 참고)
    ├── versions.tf               # 프로바이더 설정
    ├── variables.tf              # 변수 정의
    ├── network.tf                # VPC / 서브넷(PGA On) / 방화벽
    ├── compute.tf                # 외부 IP 없는 VM
    ├── storage.tf                # 버킷 + 이미지 오브젝트
    ├── nat.tf                    # Cloud Router + NAT 게이트웨이(+로깅)
    ├── outputs.tf / terraform.tfvars
    └── files/access.svg          # 버킷 업로드용 샘플 이미지
```

## 🧪 Lab 04. Implement Private Google Access and Cloud NAT

### 개요
외부 IP가 없는 VM에 Private Google Access와 Cloud NAT를 구성하여,
격리된 VM도 Google API와 인터넷(업데이트/패치용)에 필요할 때만 접근하게 하는 실습.

### 생성한 리소스 (프로젝트: kdt5-06, us-central1)

| Task | 리소스 | 핵심 설정 |
|---|---|---|
| 1 | VPC `privatenet` | 커스텀 서브넷 모드 |
| 1 | 서브넷 `privatenet-us` | 10.130.0.0/20 |
| 1 | 방화벽 `privatenet-allow-ssh` | IAP CIDR(35.235.240.0/20) → tcp:22 |
| 1 | VM `vm-internal` | e2-medium, Debian 12, **외부 IP 없음** |
| 2 | Storage 버킷 | 멀티 리전 US + access.svg |
| 2 | Private Google Access | 서브넷 수준 활성화 |
| 3 | Cloud Router `nat-router` / NAT `nat-config` | IP 자동 할당, 전체 서브넷 대상 |
| 4 | NAT 로깅 | Translation and errors (= filter ALL) |

### 핵심 개념
- **IAP 터널**: 베스천 호스트 없이 `gcloud compute ssh --tunnel-through-iap`로 내부 VM 접속
- **Private Google Access**: 프라이빗 IP만으로 Google API/서비스 접근 (서브넷 단위 설정)
- **Cloud NAT**: 아웃바운드 전용 NAT → 업데이트/패치 등 인터넷 아웃바운드 허용 (고가용성, 관리형)

## ✅ 검증 결과

```text
$ bash check_lab04.sh
  [PASS] x 17  →  17/17 통과
$ cd terraform && terraform plan
  No changes. Your infrastructure matches the configuration.
```

- 체크포인트: 리소스 존재/설정값을 자동 판정 (PASS/FAIL)
- Terraform: gcloud로 만든 기존 리소스를 `import` 하여 상태 일치 확인 완료

## 🚀 사용법

```bash
# 1) 체크포인트 검증 (WSL)
bash /mnt/c/Users/tkdxm/GCP_Lab/check_lab04.sh

# 2) Terraform 관리
cd /mnt/c/Users/tkdxm/GCP_Lab/terraform
gcloud auth application-default login   # 최초 1회
terraform plan                          # 변경 사항 미리보기
terraform apply                         # 적용
terraform destroy                       # 실습 종료 시 전체 삭제 (과금 정리)
```

## ⚠️ 주의사항

- `.gitignore`로 Terraform 상태 파일(`*.tfstate`)과 프로바이더 바이너리(`.terraform/`)는 커밋하지 않습니다.
- `terraform.tfvars`에는 프로젝트 ID/버킷 이름만 들어있으나, 공개 레포 운영 시 노출 여부를 확인하세요.
- VM(e2-medium)과 Cloud NAT는 실행 중 과금이 발생하므로 실습 종료 후 `terraform destroy` 권장.
