AI SRE Auto-Remediator
Google Gemini AI 기반 실시간 시스템 장애 탐지 및 자동 복구 에이전트

![시스템 구성도](./ai-agent-gemini.png)

이 도구는 리눅스 서버의 시스템 로그를 실시간으로 모니터링하여, 장애가 감지되면 AI가 즉각적으로 분석하고 해결 명령어를 제안합니다. 관리자는 슬랙(Slack)을 통해 보고를 받고 승인을 통해 서버를 복구할 수 있습니다.

- 주요기능

실시간 장애 감지: Journald 또는 특정 로그 파일을 감시하여 시스템 에러를 즉시 포착합니다.
AI 상황 분석: Google Gemini 모델이 에러 로그의 문맥을 분석하여 가장 적절한 Bash 명령어를 생성합니다.
보안 필터링 (Blacklist): rm, mkfs 등 시스템에 치명적인 명령어는 실행 전 자동으로 차단합니다.
자동 조치 (Auto-Execute): DISK FULL과 같이 사전에 정의된 중요 키워드는 관리자 승인 없이 AI가 즉시 복구합니다.
인터랙티브 슬랙 연동: 슬랙 버튼을 통해 조치 명령어를 실행/거절하고, 결과까지 슬랙에서 바로 확인합니다.


### 시스템 아키텍처
현재 시스템은 다음과 같은 흐름으로 동작합니다:

1. 실시간 모니터링 (Detection Phase)
Journald 또는 지정된 로그 파일을 실시간으로 감시(tail -F 방식)합니다.
시스템 에러 레벨(err, crit, alert, emerg) 또는 사용자가 지정한 에러 키워드가 포함된 로그만 추출합니다.

2. AI 상황 분석 (Analysis Phase)
탐지된 로그와 prompt.txt에 정의된 SRE 전문가 지침을 함께 Gemini AI에게 전달합니다.
AI는 발생한 장애를 해결하기 위한 최적의 단일 Bash 명령어를 생성합니다.

3. 보안 검증 (Security Filter)
AI가 제안한 명령어가 실행되기 전, blacklist.txt를 실시간으로 읽어 대조합니다.
rm, mkfs 등 시스템에 위험한 단어가 포함되어 있다면 즉시 실행을 차단하고 슬랙으로 보안 경고를 전송합니다.

4. 조치 및 보고 (Action & Notification)

자동 조치: 로그 내용이 auto_keywords.txt에 등록된 키워드(예: DISK FULL)와 일치하면 승인 없이 즉시 명령어를 실행합니다.
수동 조치: 그 외의 일반 에러는 슬랙 버튼을 통해 관리자에게 '실행' 또는 '거절' 여부를 묻습니다.
결과 보고: 명령어 실행 결과(Standard Output/Error)를 다시 슬랙으로 전송하여 최종 조치 여부를 확인합니다.


### 관리 및 설정 방법

에이전트 설치 후, 모든 설정은 /opt/ai-agent/ 디렉토리 내의 텍스트 파일을 수정하여 서비스 재시작 없이 즉시 반영할 수 있습니다.

관리대상        파일 경로                 설명 
보안 필터링      blacklist.txt           실행을 차단할 위험 단어 목록 (예: rm, mkfs)
자동 조치       auto_keywords.txt       AI가 승인 없이 즉시 조치할 로그 키워드 (예: DISK FULL)
AI 페르소나     prompt.txt              AI에게 부여할 지침 (슬랙 /prompt_change로도 수정 가능)

# 에이전트 설치 및 동작 프로세스
설치 쉘 스크립트를 실행하면 아래의 6단계 과정을 통해 AI SRE 환경이 구축됩니다.

1. 환경 초기화 및 클린업 (Cleanup Phase)
새로운 설치를 위해 기존에 구동 중인 서비스와 데이터를 정리합니다.
기존 ai-remediator 서비스 중지 및 삭제
에이전트 사용 포트(예: 7788) 점유 프로세스 종료
기존 설치 디렉토리(/opt/ai-agent) 및 전용 유저 삭제

2. 전용 유저 및 권한 설정 (Security Setup)
보안을 위해 최소 권한을 가진 전용 시스템 유저를 생성합니다.
ai-agent 시스템 유저 생성
시스템 로그를 읽을 수 있도록 adm 및 systemd-journal 그룹에 유저 추가
작업 디렉토리 생성 및 소유권 부여

3. 관리용 설정 파일 생성 (Configuration Setup)
AI의 행동을 제어하는 3대 핵심 텍스트 파일을 기본값으로 생성합니다.
prompt.txt: AI에게 부여하는 SRE 전문가 지침서
blacklist.txt: 실행을 금지할 위험 명령어 목록 (rm, mkfs 등)
auto_keywords.txt: 승인 없이 즉시 조치할 장애 키워드 (DISK FULL 등)

4. Python 가상환경 구축 및 패키지 설치 (Python Environment)
시스템 라이브러리와 분리된 독립적인 실행 환경을 구성합니다.
python3 -m venv venv: 독립 가상환경 생성
pip install: 필수 라이브러리(flask, requests, google-genai) 설치

5. 메인 로직(main.py) 및 서비스 등록 (Deployment)
에이전트의 핵심 엔진을 배치하고 백그라운드 서비스로 등록합니다.
main.py 파일 생성: 로그 감시, AI 분석, 슬랙 통신 로직 포함
systemd 유닛 파일 생성: 서버 부팅 시 자동 실행 및 프로세스 다운 시 자동 재시작 설정

6. 서비스 가동 및 상태 확인 (Activation)
모든 설정을 마치고 모니터링을 시작합니다.
systemctl start: 에이전트 서비스 즉시 가동
공백이나 특수문자가 제거된 안전한 환경 변수 주입 확인
최종 접속 IP 및 포트 정보 출력


### 관리 명령어
서버 터미널에서 에이전트의 상태를 확인하고 관리할 때 사용합니다.

실시간 작동 로그 확인

```
sudo journalctl -u ai-remediator.service -f
```

서비스 상태 확인 및 재시작
```
sudo systemctl status ai-remediator.service
sudo systemctl restart ai-remediator.service
```

보안 블랙리스트 수정
```
sudo nano /opt/ai-agent/blacklist.txt
```

### 주의 사항
API 키 보안: main.py와 서비스 설정에 포함된 Gemini API 키가 외부로 유출되지 않도록 주의하십시오.

권한 관리: 에이전트는 ai-agent 유저 권한으로 실행되나, AI가 제안하는 명령어에 따라 sudo 권한이 필요할 수 있습니다. (현재 스크립트는 원활한 조치를 위해 필요한 권한 환경을 제공합니다.)

### 프로젝트 구조

```
.
├── main.py              # 메인 실행 파일
├── prompt.txt           # 프롬프트 영구 저장 파일
├── requirements.txt     # 의존성 패키지 목록
└── README.md            # 설명서

```