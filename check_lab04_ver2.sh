#!/usr/bin/env bash
# ==================================================================
# 체크포인트 검증 스크립트
# 실습: 04. Implement Private Google Access and Cloud NAT
#
# 사용법 (WSL에서):
#   bash /mnt/c/Users/tkdxm/GCP_Lab/check_lab04.sh
#
# MD 실습 문서의 주요 구성값을 자동 검증하고,
# 실제 동작 검증이 필요한 항목은 별도로 안내합니다.
# ==================================================================
set -u

REGION="us-central1"
ZONE="us-central1-c"
NETWORK="privatenet"
SUBNET="privatenet-us"
VM="vm-internal"
BUCKET_FILE="lab04_bucket.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
WARN=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

ok() {
  PASS=$((PASS+1))
  printf "  ${GREEN}[PASS]${NC} %s\n" "$1"
}

bad() {
  FAIL=$((FAIL+1))
  printf "  ${RED}[FAIL]${NC} %s${RED}  <-- 확인 필요${NC}\n" "$1"
}

warn() {
  WARN=$((WARN+1))
  printf "  ${YELLOW}[WARN]${NC} %s\n" "$1"
}

section() {
  printf "\n${BLUE}======== %s ========${NC}\n" "$1"
}

low() {
  tr '[:upper:]' '[:lower:]'
}

# ---------------------------------------------------------------
# 사전 확인
# ---------------------------------------------------------------
if ! command -v gcloud >/dev/null 2>&1; then
  echo "오류: gcloud가 설치되어 있지 않습니다."
  exit 1
fi

PROJECT=$(gcloud config get-value project 2>/dev/null)
ACCOUNT=$(gcloud config get-value account 2>/dev/null)

if [ -z "$PROJECT" ]; then
  echo "오류: 프로젝트가 설정되지 않았습니다."
  echo "gcloud config set project <PROJECT_ID> 실행 후 다시 시도하세요."
  exit 1
fi

echo "프로젝트 : $PROJECT"
echo "계정     : $ACCOUNT"
echo "리전/존  : $REGION / $ZONE"

# ==================================================================
section "Task 1. VM 인스턴스 생성하기"
# ==================================================================

# [T1-1] VPC 존재 + Custom subnet mode
mode=$(gcloud compute networks describe "$NETWORK" \
  --format='value(subnetMode)' 2>/dev/null | low)

if [ "$mode" = "custom" ]; then
  ok "[T1-1] VPC '$NETWORK' 존재 (커스텀 서브넷 모드)"
else
  bad "[T1-1] VPC '$NETWORK' 없음 또는 커스텀 모드 아님 (현재: ${mode:-없음})"
fi

# [T1-2] 서브넷 이름 / region / CIDR
subnet_region=$(gcloud compute networks subnets describe "$SUBNET" \
  --region="$REGION" \
  --format='value(region.basename())' 2>/dev/null)

cidr=$(gcloud compute networks subnets describe "$SUBNET" \
  --region="$REGION" \
  --format='value(ipCidrRange)' 2>/dev/null)

if [ "$subnet_region" = "$REGION" ] && [ "$cidr" = "10.130.0.0/20" ]; then
  ok "[T1-2] 서브넷 '$SUBNET' 존재 ($cidr, $REGION)"
else
  bad "[T1-2] 서브넷 설정 불일치 (region=${subnet_region:-없음}, CIDR=${cidr:-없음})"
fi

# [T1-3] 방화벽 규칙 존재 / 네트워크
FWRULE="privatenet-allow-ssh"

fwnet=$(gcloud compute firewall-rules describe "$FWRULE" \
  --format='value(network.basename())' 2>/dev/null)

if [ "$fwnet" = "$NETWORK" ]; then
  ok "[T1-3] 방화벽 규칙 '$FWRULE' 존재 (네트워크: $NETWORK)"
else
  bad "[T1-3] 방화벽 규칙 '$FWRULE' 없음 또는 잘못된 네트워크"
fi

fwjson=$(gcloud compute firewall-rules describe "$FWRULE" \
  --format=json 2>/dev/null)

# [T1-4] Target = all instances in network
target_tags=$(echo "$fwjson" | grep -o '"targetTags": *\[[^]]*\]' 2>/dev/null || true)
target_service_accounts=$(echo "$fwjson" | grep -o '"targetServiceAccounts": *\[[^]]*\]' 2>/dev/null || true)

if [ -z "$target_tags" ] && [ -z "$target_service_accounts" ]; then
  ok "[T1-4] 방화벽 대상: 네트워크 내 모든 인스턴스"
else
  bad "[T1-4] 방화벽 대상이 모든 인스턴스가 아님"
fi

# [T1-5] tcp
if echo "$fwjson" | grep -q '"IPProtocol": *"tcp"\|"IPProtocol": *"TCP"\|"tcp"'; then
  ok "[T1-5] 방화벽 허용 프로토콜 tcp 확인"
else
  bad "[T1-5] 방화벽 허용 프로토콜 tcp 미설정"
fi

# [T1-6] port 22
if echo "$fwjson" | grep -qE '"22"|(^|[^0-9])22([^0-9]|$)'; then
  ok "[T1-6] SSH(tcp:22) 포트 허용 확인"
else
  bad "[T1-6] SSH(tcp:22) 포트 미허용"
fi

# [T1-7] IAP CIDR
if echo "$fwjson" | grep -q '35\.235\.240\.0/20'; then
  ok "[T1-7] 소스 IP 범위 = IAP CIDR(35.235.240.0/20)"
else
  bad "[T1-7] 소스 IP 범위가 IAP CIDR와 불일치"
fi

# [T1-8] VM 상태 / machine type / zone
status=$(gcloud compute instances describe "$VM" \
  --zone="$ZONE" \
  --format='value(status)' 2>/dev/null)

mtype=$(gcloud compute instances describe "$VM" \
  --zone="$ZONE" \
  --format='value(machineType.basename())' 2>/dev/null)

if [ "$status" = "RUNNING" ] && [ "$mtype" = "e2-medium" ]; then
  ok "[T1-8] VM '$VM' RUNNING (e2-medium, $ZONE)"
else
  bad "[T1-8] VM '$VM' 상태=${status:-없음}, 머신유형=${mtype:-없음}"
fi

# [T1-9] VM network / subnet
vmnet=$(gcloud compute instances describe "$VM" \
  --zone="$ZONE" \
  --format='value(networkInterfaces[0].network.basename())' 2>/dev/null)

vmsubnet=$(gcloud compute instances describe "$VM" \
  --zone="$ZONE" \
  --format='value(networkInterfaces[0].subnetwork.basename())' 2>/dev/null)

if [ "$vmnet" = "$NETWORK" ] && [ "$vmsubnet" = "$SUBNET" ]; then
  ok "[T1-9] VM 네트워크=$NETWORK, 서브넷=$SUBNET"
else
  bad "[T1-9] VM 네트워크/서브넷 불일치 (network=${vmnet:-없음}, subnet=${vmsubnet:-없음})"
fi

# [T1-10] External IP 없음
extip=$(gcloud compute instances describe "$VM" \
  --zone="$ZONE" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null)

if [ -z "$extip" ]; then
  ok "[T1-10] VM에 외부 IP 없음 (None)"
else
  bad "[T1-10] VM에 외부 IP가 할당되어 있음: $extip"
fi

# [T1-11] OS image 확인
image=$(gcloud compute instances describe "$VM" \
  --zone="$ZONE" \
  --format='value(disks[0].licenses)' 2>/dev/null)

if echo "$image" | grep -qi 'debian'; then
  ok "[T1-11] VM OS가 Debian 계열 이미지로 확인됨"
else
  warn "[T1-11] Debian 12 여부를 자동 확인하지 못함 (license 정보: ${image:-없음})"
fi

# ==================================================================
section "Task 2. Private Google Access 활성화하기"
# ==================================================================

# 버킷 이름 찾기
BUCKET=""

if [ -f "$SCRIPT_DIR/$BUCKET_FILE" ]; then
  BUCKET=$(tr -d '[:space:]' < "$SCRIPT_DIR/$BUCKET_FILE")
fi

if [ -z "$BUCKET" ] || ! gcloud storage ls -b "gs://$BUCKET" >/dev/null 2>&1; then
  BUCKET=$(gcloud storage buckets list \
    --format='value(name)' 2>/dev/null | grep -i 'pganat' | head -1)
fi

# [T2-1] bucket
if [ -n "$BUCKET" ] && gcloud storage ls -b "gs://$BUCKET" >/dev/null 2>&1; then
  ok "[T2-1] Storage 버킷 존재: gs://$BUCKET"
else
  bad "[T2-1] Storage 버킷을 찾을 수 없음"
fi

# [T2-2] bucket location = US multi-region
if [ -n "$BUCKET" ]; then
  loc=$(gcloud storage buckets describe "gs://$BUCKET" \
    --format='value(location)' 2>/dev/null | low)

  if [ "$loc" = "us" ]; then
    ok "[T2-2] 버킷 위치: 멀티 리전 US"
  else
    bad "[T2-2] 버킷 위치가 멀티 리전 US가 아님 (현재: ${loc:-확인불가})"
  fi
else
  bad "[T2-2] 버킷이 없어 위치 확인 불가"
fi

# [T2-3] access.svg
if [ -n "$BUCKET" ] && \
   gcloud storage ls "gs://$BUCKET/access.svg" >/dev/null 2>&1; then
  ok "[T2-3] 이미지 파일 access.svg 복사 완료"
else
  bad "[T2-3] 버킷에 access.svg 없음"
fi

# [T2-4] PGA
pga=$(gcloud compute networks subnets describe "$SUBNET" \
  --region="$REGION" \
  --format='value(privateIpGoogleAccess)' 2>/dev/null | low)

if [ "$pga" = "true" ]; then
  ok "[T2-4] 서브넷에서 Private Google Access 활성화됨"
else
  bad "[T2-4] Private Google Access 비활성화 상태"
fi

# ==================================================================
section "Task 3. Cloud NAT 게이트웨이 구성하기"
# ==================================================================

# [T3-1] Router 존재 / network
rnet=$(gcloud compute routers describe nat-router \
  --region="$REGION" \
  --format='value(network.basename())' 2>/dev/null)

if [ "$rnet" = "$NETWORK" ]; then
  ok "[T3-1] Cloud Router 'nat-router' 존재 ($REGION, $NETWORK 연결)"
else
  bad "[T3-1] Cloud Router 'nat-router' 없음 또는 네트워크 불일치"
fi

# [T3-2] NAT 존재
nat_exists=$(gcloud compute routers nats describe nat-config \
  --router=nat-router \
  --region="$REGION" \
  --format='value(name)' 2>/dev/null)

if [ "$nat_exists" = "nat-config" ]; then
  ok "[T3-2] Cloud NAT 'nat-config' 존재"
else
  bad "[T3-2] Cloud NAT 'nat-config' 없음"
fi

# [T3-3] NAT 대상
natrange=$(gcloud compute routers nats describe nat-config \
  --router=nat-router \
  --region="$REGION" \
  --format='value(sourceSubnetworkIpRangesToNat)' 2>/dev/null | low)

if [ "$natrange" = "all_subnetworks_all_ip_ranges" ]; then
  ok "[T3-3] NAT 대상: 모든 서브넷의 모든 IP 범위"
else
  bad "[T3-3] NAT 서브넷 범위 설정 불일치 (현재: ${natrange:-없음})"
fi

# [T3-4] NAT external IP allocation
natip=$(gcloud compute routers nats describe nat-config \
  --router=nat-router \
  --region="$REGION" \
  --format='value(natIpAllocateOption)' 2>/dev/null | low)

if [ "$natip" = "auto_only" ]; then
  ok "[T3-4] NAT 외부 IP 자동 할당 설정됨"
else
  bad "[T3-4] NAT 외부 IP 자동 할당 미설정 (현재: ${natip:-없음})"
fi

# ==================================================================
section "Task 4. Cloud NAT Logging 구성하기"
# ==================================================================

# [T4-1] logging enable
logenable=$(gcloud compute routers nats describe nat-config \
  --router=nat-router \
  --region="$REGION" \
  --format='value(logConfig.enable)' 2>/dev/null | low)

if [ "$logenable" = "true" ]; then
  ok "[T4-1] Cloud NAT 로깅 활성화됨"
else
  bad "[T4-1] Cloud NAT 로깅 비활성화 상태"
fi

# [T4-2] logging filter
logfilter=$(gcloud compute routers nats describe nat-config \
  --router=nat-router \
  --region="$REGION" \
  --format='value(logConfig.filter)' 2>/dev/null | low)

if [ "$logfilter" = "all" ]; then
  ok "[T4-2] 로그 필터: Translation and errors (= ALL)"
else
  bad "[T4-2] 로그 필터 불일치 (현재: ${logfilter:-없음})"
fi

# ==================================================================
section "실제 동작 검증 안내"
# ==================================================================

cat <<EOF

다음 항목은 GCP 리소스 설정만으로는 검증할 수 없으므로
VM 내부에서 직접 실행해야 합니다.

[1] IAP SSH 접속
  gcloud compute ssh $VM --zone=$ZONE --tunnel-through-iap

[2] NAT 인터넷 연결 확인
  ping -c 2 www.google.com
  sudo apt-get update

[3] Private Google Access 확인
  export MY_BUCKET=\$(cat $SCRIPT_DIR/$BUCKET_FILE)
  gcloud storage cp gs://\$MY_BUCKET/*.svg .

[4] NAT Logging 확인
  VM에서 다시:
  sudo apt-get update

  이후 Console > Network services > Cloud NAT > nat-config
  > View in Logs Explorer 에서 NAT 로그 확인

주의:
  - IAP SSH가 실제로 연결되는지는 이 스크립트에서 자동 실행하지 않습니다.
  - PGA와 NAT의 실제 통신 성공 여부도 VM 내부 테스트가 필요합니다.
  - NAT 로그 역시 실제 트래픽 발생 후 Logs Explorer에서 확인해야 합니다.

EOF

# ==================================================================
printf "\n${BLUE}================ 결과 요약 ================${NC}\n"

if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}🎉 자동 체크포인트 모두 통과! (${PASS}/${PASS})${NC}\n"
else
  printf "${RED}자동 검증 통과: ${PASS}, 실패: ${FAIL}${NC}\n"
fi

if [ "$WARN" -gt 0 ]; then
  printf "${YELLOW}경고: ${WARN}개${NC}\n"
fi

printf "\n자동 검증 범위:\n"
printf "  - VPC / Subnet / Firewall\n"
printf "  - VM / Network / Subnet / External IP\n"
printf "  - Cloud Storage bucket / access.svg\n"
printf "  - Private Google Access\n"
printf "  - Cloud Router / Cloud NAT\n"
printf "  - Cloud NAT Logging\n"

if [ "$FAIL" -eq 0 ]; then
  exit 0
else
  exit 1
fi
