# AI-SRE-System 설치 가이드

## 시스템 요구사항

### 하드웨어
- CPU: 1 코어 이상
- RAM: 512MB 이상
- 디스크: 1GB 이상의 여유 공간

### 소프트웨어
- OS: Ubuntu 20.04 LTS 이상 또는 Debian 10 이상
- Python: 3.8 이상
- 인터넷 연결 (API 통신용)

### 필수 계정
- Google Gemini API 키
- Slack Workspace 및 Webhook URL

## 설치 단계

### 1. Google Gemini API 키 발급

1. [Google AI Studio](https://makersuite.google.com/app/apikey) 접속
2. "Create API Key" 클릭
3. 생성된 API 키 복사 및 보관

### 2. Slack Webhook URL 생성

1. [Slack API](https://api.slack.com/apps) 접속
2. "Create New App" → "From scratch" 선택
3. App 이름 및 Workspace 선택
4. "Incoming Webhooks" 활성화
5. "Add New Webhook to Workspace" 클릭
6. 알림을 받을 채널 선택
7. 생성된 Webhook URL 복사

### 3. 저장소 클론

```bash
git clone https://github.com/SeongGi/AI-SRE-System.git
cd AI-SRE-System
```

### 4. 설치 스크립트 실행

```bash
sudo ./install.sh
```

설치 과정에서 다음 정보를 입력합니다:

- **Gemini API Key**: 1단계에서 발급받은 API 키
- **Slack Webhook URL**: 2단계에서 생성한 Webhook URL
- **Gemini 모델**: 사용할 모델 (기본: gemini-1.5-flash)
- **서비스 포트**: Flask 서비스 포트 (기본: 5000)
- **모니터링 방식**: 
  - 1) Journald (시스템 전체 에러 감시 - 권장)
  - 2) Log File (특정 파일 경로 지정)

### 5. 설치 확인

```bash
# 서비스 상태 확인
sudo systemctl status ai-sre-agent.service

# 로그 확인
sudo journalctl -u ai-sre-agent.service -f
```

정상적으로 설치되었다면 다음과 같은 메시지가 표시됩니다:
```
[*] Monitoring started (JOURNAL, levels: err..emerg)
[*] AI-SRE-Agent starting on 0.0.0.0:5000
```

### 6. Slack 앱 설정

#### Slash Command 설정

1. Slack App 설정 페이지에서 "Slash Commands" 선택
2. "Create New Command" 클릭
3. 다음 정보 입력:
   - Command: `/prompt_change`
   - Request URL: `http://YOUR_SERVER_IP:5000/prompt/slack`
   - Short Description: "AI 프롬프트 변경"
4. "Save" 클릭

#### Interactivity 설정

1. "Interactivity & Shortcuts" 선택
2. "Interactivity" 토글 활성화
3. Request URL 입력: `http://YOUR_SERVER_IP:5000/slack/interactive`
4. "Save Changes" 클릭

## 설치 후 설정

### 보안 블랙리스트 커스터마이징

```bash
sudo nano /opt/ai-sre-system/config/blacklist.txt
```

위험한 명령어를 추가합니다:
```
rm
mkfs
shutdown
reboot
dd
fdisk
```

### 자동 실행 키워드 설정

```bash
sudo nano /opt/ai-sre-system/config/auto_keywords.txt
```

즉시 조치가 필요한 장애 키워드를 추가합니다:
```
DISK FULL
OUT OF MEMORY
NO SPACE LEFT
DISK QUOTA EXCEEDED
```

### AI 프롬프트 최적화

```bash
sudo nano /opt/ai-sre-system/config/prompt.txt
```

프롬프트를 환경에 맞게 수정합니다.

## 트러블슈팅

### 서비스가 시작되지 않는 경우

```bash
# 상세 로그 확인
sudo journalctl -u ai-sre-agent.service -n 50

# 설정 파일 검증
sudo -u ai-agent /opt/ai-sre-system/venv/bin/python3 -c "from src.config import get_config; get_config()"
```

### API 키 오류

환경 변수가 제대로 설정되었는지 확인:
```bash
sudo systemctl cat ai-sre-agent.service | grep Environment
```

### 포트 충돌

다른 포트로 변경:
```bash
sudo nano /opt/ai-sre-system/config/config.yaml
# service.port 값 변경
sudo systemctl restart ai-sre-agent.service
```

## 업그레이드

```bash
cd AI-SRE-System
git pull origin main
sudo ./install.sh
```

## 제거

```bash
sudo systemctl stop ai-sre-agent.service
sudo systemctl disable ai-sre-agent.service
sudo rm /etc/systemd/system/ai-sre-agent.service
sudo rm -rf /opt/ai-sre-system
sudo userdel -r ai-agent
sudo systemctl daemon-reload
```
