# AI-SRE-System Test Suite

이 디렉토리는 AI-SRE-System의 테스트 코드를 포함합니다.

## 테스트 실행

전체 테스트 실행:
```bash
pytest tests/ -v
```

특정 테스트 파일 실행:
```bash
pytest tests/test_security.py -v
```

커버리지 포함 실행:
```bash
pytest tests/ --cov=src --cov-report=html
```

## 테스트 파일

- `test_security.py`: 보안 필터링 로직 테스트
- `test_executor.py`: 명령어 실행 로직 테스트
