#!/bin/bash

# Nginx가 블루 컨테이너 바라보게 세팅 -> canary는 비율임 둘 다 떠있어야 함 (weight 조정)
function update_nginx_weight() {
    local BLUE=$1   # 트래픽 비율
    local GREEN=$2  # 트래픽 비율
    echo ">> 트래픽 비율 변경 중 ... Blue(${BLUE}%) / Green(${Green}%)"

    # [핵심] 할당 비율이 0 초과인 서버만 설정 문자열 명단에 편입하여 변수 조립!
    # 둘 다 띄워놔야 하기 때문에 두 개 다 넣어놓는 구조임. weight 옵션 제공함.
    # 둘 중에 하나는 0퍼센트가 되는 순간이 있는데 0보다 큰 경우에만 이 값을 넣겠다고 제어해줌.
    CONF="upstream backend { "
    [ "$BLUE" -gt 0 ] && CONF="${CONF} server app-blue:8080 weight=${BLUE}; "
    [ "$GREEN" -gt 0 ] && CONF="${CONF} server app-green:8081 weight=${GREEN}; "
    CONF="${CONF} }"

    # 호스트 밖에서 Nginx 컨테이너 내부로 설정 파일을 덮어쓰고, 프록시를 무중단 리로드(Reload) 처리합니다.
    # excute 시킴, 해당 경로에 덮어쓰고 다시 reload 시킴
    docker exec nginx-proxy sh -c "echo '$CONF' > /etc/nginx/conf.d/upstream.inc"
    docker exec nginx-proxy nginx -s reload
}

# 1. 지금 켜져있는 서버가 누군지 검사합니다.
IS_BLUE=$(docker ps -q -f name="^app-blue$")

if [ -n "$IS_BLUE" ]; then
    CURRENT="blue"; TARGET="green"; TARGET_PORT=8081; TARGET_COLOR="🟢 GREEN"
else
    CURRENT="green"; TARGET="blue"; TARGET_PORT=8080; TARGET_COLOR="🔵 BLUE"
fi

echo "🚀 새로운 버전 [${TARGET}] 구동 시작!"

# 2. 최신 코드로 도커 이미지를 굽습니다(build).
docker build -t my-canary-app .

# 3. 혹시 예전에 쓰다 남은 타겟 컨테이너가 있다면 미리 삭제합니다.
docker rm -f app-$TARGET 2>/dev/null

# 4. 새 컨테이너를 실행합니다! (핵심: --network 로 같은 가상망에 묶어줍니다)
# my-canary-app 이미지에 위의 환경변수를 넣어서 canary-net 네트워크에 detach 하겠다
docker run -d --name app-$TARGET \
  --network canary-net \
  -e PORT=$TARGET_PORT \
  -e COLOR="$TARGET_COLOR" \
  my-canary-app # 위에서 만든 이미지

# 5. Health Check: Nginx가 새 서버랑 대화가 잘 되는지 확인합니다.
# 구동시간이 필요하기 때문에 sleep 5
sleep 5
RESPONSE=$(docker exec nginx-proxy sh -c "wget -qO- http://app-$TARGET:${TARGET_PORT}")
if [ -z "$RESPONSE" ]; then
    echo "❌ 실패! 새 서버가 제대로 켜지지 않았습니다. 롤백합니다."
    docker rm -f app-$TARGET
    exit 1
fi

# ==========================================
# 6. 점진적 트래픽 전환 (Canary Stages)
# ==========================================
echo "✅ [1단계] 10% 카나리 오픈 (15초 대기)"
# 15초 sleep인 이유는 테스트 해보라고 (새로고침 하다보면 어쩔 때는 green, 어쩔 때는 blue 뜰 거임)
if [ "$TARGET" == "green" ]; then update_nginx_weight 90 10; else update_nginx_weight 10 90; fi; sleep 15

echo "✅ [2단계] 50% 트래픽 전환 (15초 대기)"
if [ "$TARGET" == "green" ]; then update_nginx_weight 50 50; else update_nginx_weight 50 50; fi; sleep 15

echo "🎉 [3단계] 100% 완전 전환!"
if [ "$TARGET" == "green" ]; then update_nginx_weight 0 100; else update_nginx_weight 100 0; fi

# 7. 이제 쓸모없어진 구버전 컨테이너를 삭제(rm)합니다!
# 100% 이관되면 서버 내려버리는 거
docker rm -f app-$CURRENT
