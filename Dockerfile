# 1. 경량화된 Node 18 Alpine 운영체제를 뼈대 베이스 이미지로 채택
FROM node:18-alpine

# 2. 컨테이너 내부 런타임 작업의 기준 디렉토리 정의
WORKDIR /usr/src/app

# 3. 호스트에 존재하는 server.js 소스코드를 컨테이너 내부 런타임 공간으로 복사
COPY server.js .

# 4. 해당 컨테이너가 가동될 때 기본적으로 수행될 서버 실행 명령어 명시
# 다 만들어진 이미지를 가지고 컨테이너를 실행할 때 쓰는 거
CMD ["node", "server.js"]