#!/bin/bash
# AI SRE Agent

read -p "✔ Gemini API Key: " GEMINI_API_KEY
read -p "✔ Slack Webhook URL: " SLACK_WEBHOOK_URL
read -p "✔ 로그 경로 (기본: /var/log/syslog): " LOG_PATH
LOG_PATH=${LOG_PATH:-/var/log/syslog}

AGENT_USER="ai-agent"
AGENT_DIR="/opt/ai-agent"
VENV_PATH="$AGENT_DIR/venv"

cat << 'EOF' | sudo -u $AGENT_USER tee $AGENT_DIR/main.py > /dev/null
import os, subprocess, requests, json, time
from threading import Thread
from flask import Flask, request, jsonify
import google.generativeai as genai

# 환경 설정
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
LOG_PATH = os.getenv("LOG_PATH", "/var/log/syslog")
PROMPT_FILE = "/opt/ai-agent/prompt.txt"
DEFAULT_PROMPT = "Senior SRE. Provide only one safe shell command to fix the log. No prose."

# [영구 저장 로직] 파일에서 프롬프트를 읽어오거나 없으면 기본값 사용
def load_prompt():
    if os.path.exists(PROMPT_FILE):
        with open(PROMPT_FILE, "r") as f:
            return f.read().strip()
    return DEFAULT_PROMPT

def save_prompt(p):
    with open(PROMPT_FILE, "w") as f:
        f.write(p)

# AI 및 Flask 설정
genai.configure(api_key=GEMINI_API_KEY)
model = genai.GenerativeModel('gemini-3-flash-preview')
app = Flask(__name__)
SYSTEM_PROMPT = load_prompt() # 시작 시 파일에서 로드

DANGER_KEYWORDS = ["rm ", "dd ", "mkfs", "shutdown", "reboot"]

def is_safe(cmd):
    return not any(d in cmd.lower() for d in DANGER_KEYWORDS)

@app.route('/prompt/slack', methods=['POST'])
def slack_prompt():
    global SYSTEM_PROMPT
    user_input = request.form.get('text', '').strip()
    if not user_input:
        return jsonify({"response_type": "ephemeral", "text": f"현재 저장된 프롬프트: `{SYSTEM_PROMPT}`"})
    
    SYSTEM_PROMPT = user_input
    save_prompt(user_input) # 변경 시 파일에 기록
    return jsonify({"response_type": "in_channel", "text": "✅ 프롬프트가 영구적으로 저장되었습니다."})

@app.route('/slack/interactive', methods=['POST'])
def interactive():
    payload = json.loads(request.form.get('payload'))
    cmd = payload['actions'][0]['value']
    if cmd == "rejected" or not is_safe(cmd):
        return jsonify({"text": "🚫 작업이 취소되었습니다."})
    
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
    return jsonify({
        "replace_original": True,
        "text": f"✅ *실행 완료*\n명령어: `{cmd}`\n```{res.stdout if res.stdout else 'Success'}```"
    })

def watch_logs():
    process = subprocess.Popen(["tail", "-F", "-n", "0", LOG_PATH], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in iter(process.stdout.readline, ""):
        line = line.strip()
        if not line: continue
        if any(k in line.lower() for k in ["ai-remediator", "flask", "python3"]): continue
        if any(k in line.upper() for k in ["ERROR:", "CRITICAL:", "FATAL:"]):
            try:
                response = model.generate_content(f"{SYSTEM_PROMPT}\nLog: {line}")
                if response and response.text:
                    cmd = response.text.strip().replace('`', '').split('\n')[0]
                    if not is_safe(cmd): continue
                    requests.post(SLACK_WEBHOOK_URL, json={
                        "text": "🚨 *SRE 장애 탐지*",
                        "attachments": [{
                            "callback_id": "sre_action", "color": "#ff0000",
                            "fields": [{"title": "로그", "value": f"```{line}```"}, {"title": "AI 제안", "value": f"`{cmd}`"}],
                            "actions": [
                                {"name": "a", "text": "✅ 실행", "type": "button", "value": cmd, "style": "primary"},
                                {"name": "a", "text": "❌ 거절", "type": "button", "value": "rejected", "style": "danger"}
                            ]
                        }]
                    })
            except: pass

if __name__ == "__main__":
    Thread(target=watch_logs, daemon=True).start()
    app.run(host="0.0.0.0", port=5000, use_reloader=False)
EOF

sudo systemctl restart ai-remediator.service
echo " 설치 완료"
echo "로그 확인: journalctl -u ai-remediator.service -f"