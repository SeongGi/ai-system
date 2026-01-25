# AI-SRE-System

Google Gemini AI 기반 실시간 시스템 장애 탐지 및 자동 복구 에이전트

![시스템 구성도](./ai-agent-gemini.png)

## 개요

AI-SRE-System은 리눅스 서버의 시스템 로그를 실시간으로 모니터링하여, 장애가 감지되면 AI가 즉각적으로 분석하고 해결 명령어를 제안하는 지능형 시스템 관리 도구입니다. 관리자는 슬랙(Slack)을 통해 보고를 받고 승인을 통해 서버를 복구할 수 있습니다.

## 주요 기능

- **실시간 장애 감지**: Journald 또는 특정 로그 파일을 감시하여 시스템 에러를 즉시 포착
- **AI 상황 분석**: Google Gemini 모델이 에러 로그의 문맥을 분석하여 최적의 Bash 명령어 생성
- **보안 필터링**: 블랙리스트 기반으로 위험한 명령어 자동 차단
- **자동 조치**: 사전 정의된 중요 키워드는 관리자 승인 없이 AI가 즉시 복구
- **슬랙 연동**: 슬랙 버튼을 통해 조치 명령어 실행/거절 및 결과 확인
- **장애 이력 관리**: SQLite 데이터베이스에 모든 장애 이력 저장
- **통계 및 리포팅**: 장애 발생 추이 및 처리 현황 조회

## 시스템 아키텍처

```
┌─────────────────┐
│  Log Monitor    │  ← Journald / Log File
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  AI Analyzer    │  ← Google Gemini API
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Security Filter │  ← Blacklist Check
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ↓         ↓
┌─────┐   ┌──────┐
│Auto │   │Manual│  ← Slack Interactive
└──┬──┘   └───┬──┘
   │          │
   ↓          ↓
┌─────────────────┐
│Command Executor │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│   Database      │  ← Incident History
└─────────────────┘
```

## 프로젝트 구조

```
Ai-SRE-System/
├── src/                    # 소스 코드
│   ├── main.py            # 메인 애플리케이션
│   ├── config.py          # 설정 관리
│   ├── security.py        # 보안 필터링
│   ├── database.py        # 데이터베이스 관리
│   ├── ai_analyzer.py     # AI 분석
│   ├── executor.py        # 명령어 실행
│   ├── notifier.py        # 슬랙 알림
│   ├── monitor.py         # 로그 모니터링
│   └── logger.py          # 로깅 시스템
├── config/                # 설정 파일
│   ├── config.yaml        # 메인 설정
│   ├── prompt.txt         # AI 프롬프트
│   ├── blacklist.txt      # 보안 블랙리스트
│   └── auto_keywords.txt  # 자동 실행 키워드
├── tests/                 # 테스트 코드
│   ├── test_security.py
│   └── test_executor.py
├── docs/                  # 문서
├── install.sh            # 설치 스크립트
└── requirements.txt      # Python 의존성
```

## 빠른 시작

### 사전 요구사항

- Ubuntu/Debian 리눅스 시스템
- Python 3.8 이상
- sudo 권한
- Google Gemini API 키
- Slack Webhook URL

### 설치

1. 저장소 클론:
```bash
git clone https://github.com/SeongGi/AI-SRE-System.git
cd AI-SRE-System
```

2. 설치 스크립트 실행:
```bash
sudo ./install.sh
```

3. 설치 과정에서 다음 정보 입력:
   - Gemini API Key
   - Slack Webhook URL
   - Gemini 모델 버전 (기본: gemini-1.5-flash)
   - 서비스 포트 (기본: 5000)
   - 모니터링 방식 (Journald 또는 Log File)

### 슬랙 앱 설정

1. **Slash Command 설정** (`/prompt_change`):
   - Request URL: `http://YOUR_SERVER_IP:5000/prompt/slack`

2. **Interactivity 설정**:
   - Request URL: `http://YOUR_SERVER_IP:5000/slack/interactive`

## 사용 방법

### 서비스 관리

```bash
# 서비스 상태 확인
sudo systemctl status ai-sre-agent.service

# 서비스 재시작
sudo systemctl restart ai-sre-agent.service

# 서비스 중지
sudo systemctl stop ai-sre-agent.service

# 로그 확인
sudo journalctl -u ai-sre-agent.service -f

# 애플리케이션 로그 확인
tail -f /opt/ai-sre-system/logs/ai-sre-agent.log
```

### 설정 변경

설정 파일을 수정한 후 서비스를 재시작하면 변경사항이 적용됩니다:

```bash
# 메인 설정 수정
sudo nano /opt/ai-sre-system/config/config.yaml

# AI 프롬프트 수정
sudo nano /opt/ai-sre-system/config/prompt.txt

# 보안 블랙리스트 수정
sudo nano /opt/ai-sre-system/config/blacklist.txt

# 자동 실행 키워드 수정
sudo nano /opt/ai-sre-system/config/auto_keywords.txt

# 서비스 재시작
sudo systemctl restart ai-sre-agent.service
```

### API 엔드포인트

- **Health Check**: `GET /health`
- **통계 조회**: `GET /stats?days=7`
- **장애 이력**: `GET /incidents?limit=100`

## 보안

### 블랙리스트 관리

위험한 명령어는 `config/blacklist.txt`에 추가하여 차단할 수 있습니다:

```
rm
mkfs
shutdown
reboot
dd
```

### 자동 실행 키워드

즉시 조치가 필요한 장애는 `config/auto_keywords.txt`에 추가하여 자동 실행할 수 있습니다:

```
DISK FULL
OUT OF MEMORY
NO SPACE LEFT
```

## 개발

### 로컬 개발 환경 설정

```bash
# 가상환경 생성
python3 -m venv venv
source venv/bin/activate

# 의존성 설치
pip install -r requirements.txt

# 환경 변수 설정
export GEMINI_API_KEY="your-api-key"
export SLACK_WEBHOOK_URL="your-webhook-url"

# 애플리케이션 실행
python src/main.py
```

### 테스트 실행

```bash
# 전체 테스트
pytest tests/ -v

# 특정 테스트
pytest tests/test_security.py -v

# 커버리지 포함
pytest tests/ --cov=src --cov-report=html
```

## 문서

- [설치 가이드](docs/installation.md)
- [설정 가이드](docs/configuration.md)
- [API 문서](docs/api.md)

## 라이선스

MIT License

## 기여

이슈 및 풀 리퀘스트는 언제나 환영합니다!

## 문의

- Email: linux1547@hanmail.net
- GitHub: [@SeongGi](https://github.com/SeongGi)