#!/bin/bash
# AI-SRE-System 설치 스크립트 (개선 버전)

set -e  # 에러 발생 시 스크립트 중단

echo "=== AI-SRE-System 설치 시작 ==="
echo ""

# 1. 사용자 입력 받기
read -p "✔ Gemini API Key: " GEMINI_API_KEY
read -p "✔ Slack Webhook URL: " SLACK_WEBHOOK_URL
read -p "✔ Gemini 모델 버전 (기본: gemini-1.5-flash): " GEMINI_MODEL
GEMINI_MODEL=${GEMINI_MODEL:-gemini-1.5-flash}
read -p "✔ 서비스 포트 번호 (기본: 5000): " SERVICE_PORT
SERVICE_PORT=${SERVICE_PORT:-5000}

echo ""
echo "------------------------------------------------"
echo "모니터링 방식을 선택하세요:"
echo "1) Journald (시스템 전체 에러 감시 - 권장)"
echo "2) Log File (특정 파일 경로 지정 감시)"
read -p "선택 (1 또는 2): " MONITOR_MODE

if [ "$MONITOR_MODE" == "2" ]; then
    read -p "✔ 감시할 로그 파일 경로 (예: /var/log/syslog): " LOG_PATH
    LOG_PATH=${LOG_PATH:-/var/log/syslog}
    MONITOR_TYPE="FILE"
else
    MONITOR_TYPE="JOURNAL"
    LOG_PATH="N/A"
fi

AGENT_USER="ai-agent"
AGENT_DIR="/opt/ai-sre-system"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "--- [1/6] 환경 초기화 (Clean Up) ---"
sudo systemctl stop ai-sre-agent.service 2>/dev/null || true
sudo systemctl disable ai-sre-agent.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/ai-sre-agent.service
sudo fuser -k ${SERVICE_PORT}/tcp 2>/dev/null || true
sudo rm -rf $AGENT_DIR
sudo userdel -r $AGENT_USER 2>/dev/null || true

echo "--- [2/6] 유저 및 권한 설정 ---"
sudo useradd -m -s /bin/bash $AGENT_USER
sudo usermod -aG adm,systemd-journal $AGENT_USER
sudo mkdir -p $AGENT_DIR
sudo chown -R $AGENT_USER:$AGENT_USER $AGENT_DIR

echo "--- [3/6] 프로젝트 파일 복사 ---"
# 소스 코드 복사
sudo cp -r "$SCRIPT_DIR/src" $AGENT_DIR/
sudo cp -r "$SCRIPT_DIR/config" $AGENT_DIR/
sudo cp "$SCRIPT_DIR/requirements.txt" $AGENT_DIR/

# 데이터 및 로그 디렉토리 생성
sudo mkdir -p $AGENT_DIR/data
sudo mkdir -p $AGENT_DIR/logs

# 권한 설정
sudo chown -R $AGENT_USER:$AGENT_USER $AGENT_DIR

echo "--- [4/6] Python 가상환경 및 패키지 설치 ---"
# 필수 시스템 패키지 설치
sudo apt update && sudo apt install -y python3-venv python3-pip coreutils psmisc

# 가상환경 생성 및 패키지 설치
sudo -u $AGENT_USER python3 -m venv $AGENT_DIR/venv
sudo -u $AGENT_USER $AGENT_DIR/venv/bin/pip install --upgrade pip
sudo -u $AGENT_USER $AGENT_DIR/venv/bin/pip install -r $AGENT_DIR/requirements.txt

echo "--- [5/6] 설정 파일 업데이트 ---"
# config.yaml 업데이트 (환경 변수는 systemd에서 주입)
sudo -u $AGENT_USER tee $AGENT_DIR/config/config.yaml > /dev/null <<EOF
# AI-SRE-System Configuration File

# API Settings
api:
  gemini_api_key: "\${GEMINI_API_KEY}"
  gemini_model: "$GEMINI_MODEL"

# Slack Settings
slack:
  webhook_url: "\${SLACK_WEBHOOK_URL}"
  channel: "#alerts"
  username: "AI-SRE-Agent"

# Monitoring Settings
monitoring:
  type: "$MONITOR_TYPE"
  log_path: "$LOG_PATH"
  error_levels:
    - "err"
    - "crit"
    - "alert"
    - "emerg"
  error_keywords:
    - "ERROR"
    - "CRITICAL"
    - "FATAL"

# Service Settings
service:
  port: $SERVICE_PORT
  host: "0.0.0.0"
  debug: false

# Security Settings
security:
  blacklist_file: "config/blacklist.txt"
  auto_keywords_file: "config/auto_keywords.txt"
  command_timeout: 15

# Database Settings
database:
  path: "data/incidents.db"
  retention_days: 30

# Dashboard Settings
dashboard:
  enabled: false
  port: 5001
  refresh_interval: 5

# Logging Settings
logging:
  level: "INFO"
  file: "logs/ai-sre-agent.log"
  max_size_mb: 10
  backup_count: 5
EOF

echo "--- [6/6] Systemd 서비스 등록 및 시작 ---"
sudo tee /etc/systemd/system/ai-sre-agent.service > /dev/null <<EOT
[Unit]
Description=AI-SRE-Agent - Intelligent System Remediation
After=network.target

[Service]
Type=simple
User=$AGENT_USER
Group=adm
WorkingDirectory=$AGENT_DIR
ExecStart=$AGENT_DIR/venv/bin/python3 $AGENT_DIR/src/main.py
Restart=always
RestartSec=10

# Environment Variables
Environment=GEMINI_API_KEY=$GEMINI_API_KEY
Environment=SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL
Environment=PYTHONUNBUFFERED=1

# Security
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOT

# Systemd 데몬 리로드 및 서비스 시작
sudo systemctl daemon-reload
sudo systemctl enable ai-sre-agent.service
sudo systemctl start ai-sre-agent.service

# 서비스 상태 확인
sleep 2
sudo systemctl status ai-sre-agent.service --no-pager

# 최종 정보 출력
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
echo ""
echo "===================================================="
echo "🎉 AI-SRE-System 설치가 완료되었습니다!"
echo "===================================================="
echo "[서비스 정보]"
echo " - 설치 위치: $AGENT_DIR"
echo " - 서비스 포트: $SERVICE_PORT"
echo " - 모니터링 방식: $MONITOR_TYPE"
if [ "$MONITOR_TYPE" == "FILE" ]; then
    echo " - 로그 파일: $LOG_PATH"
fi
echo ""
echo "[슬랙 API 설정 URL]"
echo " 1. Slash Command (/prompt_change):"
echo "    http://$PUBLIC_IP:$SERVICE_PORT/prompt/slack"
echo " 2. Interactivity & Shortcuts:"
echo "    http://$PUBLIC_IP:$SERVICE_PORT/slack/interactive"
echo ""
echo "[관리 명령어]"
echo " - 서비스 상태: sudo systemctl status ai-sre-agent.service"
echo " - 서비스 재시작: sudo systemctl restart ai-sre-agent.service"
echo " - 로그 확인: sudo journalctl -u ai-sre-agent.service -f"
echo " - 애플리케이션 로그: tail -f $AGENT_DIR/logs/ai-sre-agent.log"
echo ""
echo "[설정 파일]"
echo " - 메인 설정: $AGENT_DIR/config/config.yaml"
echo " - AI 프롬프트: $AGENT_DIR/config/prompt.txt"
echo " - 보안 블랙리스트: $AGENT_DIR/config/blacklist.txt"
echo " - 자동 실행 키워드: $AGENT_DIR/config/auto_keywords.txt"
echo ""
echo "[API 엔드포인트]"
echo " - Health Check: http://$PUBLIC_IP:$SERVICE_PORT/health"
echo " - Statistics: http://$PUBLIC_IP:$SERVICE_PORT/stats"
echo " - Incidents: http://$PUBLIC_IP:$SERVICE_PORT/incidents"
echo "===================================================="
