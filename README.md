# claude-multi-account

Claude Code 멀티 계정 프로필 관리 — 사용량 기반 자동 밸런싱 & 토큰 자동 갱신

## 기능

- **프로필 전환** — `/login` 없이 계정 전환
- **사용량 밸런싱** — 세션 시작 시 토큰 사용량 적은 계정 자동 선택
- **토큰 키퍼** — 크론으로 토큰 만료 전 자동 갱신 (로그아웃 방지)

## 설치

### Claude Code 플러그인으로 설치

```bash
claude plugin add /path/to/claude-multi-account
```

또는 스킬 디렉토리에 직접 복사:

```bash
cp -r . ~/.claude/skills/profile
```

### 초기 설정

```bash
# 1. 현재 계정 저장
/profile save account-a

# 2. 다른 계정 로그인 후 저장
claude auth login --email other@example.com
/profile save account-b

# 3. 토큰 자동 갱신 크론 등록
/profile keeper setup
```

## 사용법

| 명령어 | 설명 |
|--------|------|
| `/profile list` | 프로필 목록 + 사용량 + 토큰 상태 |
| `/profile save <name>` | 현재 계정을 프로필로 저장 |
| `/profile switch <name>` | 수동 전환 |
| `/profile balance` | 사용량 적은 계정으로 자동 전환 |
| `/profile status` | 전체 상태 상세 |
| `/profile keeper` | 토큰 갱신 즉시 실행 |
| `/profile keeper setup` | 4시간마다 크론 등록 |
| `/profile delete <name>` | 프로필 삭제 |

## 동작 원리

### 사용량 밸런싱

```
stats-cache.json (dailyModelTokens)
  → 프로필별 .usage.json에 기록
  → 세션 시작 시 사용량 적은 계정의 credentials로 교체
  → 다음 세션부터 적용
```

### 토큰 키퍼

```
cron (매 4시간)
  → 각 프로필의 refreshToken으로 accessToken 갱신
  → 토큰 만료 방지 → /login 불필요
```

### 데이터 경로

```
~/.claude/profiles/
├── {name}/.credentials.json    # OAuth 인증 정보
├── {name}/meta.json            # 메타 (이메일, 플랜, 저장일시)
├── _previous/.credentials.json # 전환 시 자동 백업
└── .usage.json                 # 프로필별 일일 사용량
```

## 제약사항

- 세션 중간에 계정 전환 불가 (Claude Code가 시작 시 토큰 로드)
- 전환은 **다음 세션**부터 적용
- OAuth refresh endpoint가 변경되면 토큰 키퍼 업데이트 필요

## License

MIT
