#!/bin/bash
# AI-SRE-System 업그레이드 스크립트
# 주의: 실행 전 실제 API 키와 Webhook URL을 입력하세요.

set -e

echo "=== AI-SRE-System 업그레이드 시작 ==="
echo ""

# 기존 설정에서 환경 변수 가져오기 (실행 전 수정 필요)
GEMINI_API_KEY="YOUR_GEMINI_API_KEY"
SLACK_WEBHOOK_URL="YOUR_SLACK_WEBHOOK_URL"
GEMINI_MODEL="gemini-1.5-flash"
SERVICE_PORT="5000"  # 기존과 다른 포트 사용
MONITOR_TYPE="JOURNAL"

AGENT_USER="ai-sre-agent"
AGENT_DIR="/opt/ai-sre-system"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "--- [1/6] 환경 초기화 ---"
sudo systemctl stop ai-sre-agent.service 2>/dev/null || true
sudo systemctl disable ai-sre-agent.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/ai-sre-agent.service
sudo fuser -k ${SERVICE_PORT}/tcp 2>/dev/null || true

# 기존 디렉토리가 있으면 백업
if [ -d "$AGENT_DIR" ]; then
    echo "기존 설치 발견, 백업 중..."
    sudo mv $AGENT_DIR ${AGENT_DIR}.backup.$(date +%Y%m%d_%H%M%S)
fi

# 유저가 없으면 생성
if ! id "$AGENT_USER" &>/dev/null; then
    echo "--- [2/6] 유저 생성 ---"
    sudo useradd -m -s /bin/bash $AGENT_USER
    sudo usermod -aG adm,systemd-journal $AGENT_USER
fi

sudo mkdir -p $AGENT_DIR
sudo chown -R $AGENT_USER:$AGENT_USER $AGENT_DIR

echo "--- [3/6] 프로젝트 파일 복사 ---"
sudo cp -r "$SCRIPT_DIR/src" $AGENT_DIR/
sudo cp -r "$SCRIPT_DIR/config" $AGENT_DIR/
sudo cp "$SCRIPT_DIR/requirements.txt" $AGENT_DIR/

sudo mkdir -p $AGENT_DIR/data
sudo mkdir -p $AGENT_DIR/logs

sudo chown -R $AGENT_USER:$AGENT_USER $AGENT_DIR

echo "--- [4/6] Python 가상환경 및 패키지 설치 ---"
sudo apt update && sudo apt install -y python3-venv python3-pip coreutils psmisc

sudo -u $AGENT_USER python3 -m venv $AGENT_DIR/venv
sudo -u $AGENT_USER $AGENT_DIR/venv/bin/pip install --upgrade pip
sudo -u $AGENT_USER $AGENT_DIR/venv/bin/pip install -r $AGENT_DIR/requirements.txt

echo "--- [5/6] 설정 파일 업데이트 ---"
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
  username: "AI-SRE-Agent-v2"

# Monitoring Settings
monitoring:
  type: "$MONITOR_TYPE"
  log_path: "/var/log/syslog"
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
Description=AI-SRE-Agent v2 - Intelligent System Remediation
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

sudo systemctl daemon-reload
sudo systemctl enable ai-sre-agent.service
sudo systemctl start ai-sre-agent.service

sleep 2
sudo systemctl status ai-sre-agent.service --no-pager

PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
echo ""
echo "===================================================="
echo "🎉 AI-SRE-System v2 설치가 완료되었습니다!"
echo "===================================================="
echo "[서비스 정보]"
echo " - 설치 위치: $AGENT_DIR"
echo " - 서비스 포트: $SERVICE_PORT"
echo " - 모니터링 방식: $MONITOR_TYPE"
echo ""
echo "[슬랙 API 설정 URL - 업데이트 필요]"
echo " 1. Slash Command (/prompt_change):"
echo "    http://$PUBLIC_IP:$SERVICE_PORT/prompt/slack"
echo " 2. Interactivity & Shortcuts:"
echo "    http://$PUBLIC_IP:$SERVICE_PORT/slack/interactive"
echo ""
echo "[관리 명령어]"
echo " - 서비스 상태: sudo systemctl status ai-sre-agent.service"
echo " - 로그 확인: sudo journalctl -u ai-sre-agent.service -f"
echo " - 애플리케이션 로그: tail -f $AGENT_DIR/logs/ai-sre-agent.log"
echo "===================================================="
