# claude-multi-account

Claude Code 멀티 계정 프로필 관리 — macOS 메뉴바 앱 + CLI 스킬

## Features

- **원클릭 계정 전환** — macOS 메뉴바에서 클릭 한번으로 전환
- **사용량 대시보드** — 일별 추이 차트, 모델별 분석, 주간/월간 요약
- **자동 토큰 갱신** — 만료 전 자동 refresh (재로그인 불필요)
- **사용량 밸런싱** — 토큰 사용량 적은 계정으로 자동 전환
- **CLI 스킬** — `/profile` 명령어로 터미널에서도 관리

## macOS App (Claude Profile Manager)

메뉴바에서 Claude Code 계정을 관리하는 네이티브 macOS 앱.

### 설치

[GitHub Releases](https://github.com/wowoyong/claude-multi-account/releases)에서 최신 `.zip` 다운로드 → 압축 해제 → Applications에 드래그.

> **Gatekeeper 경고 시:** System Settings → Privacy & Security → "Open Anyway" 클릭.

> **Keychain 접근:** 첫 실행 시 macOS가 비밀번호를 물어봅니다. **"항상 허용(Always Allow)"**을 선택하세요. "허용(Allow)"만 누르면 매번 물어봅니다.

### 빌드 (개발자)

```bash
# 사전 요구: Xcode, xcodegen
brew install xcodegen

cd ClaudeProfileManager
xcodegen generate
xcodebuild build -scheme ClaudeProfileManager -destination "platform=macOS"

# 실행
open ~/Library/Developer/Xcode/DerivedData/ClaudeProfileManager-*/Build/Products/Debug/ClaudeProfileManager.app
```

### 기능
- 메뉴바에서 원클릭 계정 전환
- 토큰 잔여시간 실시간 표시
- 자동 토큰 갱신 (4시간 간격)
- 일별 사용량 차트 + 모델별 분석 (Swift Charts)
- 주간/월간 사용량 요약

### 기술 스택
- Swift + SwiftUI
- Swift Charts (macOS 13+)
- Security framework (macOS Keychain)
- 비샌드박스 (Keychain 직접 접근)

## CLI 스킬 (`/profile`)

Claude Code 터미널에서 프로필을 관리하는 슬래시 명령어.

### 설치

```bash
# Claude Code 플러그인으로 설치
claude plugin add /path/to/claude-multi-account

# 또는 스킬 디렉토리에 직접 복사
cp -r . ~/.claude/skills/profile
```

### 초기 설정

```bash
# 1. 현재 계정 저장
/profile save account-a

# 2. 다른 계정 로그인 후 저장
# 터미널에서: claude auth login
# 새 세션에서: /profile save account-b

# 3. 토큰 자동 갱신 크론 등록
/profile keeper setup
```

### 명령어

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

### Keychain 연동 (Claude Code 2.x)

Claude Code 2.x는 macOS Keychain(`Claude Code-credentials`)에 인증 정보를 저장합니다. 이 도구는 Keychain을 직접 읽고 써서 계정을 전환합니다.

```
macOS Keychain ("Claude Code-credentials")
  ↕ 앱/스킬이 읽기/쓰기
~/.claude/profiles/{name}/.credentials.json
  ↕ 프로필별 저장
```

### OAuth 토큰 갱신

```
POST https://platform.claude.com/v1/oauth/token
Content-Type: application/json

{
  "grant_type": "refresh_token",
  "refresh_token": "<token>",
  "client_id": "<auto-detected>",
  "scope": "user:inference user:profile user:sessions:claude_code ..."
}
```

### 데이터 경로

```
~/.claude/profiles/
├── {name}/.credentials.json    # OAuth 인증 정보
├── {name}/meta.json            # 메타 (이메일, 플랜, 저장일시)
├── _previous/.credentials.json # 전환 시 자동 백업
├── .usage.json                 # 프로필별 일일 사용량
└── switch_log.json             # 전환 이력 (앱 전용)
```

## 제약사항

- 세션 중간에 계정 전환 불가 — 전환은 **다음 세션**부터 적용
- macOS 전용 (v1) — Linux/Windows는 아키텍처만 확장 가능하게 설계
- 사용량 추적은 추정치 — `stats-cache.json`이 계정별로 분리되지 않음
- 비샌드박스 앱 — Mac App Store 배포 불가

## License

MIT
