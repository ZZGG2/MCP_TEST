#!/usr/bin/env bash
# ==================================================================
#  체크포인트 검증 스크립트
#  실습: 04.Implement Private Google Access and Cloud NAT
#
#  사용법 (WSL에서):
#     bash /mnt/c/Users/tkdxm/GCP_Lab/check_lab04.sh
#
#  각 체크포인트를 검사해서 [PASS]/[FAIL]로 알려줍니다.
# ==================================================================
set -u

REGION="us-central1"
ZONE="us-central1-c"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0; FAIL=0
GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[1;34m'; NC='\033[0m'

ok()  { PASS=$((PASS+1)); printf "  ${GREEN}[PASS]${NC} %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  ${RED}[FAIL]${NC} %s${RED}  <-- 확인 필요${NC}\n" "$1"; }
section() { printf "\n${BLUE}======== %s ========${NC}\n" "$1"; }
low() { tr '[:upper:]' '[:lower:]'; }

# 사전 확인: gcloud / 인증 / 프로젝트
if ! command -v gcloud >/dev/null 2>&1; then
  echo "오류: gcloud가 설치되어 있지 않습니다."; exit 1
fi
PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT" ]; then
  echo "오류: 프로젝트가 설정되지 않았습니다. 'gcloud config set project <PROJECT_ID>' 실행 후 다시 시도하세요."
  exit 1
fi
echo "프로젝트 : $PROJECT"
echo "계정     : $(gcloud config get-value account 2>/dev/null)"
echo "리전/존  : $REGION / $ZONE"

section "Task 1. VM 인스턴스 생성하기"

# [T1-1] VPC 네트워크 (커스텀 서브넷 모드)
mode=$(gcloud compute networks describe privatenet --format=yaml 2>/dev/null \
       | grep -iE '(x_gcloud_subnet_mode|subnetMode):' | head -1 | awk '{print $2}' | low)
if [ "$mode" = "custom" ]; then
  ok "[T1-1] VPC 'privatenet' 존재 (커스텀 서브넷 모드)"
else
  bad "[T1-1] VPC 'privatenet' 없음 또는 커스텀 모드 아님"
fi

# [T1-2] 서브넷 CIDR
cidr=$(gcloud compute networks subnets describe privatenet-us --region=$REGION \
       --format='value(ipCidrRange)' 2>/dev/null)
if [ "$cidr" = "10.130.0.0/20" ]; then
  ok "[T1-2] 서브넷 'privatenet-us' 존재 (10.130.0.0/20, us-central1)"
else
  bad "[T1-2] 서브넷 'privatenet-us' 없음 또는 CIDR 불일치 (현재: ${cidr:-없음})"
fi

# [T1-3] 방화벽 규칙 - 존재/네트워크
fwnet=$(gcloud compute firewall-rules describe privatenet-allow-ssh \
        --format='value(network.basename())' 2>/dev/null)
if [ "$fwnet" = "privatenet" ]; then
  ok "[T1-3] 방화벽 규칙 'privatenet-allow-ssh' 존재 (네트워크: privatenet)"
else
  bad "[T1-3] 방화벽 규칙 'privatenet-allow-ssh' 없음 또는 잘못된 네트워크"
fi

# [T1-4~6] 방화벽 규칙 - 프로토콜/포트/소스 범위
fwjson=$(gcloud compute firewall-rules describe privatenet-allow-ssh --format=json 2>/dev/null)
if echo "$fwjson" | grep -q '"tcp"'; then
  ok "[T1-4] 방화벽 허용 프로토콜 tcp 확인"
else
  bad "[T1-4] 방화벽 허용 프로토콜 tcp 미설정"
fi
if echo "$fwjson" | grep -q "'22'\|\"22\""; then
  ok "[T1-5] SSH(tcp:22) 포트 허용 확인"
else
  bad "[T1-5] SSH(tcp:22) 포트 미허용"
fi
if echo "$fwjson" | grep -q '35\.235\.240\.0/20'; then
  ok "[T1-6] 소스 IP 범위 = IAP용 CIDR(35.235.240.0/20) 확인"
else
  bad "[T1-6] 소스 IP 범위가 IAP CIDR(35.235.240.0/20)과 불일치"
fi

# [T1-7] VM 인스턴스 상태/머신유형
status=$(gcloud compute instances describe vm-internal --zone=$ZONE \
         --format='value(status)' 2>/dev/null)
mtype=$(gcloud compute instances describe vm-internal --zone=$ZONE \
        --format='value(machineType.basename())' 2>/dev/null)
if [ "$status" = "RUNNING" ] && [ "$mtype" = "e2-medium" ]; then
  ok "[T1-7] VM 'vm-internal' RUNNING (e2-medium, $ZONE)"
else
  bad "[T1-7] VM 'vm-internal' 상태=${status:-없음}, 머신유형=${mtype:-없음}"
fi

# [T1-8] 외부 IP가 None인지
extip=$(gcloud compute instances describe vm-internal --zone=$ZONE \
        --format='value(networkInterfaces[0].accessConfigs)' 2>/dev/null)
if [ -z "$extip" ]; then
  ok "[T1-8] VM에 외부 IP 없음 (None) - 격리됨"
else
  bad "[T1-8] VM에 외부 IP가 할당되어 있음: $extip (--no-address 필요)"
fi

# ------------------------------------------------------------------
section "Task 2. Private Google Access 활성화하기"

# 버킷 이름 찾기 (lab04_bucket.txt 우선, 없으면 접두어 검색)
BUCKET=""
if [ -f "$SCRIPT_DIR/lab04_bucket.txt" ]; then
  BUCKET=$(tr -d '[:space:]' < "$SCRIPT_DIR/lab04_bucket.txt")
fi
if [ -z "$BUCKET" ] || ! gcloud storage ls -b "gs://$BUCKET" >/dev/null 2>&1; then
  BUCKET=$(gcloud storage buckets list --format='value(name)' 2>/dev/null | grep -i 'pganat' | head -1)
fi

if [ -n "$BUCKET" ] && gcloud storage ls -b "gs://$BUCKET" >/dev/null 2>&1; then
  ok "[T2-1] Storage 버킷 존재: gs://$BUCKET"
else
  bad "[T2-1] Storage 버킷을 찾을 수 없음"
fi

loc=$(gcloud storage buckets describe "gs://$BUCKET" --format=json 2>/dev/null \
      | grep -o '"location": *"[^"]*"' | head -1)
if echo "$loc" | grep -qi '"US"'; then
  ok "[T2-2] 버킷 위치: 멀티 리전 US"
else
  bad "[T2-2] 버킷 위치가 멀티 리전 US가 아님 (현재: ${loc:-확인불가})"
fi

if gcloud storage ls "gs://$BUCKET/access.svg" >/dev/null 2>&1; then
  ok "[T2-3] 이미지 파일 access.svg 복사 완료"
else
  bad "[T2-3] 버킷에 access.svg 없음"
fi

pga=$(gcloud compute networks subnets describe privatenet-us --region=$REGION \
      --format='value(privateIpGoogleAccess)' 2>/dev/null | low)
if [ "$pga" = "true" ]; then
  ok "[T2-4] 서브넷에서 Private Google Access 활성화됨"
else
  bad "[T2-4] Private Google Access 비활성화 상태"
fi

# ------------------------------------------------------------------
section "Task 3. Cloud NAT 게이트웨이 구성하기"

rnet=$(gcloud compute routers describe nat-router --region=$REGION \
       --format='value(network.basename())' 2>/dev/null)
if [ "$rnet" = "privatenet" ]; then
  ok "[T3-1] Cloud Router 'nat-router' 존재 ($REGION, privatenet 연결)"
else
  bad "[T3-1] Cloud Router 'nat-router' 없음 또는 네트워크 불일치"
fi

natrange=$(gcloud compute routers nats describe nat-config --router=nat-router \
           --region=$REGION --format='value(sourceSubnetworkIpRangesToNat)' 2>/dev/null | low)
if [ "$natrange" = "all_subnetworks_all_ip_ranges" ]; then
  ok "[T3-2] NAT 대상: 모든 서브넷의 모든 IP 범위"
else
  bad "[T3-2] NAT 서브넷 범위 설정 불일치 (현재: ${natrange:-없음})"
fi

natip=$(gcloud compute routers nats describe nat-config --router=nat-router \
        --region=$REGION --format='value(natIpAllocateOption)' 2>/dev/null | low)
if [ "$natip" = "auto_only" ]; then
  ok "[T3-3] NAT 외부 IP 자동 할당 설정됨"
else
  bad "[T3-3] NAT 외부 IP 자동 할당 미설정 (현재: ${natip:-없음})"
fi

# ------------------------------------------------------------------
section "Task 4. Cloud NAT Logging 구성하기"

logenable=$(gcloud compute routers nats describe nat-config --router=nat-router \
            --region=$REGION --format='value(logConfig.enable)' 2>/dev/null | low)
if [ "$logenable" = "true" ]; then
  ok "[T4-1] Cloud NAT 로깅 활성화됨"
else
  bad "[T4-1] Cloud NAT 로깅 비활성화 상태"
fi

logfilter=$(gcloud compute routers nats describe nat-config --router=nat-router \
            --region=$REGION --format='value(logConfig.filter)' 2>/dev/null | low)
if [ "$logfilter" = "all" ]; then
  ok "[T4-2] 로그 필터: Translation and errors (= ALL)"
else
  bad "[T4-2] 로그 필터 불일치 (현재: ${logfilter:-없음})"
fi

# ------------------------------------------------------------------
printf "\n${BLUE}================ 결과 요약 ================${NC}\n"
if [ $FAIL -eq 0 ]; then
  printf "${GREEN}🎉 모든 체크포인트 통과! (${PASS}/${PASS})${NC}\n"
  RESULT=0
else
  printf "${RED}통과: ${PASS}, 실패: ${FAIL}${NC}\n"
  RESULT=1
fi

cat <<'EOF'

--- 선택: 수동 연결 테스트 (실습 문서의 핵심 동작 확인) ---
  # 1) IAP 터널로 내부 VM 접속 (베스천 호스트 없이)
  gcloud compute ssh vm-internal --zone=us-central1-c --tunnel-through-iap

  # 2) VM 안에서 인터넷/NAT 확인 (둘 다 성공해야 정상)
  ping -c 2 www.google.com
  sudo apt-get update

  # 3) Private Google Access 확인 (VM 안에서 성공해야 정상)
  export MY_BUCKET=$(cat /mnt/c/Users/tkdxm/GCP_Lab/lab04_bucket.txt)
  gcloud storage cp gs://$MY_BUCKET/*.svg .

  # 4) NAT 로그 확인: Console > Network services > Cloud NAT > nat-config > View in Logs Explorer
EOF

exit $RESULT