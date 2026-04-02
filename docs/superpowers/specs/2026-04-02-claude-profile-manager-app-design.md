# Claude Profile Manager — macOS App Design Spec

> 오픈소스 macOS 앱. Claude Code 멀티 계정을 메뉴바에서 원클릭 전환하고, 프로필별 토큰 사용량을 대시보드로 확인한다.

## 1. Overview

### Problem
Claude Code 사용자가 개인 계정(Pro, Max 등)을 여러 개 운영할 때:
- CLI(`/profile switch`)로만 전환 가능 — 불편
- 토큰 사용량을 한눈에 비교할 수 없음
- 토큰 만료 시 수동 갱신 필요

### Solution
macOS 메뉴바 상주 앱 + 대시보드 윈도우.
- 메뉴바: 원클릭 계정 전환, 토큰 잔여시간
- 대시보드: 일별 추이 차트, 모델별 분리, 주간/월간 요약

### Target Users
Claude Code를 여러 개인 계정으로 사용하는 개발자. 오픈소스 공개.

## 2. Design Decisions

| 항목 | 결정 | 이유 |
|------|------|------|
| 플랫폼 | macOS only (v1) | Claude Code 사용자 대부분 Mac. Keychain 네이티브 연동 |
| 형태 | 메뉴바 상주 + 대시보드 윈도우 | 빠른 전환(메뉴바) + 상세 분석(윈도우) |
| 스택 | Swift + SwiftUI | NSStatusItem 1급 지원, Keychain 네이티브, 초경량(~5MB) |
| 전환 방식 | Keychain 교체, 다음 세션 적용 | 기존 세션 보호. 프로세스 강제 종료 안 함 |
| 사용량 | 일별 추이, 모델별 분리, 주간/월간 | CLI 대비 가치 차별화. stats-cache.json 기반 |
| 배포 | GitHub Releases → Homebrew Cask | v1은 비서명, 이후 Notarization |
| 샌드박스 | 비샌드박스 | Keychain ACL 접근 필수. Mac App Store 불가 |

## 3. Architecture

### 모듈 구성 (8개)

```
ClaudeProfileManager.app/
├── App/
│   ├── ClaudeProfileManagerApp.swift   # @main, MenuBar + Window
│   └── AppState.swift                  # 전역 상태 (ObservableObject)
├── MenuBar/
│   ├── MenuBarController.swift         # NSStatusItem + NSPopover
│   └── MenuBarView.swift               # 팝오버 SwiftUI 뷰
├── Dashboard/
│   ├── DashboardWindow.swift           # SwiftUI Window
│   ├── ProfileCardView.swift           # 프로필 카드
│   ├── UsageChartView.swift            # Swift Charts 일별 추이
│   └── ModelBreakdownView.swift        # 모델별 파이 차트
├── Core/
│   ├── ProfileManager.swift            # CRUD + 전환 + 3단계 식별
│   ├── TokenKeeper.swift               # OAuth 갱신 + DispatchSourceTimer
│   ├── UsageTracker.swift              # stats-cache 파싱 + 집계
│   ├── SessionGuard.swift              # Claude Code 프로세스 감지
│   └── ClientIDResolver.swift          # client_id 동적 추출
├── Backend/
│   ├── CredentialBackend.swift         # Protocol 정의
│   └── KeychainBackend.swift           # macOS Keychain 구현
├── Models/
│   ├── Profile.swift                   # 프로필 데이터 모델
│   ├── OAuthCredential.swift           # OAuth 토큰 모델
│   ├── UsageRecord.swift               # 사용량 모델
│   └── SwitchLog.swift                 # 전환 이력 모델
├── Onboarding/
│   └── KeychainPermissionView.swift    # 첫 실행 권한 안내
└── Resources/
    └── Assets.xcassets                 # 아이콘
```

### 모듈 의존 관계

```
MenuBar, Dashboard
    ↓ observe
AppState (ObservableObject)
    ↓ uses
ProfileManager ← SessionGuard
TokenKeeper ← ClientIDResolver
UsageTracker
    ↓ uses
CredentialBackend (Protocol)
    ↓ impl
KeychainBackend
```

## 4. Module Details

### 4.1 ProfileManager

**책임**: 프로필 CRUD, 전환, 활성 프로필 식별

**프로필 식별 — 3단계 체인**:
1. `refreshToken` 직접 매칭 (정확, 토큰 로테이션 전)
2. `email` 매칭 (meta.json, 토큰 로테이션 후에도 안정)
3. `subscriptionType + rateLimitTier` fallback (최후 수단)

**프로필 전환 flow**:
1. SessionGuard.checkRunning() → 실행 중이면 경고
2. 현재 Keychain → `_previous/` 백업
3. 대상 프로필 `.credentials.json` → Keychain 쓰기
4. `switch_log.json`에 전환 시점 기록
5. UsageTracker: 현재 프로필 사용량 스냅샷
6. AppState 업데이트 → UI 반영 + 토스트

**데이터 경로**:
- 프로필 저장: `~/.claude/profiles/{name}/.credentials.json`
- 메타 정보: `~/.claude/profiles/{name}/meta.json`
- 백업: `~/.claude/profiles/_previous/.credentials.json`
- 전환 이력: `~/.claude/profiles/switch_log.json`

### CLI 스킬과의 공존

앱과 기존 `/profile` CLI 스킬은 동일한 파일(`profiles/`, Keychain)을 조작한다.
- **읽기**: 항상 안전 (파일/Keychain은 atomic read)
- **쓰기 충돌 방지**: 앱이 전환 시 `.lock` 파일(`~/.claude/profiles/.switch.lock`)을 생성하고, CLI 스킬도 동일 lock을 확인. advisory lock이므로 강제는 아니지만, 동시 쓰기를 감지하고 경고할 수 있음
- **switch_log.json**: 앱에서만 기록. CLI로 전환하면 기록 누락 → UsageTracker의 "Estimated" 표시로 한계 명시
- **기존 cron 토큰 갱신**: 앱 설치 시 기존 cron 제거를 안내 (앱 내 타이머로 대체). cron이 남아 있어도 토큰 갱신이 두 번 실행될 뿐 부작용 없음 (idempotent)

### 4.2 TokenKeeper

**책임**: 모든 프로필의 OAuth 토큰 만료 감시 + 자동 갱신

**갱신 방식**:
```
POST https://platform.claude.com/v1/oauth/token
Content-Type: application/json

{
  "grant_type": "refresh_token",
  "refresh_token": "<token>",
  "client_id": "<resolved or fallback>",
  "scope": "user:inference user:profile user:sessions:claude_code user:mcp_servers user:file_upload"
}
```

**타이머**: `DispatchSourceTimer` (앱 내부)
- 4시간 간격 실행
- 앱 시작 시 즉시 1회 체크
- `expiresAt < now + 6h` → 갱신 트리거

**갱신 후 처리**:
- `.credentials.json` 업데이트 (새 accessToken + refreshToken + expiresAt)
- 이 프로필이 현재 활성 → Keychain도 업데이트 (email 기반 매칭)
- AppState 갱신 → UI 반영

**LaunchAgent 대신 앱 내 타이머를 선택한 이유**:
- LaunchAgent 컨텍스트에서 Keychain 접근 시 보안 프롬프트/거부 위험
- 앱 프로세스 내에서는 한번 허용하면 이후 무프롬프트
- 앱이 꺼져 있으면 재시작 시 즉시 갱신으로 보완
- Login Items 등록으로 부팅 시 자동 시작 권장

### 4.3 UsageTracker

**책임**: 토큰 사용량 파싱, 프로필별 귀속, 집계

**데이터 소스**:
- `~/.claude/stats-cache.json` → `dailyModelTokens` 배열 (date + tokensByModel)
- `~/.claude/profiles/.usage.json` → 프로필별 일일 사용량
- `~/.claude/profiles/switch_log.json` → 전환 이력 (앱 자체 기록)

**프로필별 귀속 로직**:
1. FileWatcher가 stats-cache.json 변경 감지
2. switch_log.json에서 현재 활성 프로필 확인
3. 마지막 전환 이후의 토큰 delta를 해당 프로필에 귀속
4. .usage.json 업데이트

**정확도 한계**:
- stats-cache.json은 계정 구분 없이 머신 전체 누적
- 앱 밖에서 CLI(`/profile switch`)로 전환하면 switch_log에 기록 안 됨
- UI에 "Estimated" 뱃지로 한계 명시

**집계 제공**:
- 일별 추이 (최근 30일)
- 모델별 분리 (Opus, Sonnet, Haiku)
- 주간/월간 합계

### 4.4 SessionGuard

**책임**: Claude Code 프로세스 실행 감지, 전환 시 경고

**구현**:
- `Process` API 또는 `pgrep -f "claude"` 로 실행 중인 세션 감지
- 전환 시 실행 중이면 Alert 표시:
  > "Claude Code 세션 N개가 실행 중입니다. 전환하면 새 세션부터 적용됩니다. 기존 세션은 영향받지 않습니다."
  > [전환] [취소]

### 4.5 ClientIDResolver

**책임**: Claude Code의 OAuth client_id를 동적으로 확보

**로직**:
1. Claude Code cli.js 경로 탐색 (`which claude` → npm global path)
2. cli.js에서 UUID 패턴(`CLIENT_ID:"<uuid>"`) 추출
3. 성공 → 추출값 사용
4. 실패 → 하드코딩 fallback (`9d1c250a-e61b-44d9-88ed-5944d1962f5e`)
5. 추출값과 fallback이 다르면 로그 경고
6. fallback으로 갱신 실패(HTTP 400) 시 → 대시보드에 "client_id가 변경되었을 수 있습니다. Claude Code를 업데이트하세요." 알림

### 4.6 CredentialBackend (Protocol)

**책임**: credential 저장소 추상화

```swift
protocol CredentialBackend {
    func read() throws -> OAuthCredential?
    func write(_ credential: OAuthCredential) throws
    func delete() throws
}
```

**macOS 구현**: `KeychainBackend`
- Security framework (`SecItemCopyMatching`, `SecItemAdd`, `SecItemUpdate`)
- Keychain service name: `"Claude Code-credentials"`
- 비샌드박스 환경에서 직접 접근

**향후 확장**:
- Linux: `libsecret` (Secret Service API)
- Windows: `Credential Manager`

## 5. UI Design

### 5.1 MenuBar Popover

```
┌──────────────────────────────┐
│  ● Claude Profile Manager    │
├──────────────────────────────┤
│  Active: rtb-team-2          │
│  max (20x) • 5.8h remaining  │
├──────────────────────────────┤
│  ○ max-account               │
│    max (5x) • ⚠️ 4.3h        │
│  ○ pro-account               │
│    pro • ⚠️ 5.6h              │
│  ● rtb-team-2          ← 현재 │
│    max (20x) • 5.8h          │
├──────────────────────────────┤
│  ⟳ Balance Now (1회 밸런싱)    │
│  📊 Open Dashboard           │
│  ⚙ Settings                  │
│  ─────────────               │
│  Quit                        │
└──────────────────────────────┘
```

### 5.2 Dashboard Window

```
┌─────────────────────────────────────────────────────┐
│  Claude Profile Manager — Dashboard                  │
├──────────┬──────────────────────────────────────────┤
│ Profiles │  Daily Usage (Estimated)                  │
│          │  ┌──────────────────────────────────┐     │
│ [card]   │  │  ▁▂▃▅▇█▆▄▃▂  ← 30일 추이 차트   │     │
│ rtb-2    │  │  Opus ■  Sonnet ■  Haiku ■       │     │
│ ● active │  └──────────────────────────────────┘     │
│ 5.8h     │                                           │
│          │  Model Breakdown        Weekly Summary     │
│ [card]   │  ┌──────────┐          ┌──────────────┐  │
│ max-acc  │  │  🟣 72%   │          │ This week:    │  │
│ ⚠️ 4.3h  │  │  🔵 25%   │          │  142K tokens  │  │
│          │  │  ⚪ 3%    │          │ Last week:    │  │
│ [card]   │  └──────────┘          │  98K tokens   │  │
│ pro-acc  │                         └──────────────┘  │
│ ⚠️ 5.6h  │                                           │
├──────────┴──────────────────────────────────────────┤
│  Token Keeper: Last refresh 2h ago • Next in 2h     │
└─────────────────────────────────────────────────────┘
```

## 6. Data Models

### Profile

```swift
struct Profile: Identifiable, Codable {
    let id: String          // directory name (e.g. "max-account")
    var email: String       // primary identifier
    var subscriptionType: String  // "max", "pro"
    var rateLimitTier: String
    var scopes: [String]
    var savedAt: Date
}
```

### OAuthCredential

```swift
struct OAuthCredential: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Int64        // milliseconds
    var scopes: [String]
    var subscriptionType: String?
    var rateLimitTier: String?
}
```

### SwitchLog

```swift
struct SwitchLogEntry: Codable {
    let timestamp: Date
    let fromProfile: String?
    let toProfile: String
}
```

## 7. Distribution

### v1.0: GitHub Releases
- Xcode build → Universal binary (arm64 + x86_64)
- .app을 zip으로 압축 → GitHub Release 업로드
- GitHub Actions 자동화
- 비서명: 사용자가 Gatekeeper 허용 필요 (README에 안내)

### v1.1+: Homebrew Cask
- Custom tap: `brew tap wowoyong/tap`
- `brew install --cask claude-profile-manager`
- Apple Developer 계정 ($99/yr) → Notarization

### CI/CD (GitHub Actions)

```yaml
on:
  push:
    tags: ['v*']
jobs:
  build:
    runs-on: macos-latest
    steps:
      - xcodebuild archive (Release, arm64+x86_64)
      - zip .app
      - gh release create with .zip asset
```

## 8. Onboarding Flow

```
첫 실행:
1. "Claude Profile Manager에 오신 것을 환영합니다" 화면
2. Keychain 접근 시도 → macOS 프롬프트 → "항상 허용" 안내
3. 접근 성공 → 기존 프로필 자동 감지 (~/.claude/profiles/ 스캔)
4. 프로필이 있으면 → 목록 표시 + "이 프로필들을 가져왔습니다"
   프로필이 없으면 → Keychain에서 현재 계정 읽기 → "현재 계정을 첫 프로필로 저장하시겠습니까?"
5. Login Items 등록 제안 (부팅 시 자동 시작)
6. 메뉴바 아이콘 표시 → 사용 시작
```

## 9. Risks & Mitigations

| 위험 | 심각도 | 완화 |
|------|--------|------|
| Keychain ACL 접근 거부 | 상 | 비샌드박스 배포 + Onboarding에서 권한 안내 |
| 동일 구독 다계정 식별 충돌 | 상 | email 기반 3단계 식별 체인 |
| client_id 변경 | 하 | 동적 추출 + 하드코딩 fallback |
| stats-cache.json 계정 미분리 | 중 | switch_log 기반 귀속 + "Estimated" 표시 |
| 코드 서명 없이 Gatekeeper 차단 | 중 | README 안내, v1.1에서 Notarization |
| 동시 세션 중 전환 | 중 | SessionGuard 경고 + "다음 세션 적용" 명시 |

## 10. Out of Scope (v1)

- Linux / Windows 지원 (아키텍처만 확장 가능하게)
- 비용($) 추정
- Rate limit 실시간 표시
- 세션별 사용량 breakdown
- Mac App Store 배포
- Claude Code 프로세스 자동 재시작
