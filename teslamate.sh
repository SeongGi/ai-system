#!/bin/bash

# ================================================================
# TeslaMate 자동 설치 스크립트
# 
# 작성자: Choi Seonggi <linux1547@hanmail.net>
# 블로그: https://seonggi.kr
# 버전: 1.0
# 지원 OS: Ubuntu, Debian, CentOS, RHEL, Fedora, Oracle Linux
# 설명: Docker와 Docker compose 사용하여 TeslaMate를 자동으로 설치합니다
# 
# 실행 방법: bash install_teslamate.sh
# ================================================================

set -e

# 색상 코드 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 로깅 함수
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

log_install() {
    printf "${CYAN}[INSTALL]${NC} %s\n" "$1"
}

log_author() {
    printf "${PURPLE}[INFO]${NC} %s\n" "$1"
}

log_progress() {
    printf "${WHITE}[진행중]${NC} %s\n" "$1"
}

# 명령어 실행 함수 (실시간 출력)
run_command() {
    local cmd="$1"
    local description="$2"
    
    log_progress "$description"
    printf "${CYAN}실행중: %s${NC}\n" "$cmd"
    
    if eval "$cmd"; then
        log_info "$description 완료"
        return 0
    else
        log_error "$description 실패"
        log_error "실행 명령어: $cmd"
        return 1
    fi
}

# 배너 출력
show_banner() {
    printf "${BLUE}"
    echo "================================================================"
    echo "    TeslaMate 자동 설치 스크립트 v1.0 "
    echo "================================================================"
    printf "${NC}\n"
    printf "${PURPLE}작성자: Choi Seonggi <linux1547@hanmail.net>${NC}\n"
    printf "${PURPLE}블로그: https://seonggi.kr${NC}\n"
    echo ""
    echo "이 스크립트는 TeslaMate를 Docker로 자동 설치합니다."
    echo "Docker가 없으면 자동으로 설치할 수 있습니다."
    echo "설치 과정에서 몇 가지 정보를 입력해야 합니다."
    printf "${YELLOW}※ 설치 과정이 실시간으로 표시됩니다${NC}\n"
    echo ""
}

# OS 감지
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        OS_VERSION=$VERSION_ID
        PRETTY_NAME=$PRETTY_NAME
    elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | cut -d' ' -f1)
        PRETTY_NAME=$(cat /etc/redhat-release)
    elif [ -f /etc/debian_version ]; then
        OS="Debian"
        PRETTY_NAME="Debian"
    else
        OS=$(uname -s)
        PRETTY_NAME=$(uname -s)
    fi
    
    log_info "감지된 OS: $PRETTY_NAME"
    log_info "OS 버전: ${OS_VERSION:-알 수 없음}"
}

# 패키지 관리자 확인
get_package_manager() {
    if command -v apt > /dev/null 2>&1; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt update"
        PKG_INSTALL="apt install -y"
    elif command -v yum > /dev/null 2>&1; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum update -y"
        PKG_INSTALL="yum install -y"
    elif command -v dnf > /dev/null 2>&1; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf update -y"
        PKG_INSTALL="dnf install -y"
    elif command -v pacman > /dev/null 2>&1; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy"
        PKG_INSTALL="pacman -S --noconfirm"
    else
        log_error "지원하지 않는 패키지 관리자입니다."
        return 1
    fi
    
    log_info "패키지 관리자: $PKG_MANAGER"
    return 0
}

# Docker 설치 (Ubuntu/Debian)
install_docker_debian() {
    log_install "Docker 설치 시작 (Debian 계열)..."
    
    # 기존 Docker 패키지 제거
    log_progress "기존 Docker 패키지 제거 중..."
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # 필수 패키지 설치
    if ! run_command "sudo apt update" "패키지 목록 업데이트"; then
        return 1
    fi
    
    if ! run_command "sudo apt install -y ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common" "필수 패키지 설치"; then
        return 1
    fi
    
    # Docker GPG 키 추가
    log_progress "Docker GPG 키 추가 중..."
    sudo mkdir -p /etc/apt/keyrings
    if ! run_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg" "Docker GPG 키 추가"; then
        return 1
    fi
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # APT 저장소 추가
    log_progress "Docker APT 저장소 추가 중..."
    if echo "$OS" | grep -q "Ubuntu"; then
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    else
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
            $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    
    # 패키지 목록 다시 업데이트
    if ! run_command "sudo apt update" "Docker 저장소 추가 후 패키지 목록 업데이트"; then
        return 1
    fi
    
    # Docker 설치
    if ! run_command "sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Docker 엔진 설치"; then
        return 1
    fi
    
    # Docker 서비스 시작
    if ! run_command "sudo systemctl start docker" "Docker 서비스 시작"; then
        return 1
    fi
    
    if ! run_command "sudo systemctl enable docker" "Docker 자동 시작 설정"; then
        return 1
    fi
    
    # 사용자를 docker 그룹에 추가
    if ! run_command "sudo usermod -aG docker $USER" "사용자를 docker 그룹에 추가"; then
        return 1
    fi
    
    return 0
}

# Docker 설치 (CentOS/RHEL/Fedora/Oracle Linux)
install_docker_redhat() {
    log_install "Docker 설치 시작 (Red Hat 계열)..."
    
    # 기존 Docker 패키지 제거
    log_progress "기존 Docker 패키지 제거 중..."
    sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    
    if [ "$PKG_MANAGER" = "dnf" ]; then
        # Fedora
        log_progress "Fedora용 Docker 저장소 설정 중..."
        if ! run_command "sudo dnf -y install dnf-plugins-core" "dnf-plugins-core 설치"; then
            return 1
        fi
        
        if ! run_command "sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo" "Docker 저장소 추가"; then
            return 1
        fi
        
        if ! run_command "sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Docker 설치"; then
            return 1
        fi
    else
        # CentOS/RHEL/Oracle Linux
        log_progress "Red Hat 계열용 필수 패키지 설치 중..."
        if ! run_command "sudo yum install -y yum-utils device-mapper-persistent-data lvm2" "필수 패키지 설치"; then
            log_warn "필수 패키지 설치에 실패했지만 계속 진행합니다..."
        fi
        
        log_progress "Docker 저장소 추가 중..."
        if ! run_command "sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo" "Docker 저장소 추가"; then
            return 1
        fi
        
        log_progress "Docker 설치 중... (시간이 오래 걸릴 수 있습니다)"
        if ! run_command "sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Docker 설치"; then
            return 1
        fi
    fi
    
    # Docker 서비스 시작
    if ! run_command "sudo systemctl start docker" "Docker 서비스 시작"; then
        return 1
    fi
    
    if ! run_command "sudo systemctl enable docker" "Docker 자동 시작 설정"; then
        return 1
    fi
    
    # 사용자를 docker 그룹에 추가
    if ! run_command "sudo usermod -aG docker $USER" "사용자를 docker 그룹에 추가"; then
        return 1
    fi
    
    # Docker 설치 검증
    log_progress "Docker 설치 검증 중..."
    sleep 3
    if sudo docker run --rm hello-world; then
        log_info "Docker 설치 검증 완료!"
    else
        log_warn "Docker 설치 검증에 실패했지만 설치는 완료되었습니다."
    fi
    
    return 0
}

# Docker 설치
install_docker() {
    case $PKG_MANAGER in
        "apt")
            if ! install_docker_debian; then
                return 1
            fi
            ;;
        "yum"|"dnf")
            if ! install_docker_redhat; then
                return 1
            fi
            ;;
        *)
            log_error "Docker 자동 설치가 지원되지 않는 OS입니다."
            log_error "다음 가이드를 참고하여 수동 설치해주세요:"
            log_error "https://docs.docker.com/engine/install/"
            return 1
            ;;
    esac
    
    if command -v docker > /dev/null 2>&1; then
        local docker_version=$(docker --version)
        log_info "Docker 설치 완료: $docker_version"
        
        # Docker Compose 확인
        if docker compose version > /dev/null 2>&1; then
            local compose_version=$(docker compose version)
            log_info "Docker Compose 설치 완료: $compose_version"
        fi
        
        log_warn "Docker 그룹 권한을 적용하려면 로그아웃 후 다시 로그인하세요."
        return 0
    else
        log_error "Docker 설치에 실패했습니다."
        return 1
    fi
}

# 필수 프로그램 확인 (Docker만)
check_requirements() {
    log_step "1. 필수 프로그램 확인 중..."
    
    local need_relogin=false
    
    # OS 및 패키지 관리자 감지
    detect_os
    if ! get_package_manager; then
        log_error "지원하지 않는 OS입니다."
        exit 1
    fi
    
    # Docker 확인
    if ! command -v docker > /dev/null 2>&1; then
        log_warn "Docker가 설치되어 있지 않습니다."
        printf "Docker를 자동으로 설치하시겠습니까? (y/N): "
        read install_docker_choice
        
        if [ "$install_docker_choice" = "y" ] || [ "$install_docker_choice" = "Y" ]; then
            echo ""
            log_install "Docker 설치를 시작합니다..."
            printf "${YELLOW}※ 설치 과정이 표시됩니다. 시간이 오래 걸릴 수 있습니다.${NC}\n"
            echo ""
            
            if ! install_docker; then
                log_error "Docker 설치에 실패했습니다."
                log_error "수동 설치 가이드: https://docs.docker.com/get-docker/"
                exit 1
            fi
            need_relogin=true
        else
            log_error "Docker가 필요합니다."
            log_error "설치 가이드: https://docs.docker.com/get-docker/"
            exit 1
        fi
    else
        local docker_version=$(docker --version 2>/dev/null || echo "Docker installed but permission denied")
        log_info "Docker 확인됨: $docker_version"
        
        # Docker 그룹 권한 확인
        if ! docker ps > /dev/null 2>&1; then
            log_warn "Docker 실행 권한이 없습니다."
            if ! groups $USER | grep -q docker; then
                printf "현재 사용자를 docker 그룹에 추가하시겠습니까? (y/N): "
                read add_docker_group
                
                if [ "$add_docker_group" = "y" ] || [ "$add_docker_group" = "Y" ]; then
                    if run_command "sudo usermod -aG docker $USER" "사용자를 docker 그룹에 추가"; then
                        need_relogin=true
                        log_info "사용자를 docker 그룹에 추가했습니다."
                    fi
                fi
            fi
        fi
    fi
    
    # Docker Compose 확인
    if ! command -v docker-compose > /dev/null 2>&1 && ! docker compose version > /dev/null 2>&1; then
        log_warn "Docker Compose가 설치되어 있지 않습니다."
        
        if command -v docker > /dev/null 2>&1; then
            # 최신 Docker는 compose 플러그인 포함
            if docker compose version > /dev/null 2>&1; then
                log_info "Docker Compose 플러그인이 사용 가능합니다."
            else
                log_error "Docker Compose를 수동으로 설치해주세요."
                log_error "설치 가이드: https://docs.docker.com/compose/install/"
                exit 1
            fi
        else
            log_error "Docker가 설치되지 않아 Docker Compose를 확인할 수 없습니다."
            exit 1
        fi
    else
        if docker compose version > /dev/null 2>&1; then
            local compose_version=$(docker compose version)
            log_info "Docker Compose 확인됨: $compose_version"
        elif command -v docker-compose > /dev/null 2>&1; then
            local compose_version=$(docker-compose --version)
            log_info "Docker Compose 확인됨: $compose_version"
        fi
    fi
    
    # 재로그인 안내
    if [ "$need_relogin" = true ]; then
        echo ""
        log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_warn "Docker 권한을 적용하려면 다음 중 하나를 선택하세요:"
        log_warn "1. 터미널을 종료하고 새로 열기"
        log_warn "2. 'newgrp docker' 명령어 실행"  
        log_warn "3. 로그아웃 후 다시 로그인"
        log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        printf "지금 'newgrp docker'를 실행하고 계속하시겠습니까? (y/N): "
        read continue_choice
        
        if [ "$continue_choice" = "y" ] || [ "$continue_choice" = "Y" ]; then
            log_info "Docker 그룹 권한을 활성화하고 스크립트를 계속합니다..."
            exec newgrp docker -c "$0 $*"
        else
            log_info "권한 설정 후 스크립트를 다시 실행해주세요."
            log_info "재실행 명령어: bash $0"
            exit 0
        fi
    fi
    
    log_info "모든 필수 프로그램이 설치되어 있습니다."
}

# 사용자 입력 받기
get_user_input() {
    log_step "2. 설정 정보 입력"
    
    echo "TeslaMate 설치를 위한 정보를 입력해주세요:"
    echo ""
    
    # 설치 디렉토리
    printf "설치할 디렉토리 이름을 입력해주세요 (기본값: teslamate): "
    read INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-teslamate}
    
    # 암호화 키
    echo ""
    echo "Tesla API 토큰 암호화를 위한 보안 키를 입력해주세요."
    echo "(최소 16자 이상의 복잡한 문자열을 권장합니다)"
    while true; do
        printf "암호화 키: "
        stty -echo
        read ENCRYPTION_KEY
        stty echo
        echo ""
        if [ ${#ENCRYPTION_KEY} -lt 8 ]; then
            log_warn "암호화 키가 너무 짧습니다. 최소 8자 이상 입력해주세요."
        else
            break
        fi
    done
    
    # 데이터베이스 비밀번호
    echo ""
    echo "PostgreSQL 데이터베이스 비밀번호를 입력해주세요."
    echo "(최소 8자 이상의 복잡한 비밀번호를 권장합니다)"
    while true; do
        printf "데이터베이스 비밀번호: "
        stty -echo
        read DATABASE_PASS
        stty echo
        echo ""
        if [ ${#DATABASE_PASS} -lt 8 ]; then
            log_warn "비밀번호가 너무 짧습니다. 최소 8자 이상 입력해주세요."
        else
            break
        fi
    done
    
    # 포트 설정
    echo ""
    printf "TeslaMate 웹 포트 (기본값: 4000): "
    read TESLAMATE_PORT
    TESLAMATE_PORT=${TESLAMATE_PORT:-4000}
    
    printf "Grafana 포트 (기본값: 3000): "
    read GRAFANA_PORT
    GRAFANA_PORT=${GRAFANA_PORT:-3000}
    
    # MQTT 포트 (선택사항)
    echo ""
    printf "MQTT 포트를 외부에 노출하시겠습니까? (y/N): "
    read EXPOSE_MQTT
    
    echo ""
    log_info "입력된 설정:"
    echo "  - 설치 디렉토리: $INSTALL_DIR"
    echo "  - TeslaMate 포트: $TESLAMATE_PORT"
    echo "  - Grafana 포트: $GRAFANA_PORT"
    echo "  - MQTT 외부 노출: ${EXPOSE_MQTT:-N}"
    echo ""
    printf "이 설정으로 진행하시겠습니까? (y/N): "
    read CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        log_info "설치를 취소합니다."
        exit 0
    fi
}

# 프로젝트 디렉토리 생성 및 이동
setup_directory() {
    log_step "3. 프로젝트 디렉토리 설정"
    
    if [ -d "$INSTALL_DIR" ]; then
        log_warn "디렉토리 '$INSTALL_DIR'가 이미 존재합니다."
        printf "기존 디렉토리를 사용하시겠습니까? (y/N): "
        read USE_EXISTING
        if [ "$USE_EXISTING" != "y" ] && [ "$USE_EXISTING" != "Y" ]; then
            log_info "설치를 취소합니다."
            exit 0
        fi
    else
        if run_command "mkdir -p \"$INSTALL_DIR\"" "디렉토리 생성"; then
            log_info "디렉토리 '$INSTALL_DIR'를 생성했습니다."
        fi
    fi
    
    cd "$INSTALL_DIR"
    log_info "작업 디렉토리: $(pwd)"
}

# Docker Compose 파일 생성
create_docker_compose() {
    log_step "4. Docker Compose 설정 파일 생성"
    
    # MQTT 포트 설정
    MQTT_PORTS=""
    if [ "$EXPOSE_MQTT" = "y" ] || [ "$EXPOSE_MQTT" = "Y" ]; then
        MQTT_PORTS="    ports:\n      - 1883:1883"
    else
        MQTT_PORTS="    # ports:\n    #   - 1883:1883"
    fi
    
    log_progress "docker-compose.yml 파일 생성 중..."
    
    cat > docker-compose.yml << EOF
# TeslaMate Docker Compose 설정
# 작성자: Choi Seonggi <linux1547@hanmail.net>
# 블로그: https://seonggi.kr

services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    environment:
      - ENCRYPTION_KEY=$ENCRYPTION_KEY
      - DATABASE_USER=teslamate
      - DATABASE_PASS=$DATABASE_PASS
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
      - MQTT_HOST=mosquitto
      - TZ=Asia/Seoul
      - VIRTUAL_HOST=localhost
      - DATABASE_POOL_SIZE=15
      - DATABASE_TIMEOUT=90000
    ports:
      - $TESLAMATE_PORT:4000
    volumes:
      - ./import:/opt/app/import
    cap_drop:
      - all
    depends_on:
      database:
        condition: service_healthy
      mosquitto:
        condition: service_started

  database:
    image: postgres:17-trixie
    restart: always
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=$DATABASE_PASS
      - POSTGRES_DB=teslamate
      - TZ=Asia/Seoul
    volumes:
      - teslamate-db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U teslamate -d teslamate"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  grafana:
    image: teslamate/grafana:latest
    restart: always
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=$DATABASE_PASS
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
      - TZ=Asia/Seoul
    ports:
      - $GRAFANA_PORT:3000
    volumes:
      - teslamate-grafana-data:/var/lib/grafana
    depends_on:
      database:
        condition: service_healthy

  mosquitto:
    image: eclipse-mosquitto:2
    restart: always
    command: mosquitto -c /mosquitto-no-auth.conf
    environment:
      - TZ=Asia/Seoul
$(printf "$MQTT_PORTS")
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data

volumes:
  teslamate-db:
  teslamate-grafana-data:
  mosquitto-conf:
  mosquitto-data:
EOF
    
    log_info "docker-compose.yml 파일을 생성했습니다."
}

# 필요한 디렉토리 생성
create_directories() {
    log_step "5. 필요한 디렉토리 생성"
    
    if run_command "mkdir -p import" "import 디렉토리 생성"; then
        log_info "import 디렉토리를 생성했습니다."
    fi
}

# Docker 이미지 다운로드 및 실행
start_services() {
    log_step "6. TeslaMate 서비스 시작"
    
    log_info "Docker 이미지를 다운로드하고 서비스를 시작합니다..."
    log_info "이 과정은 인터넷 속도에 따라 몇 분이 소요될 수 있습니다."
    echo ""
    
    # Docker Compose 버전 확인 후 적절한 명령어 사용
    if docker compose version > /dev/null 2>&1; then
        if run_command "docker compose up -d" "Docker Compose로 서비스 시작"; then
            log_info "서비스가 시작되었습니다."
        fi
    else
        if run_command "docker-compose up -d" "Docker Compose (Legacy)로 서비스 시작"; then
            log_info "서비스가 시작되었습니다."
        fi
    fi
}

# 서비스 상태 확인
check_services() {
    log_step "7. 서비스 상태 확인"
    
    log_progress "서비스 상태를 확인하는 중..."
    sleep 10
    
    # Docker Compose 버전에 따른 명령어 선택
    if docker compose version > /dev/null 2>&1; then
        run_command "docker compose ps" "서비스 상태 확인"
    else
        run_command "docker-compose ps" "서비스 상태 확인"
    fi
}

# 설치 완료 메시지
show_completion() {
    echo ""
    printf "${GREEN}================================================================\n"
    echo "              TeslaMate 설치가 완료되었습니다!"
    printf "================================================================${NC}\n"
    echo ""
    log_author "작성자: Choi Seonggi <linux1547@hanmail.net>"
    log_author "블로그: https://seonggi.kr"
    echo ""
    echo "다음 단계를 따라 TeslaMate를 설정하세요:"
    echo ""
    echo "1. 웹 브라우저에서 다음 주소에 접속하세요:"
    printf "   ${BLUE}http://localhost:$TESLAMATE_PORT${NC}\n"
    echo ""
    echo "2. Tesla 계정으로 로그인하여 API 토큰을 설정하세요."
    echo "   토큰 생성은 다음 도구를 사ƒ용하세요:"
    printf "   ${BLUE}https://github.com/adriankumpf/tesla_auth${NC}\n"
    echo ""
    echo "3. Grafana 대시보드는 다음 주소에서 확인할 수 있습니다:"
    printf "   ${BLUE}http://localhost:$GRAFANA_PORT${NC}\n"
    echo "   (초기 로그인: admin/admin)"
    echo " 꼭 초기 패스워드를 변경하시길 바랍니다. "
    echo ""
    printf "${CYAN}유용한 명령어:${NC}\n"
    echo "  - 서비스 중지: docker compose down"
    echo "  - 서비스 재시작: docker compose restart"
    echo "  - 로그 확인: docker compose logs -f"
    echo "  - 업데이트: docker compose pull && docker compose up -d"
    echo ""
    printf "${PURPLE}더 많은 Tesla 관련 정보는 https://seonggi.kr 을 방문하세요!${NC}\n"
    echo ""
    log_info "설치 스크립트가 완료되었습니다. TeslaMate를 즐겨보세요! 🚗⚡"
}

# 메인 실행 함수
main() {
    # Root 권한으로 실행 방지
    if [ "$(id -u)" -eq 0 ]; then
        log_error "이 스크립트를 root 권한으로 실행하지 마세요."
        log_error "일반 사용자 계정으로 실행해주세요."
        exit 1
    fi
    
    show_banner
    check_requirements
    get_user_input
    setup_directory
    create_docker_compose
    create_directories
    start_services
    check_services
    show_completion
}

# 스크립트 실행
main "$@"

# ================================================================
# 스크립트 종료
# 문의사항이나 개선사항은 linux1547@hanmail.net 또는 
# https://seonggi.kr 을 통해 연락 주세요.
# ================================================================
출처: https://seonggi.kr/288 [달빛이 비추는 궁전에서:티스토리]