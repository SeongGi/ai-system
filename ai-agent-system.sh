#!/bin/bash

read -p "Gemini API Key: " GEMINI_API_KEY
read -p "Slack Webhook: " SLACK_WEBHOOK_URL
LOG_PATH=${1:-/var/log/syslog}

USER="ai-agent"
DIR="/opt/ai-agent"
VENV="$DIR/venv"

sudo useradd --system --shell /usr/sbin/nologin $USER || true
sudo usermod -aG adm $USER
sudo mkdir -p $DIR
sudo chown $USER:$USER $DIR
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER

sudo -u $USER python3 -m venv $VENV
sudo -u $USER $VENV/bin/pip install --upgrade pip
sudo -u $USER $VENV/bin/pip install flask google-generativeai requests

cat << 'EOF' | sudo -u $USER tee $DIR/main.py > /dev/null
import os, time, subprocess, requests, json
from threading import Thread
from flask import Flask, request, jsonify
import google.generativeai as genai

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
LOG_PATH = os.getenv("LOG_PATH", "/var/log/syslog")

genai.configure(api_key=GEMINI_API_KEY)
model = genai.GenerativeModel('gemini-1.5-flash')
app = Flask(__name__)

AUTO_KEY = ["disk space", "disk full", "out of space", "usage exceeded"]
DANGER = ["rm -rf /", "mkfs", "dd ", "shutdown", "reboot"]

def is_safe(cmd):
    return not any(d in cmd.lower() for d in DANGER)

def execute(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return ("성공" if r.returncode == 0 else "실패"), (r.stdout if r.stdout else "No Output")
    except Exception as e: return "에러", str(e)

def send_slack(error, cmd, status, out, auto=False):
    p = {"text": f"{'[Auto]' if auto else '✅ [Approved]'}\n*Cmd:* `{cmd}`",
         "attachments": [{"color": "#36a64f" if status=="성공" else "#ff0000",
                          "fields": [{"title": "Log", "value": f"```{error}```"},
                                     {"title": "Result", "value": f"`{status}`: {out}"}]}]}
    requests.post(SLACK_WEBHOOK_URL, json=p)

def watch():
    proc = subprocess.Popen(["tail", "-F", "-n", "0", LOG_PATH], stdout=subprocess.PIPE, text=True)
    for line in iter(proc.stdout.readline, ""):
        if not line.strip() or "python" in line: continue
        if "error" in line.lower() or "critical" in line.lower():
            res = model.generate_content(f"Solve with one linux command: {line}")
            if res and res.text:
                cmd = res.text.strip().replace('`', '')
                if any(k in line.lower() for k in AUTO_KEY) and is_safe(cmd):
                    s, o = execute(cmd)
                    send_slack(line, cmd, s, o, True)
                else:
                    payload = {"text": " *Approval Required*", "attachments": [{"callback_id": "rem", "color": "#ff9800",
                        "fields": [{"title": "Log", "value": f"```{line}```"}, {"title": "AI", "value": f"`{cmd}`"}],
                        "actions": [{"name": "ok", "text": "Approve", "type": "button", "value": cmd, "style": "primary"}]}]}
                    requests.post(SLACK_WEBHOOK_URL, json=payload)

@app.route('/slack/interactive', methods=['POST'])
def interactive():
    payload = json.loads(request.form.get('payload'))
    cmd = payload['actions'][0]['value']
    s, o = execute(cmd)
    return jsonify({"replace_original": True, "text": f"✅ Done\n*Cmd:* `{cmd}`\n*Res:* `{s}`\n```{o}```"})

if __name__ == "__main__":
    Thread(target=watch, daemon=True).start()
    app.run(host="0.0.0.0", port=5000)
EOF

sudo bash -c "cat <<EOF > /etc/systemd/system/ai-remediator.service
[Unit]
Description=AI Auto-Healing Agent
After=network.target
[Service]
ExecStart=$VENV/bin/python3 $DIR/main.py
Restart=always
User=$USER
Environment=GEMINI_API_KEY=$GEMINI_API_KEY
Environment=SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL
Environment=LOG_PATH=$LOG_PATH
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable --now ai-remediator.service