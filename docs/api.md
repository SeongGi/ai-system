# AI-SRE-System API 문서

## 개요

AI-SRE-System은 RESTful API를 제공하여 시스템 상태 조회, 장애 이력 확인, 통계 조회 등의 기능을 제공합니다.

**Base URL**: `http://YOUR_SERVER_IP:5000`

## 인증

현재 버전은 인증을 요구하지 않습니다. 프로덕션 환경에서는 방화벽 규칙으로 접근을 제한하는 것을 권장합니다.

## 엔드포인트

### Health Check

시스템 상태를 확인합니다.

**Endpoint**: `GET /health`

**Response**:
```json
{
  "status": "healthy",
  "service": "AI-SRE-Agent"
}
```

**예제**:
```bash
curl http://localhost:5000/health
```

---

### 통계 조회

지정된 기간 동안의 장애 통계를 조회합니다.

**Endpoint**: `GET /stats`

**Query Parameters**:
- `days` (optional): 조회 기간 (일), 기본값: 7

**Response**:
```json
{
  "total_incidents": 42,
  "auto_executed": 15,
  "manually_executed": 20,
  "blocked": 3,
  "pending": 4,
  "risk_distribution": {
    "LOW": 25,
    "MEDIUM": 12,
    "HIGH": 3,
    "CRITICAL": 2
  },
  "daily_counts": [
    {"date": "2026-01-20", "count": 5},
    {"date": "2026-01-21", "count": 8},
    {"date": "2026-01-22", "count": 6}
  ]
}
```

**필드 설명**:
- `total_incidents`: 전체 장애 건수
- `auto_executed`: 자동 실행된 건수
- `manually_executed`: 수동 실행된 건수
- `blocked`: 보안 필터로 차단된 건수
- `pending`: 대기 중인 건수
- `risk_distribution`: 위험도별 분포
- `daily_counts`: 일별 장애 발생 건수

**예제**:
```bash
# 최근 7일 통계
curl http://localhost:5000/stats

# 최근 30일 통계
curl http://localhost:5000/stats?days=30
```

---

### 장애 이력 조회

최근 장애 이력을 조회합니다.

**Endpoint**: `GET /incidents`

**Query Parameters**:
- `limit` (optional): 조회할 최대 건수, 기본값: 100

**Response**:
```json
[
  {
    "id": 123,
    "timestamp": "2026-01-25 09:30:15",
    "log_line": "Jan 25 09:30:15 server kernel: Out of memory: Kill process 1234",
    "ai_command": "kill -9 1234",
    "is_auto_executed": true,
    "is_executed": true,
    "execution_result": "Process killed successfully",
    "execution_timestamp": "2026-01-25 09:30:16",
    "is_safe": true,
    "risk_level": "MEDIUM",
    "error_message": null
  },
  {
    "id": 122,
    "timestamp": "2026-01-25 08:15:30",
    "log_line": "Jan 25 08:15:30 server systemd: Failed to start nginx.service",
    "ai_command": "systemctl restart nginx",
    "is_auto_executed": false,
    "is_executed": true,
    "execution_result": "Service restarted successfully",
    "execution_timestamp": "2026-01-25 08:16:00",
    "is_safe": true,
    "risk_level": "LOW",
    "error_message": null
  }
]
```

**필드 설명**:
- `id`: 장애 ID
- `timestamp`: 장애 발생 시각
- `log_line`: 원본 로그 라인
- `ai_command`: AI가 생성한 명령어
- `is_auto_executed`: 자동 실행 여부
- `is_executed`: 실행 여부
- `execution_result`: 실행 결과
- `execution_timestamp`: 실행 시각
- `is_safe`: 보안 검증 통과 여부
- `risk_level`: 위험도 (LOW, MEDIUM, HIGH, CRITICAL)
- `error_message`: 에러 메시지 (있는 경우)

**예제**:
```bash
# 최근 100건 조회
curl http://localhost:5000/incidents

# 최근 10건만 조회
curl http://localhost:5000/incidents?limit=10
```

---

### AI 프롬프트 변경 (Slack)

Slack Slash Command를 통해 AI 프롬프트를 변경합니다.

**Endpoint**: `POST /prompt/slack`

**Content-Type**: `application/x-www-form-urlencoded`

**Request Body**:
- `text`: 새로운 프롬프트 (비어있으면 현재 프롬프트 조회)

**Response**:
```json
{
  "response_type": "in_channel",
  "text": "✅ 프롬프트가 업데이트되었습니다:\n```Your new prompt```"
}
```

**Slack 사용법**:
```
# 현재 프롬프트 확인
/prompt_change

# 프롬프트 변경
/prompt_change You are an expert SRE. Provide safe commands only.
```

---

### 슬랙 인터랙티브 버튼

슬랙 인터랙티브 버튼 클릭을 처리합니다.

**Endpoint**: `POST /slack/interactive`

**Content-Type**: `application/x-www-form-urlencoded`

**Request Body**:
- `payload`: JSON 형식의 슬랙 페이로드

**Response**:
```json
{
  "replace_original": true,
  "text": "✅ *명령어 실행 완료*\n명령어: `df -h`\n결과:\n```Filesystem      Size  Used Avail Use% Mounted on```"
}
```

이 엔드포인트는 슬랙 앱 설정에서 자동으로 호출됩니다.

---

## 에러 응답

API 에러 발생 시 다음 형식으로 응답합니다:

```json
{
  "error": "Error message here"
}
```

**HTTP 상태 코드**:
- `200`: 성공
- `400`: 잘못된 요청
- `500`: 서버 내부 오류

---

## 사용 예제

### Python

```python
import requests

# Health check
response = requests.get('http://localhost:5000/health')
print(response.json())

# 통계 조회
response = requests.get('http://localhost:5000/stats?days=7')
stats = response.json()
print(f"Total incidents: {stats['total_incidents']}")

# 장애 이력 조회
response = requests.get('http://localhost:5000/incidents?limit=10')
incidents = response.json()
for incident in incidents:
    print(f"{incident['timestamp']}: {incident['log_line']}")
```

### cURL

```bash
# Health check
curl http://localhost:5000/health

# 통계 조회 (JSON 포맷팅)
curl http://localhost:5000/stats | jq .

# 장애 이력 조회
curl http://localhost:5000/incidents?limit=5 | jq .
```

### JavaScript (Fetch)

```javascript
// Health check
fetch('http://localhost:5000/health')
  .then(response => response.json())
  .then(data => console.log(data));

// 통계 조회
fetch('http://localhost:5000/stats?days=30')
  .then(response => response.json())
  .then(stats => {
    console.log(`Total incidents: ${stats.total_incidents}`);
  });

// 장애 이력 조회
fetch('http://localhost:5000/incidents?limit=10')
  .then(response => response.json())
  .then(incidents => {
    incidents.forEach(incident => {
      console.log(`${incident.timestamp}: ${incident.log_line}`);
    });
  });
```

---

## 보안 고려사항

1. **방화벽 설정**: API 포트는 신뢰할 수 있는 IP에서만 접근 가능하도록 설정
2. **HTTPS 사용**: 프로덕션 환경에서는 리버스 프록시(Nginx 등)를 통해 HTTPS 적용
3. **인증 추가**: 필요시 API 키 또는 OAuth 인증 추가 고려

---

## 향후 계획

- [ ] API 인증 (API Key)
- [ ] 웹소켓 기반 실시간 알림
- [ ] GraphQL 지원
- [ ] Rate Limiting
