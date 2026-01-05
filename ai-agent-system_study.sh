#!/bin/bash
# AI SRE Agent - Ultimate Final Version (Log File vs Journald Selectable)

# 1. 사용자 입력 받기
echo "=== AI SRE 에이전트 설정 시작 ==="
read -p "✔ Gemini API Key: " GEMINI_API_KEY
read -p "✔ Slack Webhook URL: " SLACK_WEBHOOK_URL
read -p "✔ Gemini 모델 버전 (예: gemini-1.5-flash): " GEMINI_MODEL
read -p "✔ 서비스 포트 번호 (기본: 5000): " SERVICE_PORT
SERVICE_PORT=${SERVICE_PORT:-5000}

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
    LOG_PATH="N/A (Journald)"
fi

AGENT_USER="ai-agent"
AGENT_DIR="/opt/ai-agent"

echo "--- [1/5] 환경 초기화 (Clean Up) ---"
sudo systemctl stop ai-remediator.service 2>/dev/null
sudo systemctl disable ai-remediator.service 2>/dev/null
sudo rm -f /etc/systemd/system/ai-remediator.service
sudo fuser -k ${SERVICE_PORT}/tcp 2>/dev/null
sudo rm -rf $AGENT_DIR
sudo userdel -r $AGENT_USER 2>/dev/null

echo "--- [2/5] 유저 및 권한 설정 ---"
sudo useradd -m -s /bin/bash $AGENT_USER
sudo usermod -aG adm,systemd-journal $AGENT_USER
sudo mkdir -p $AGENT_DIR
sudo chown -R $AGENT_USER:$AGENT_USER $AGENT_DIR

echo "--- [3/5] 필수 파일 및 가상환경 생성 ---"
sudo -u $AGENT_USER tee $AGENT_DIR/prompt.txt << 'EOF' > /dev/null
Senior SRE. Provide only one safe bash command to fix the log. No prose.
EOF

sudo apt update && sudo apt install -y python3-venv coreutils psmisc
sudo -u $AGENT_USER python3 -m venv $AGENT_DIR/venv
sudo -u $AGENT_USER $AGENT_DIR/venv/bin/pip install flask requests google-genai

echo "--- [4/5] 메인 코드(main.py) 생성 ---"
cat << 'EOF' | sudo -u $AGENT_USER tee $AGENT_DIR/main.py > /dev/null
import os, subprocess, requests, json, time, sys
from threading import Thread
from flask import Flask, request, jsonify
from google import genai

API_KEY = os.getenv("GEMINI_API_KEY")
SLACK_WEBHOOK = os.getenv("SLACK_WEBHOOK_URL")
MODEL_NAME = os.getenv("GEMINI_MODEL")
PORT = int(os.getenv("SERVICE_PORT", 5000))
MONITOR_TYPE = os.getenv("MONITOR_TYPE")
LOG_PATH = os.getenv("LOG_PATH")
PROMPT_FILE = "/opt/ai-agent/prompt.txt"

client = genai.Client(api_key=API_KEY)
app = Flask(__name__)

def load_prompt():
    try:
        with open(PROMPT_FILE, "r") as f: return f.read().strip()
    except: return "Senior SRE. Provide only one safe bash command to fix the log."

@app.route('/prompt/slack', methods=['POST'])
def handle_slash_command():
    user_text = request.form.get('text', '').strip()
    if not user_text:
        return jsonify({"response_type": "ephemeral", "text": f"현재 프롬프트: `{load_prompt()}`"})
    with open(PROMPT_FILE, "w") as f: f.write(user_text)
    return jsonify({"response_type": "in_channel", "text": f"✅ 프롬프트 변경됨: `{user_text}`"})

@app.route('/slack/interactive', methods=['POST'])
def handle_interactive():
    payload = json.loads(request.form.get('payload'))
    cmd = payload['actions'][0]['value']
    if cmd == "ignore": return jsonify({"replace_original": True, "text": "🚫 조치 거절됨"})
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
    return jsonify({"replace_original": True, "text": f"✅ *실행 완료*\n명령어: `{cmd}`\n```{res.stdout if res.stdout else res.stderr}```"})

def monitor():
    if MONITOR_TYPE == "JOURNAL":
        proc = subprocess.Popen(['journalctl', '-f', '-n', '0', '-p', 'err..emerg'], stdout=subprocess.PIPE, text=True)
    else:
        proc = subprocess.Popen(['tail', '-F', '-n', '0', LOG_PATH], stdout=subprocess.PIPE, text=True)

    print(f"[*] 모니터링 시작 ({MONITOR_TYPE})")
    while True:
        line = proc.stdout.readline()
        if not line: break
        line = line.strip()
        if MONITOR_TYPE == "FILE" and not any(k in line.upper() for k in ["ERROR", "CRITICAL", "FATAL"]): continue
        
        try:
            resp = client.models.generate_content(model=MODEL_NAME, contents=f"{load_prompt()}\nLog: {line}")
            ai_cmd = resp.text.strip().replace('`', '').split('\n')[0]
            requests.post(SLACK_WEBHOOK, json={
                "text": "🚨 *장애 탐지 및 AI 조치 제안*",
                "attachments": [{
                    "callback_id": "fix", "color": "#F44336",
                    "fields": [{"title": "로그", "value": f"```{line}```"}, {"title": "AI 제안", "value": f"`{ai_cmd}`"}],
                    "actions": [
                        {"name": "e", "text": "✅ 실행", "type": "button", "value": ai_cmd, "style": "primary"},
                        {"name": "d", "text": "❌ 거절", "type": "button", "value": "ignore", "style": "danger"}
                    ]
                }]
            })
        except Exception as e: print(f"Monitor Error: {e}")

if __name__ == "__main__":
    Thread(target=monitor, daemon=True).start()
    app.run(host="0.0.0.0", port=PORT, debug=False)
EOF

echo "--- [5/5] 서비스 등록 및 시작 ---"
sudo tee /etc/systemd/system/ai-remediator.service > /dev/null <<EOT
[Unit]
Description=AI SRE Agent Final
After=network.target

[Service]
ExecStart=$AGENT_DIR/venv/bin/python3 $AGENT_DIR/main.py
Restart=always
User=$AGENT_USER
Group=adm
Environment=GEMINI_API_KEY=$GEMINI_API_KEY
Environment=SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL
Environment=GEMINI_MODEL=$GEMINI_MODEL
Environment=SERVICE_PORT=$SERVICE_PORT
Environment=MONITOR_TYPE=$MONITOR_TYPE
Environment=LOG_PATH=$LOG_PATH
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOT

sudo systemctl daemon-reload
sudo systemctl enable ai-remediator.service
sudo systemctl restart ai-remediator.service

# 최종 정보 출력
PUBLIC_IP=$(curl -s ifconfig.me)
echo ""
echo "===================================================="
echo "🎉 AI SRE 에이전트 설치가 완료되었습니다!"
echo "===================================================="
echo "📍 [에이전트 정보]"
echo " - 설치 위치: $AGENT_DIR"
echo " - 사용 모델: $GEMINI_MODEL"
echo " - 서비스 포트: $SERVICE_PORT"
echo " - 모니터링 방식: $MONITOR_TYPE ($LOG_PATH)"
echo ""
echo "🔗 [슬랙 API 설정 URL]"
echo " 1. Slash Command (/prompt_change):"
echo "    http://$PUBLIC_IP:$SERVICE_PORT/prompt/slack"
echo " 2. Interactivity & Shortcuts:"
echo "    http://$PUBLIC_IP:$SERVICE_PORT/slack/interactive"
echo ""
echo "🔍 [관리 명령어]"
echo " - 실시간 로그 확인: sudo journalctl -u ai-remediator.service -f"
echo " - 서비스 재시작: sudo systemctl restart ai-remediator.service"
echo " - 프롬프트 수동 수정: sudo nano $AGENT_DIR/prompt.txt"
echo "===================================================="