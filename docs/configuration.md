# AI-SRE-System 설정 가이드

## 설정 파일 구조

AI-SRE-System은 YAML 기반의 중앙 집중식 설정 관리를 사용합니다.

### 메인 설정 파일

**위치**: `/opt/ai-sre-system/config/config.yaml`

```yaml
# API Settings
api:
  gemini_api_key: "${GEMINI_API_KEY}"  # 환경 변수에서 로드
  gemini_model: "gemini-1.5-flash"     # 사용할 Gemini 모델

# Slack Settings
slack:
  webhook_url: "${SLACK_WEBHOOK_URL}"  # 환경 변수에서 로드
  channel: "#alerts"                   # 알림 채널
  username: "AI-SRE-Agent"             # 봇 사용자명

# Monitoring Settings
monitoring:
  type: "JOURNAL"                      # JOURNAL 또는 FILE
  log_path: "/var/log/syslog"         # FILE 모드일 때 사용
  error_levels:                        # JOURNAL 모드 에러 레벨
    - "err"
    - "crit"
    - "alert"
    - "emerg"
  error_keywords:                      # FILE 모드 필터 키워드
    - "ERROR"
    - "CRITICAL"
    - "FATAL"

# Service Settings
service:
  port: 5000                           # Flask 서비스 포트
  host: "0.0.0.0"                      # 바인딩 호스트
  debug: false                         # 디버그 모드

# Security Settings
security:
  blacklist_file: "config/blacklist.txt"
  auto_keywords_file: "config/auto_keywords.txt"
  command_timeout: 15                  # 명령어 실행 타임아웃 (초)

# Database Settings
database:
  path: "data/incidents.db"            # SQLite DB 경로
  retention_days: 30                   # 이력 보관 기간

# Logging Settings
logging:
  level: "INFO"                        # 로그 레벨
  file: "logs/ai-sre-agent.log"       # 로그 파일 경로
  max_size_mb: 10                      # 최대 로그 파일 크기
  backup_count: 5                      # 백업 파일 개수
```

## 상세 설정 가이드

### 1. API 설정

#### Gemini 모델 선택

사용 가능한 모델:
- `gemini-1.5-flash`: 빠른 응답, 비용 효율적 (권장)
- `gemini-1.5-pro`: 더 정확한 분석, 높은 비용
- `gemini-2.0-flash-exp`: 실험적 버전

변경 방법:
```yaml
api:
  gemini_model: "gemini-1.5-pro"
```

### 2. 모니터링 설정

#### Journald 모드 (권장)

시스템 전체 로그를 모니터링합니다.

```yaml
monitoring:
  type: "JOURNAL"
  error_levels:
    - "err"      # 에러
    - "crit"     # 치명적
    - "alert"    # 경고
    - "emerg"    # 긴급
```

#### Log File 모드

특정 로그 파일을 모니터링합니다.

```yaml
monitoring:
  type: "FILE"
  log_path: "/var/log/application.log"
  error_keywords:
    - "ERROR"
    - "CRITICAL"
    - "FATAL"
    - "Exception"
```

### 3. 보안 설정

#### 블랙리스트 관리

**파일**: `/opt/ai-sre-system/config/blacklist.txt`

위험한 명령어나 패턴을 한 줄에 하나씩 추가:

```
rm
mkfs
shutdown
reboot
dd
fdisk
parted
>
>>
&&
||
```

#### 자동 실행 키워드

**파일**: `/opt/ai-sre-system/config/auto_keywords.txt`

즉시 조치가 필요한 장애 키워드:

```
DISK FULL
OUT OF MEMORY
NO SPACE LEFT
DISK QUOTA EXCEEDED
INODE FULL
```

⚠️ **주의**: 자동 실행 키워드는 신중하게 설정하세요. 잘못된 설정은 시스템에 예기치 않은 영향을 줄 수 있습니다.

#### 명령어 타임아웃

```yaml
security:
  command_timeout: 15  # 초 단위
```

장시간 실행되는 명령어를 방지합니다.

### 4. AI 프롬프트 커스터마이징

**파일**: `/opt/ai-sre-system/config/prompt.txt`

AI의 행동을 제어하는 시스템 프롬프트를 수정할 수 있습니다.

기본 프롬프트:
```
You are a Senior SRE (Site Reliability Engineer) expert specializing in Linux system administration and troubleshooting.

Your task is to analyze system error logs and provide a single, safe bash command to resolve the issue.

Guidelines:
1. Provide ONLY ONE bash command - no explanations, no prose, no multiple commands
2. The command must be safe and non-destructive
3. Avoid commands that could cause data loss or system instability
4. Use standard Linux utilities when possible
5. Include appropriate error handling flags
6. Consider the least invasive solution first

Output format: Just the command itself, nothing else.
```

슬랙에서 실시간으로 변경:
```
/prompt_change Your custom prompt here
```

### 5. 데이터베이스 설정

```yaml
database:
  path: "data/incidents.db"
  retention_days: 30
```

- `path`: SQLite 데이터베이스 파일 경로
- `retention_days`: 이력 보관 기간 (일)

오래된 이력은 자동으로 삭제됩니다.

### 6. 로깅 설정

```yaml
logging:
  level: "INFO"              # DEBUG, INFO, WARNING, ERROR, CRITICAL
  file: "logs/ai-sre-agent.log"
  max_size_mb: 10
  backup_count: 5
```

로그 레벨:
- `DEBUG`: 모든 디버그 정보 포함
- `INFO`: 일반 정보 (권장)
- `WARNING`: 경고 이상만
- `ERROR`: 에러 이상만
- `CRITICAL`: 치명적 에러만

### 7. 슬랙 설정

```yaml
slack:
  webhook_url: "${SLACK_WEBHOOK_URL}"
  channel: "#alerts"
  username: "AI-SRE-Agent"
```

- `webhook_url`: Slack Incoming Webhook URL
- `channel`: 알림을 받을 채널 (Webhook 설정에서 변경 가능)
- `username`: 봇 표시 이름

## 설정 변경 적용

설정 파일을 수정한 후 서비스를 재시작해야 합니다:

```bash
sudo systemctl restart ai-sre-agent.service
```

## 환경별 설정 예제

### 개발 환경

```yaml
service:
  debug: true

logging:
  level: "DEBUG"

security:
  command_timeout: 30
```

### 프로덕션 환경

```yaml
service:
  debug: false

logging:
  level: "INFO"

security:
  command_timeout: 15

database:
  retention_days: 90
```

## 설정 검증

설정 파일이 올바른지 확인:

```bash
sudo -u ai-agent /opt/ai-sre-system/venv/bin/python3 << EOF
import sys
sys.path.insert(0, '/opt/ai-sre-system/src')
from config import get_config
try:
    config = get_config('/opt/ai-sre-system/config/config.yaml')
    print("✅ 설정 파일이 유효합니다.")
except Exception as e:
    print(f"❌ 설정 오류: {e}")
EOF
```
