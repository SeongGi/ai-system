#!/bin/bash
# AI SRE Agent

read -p "Gemini Key: " G_K
read -p "Slack Webhook: " S_W
L_P=${1:-/var/log/syslog}
U="ai-agent"; D="/opt/ai-agent"; V="$D/venv"; F="$D/prompt.txt"

sudo -u $U $V/bin/python3 - << 'EOF' | sudo -u $U tee $D/main.py > /dev/null
import os, subprocess, requests, json, time
from threading import Thread
from flask import Flask, request, jsonify
import google.generativeai as genai

G_K, S_W, L_P, F = os.getenv("GEMINI_API_KEY"), os.getenv("SLACK_WEBHOOK_URL"), os.getenv("LOG_PATH"), "/opt/ai-agent/prompt.txt"
genai.configure(api_key=G_K)
model = genai.GenerativeModel('gemini-3-pro-preview')
app = Flask(__name__)

def load(): return open(F, "r").read().strip() if os.path.exists(F) else "Senior SRE. One safe command only."
def save(p): open(F, "w").write(p)
S_P = load()

@app.route('/prompt/slack', methods=['POST'])
def prompt():
    global S_P
    t = request.form.get('text', '').strip()
    if t: S_P = t; save(t)
    return jsonify({"text": f"Saved Prompt: `{S_P}`"})

@app.route('/slack/interactive', methods=['POST'])
def interactive():
    p = json.loads(request.form.get('payload'))
    c = p['actions'][0]['value']
    if c == "rejected" or not any(d in c.lower() for d in ["rm ", "dd ", "mkfs"]):
        r = subprocess.run(c, shell=True, capture_output=True, text=True, timeout=30)
        return jsonify({"replace_original": True, "text": f"✅ `{c}`\n```{r.stdout}```"})
    return jsonify({"text": "🚫 Cancelled"})

def watch():
    p = subprocess.Popen(["tail", "-F", "-n", "0", L_P], stdout=subprocess.PIPE, text=True)
    for l in iter(p.stdout.readline, ""):
        if not any(k in l.lower() for k in ["ai-agent", "flask", "python"]) and any(k in l.upper() for k in ["ERROR", "CRITICAL"]):
            try:
                res = model.generate_content(f"{S_P}\nLog: {l}")
                cmd = res.text.strip().replace('`', '').split('\n')[0]
                requests.post(S_W, json={"attachments": [{"callback_id": "sre", "color": "#f00", "fields": [{"title": "Log", "value": f"```{l}```"}, {"title": "AI", "value": f"`{cmd}`"}],
                "actions": [{"name": "a", "text": "Run", "type": "button", "value": cmd, "style": "primary"}, {"name": "a", "text": "No", "type": "button", "value": "rejected"}]}]})
            except: pass

Thread(target=watch, daemon=True).start()
app.run(host="0.0.0.0", port=5000)
EOF

sudo systemctl restart ai-remediator.service
echo "설치 완료"
echo "로그 확인: journalctl -u ai-remediator.service -f"