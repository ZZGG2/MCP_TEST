# Terraform - 04. Implement Private Google Access and Cloud NAT

이 실습(04.Implement Private Google Access and Cloud NAT_KR.md)에서 만든
GCP 리소스를 코드(IaC)로 관리합니다.

## 관리 대상 리소스 (8개)

| 파일 | 리소스 | 실습 Task |
|---|---|---|
| network.tf | VPC `privatenet` (커스텀 모드) | Task 1 |
| network.tf | 서브넷 `privatenet-us` (10.130.0.0/20) + **Private Google Access On** | Task 1, 2 |
| network.tf | 방화벽 `privatenet-allow-ssh` (IAP CIDR → tcp:22) | Task 1 |
| compute.tf | VM `vm-internal` (외부 IP 없음, e2-medium, Debian 12) | Task 1 |
| storage.tf | 버킷 + `access.svg` 오브젝트 | Task 2 |
| nat.tf | Cloud Router `nat-router` / NAT `nat-config` (+로깅 ALL) | Task 3, 4 |

## 사용법

```bash
cd /mnt/c/Users/tkdxm/GCP_Lab/terraform
terraform init        # 최초 1회: 프로바이더 설치

# 인증 (둘 중 하나)
gcloud auth application-default login   # 권장: 브라우저 로그인 1회
# 또는 세션별 임시 토큰 사용:
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)

terraform plan      # 변경 사항 미리보기
terraform apply     # 생성/수정 적용
terraform destroy   # 실습 종료 시 전체 삭제 (버킷 포함, force_destroy=true)
```

## 현재 상태

- **기존 리소스를 import 한 상태**입니다. 즉 gcloud로 만든 것과 동일한 리소스를
  Terraform이 관리하며, `terraform plan` 결과는 "No changes" 입니다.
- 상태 확인: `terraform state list`
- 출력 값 확인: `terraform output`

## 주요 변수 (terraform.tfvars)

```hcl
project_id  = "kdt5-06"
bucket_name = "kdt5-06-lab04-pganat-4328"  # 전역 고유 이름
```

새 프로젝트에 처음부터 재구축하려면 bucket_name만 바꾸고
`terraform apply` 하면 됩니다.
