# Claude Profile Manager — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 메뉴바 상주 앱으로 Claude Code 멀티 계정을 원클릭 전환하고, 프로필별 토큰 사용량을 대시보드로 확인한다.

**Architecture:** 8개 모듈 (Models → Backend → Core → MenuBar/Dashboard → Onboarding → App). CredentialBackend protocol로 Keychain 추상화. AppState(ObservableObject)가 UI와 Core를 연결. 비샌드박스 배포.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Charts, Security framework, macOS 13+ (Ventura)

**Spec:** `docs/superpowers/specs/2026-04-02-claude-profile-manager-app-design.md`

---

## File Structure

```
ClaudeProfileManager/
├── ClaudeProfileManager.xcodeproj
├── ClaudeProfileManager/
│   ├── App/
│   │   ├── ClaudeProfileManagerApp.swift     # @main entry, menubar + window
│   │   └── AppState.swift                    # ObservableObject global state
│   ├── Models/
│   │   ├── Profile.swift                     # Profile data model + meta.json Codable
│   │   ├── OAuthCredential.swift             # claudeAiOauth JSON structure
│   │   ├── UsageRecord.swift                 # .usage.json + stats-cache.json models
│   │   └── SwitchLog.swift                   # switch_log.json model
│   ├── Backend/
│   │   ├── CredentialBackend.swift           # Protocol definition
│   │   └── KeychainBackend.swift             # macOS Keychain implementation
│   ├── Core/
│   │   ├── ProfileManager.swift              # CRUD + switch + 3-stage identification
│   │   ├── TokenKeeper.swift                 # OAuth refresh + DispatchSourceTimer
│   │   ├── UsageTracker.swift                # stats-cache parsing + aggregation
│   │   ├── SessionGuard.swift                # Claude Code process detection
│   │   └── ClientIDResolver.swift            # client_id dynamic extraction
│   ├── MenuBar/
│   │   ├── MenuBarController.swift           # NSStatusItem + NSPopover
│   │   └── MenuBarView.swift                 # Popover SwiftUI view
│   ├── Dashboard/
│   │   ├── DashboardView.swift               # Main dashboard layout
│   │   ├── ProfileCardView.swift             # Profile card component
│   │   ├── UsageChartView.swift              # Swift Charts daily trend
│   │   └── ModelBreakdownView.swift          # Model pie chart
│   ├── Onboarding/
│   │   └── OnboardingView.swift              # First-run permission + setup
│   ├── Resources/
│   │   └── Assets.xcassets/                  # App icon + menubar icon
│   └── Info.plist
├── ClaudeProfileManagerTests/
│   ├── Models/
│   │   ├── ProfileTests.swift
│   │   ├── OAuthCredentialTests.swift
│   │   └── SwitchLogTests.swift
│   ├── Backend/
│   │   └── KeychainBackendTests.swift
│   ├── Core/
│   │   ├── ProfileManagerTests.swift
│   │   ├── TokenKeeperTests.swift
│   │   ├── UsageTrackerTests.swift
│   │   ├── SessionGuardTests.swift
│   │   └── ClientIDResolverTests.swift
│   └── Helpers/
│       └── MockCredentialBackend.swift
└── .github/
    └── workflows/
        └── build.yml
```

---

### Task 1: Xcode 프로젝트 생성

**Files:**
- Create: `ClaudeProfileManager/` (전체 Xcode 프로젝트)

- [ ] **Step 1: Xcode 프로젝트 생성**

```bash
cd /Users/chojaeyong/RSQUARE/claude-multi-account
mkdir -p ClaudeProfileManager
```

Xcode에서 새 프로젝트:
- Template: macOS → App
- Product Name: `ClaudeProfileManager`
- Interface: SwiftUI
- Language: Swift
- 위치: `/Users/chojaeyong/RSQUARE/claude-multi-account/ClaudeProfileManager/`

**중요: SPM `.executableTarget`으로는 SwiftUI 메뉴바 앱(MenuBarExtra, Assets.xcassets, Info.plist/LSUIElement)을 빌드할 수 없음. Xcode 프로젝트 필수.**

CLI에서 Xcode 프로젝트를 생성하려면 `xcodegen` 또는 Xcode GUI를 사용:

```bash
# xcodegen 사용 시
cd /Users/chojaeyong/RSQUARE/claude-multi-account/ClaudeProfileManager
cat > project.yml << 'YAML'
name: ClaudeProfileManager
options:
  bundleIdPrefix: com.claude
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
targets:
  ClaudeProfileManager:
    type: application
    platform: macOS
    sources: [Sources]
    settings:
      base:
        INFOPLIST_FILE: Sources/Info.plist
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        CODE_SIGN_IDENTITY: "-"
        PRODUCT_BUNDLE_IDENTIFIER: com.claude.profile-manager
  ClaudeProfileManagerTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests]
    dependencies:
      - target: ClaudeProfileManager
YAML
xcodegen generate
```

또는 Xcode GUI: File → New Project → macOS App → SwiftUI → Product Name: ClaudeProfileManager

- [ ] **Step 2: 디렉토리 구조 생성**

```bash
cd /Users/chojaeyong/RSQUARE/claude-multi-account/ClaudeProfileManager

mkdir -p Sources/{App,Models,Backend,Core,MenuBar,Dashboard,Onboarding,Resources}
mkdir -p Tests/{Models,Backend,Core,Helpers}
```

- [ ] **Step 3: Info.plist 생성 (LSUIElement = menubar-only 앱)**

Create `Sources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>Claude Profile Manager</string>
    <key>CFBundleIdentifier</key>
    <string>com.claude.profile-manager</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
```

- [ ] **Step 4: 최소 @main 앱 진입점 작성**

Create `Sources/App/ClaudeProfileManagerApp.swift`:

```swift
import SwiftUI

@main
struct ClaudeProfileManagerApp: App {
    var body: some Scene {
        // MenuBar 앱 — Dock 아이콘 없이 메뉴바에만 표시
        MenuBarExtra("Claude Profile Manager", systemImage: "person.2.circle") {
            Text("Loading...")
        }
        
        Window("Dashboard", id: "dashboard") {
            Text("Dashboard will appear here")
        }
    }
}
```

- [ ] **Step 5: 빌드 확인**

```bash
cd /Users/chojaeyong/RSQUARE/claude-multi-account/ClaudeProfileManager
xcodebuild build -scheme ClaudeProfileManager 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: 커밋**

```bash
cd /Users/chojaeyong/RSQUARE/claude-multi-account
git add ClaudeProfileManager/
git commit -m "feat: scaffold Xcode project with SPM structure"
```

---

### Task 2: Data Models

**Files:**
- Create: `Sources/Models/Profile.swift`
- Create: `Sources/Models/OAuthCredential.swift`
- Create: `Sources/Models/UsageRecord.swift`
- Create: `Sources/Models/SwitchLog.swift`
- Test: `Tests/Models/ProfileTests.swift`
- Test: `Tests/Models/OAuthCredentialTests.swift`
- Test: `Tests/Models/SwitchLogTests.swift`

- [ ] **Step 1: Write failing tests for Profile model**

Create `Tests/Models/ProfileTests.swift`:

```swift
import XCTest
@testable import ClaudeProfileManager

final class ProfileTests: XCTestCase {
    
    func testDecodeMetaJSON() throws {
        let json = """
        {
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_20x",
            "email": "user@example.com",
            "scopes": ["user:inference", "user:profile"],
            "savedAt": "2026-04-02T13:52:06.249316"
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder.profileDecoder.decode(ProfileMeta.self, from: json)
        XCTAssertEqual(profile.email, "user@example.com")
        XCTAssertEqual(profile.subscriptionType, "max")
        XCTAssertEqual(profile.rateLimitTier, "default_claude_max_20x")
        XCTAssertEqual(profile.scopes.count, 2)
    }
    
    func testProfileIdentity() {
        let a = Profile(id: "account-a", meta: ProfileMeta(
            subscriptionType: "max", rateLimitTier: "20x",
            email: "a@test.com", scopes: [], savedAt: Date()
        ))
        let b = Profile(id: "account-b", meta: ProfileMeta(
            subscriptionType: "max", rateLimitTier: "20x",
            email: "b@test.com", scopes: [], savedAt: Date()
        ))
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a.meta.email, b.meta.email)
    }
    
    func testProfileWithEmptyEmail() {
        let profile = Profile(id: "test", meta: ProfileMeta(
            subscriptionType: "pro", rateLimitTier: "default",
            email: "", scopes: [], savedAt: Date()
        ))
        XCTAssertTrue(profile.meta.email.isEmpty)
    }
}
```

- [ ] **Step 2: Write failing tests for OAuthCredential**

Create `Tests/Models/OAuthCredentialTests.swift`:

```swift
import XCTest
@testable import ClaudeProfileManager

final class OAuthCredentialTests: XCTestCase {
    
    func testDecodeKeychainJSON() throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "sk-ant-oat01-test",
                "refreshToken": "sk-ant-ort01-test",
                "expiresAt": 1775127167770,
                "scopes": ["user:inference", "user:profile", "user:sessions:claude_code"],
                "subscriptionType": "max",
                "rateLimitTier": "default_claude_max_20x"
            }
        }
        """.data(using: .utf8)!
        
        let wrapper = try JSONDecoder().decode(CredentialWrapper.self, from: json)
        let oauth = wrapper.claudeAiOauth
        XCTAssertEqual(oauth.accessToken, "sk-ant-oat01-test")
        XCTAssertEqual(oauth.refreshToken, "sk-ant-ort01-test")
        XCTAssertEqual(oauth.expiresAt, 1775127167770)
        XCTAssertEqual(oauth.subscriptionType, "max")
        XCTAssertEqual(oauth.scopes.count, 3)
    }
    
    func testTokenExpiry() {
        let expired = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: 0, scopes: [],
            subscriptionType: "max", rateLimitTier: "20x"
        )
        XCTAssertTrue(expired.isExpired)
        XCTAssertTrue(expired.isExpiringSoon(thresholdHours: 6))
        
        let future = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: Int64(Date().timeIntervalSince1970 * 1000) + 24 * 3600 * 1000,
            scopes: [], subscriptionType: "pro", rateLimitTier: "default"
        )
        XCTAssertFalse(future.isExpired)
        XCTAssertFalse(future.isExpiringSoon(thresholdHours: 6))
    }
    
    func testRemainingHours() {
        let sixHoursFromNow = Int64(Date().timeIntervalSince1970 * 1000) + 6 * 3600 * 1000
        let cred = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: sixHoursFromNow, scopes: [],
            subscriptionType: nil, rateLimitTier: nil
        )
        let remaining = cred.remainingHours
        XCTAssertGreaterThan(remaining, 5.9)
        XCTAssertLessThan(remaining, 6.1)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd /Users/chojaeyong/RSQUARE/claude-multi-account/ClaudeProfileManager
swift test 2>&1 | tail -10
```

Expected: Compilation errors (types not defined yet)

- [ ] **Step 4: Implement Profile model**

Create `Sources/Models/Profile.swift`:

```swift
import Foundation

struct ProfileMeta: Codable, Equatable {
    var subscriptionType: String
    var rateLimitTier: String
    var email: String
    var scopes: [String]
    var savedAt: Date
}

struct Profile: Identifiable, Equatable {
    let id: String          // directory name (e.g. "max-account")
    var meta: ProfileMeta
    var credential: OAuthCredential?
    
    var displayName: String {
        meta.email.isEmpty ? id : meta.email
    }
}

extension JSONDecoder {
    static let profileDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Try ISO8601 with fractional seconds first, then without
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Cannot decode date: \(string)"
            )
        }
        return decoder
    }()
}
```

- [ ] **Step 5: Implement OAuthCredential model**

Create `Sources/Models/OAuthCredential.swift`:

```swift
import Foundation

struct OAuthCredential: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Int64        // milliseconds since epoch
    var scopes: [String]
    var subscriptionType: String?
    var rateLimitTier: String?
    
    var isExpired: Bool {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return expiresAt <= nowMs
    }
    
    func isExpiringSoon(thresholdHours: Double = 6) -> Bool {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let thresholdMs = Int64(thresholdHours * 3600 * 1000)
        return expiresAt <= nowMs + thresholdMs
    }
    
    var remainingHours: Double {
        let nowMs = Double(Date().timeIntervalSince1970 * 1000)
        return (Double(expiresAt) - nowMs) / 1000 / 3600
    }
}

/// Top-level wrapper matching Keychain JSON: { "claudeAiOauth": {...}, "mcpOAuth": {...} }
struct CredentialWrapper: Codable {
    var claudeAiOauth: OAuthCredential
    var mcpOAuth: AnyCodable?
    
    struct AnyCodable: Codable {
        // Opaque pass-through for mcpOAuth — preserve but don't parse
        let value: Any
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let dict = try? container.decode([String: String].self) {
                value = dict
            } else {
                value = try container.decode(String.self)
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let dict = value as? [String: String] {
                try container.encode(dict)
            } else if let str = value as? String {
                try container.encode(str)
            }
        }
    }
}
```

- [ ] **Step 6: Implement UsageRecord and SwitchLog models**

Create `Sources/Models/UsageRecord.swift`:

```swift
import Foundation

/// Matches stats-cache.json dailyModelTokens entry
struct DailyModelTokens: Codable {
    let date: String            // "2026-04-02"
    let tokensByModel: [String: Int]
    
    var totalTokens: Int {
        tokensByModel.values.reduce(0, +)
    }
}

/// Matches stats-cache.json top-level
struct StatsCache: Codable {
    let dailyModelTokens: [DailyModelTokens]
}

/// Per-profile usage stored in .usage.json
struct ProfileUsage: Codable {
    var daily: [String: Int]    // date -> tokens
    var total: Int
    var lastUsed: String?
}

typealias UsageDatabase = [String: ProfileUsage]  // profileName -> usage
```

Create `Sources/Models/SwitchLog.swift`:

```swift
import Foundation

struct SwitchLogEntry: Codable, Equatable {
    let timestamp: Date
    let fromProfile: String?
    let toProfile: String
}
```

Create `Tests/Models/SwitchLogTests.swift`:

```swift
import XCTest
@testable import ClaudeProfileManager

final class SwitchLogTests: XCTestCase {
    
    func testEncodeDecodeSwitchLog() throws {
        let entry = SwitchLogEntry(
            timestamp: Date(timeIntervalSince1970: 1712000000),
            fromProfile: "pro-account",
            toProfile: "max-account"
        )
        let data = try JSONEncoder().encode([entry])
        let decoded = try JSONDecoder().decode([SwitchLogEntry].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].fromProfile, "pro-account")
        XCTAssertEqual(decoded[0].toProfile, "max-account")
    }
    
    func testSwitchLogWithNilFrom() throws {
        let entry = SwitchLogEntry(
            timestamp: Date(), fromProfile: nil, toProfile: "first-account"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(SwitchLogEntry.self, from: data)
        XCTAssertNil(decoded.fromProfile)
        XCTAssertEqual(decoded.toProfile, "first-account")
    }
    
    func testEmptyLog() throws {
        let data = "[]".data(using: .utf8)!
        let log = try JSONDecoder().decode([SwitchLogEntry].self, from: data)
        XCTAssertTrue(log.isEmpty)
    }
}
```

- [ ] **Step 7: Run tests**

```bash
cd /Users/chojaeyong/RSQUARE/claude-multi-account/ClaudeProfileManager
swift test 2>&1 | tail -20
```

Expected: All tests pass

- [ ] **Step 8: 커밋**

```bash
cd /Users/chojaeyong/RSQUARE/claude-multi-account
git add ClaudeProfileManager/Sources/Models/ ClaudeProfileManager/Tests/Models/
git commit -m "feat: add data models (Profile, OAuthCredential, UsageRecord, SwitchLog)"
```

---

### Task 3: CredentialBackend Protocol + KeychainBackend

**Files:**
- Create: `Sources/Backend/CredentialBackend.swift`
- Create: `Sources/Backend/KeychainBackend.swift`
- Create: `Tests/Helpers/MockCredentialBackend.swift`
- Create: `Tests/Backend/KeychainBackendTests.swift`

- [ ] **Step 1: Write CredentialBackend protocol and mock**

Create `Sources/Backend/CredentialBackend.swift`:

```swift
import Foundation

protocol CredentialBackend {
    func read() throws -> CredentialWrapper?
    func write(_ credential: CredentialWrapper) throws
    func delete() throws
}
```

Create `Tests/Helpers/MockCredentialBackend.swift`:

```swift
import Foundation
@testable import ClaudeProfileManager

final class MockCredentialBackend: CredentialBackend {
    var stored: CredentialWrapper?
    var readCallCount = 0
    var writeCallCount = 0
    var shouldThrowOnRead = false
    var shouldThrowOnWrite = false
    
    func read() throws -> CredentialWrapper? {
        readCallCount += 1
        if shouldThrowOnRead { throw NSError(domain: "Mock", code: -1) }
        return stored
    }
    
    func write(_ credential: CredentialWrapper) throws {
        writeCallCount += 1
        if shouldThrowOnWrite { throw NSError(domain: "Mock", code: -1) }
        stored = credential
    }
    
    func delete() throws {
        stored = nil
    }
}
```

- [ ] **Step 2: Write failing tests for KeychainBackend**

Create `Tests/Backend/KeychainBackendTests.swift`:

```swift
import XCTest
@testable import ClaudeProfileManager

final class KeychainBackendTests: XCTestCase {
    
    // Use a test-specific service name to avoid touching real Keychain
    let testService = "ClaudeProfileManager-Test-\(UUID().uuidString)"
    var backend: KeychainBackend!
    
    override func setUp() {
        backend = KeychainBackend(serviceName: testService)
    }
    
    override func tearDown() {
        try? backend.delete()
    }
    
    func testReadNonexistent() throws {
        let result = try backend.read()
        XCTAssertNil(result)
    }
    
    func testWriteAndRead() throws {
        let oauth = OAuthCredential(
            accessToken: "test-at", refreshToken: "test-rt",
            expiresAt: 9999999999999, scopes: ["user:inference"],
            subscriptionType: "max", rateLimitTier: "20x"
        )
        let wrapper = CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil)
        
        try backend.write(wrapper)
        let read = try backend.read()
        
        XCTAssertNotNil(read)
        XCTAssertEqual(read?.claudeAiOauth.accessToken, "test-at")
        XCTAssertEqual(read?.claudeAiOauth.refreshToken, "test-rt")
        XCTAssertEqual(read?.claudeAiOauth.subscriptionType, "max")
    }
    
    func testOverwrite() throws {
        let oauth1 = OAuthCredential(
            accessToken: "old", refreshToken: "old-rt",
            expiresAt: 1, scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        try backend.write(CredentialWrapper(claudeAiOauth: oauth1, mcpOAuth: nil))
        
        let oauth2 = OAuthCredential(
            accessToken: "new", refreshToken: "new-rt",
            expiresAt: 2, scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        try backend.write(CredentialWrapper(claudeAiOauth: oauth2, mcpOAuth: nil))
        
        let read = try backend.read()
        XCTAssertEqual(read?.claudeAiOauth.accessToken, "new")
    }
    
    func testDelete() throws {
        let oauth = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: 1, scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        try backend.write(CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil))
        try backend.delete()
        XCTAssertNil(try backend.read())
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
swift test --filter KeychainBackendTests 2>&1 | tail -10
```

Expected: Compilation error (KeychainBackend not defined)

- [ ] **Step 4: Implement KeychainBackend**

Create `Sources/Backend/KeychainBackend.swift`:

```swift
import Foundation
import Security

final class KeychainBackend: CredentialBackend {
    let serviceName: String
    
    init(serviceName: String = "Claude Code-credentials") {
        self.serviceName = serviceName
    }
    
    func read() throws -> CredentialWrapper? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.readFailed(status)
        }
        
        return try JSONDecoder().decode(CredentialWrapper.self, from: data)
    }
    
    func write(_ credential: CredentialWrapper) throws {
        let data = try JSONEncoder().encode(credential)
        
        // Try update first, then add
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccount as String] = "" as String
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.writeFailed(status)
        }
    }
    
    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .readFailed(let s): return "Keychain read failed: \(s)"
        case .writeFailed(let s): return "Keychain write failed: \(s)"
        case .deleteFailed(let s): return "Keychain delete failed: \(s)"
        }
    }
}
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter KeychainBackendTests 2>&1 | tail -10
```

Expected: All pass

- [ ] **Step 6: 커밋**

```bash
git add ClaudeProfileManager/Sources/Backend/ ClaudeProfileManager/Tests/Backend/ ClaudeProfileManager/Tests/Helpers/
git commit -m "feat: add CredentialBackend protocol + KeychainBackend implementation"
```

---

### Task 4: Core — SessionGuard + ClientIDResolver

**Files:**
- Create: `Sources/Core/SessionGuard.swift`
- Create: `Sources/Core/ClientIDResolver.swift`
- Create: `Tests/Core/SessionGuardTests.swift`
- Create: `Tests/Core/ClientIDResolverTests.swift`

- [ ] **Step 1: Write failing tests for SessionGuard**

Create `Tests/Core/SessionGuardTests.swift`:

```swift
import XCTest
@testable import ClaudeProfileManager

final class SessionGuardTests: XCTestCase {
    
    func testCheckReturnsProcessList() {
        let guard_ = SessionGuard()
        let sessions = guard_.findClaudeSessions()
        // May be 0 or more — just verify it doesn't crash
        XCTAssertTrue(sessions.count >= 0)
    }
    
    func testHasRunningSessions() {
        let guard_ = SessionGuard()
        // Boolean result, no crash
        let _ = guard_.hasRunningSessions
    }
    
    func testSessionCountType() {
        let guard_ = SessionGuard()
        let count = guard_.runningSessionCount
        XCTAssertTrue(count >= 0)
    }
}
```

- [ ] **Step 2: Write failing tests for ClientIDResolver**

Create `Tests/Core/ClientIDResolverTests.swift`:

```swift
import XCTest
@testable import ClaudeProfileManager

final class ClientIDResolverTests: XCTestCase {
    
    func testFallbackClientID() {
        let resolver = ClientIDResolver()
        let clientID = resolver.resolve()
        // Should always return something (at minimum the fallback)
        XCTAssertFalse(clientID.isEmpty)
    }
    
    func testFallbackIsValidUUID() {
        let fallback = ClientIDResolver.fallbackClientID
        XCTAssertNotNil(UUID(uuidString: fallback))
    }
    
    func testExtractFromInvalidPath() {
        let resolver = ClientIDResolver()
        let result = resolver.extractFromCLI(at: "/nonexistent/path")
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
swift test --filter "SessionGuardTests|ClientIDResolverTests" 2>&1 | tail -10
```

Expected: Compilation errors

- [ ] **Step 4: Implement SessionGuard**

Create `Sources/Core/SessionGuard.swift`:

```swift
import Foundation

final class SessionGuard {
    
    struct ClaudeSession {
        let pid: Int32
        let command: String
    }
    
    var hasRunningSessions: Bool {
        runningSessionCount > 0
    }
    
    var runningSessionCount: Int {
        findClaudeSessions().count
    }
    
    func findClaudeSessions() -> [ClaudeSession] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-fl", "claude"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2,
                  let pid = Int32(parts[0]) else { return nil }
            let command = String(parts[1])
            // Filter out ourselves and grep processes
            if command.contains("ClaudeProfileManager") { return nil }
            if command.contains("pgrep") { return nil }
            return ClaudeSession(pid: pid, command: command)
        }
    }
}
```

- [ ] **Step 5: Implement ClientIDResolver**

Create `Sources/Core/ClientIDResolver.swift`:

```swift
import Foundation

final class ClientIDResolver {
    
    static let fallbackClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    
    func resolve() -> String {
        if let cliPath = findCLIPath(),
           let extracted = extractFromCLI(at: cliPath) {
            if extracted != Self.fallbackClientID {
                print("[ClientIDResolver] Extracted client_id differs from fallback: \(extracted)")
            }
            return extracted
        }
        return Self.fallbackClientID
    }
    
    func extractFromCLI(at path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-oE", #"CLIENT_ID:"[0-9a-f-]{36}""#, path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        
        // Extract UUID from CLIENT_ID:"uuid"
        let pattern = #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range, in: output) else { return nil }
        
        return String(output[range])
    }
    
    private func findCLIPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        
        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else { return nil }
        
        // Resolve symlinks to find the actual cli.js
        // claude binary → npm global → @anthropic-ai/claude-code/cli.js
        let resolved = (output as NSString).resolvingSymlinksInPath
        let dir = (resolved as NSString).deletingLastPathComponent
        let npmBase = (dir as NSString).deletingLastPathComponent
        let cliJS = "\(npmBase)/lib/node_modules/@anthropic-ai/claude-code/cli.js"
        
        if FileManager.default.fileExists(atPath: cliJS) { return cliJS }
        return nil
    }
}
```

- [ ] **Step 6: Run tests**

```bash
swift test --filter "SessionGuardTests|ClientIDResolverTests" 2>&1 | tail -10
```

Expected: All pass

- [ ] **Step 7: 커밋**

```bash
git add ClaudeProfileManager/Sources/Core/SessionGuard.swift ClaudeProfileManager/Sources/Core/ClientIDResolver.swift
git add ClaudeProfileManager/Tests/Core/
git commit -m "feat: add SessionGuard (process detection) + ClientIDResolver (dynamic client_id)"
```

---

### Task 5: Core — ProfileManager

**Files:**
- Create: `Sources/Core/ProfileManager.swift`
- Create: `Tests/Core/ProfileManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/Core/ProfileManagerTests.swift`:

```swift
import XCTest
@testable import ClaudeProfileManager

final class ProfileManagerTests: XCTestCase {
    
    var tempDir: URL!
    var profilesDir: URL!
    var mockBackend: MockCredentialBackend!
    var manager: ProfileManager!
    
    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpm-test-\(UUID().uuidString)")
        profilesDir = tempDir.appendingPathComponent("profiles")
        try! FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        
        mockBackend = MockCredentialBackend()
        manager = ProfileManager(profilesDirectory: profilesDir, backend: mockBackend)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testListProfilesEmpty() throws {
        let profiles = try manager.listProfiles()
        XCTAssertTrue(profiles.isEmpty)
    }
    
    func testSaveAndListProfile() throws {
        // Create a profile directory with credentials + meta
        let profileDir = profilesDir.appendingPathComponent("test-account")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        
        let oauth = OAuthCredential(
            accessToken: "at", refreshToken: "rt", expiresAt: 9999999999999,
            scopes: ["user:inference"], subscriptionType: "max", rateLimitTier: "20x"
        )
        let wrapper = CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil)
        try JSONEncoder().encode(wrapper).write(to: profileDir.appendingPathComponent(".credentials.json"))
        
        let meta = ProfileMeta(
            subscriptionType: "max", rateLimitTier: "20x",
            email: "test@example.com", scopes: ["user:inference"], savedAt: Date()
        )
        try JSONEncoder().encode(meta).write(to: profileDir.appendingPathComponent("meta.json"))
        
        let profiles = try manager.listProfiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].id, "test-account")
        XCTAssertEqual(profiles[0].meta.email, "test@example.com")
    }
    
    func testIdentifyByRefreshToken() throws {
        // Setup profile
        let profileDir = profilesDir.appendingPathComponent("my-account")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        
        let oauth = OAuthCredential(
            accessToken: "at", refreshToken: "unique-rt-123", expiresAt: 9999999999999,
            scopes: [], subscriptionType: "max", rateLimitTier: "20x"
        )
        try JSONEncoder().encode(CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil))
            .write(to: profileDir.appendingPathComponent(".credentials.json"))
        try JSONEncoder().encode(ProfileMeta(
            subscriptionType: "max", rateLimitTier: "20x",
            email: "me@test.com", scopes: [], savedAt: Date()
        )).write(to: profileDir.appendingPathComponent("meta.json"))
        
        // Set active credential to same refreshToken
        mockBackend.stored = CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil)
        
        let identified = try manager.identifyActiveProfile()
        XCTAssertEqual(identified?.id, "my-account")
    }
    
    func testIdentifyByEmail() throws {
        let profileDir = profilesDir.appendingPathComponent("email-account")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        
        let savedOAuth = OAuthCredential(
            accessToken: "at", refreshToken: "old-rt", expiresAt: 9999999999999,
            scopes: [], subscriptionType: "pro", rateLimitTier: "default"
        )
        try JSONEncoder().encode(CredentialWrapper(claudeAiOauth: savedOAuth, mcpOAuth: nil))
            .write(to: profileDir.appendingPathComponent(".credentials.json"))
        try JSONEncoder().encode(ProfileMeta(
            subscriptionType: "pro", rateLimitTier: "default",
            email: "unique@test.com", scopes: [], savedAt: Date()
        )).write(to: profileDir.appendingPathComponent("meta.json"))
        
        // Active has different refreshToken but we know the email
        let activeOAuth = OAuthCredential(
            accessToken: "new-at", refreshToken: "new-rt-rotated", expiresAt: 9999999999999,
            scopes: [], subscriptionType: "pro", rateLimitTier: "default"
        )
        mockBackend.stored = CredentialWrapper(claudeAiOauth: activeOAuth, mcpOAuth: nil)
        
        let identified = try manager.identifyActiveProfile(activeEmail: "unique@test.com")
        XCTAssertEqual(identified?.id, "email-account")
    }
    
    func testSwitchProfile() throws {
        let profileDir = profilesDir.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        
        let oauth = OAuthCredential(
            accessToken: "target-at", refreshToken: "target-rt", expiresAt: 9999999999999,
            scopes: [], subscriptionType: "max", rateLimitTier: "20x"
        )
        try JSONEncoder().encode(CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil))
            .write(to: profileDir.appendingPathComponent(".credentials.json"))
        try JSONEncoder().encode(ProfileMeta(
            subscriptionType: "max", rateLimitTier: "20x",
            email: "t@test.com", scopes: [], savedAt: Date()
        )).write(to: profileDir.appendingPathComponent("meta.json"))
        
        // Set current active
        let currentOAuth = OAuthCredential(
            accessToken: "old", refreshToken: "old-rt", expiresAt: 1,
            scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        mockBackend.stored = CredentialWrapper(claudeAiOauth: currentOAuth, mcpOAuth: nil)
        
        try manager.switchTo(profileId: "target")
        
        // Verify new credential was written to backend
        XCTAssertEqual(mockBackend.stored?.claudeAiOauth.accessToken, "target-at")
        XCTAssertEqual(mockBackend.writeCallCount, 1)
        
        // Verify _previous backup was created
        let backupPath = profilesDir.appendingPathComponent("_previous/.credentials.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath.path))
    }
    
    func testDeleteProfile() throws {
        let profileDir = profilesDir.appendingPathComponent("to-delete")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        try "{}".data(using: .utf8)!.write(to: profileDir.appendingPathComponent(".credentials.json"))
        
        try manager.deleteProfile(id: "to-delete")
        XCTAssertFalse(FileManager.default.fileExists(atPath: profileDir.path))
    }
    
    func testCannotDeletePrevious() {
        XCTAssertThrowsError(try manager.deleteProfile(id: "_previous"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter ProfileManagerTests 2>&1 | tail -10
```

Expected: Compilation error

- [ ] **Step 3: Implement ProfileManager**

Create `Sources/Core/ProfileManager.swift`:

```swift
import Foundation

final class ProfileManager {
    
    let profilesDirectory: URL
    private let backend: CredentialBackend
    
    init(profilesDirectory: URL? = nil, backend: CredentialBackend? = nil) {
        self.profilesDirectory = profilesDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/profiles")
        self.backend = backend ?? KeychainBackend()
    }
    
    // MARK: - List
    
    func listProfiles() throws -> [Profile] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: profilesDirectory.path) else { return [] }
        
        let contents = try fm.contentsOfDirectory(atPath: profilesDirectory.path)
        return contents.compactMap { name -> Profile? in
            guard !name.hasPrefix("."), name != "_previous" else { return nil }
            let dir = profilesDirectory.appendingPathComponent(name)
            let credPath = dir.appendingPathComponent(".credentials.json")
            let metaPath = dir.appendingPathComponent("meta.json")
            
            guard fm.fileExists(atPath: credPath.path),
                  fm.fileExists(atPath: metaPath.path) else { return nil }
            
            do {
                let metaData = try Data(contentsOf: metaPath)
                let meta = try JSONDecoder.profileDecoder.decode(ProfileMeta.self, from: metaData)
                let credData = try Data(contentsOf: credPath)
                let cred = try JSONDecoder().decode(CredentialWrapper.self, from: credData)
                return Profile(id: name, meta: meta, credential: cred.claudeAiOauth)
            } catch {
                return nil
            }
        }.sorted { $0.id < $1.id }
    }
    
    // MARK: - Identify Active (3-stage chain)
    
    func identifyActiveProfile(activeEmail: String? = nil) throws -> Profile? {
        guard let active = try backend.read() else { return nil }
        let profiles = try listProfiles()
        
        // Stage 1: refreshToken match
        if let match = profiles.first(where: {
            $0.credential?.refreshToken == active.claudeAiOauth.refreshToken
        }) { return match }
        
        // Stage 2: email match
        if let email = activeEmail, !email.isEmpty,
           let match = profiles.first(where: { $0.meta.email == email }) {
            return match
        }
        
        // Stage 3: subscriptionType + rateLimitTier fallback
        let activeSub = active.claudeAiOauth.subscriptionType
        let activeTier = active.claudeAiOauth.rateLimitTier
        let fallbackMatches = profiles.filter {
            $0.credential?.subscriptionType == activeSub &&
            $0.credential?.rateLimitTier == activeTier
        }
        // Only use fallback if exactly 1 match (avoid ambiguity)
        if fallbackMatches.count == 1 { return fallbackMatches[0] }
        
        return nil
    }
    
    // MARK: - Switch
    
    func switchTo(profileId: String) throws {
        let profileDir = profilesDirectory.appendingPathComponent(profileId)
        let credPath = profileDir.appendingPathComponent(".credentials.json")
        
        guard FileManager.default.fileExists(atPath: credPath.path) else {
            throw ProfileError.profileNotFound(profileId)
        }
        
        // Backup current to _previous
        if let current = try backend.read() {
            let backupDir = profilesDirectory.appendingPathComponent("_previous")
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let backupData = try JSONEncoder().encode(current)
            try backupData.write(to: backupDir.appendingPathComponent(".credentials.json"))
        }
        
        // Load target and write to Keychain
        let data = try Data(contentsOf: credPath)
        let wrapper = try JSONDecoder().decode(CredentialWrapper.self, from: data)
        try backend.write(wrapper)
        
        // Log switch
        appendSwitchLog(toProfile: profileId)
    }
    
    // MARK: - Save Current
    
    func saveCurrent(as name: String, email: String) throws {
        guard let current = try backend.read() else {
            throw ProfileError.noActiveCredential
        }
        
        let profileDir = profilesDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        
        // Save credentials
        let credData = try JSONEncoder().encode(current)
        let credPath = profileDir.appendingPathComponent(".credentials.json")
        try credData.write(to: credPath)
        
        // Set file permissions to 600
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: credPath.path
        )
        
        // Save meta
        let meta = ProfileMeta(
            subscriptionType: current.claudeAiOauth.subscriptionType ?? "unknown",
            rateLimitTier: current.claudeAiOauth.rateLimitTier ?? "unknown",
            email: email,
            scopes: current.claudeAiOauth.scopes,
            savedAt: Date()
        )
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: profileDir.appendingPathComponent("meta.json"))
    }
    
    // MARK: - Delete
    
    func deleteProfile(id: String) throws {
        guard id != "_previous" else {
            throw ProfileError.cannotDeleteBackup
        }
        let dir = profilesDirectory.appendingPathComponent(id)
        try FileManager.default.removeItem(at: dir)
    }
    
    // MARK: - Switch Log
    
    private func appendSwitchLog(toProfile: String) {
        let logPath = profilesDirectory.appendingPathComponent("switch_log.json")
        var entries: [SwitchLogEntry] = []
        
        if let data = try? Data(contentsOf: logPath),
           let existing = try? JSONDecoder().decode([SwitchLogEntry].self, from: data) {
            entries = existing
        }
        
        entries.append(SwitchLogEntry(
            timestamp: Date(), fromProfile: nil, toProfile: toProfile
        ))
        
        // Keep last 1000 entries
        if entries.count > 1000 { entries = Array(entries.suffix(1000)) }
        
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: logPath)
        }
    }
}

enum ProfileError: LocalizedError {
    case profileNotFound(String)
    case noActiveCredential
    case cannotDeleteBackup
    
    var errorDescription: String? {
        switch self {
        case .profileNotFound(let id): return "Profile '\(id)' not found"
        case .noActiveCredential: return "No active credential in Keychain"
        case .cannotDeleteBackup: return "'_previous' is an auto-backup and cannot be deleted"
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter ProfileManagerTests 2>&1 | tail -20
```

Expected: All pass

- [ ] **Step 5: 커밋**

```bash
git add ClaudeProfileManager/Sources/Core/ProfileManager.swift ClaudeProfileManager/Tests/Core/ProfileManagerTests.swift
git commit -m "feat: add ProfileManager with 3-stage identification + switch + save + delete"
```

---

### Task 6: Core — TokenKeeper

**Files:**
- Create: `Sources/Core/TokenKeeper.swift`
- Create: `Tests/Core/TokenKeeperTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/Core/TokenKeeperTests.swift`:

```swift
import XCTest
@testable import ClaudeProfileManager

final class TokenKeeperTests: XCTestCase {
    
    func testBuildRefreshRequestBody() throws {
        let keeper = TokenKeeper(backend: MockCredentialBackend())
        let body = keeper.buildRefreshBody(
            refreshToken: "test-rt",
            clientID: "test-client-id",
            scopes: ["user:inference", "user:profile"]
        )
        
        let parsed = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertEqual(parsed["grant_type"] as? String, "refresh_token")
        XCTAssertEqual(parsed["refresh_token"] as? String, "test-rt")
        XCTAssertEqual(parsed["client_id"] as? String, "test-client-id")
        XCTAssertEqual(parsed["scope"] as? String, "user:inference user:profile")
    }
    
    func testParseRefreshResponse() throws {
        let keeper = TokenKeeper(backend: MockCredentialBackend())
        let responseJSON = """
        {
            "access_token": "new-at",
            "refresh_token": "new-rt",
            "expires_in": 21600,
            "scope": "user:inference user:profile"
        }
        """.data(using: .utf8)!
        
        let result = try keeper.parseRefreshResponse(responseJSON)
        XCTAssertEqual(result.accessToken, "new-at")
        XCTAssertEqual(result.refreshToken, "new-rt")
        XCTAssertEqual(result.expiresIn, 21600)
    }
    
    func testCheckProfileNeedsRefresh() {
        let expiringSoon = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: Int64(Date().timeIntervalSince1970 * 1000) + 2 * 3600 * 1000,
            scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        XCTAssertTrue(expiringSoon.isExpiringSoon(thresholdHours: 6))
        
        let fresh = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: Int64(Date().timeIntervalSince1970 * 1000) + 20 * 3600 * 1000,
            scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        XCTAssertFalse(fresh.isExpiringSoon(thresholdHours: 6))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter TokenKeeperTests 2>&1 | tail -10
```

- [ ] **Step 3: Implement TokenKeeper**

Create `Sources/Core/TokenKeeper.swift`:

```swift
import Foundation

final class TokenKeeper {
    
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let defaultScopes = [
        "user:inference", "user:profile", "user:sessions:claude_code",
        "user:mcp_servers", "user:file_upload"
    ]
    
    private let backend: CredentialBackend
    private let clientIDResolver: ClientIDResolver
    private var timer: DispatchSourceTimer?
    
    var onRefreshComplete: ((String, Result<Void, Error>) -> Void)?  // profileName, result
    
    init(backend: CredentialBackend, clientIDResolver: ClientIDResolver = ClientIDResolver()) {
        self.backend = backend
        self.clientIDResolver = clientIDResolver
    }
    
    // MARK: - Timer
    
    func startPeriodicRefresh(intervalHours: Double = 4) {
        let queue = DispatchQueue(label: "com.claude.tokenkeeper", qos: .utility)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(
            deadline: .now(),  // Run immediately on start
            repeating: intervalHours * 3600
        )
        timer?.setEventHandler { [weak self] in
            self?.checkAndRefreshAll()
        }
        timer?.resume()
    }
    
    func stopPeriodicRefresh() {
        timer?.cancel()
        timer = nil
    }
    
    // MARK: - Refresh Logic
    
    func checkAndRefreshAll() {
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/profiles")
        
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: profilesDir.path) else { return }
        
        for name in contents where !name.hasPrefix(".") && name != "_previous" {
            let credPath = profilesDir.appendingPathComponent(name).appendingPathComponent(".credentials.json")
            guard let data = try? Data(contentsOf: credPath),
                  var wrapper = try? JSONDecoder().decode(CredentialWrapper.self, from: data) else { continue }
            
            if wrapper.claudeAiOauth.isExpiringSoon(thresholdHours: 6) {
                refreshProfile(name: name, wrapper: &wrapper, credPath: credPath)
            }
        }
    }
    
    func refreshProfile(name: String, wrapper: inout CredentialWrapper, credPath: URL) {
        let clientID = clientIDResolver.resolve()
        let scopes = wrapper.claudeAiOauth.scopes.isEmpty
            ? Self.defaultScopes
            : wrapper.claudeAiOauth.scopes
        
        let body = buildRefreshBody(
            refreshToken: wrapper.claudeAiOauth.refreshToken,
            clientID: clientID,
            scopes: scopes
        )
        
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.1.90", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        
        let semaphore = DispatchSemaphore(value: 0)
        var refreshError: Error?
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                refreshError = error
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                refreshError = TokenKeeperError.httpError(statusCode)
                return
            }
            
            do {
                let result = try self?.parseRefreshResponse(data)
                
                // Update credential
                wrapper.claudeAiOauth.accessToken = result?.accessToken ?? wrapper.claudeAiOauth.accessToken
                if let newRT = result?.refreshToken {
                    wrapper.claudeAiOauth.refreshToken = newRT
                }
                if let expiresIn = result?.expiresIn {
                    wrapper.claudeAiOauth.expiresAt = Int64(Date().timeIntervalSince1970 * 1000) + Int64(expiresIn) * 1000
                }
                
                // Save to file
                let encoded = try JSONEncoder().encode(wrapper)
                try encoded.write(to: credPath)
                
                // Update Keychain if this is the active profile
                self?.updateKeychainIfActive(wrapper: wrapper)
                
            } catch {
                refreshError = error
            }
        }.resume()
        
        semaphore.wait()
        
        let result: Result<Void, Error> = refreshError.map { .failure($0) } ?? .success(())
        onRefreshComplete?(name, result)
    }
    
    // MARK: - Request/Response
    
    func buildRefreshBody(refreshToken: String, clientID: String, scopes: [String]) -> Data {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": scopes.joined(separator: " "),
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }
    
    struct RefreshResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
    }
    
    func parseRefreshResponse(_ data: Data) throws -> RefreshResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let accessToken = json["access_token"] as? String else {
            throw TokenKeeperError.invalidResponse
        }
        return RefreshResponse(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: json["expires_in"] as? Int
        )
    }
    
    // MARK: - Keychain Sync
    
    private func updateKeychainIfActive(wrapper: CredentialWrapper) {
        guard let active = try? backend.read() else { return }
        
        let activeRT = active.claudeAiOauth.refreshToken
        let profileRT = wrapper.claudeAiOauth.refreshToken
        let activeSub = active.claudeAiOauth.subscriptionType
        let profileSub = wrapper.claudeAiOauth.subscriptionType
        let activeTier = active.claudeAiOauth.rateLimitTier
        let profileTier = wrapper.claudeAiOauth.rateLimitTier
        
        if activeRT == profileRT || (activeSub == profileSub && activeTier == profileTier) {
            try? backend.write(wrapper)
        }
    }
}

enum TokenKeeperError: LocalizedError {
    case httpError(Int)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Token refresh failed: HTTP \(code)"
        case .invalidResponse: return "Invalid token refresh response"
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TokenKeeperTests 2>&1 | tail -10
```

Expected: All pass

- [ ] **Step 5: 커밋**

```bash
git add ClaudeProfileManager/Sources/Core/TokenKeeper.swift ClaudeProfileManager/Tests/Core/TokenKeeperTests.swift
git commit -m "feat: add TokenKeeper with OAuth refresh + periodic timer"
```

---

### Task 7: Core — UsageTracker

**Files:**
- Create: `Sources/Core/UsageTracker.swift`
- Create: `Tests/Core/UsageTrackerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/Core/UsageTrackerTests.swift`:

```swift
import XCTest
@testable import ClaudeProfileManager

final class UsageTrackerTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpm-usage-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testParseStatsCache() throws {
        let statsJSON = """
        {
            "dailyModelTokens": [
                {"date": "2026-04-01", "tokensByModel": {"claude-opus-4-6": 5000, "claude-sonnet-4-6": 3000}},
                {"date": "2026-04-02", "tokensByModel": {"claude-opus-4-6": 8000}}
            ]
        }
        """.data(using: .utf8)!
        let statsPath = tempDir.appendingPathComponent("stats-cache.json")
        try statsJSON.write(to: statsPath)
        
        let tracker = UsageTracker(
            statsCachePath: statsPath,
            profilesDirectory: tempDir
        )
        let daily = try tracker.parseDailyUsage()
        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily[0].totalTokens, 8000)
        XCTAssertEqual(daily[1].totalTokens, 8000)
    }
    
    func testModelBreakdown() throws {
        let statsJSON = """
        {
            "dailyModelTokens": [
                {"date": "2026-04-02", "tokensByModel": {"claude-opus-4-6": 7200, "claude-sonnet-4-6": 2500, "claude-haiku-4-5": 300}}
            ]
        }
        """.data(using: .utf8)!
        let statsPath = tempDir.appendingPathComponent("stats-cache.json")
        try statsJSON.write(to: statsPath)
        
        let tracker = UsageTracker(statsCachePath: statsPath, profilesDirectory: tempDir)
        let breakdown = try tracker.modelBreakdown(forDate: "2026-04-02")
        
        XCTAssertEqual(breakdown["claude-opus-4-6"], 7200)
        XCTAssertEqual(breakdown["claude-sonnet-4-6"], 2500)
        XCTAssertEqual(breakdown["claude-haiku-4-5"], 300)
    }
    
    func testWeeklySummary() throws {
        // 7 days of data
        var entries: [[String: Any]] = []
        for i in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let dateStr = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: [.withFullDate])
            entries.append(["date": dateStr, "tokensByModel": ["claude-opus-4-6": 1000 * (i + 1)]])
        }
        
        let statsJSON = try JSONSerialization.data(withJSONObject: ["dailyModelTokens": entries])
        let statsPath = tempDir.appendingPathComponent("stats-cache.json")
        try statsJSON.write(to: statsPath)
        
        let tracker = UsageTracker(statsCachePath: statsPath, profilesDirectory: tempDir)
        let weekly = try tracker.weeklySummary()
        XCTAssertGreaterThan(weekly, 0)
    }
    
    func testMissingStatsFile() {
        let tracker = UsageTracker(
            statsCachePath: tempDir.appendingPathComponent("nonexistent.json"),
            profilesDirectory: tempDir
        )
        let daily = try? tracker.parseDailyUsage()
        XCTAssertNil(daily)
    }
}
```

- [ ] **Step 2: Implement UsageTracker**

Create `Sources/Core/UsageTracker.swift`:

```swift
import Foundation

final class UsageTracker {
    
    let statsCachePath: URL
    let profilesDirectory: URL
    
    init(
        statsCachePath: URL? = nil,
        profilesDirectory: URL? = nil
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.statsCachePath = statsCachePath ?? home.appendingPathComponent(".claude/stats-cache.json")
        self.profilesDirectory = profilesDirectory ?? home.appendingPathComponent(".claude/profiles")
    }
    
    // MARK: - Parse
    
    func parseDailyUsage() throws -> [DailyModelTokens] {
        let data = try Data(contentsOf: statsCachePath)
        let stats = try JSONDecoder().decode(StatsCache.self, from: data)
        return stats.dailyModelTokens
    }
    
    func modelBreakdown(forDate date: String) throws -> [String: Int] {
        let daily = try parseDailyUsage()
        return daily.first(where: { $0.date == date })?.tokensByModel ?? [:]
    }
    
    func todayUsage() throws -> Int {
        let today = Self.todayString()
        let daily = try parseDailyUsage()
        return daily.first(where: { $0.date == today })?.totalTokens ?? 0
    }
    
    func weeklySummary() throws -> Int {
        let daily = try parseDailyUsage()
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        
        return daily.filter { entry in
            guard let date = Self.parseDate(entry.date) else { return false }
            return date >= weekAgo
        }.reduce(0) { $0 + $1.totalTokens }
    }
    
    func monthlySummary() throws -> Int {
        let daily = try parseDailyUsage()
        let calendar = Calendar.current
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: Date())!
        
        return daily.filter { entry in
            guard let date = Self.parseDate(entry.date) else { return false }
            return date >= monthAgo
        }.reduce(0) { $0 + $1.totalTokens }
    }
    
    // MARK: - Helpers
    
    static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter UsageTrackerTests 2>&1 | tail -10
```

Expected: All pass

- [ ] **Step 4: 커밋**

```bash
git add ClaudeProfileManager/Sources/Core/UsageTracker.swift ClaudeProfileManager/Tests/Core/UsageTrackerTests.swift
git commit -m "feat: add UsageTracker with stats-cache parsing + daily/weekly/monthly aggregation"
```

---

### Task 8: AppState + MenuBar

**Files:**
- Create: `Sources/App/AppState.swift`
- Modify: `Sources/App/ClaudeProfileManagerApp.swift`
- Create: `Sources/MenuBar/MenuBarController.swift`
- Create: `Sources/MenuBar/MenuBarView.swift`

- [ ] **Step 1: Implement AppState**

Create `Sources/App/AppState.swift`:

```swift
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var isLoading = true
    @Published var error: String?
    @Published var lastRefreshTime: Date?
    @Published var showOnboarding = false
    
    let profileManager: ProfileManager
    let tokenKeeper: TokenKeeper
    let usageTracker: UsageTracker
    let sessionGuard: SessionGuard
    
    private let backend: CredentialBackend
    
    init(backend: CredentialBackend? = nil) {
        let b = backend ?? KeychainBackend()
        self.backend = b
        self.profileManager = ProfileManager(backend: b)
        self.tokenKeeper = TokenKeeper(backend: b)
        self.usageTracker = UsageTracker()
        self.sessionGuard = SessionGuard()
    }
    
    func loadProfiles() {
        Task {
            do {
                let loaded = try profileManager.listProfiles()
                profiles = loaded
                
                if profiles.isEmpty {
                    // Check if Keychain has credentials but no profiles saved
                    if (try? backend.read()) != nil {
                        showOnboarding = true
                    }
                }
                
                activeProfile = try profileManager.identifyActiveProfile()
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    func switchProfile(to profileId: String) {
        Task {
            do {
                try profileManager.switchTo(profileId: profileId)
                activeProfile = profiles.first(where: { $0.id == profileId })
                loadProfiles()  // Refresh
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
    
    func balanceNow() {
        // Pick profile with lowest usage today
        guard profiles.count >= 2 else { return }
        
        // For now, pick the first non-active profile with valid token
        let candidates = profiles.filter {
            $0.id != activeProfile?.id && $0.credential?.isExpired != true
        }
        guard let best = candidates.first else { return }
        switchProfile(to: best.id)
    }
    
    func startTokenKeeper() {
        tokenKeeper.onRefreshComplete = { [weak self] name, result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.lastRefreshTime = Date()
                    self?.loadProfiles()
                case .failure(let error):
                    self?.error = "Token refresh failed for \(name): \(error.localizedDescription)"
                }
            }
        }
        tokenKeeper.startPeriodicRefresh()
    }
}
```

- [ ] **Step 2: Implement MenuBarView**

Create `Sources/MenuBar/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active profile header
            if let active = appState.activeProfile {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active: \(active.displayName)")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text(active.meta.subscriptionType)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                        if let cred = active.credential {
                            Text(tokenStatusText(cred))
                                .font(.caption)
                                .foregroundColor(tokenStatusColor(cred))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                Divider()
            }
            
            // Profile list
            ForEach(appState.profiles) { profile in
                Button(action: {
                    if profile.id != appState.activeProfile?.id {
                        if appState.sessionGuard.hasRunningSessions {
                            // Show warning inline
                            appState.switchProfile(to: profile.id)
                        } else {
                            appState.switchProfile(to: profile.id)
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: profile.id == appState.activeProfile?.id
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(profile.id == appState.activeProfile?.id ? .green : .secondary)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.id)
                                .font(.body)
                            HStack(spacing: 4) {
                                Text(profile.meta.subscriptionType)
                                    .font(.caption2)
                                if let cred = profile.credential {
                                    Text(tokenStatusText(cred))
                                        .font(.caption2)
                                        .foregroundColor(tokenStatusColor(cred))
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Actions
            Button(action: { appState.balanceNow() }) {
                Label("Balance Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .buttonStyle(.plain)
            
            Button(action: { openWindow(id: "dashboard") }) {
                Label("Open Dashboard", systemImage: "chart.bar")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .buttonStyle(.plain)
            
            Divider()
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Quit")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .buttonStyle(.plain)
        }
        .frame(width: 280)
        .padding(.vertical, 4)
    }
    
    private func tokenStatusText(_ cred: OAuthCredential) -> String {
        let hours = cred.remainingHours
        if hours <= 0 { return "Expired" }
        return String(format: "%.1fh", hours)
    }
    
    private func tokenStatusColor(_ cred: OAuthCredential) -> Color {
        let hours = cred.remainingHours
        if hours <= 0 { return .red }
        if hours <= 6 { return .orange }
        return .green
    }
}
```

- [ ] **Step 3: Update App entry point**

Modify `Sources/App/ClaudeProfileManagerApp.swift`:

```swift
import SwiftUI

@main
struct ClaudeProfileManagerApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra("Claude Profile Manager", systemImage: "person.2.circle") {
            MenuBarView(appState: appState)
        }
        .menuBarExtraStyle(.window)
        
        Window("Dashboard", id: "dashboard") {
            Text("Dashboard — coming in Task 9")
                .frame(minWidth: 600, minHeight: 400)
        }
    }
    
    init() {
        // Disable dock icon — menubar only
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
```

Note: `init()` 에서 `setActivationPolicy(.accessory)`는 `@main` 이전에 호출되므로, 실제로는 `applicationDidFinishLaunching`에서 호출해야 할 수 있음. 빌드 시 확인.

- [ ] **Step 4: 빌드 확인**

```bash
cd /Users/chojaeyong/RSQUARE/claude-multi-account/ClaudeProfileManager
xcodebuild build -scheme ClaudeProfileManager 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: 커밋**

```bash
git add ClaudeProfileManager/Sources/App/ ClaudeProfileManager/Sources/MenuBar/
git commit -m "feat: add AppState + MenuBar with profile list, switching, balance"
```

---

### Task 9: Dashboard Views

**Files:**
- Create: `Sources/Dashboard/DashboardView.swift`
- Create: `Sources/Dashboard/ProfileCardView.swift`
- Create: `Sources/Dashboard/UsageChartView.swift`
- Create: `Sources/Dashboard/ModelBreakdownView.swift`

- [ ] **Step 1: Implement ProfileCardView**

Create `Sources/Dashboard/ProfileCardView.swift`:

```swift
import SwiftUI

struct ProfileCardView: View {
    let profile: Profile
    let isActive: Bool
    let onSwitch: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.id)
                    .font(.headline)
                Spacer()
                if isActive {
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }
            
            if !profile.meta.email.isEmpty {
                Text(profile.meta.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text(profile.meta.subscriptionType.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)
                
                Text(profile.meta.rateLimitTier)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if let cred = profile.credential {
                HStack {
                    Circle()
                        .fill(tokenColor(cred))
                        .frame(width: 8, height: 8)
                    Text(String(format: "%.1fh remaining", cred.remainingHours))
                        .font(.caption)
                }
            }
            
            if !isActive {
                Button("Switch") { onSwitch() }
                    .font(.caption)
            }
        }
        .padding()
        .background(isActive ? Color.accentColor.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func tokenColor(_ cred: OAuthCredential) -> Color {
        if cred.isExpired { return .red }
        if cred.isExpiringSoon() { return .orange }
        return .green
    }
}
```

- [ ] **Step 2: Implement UsageChartView**

Create `Sources/Dashboard/UsageChartView.swift`:

```swift
import SwiftUI
import Charts

struct UsageChartView: View {
    let dailyUsage: [DailyModelTokens]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Daily Usage (Estimated)")
                .font(.headline)
            
            if dailyUsage.isEmpty {
                Text("No usage data yet")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(chartData, id: \.id) { entry in
                        BarMark(
                            x: .value("Date", entry.date),
                            y: .value("Tokens", entry.tokens)
                        )
                        .foregroundStyle(by: .value("Model", entry.model))
                    }
                }
                .chartForegroundStyleScale([
                    "Opus": Color.purple,
                    "Sonnet": Color.blue,
                    "Haiku": Color.gray,
                    "Other": Color.secondary,
                ])
                .frame(height: 200)
            }
        }
    }
    
    private var chartData: [ChartEntry] {
        // Last 30 days
        let recent = dailyUsage.suffix(30)
        return recent.flatMap { day in
            day.tokensByModel.map { model, tokens in
                ChartEntry(
                    date: day.date,
                    model: modelShortName(model),
                    tokens: tokens
                )
            }
        }
    }
    
    private func modelShortName(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return "Other"
    }
}

private struct ChartEntry: Identifiable {
    let id = UUID()
    let date: String
    let model: String
    let tokens: Int
}
```

- [ ] **Step 3: Implement ModelBreakdownView**

Create `Sources/Dashboard/ModelBreakdownView.swift`:

```swift
import SwiftUI
import Charts

struct ModelBreakdownView: View {
    let breakdown: [String: Int]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Model Breakdown")
                .font(.headline)
            
            if breakdown.isEmpty {
                Text("No data")
                    .foregroundColor(.secondary)
            } else {
                Chart(pieData, id: \.model) { entry in
                    SectorMark(
                        angle: .value("Tokens", entry.tokens),
                        innerRadius: .ratio(0.5)
                    )
                    .foregroundStyle(by: .value("Model", entry.model))
                }
                .chartForegroundStyleScale([
                    "Opus": Color.purple,
                    "Sonnet": Color.blue,
                    "Haiku": Color.gray,
                    "Other": Color.secondary,
                ])
                .frame(height: 150)
                
                // Legend with percentages
                ForEach(pieData, id: \.model) { entry in
                    HStack {
                        Circle().fill(modelColor(entry.model)).frame(width: 8, height: 8)
                        Text(entry.model)
                            .font(.caption)
                        Spacer()
                        Text("\(entry.percentage)%")
                            .font(.caption.monospacedDigit())
                        Text("(\(formatTokens(entry.tokens)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var pieData: [PieEntry] {
        let total = breakdown.values.reduce(0, +)
        guard total > 0 else { return [] }
        return breakdown.map { model, tokens in
            let shortName: String
            if model.contains("opus") { shortName = "Opus" }
            else if model.contains("sonnet") { shortName = "Sonnet" }
            else if model.contains("haiku") { shortName = "Haiku" }
            else { shortName = "Other" }
            return PieEntry(model: shortName, tokens: tokens, percentage: tokens * 100 / total)
        }.sorted { $0.tokens > $1.tokens }
    }
    
    private func modelColor(_ model: String) -> Color {
        switch model {
        case "Opus": return .purple
        case "Sonnet": return .blue
        case "Haiku": return .gray
        default: return .secondary
        }
    }
    
    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

private struct PieEntry {
    let model: String
    let tokens: Int
    let percentage: Int
}
```

- [ ] **Step 4: Implement DashboardView**

Create `Sources/Dashboard/DashboardView.swift`:

```swift
import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var dailyUsage: [DailyModelTokens] = []
    @State private var todayBreakdown: [String: Int] = [:]
    @State private var weeklyTotal = 0
    @State private var monthlyTotal = 0
    
    var body: some View {
        HSplitView {
            // Left: Profiles
            ScrollView {
                VStack(spacing: 8) {
                    Text("Profiles")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ForEach(appState.profiles) { profile in
                        ProfileCardView(
                            profile: profile,
                            isActive: profile.id == appState.activeProfile?.id,
                            onSwitch: { appState.switchProfile(to: profile.id) }
                        )
                    }
                }
                .padding()
            }
            .frame(minWidth: 200, maxWidth: 250)
            
            // Right: Charts
            ScrollView {
                VStack(spacing: 20) {
                    UsageChartView(dailyUsage: dailyUsage)
                    
                    HStack(alignment: .top, spacing: 20) {
                        ModelBreakdownView(breakdown: todayBreakdown)
                            .frame(maxWidth: .infinity)
                        
                        // Weekly/Monthly summary
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Summary")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("This Week")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatTokens(weeklyTotal))
                                    .font(.title2.bold().monospacedDigit())
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("This Month")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatTokens(monthlyTotal))
                                    .font(.title2.bold().monospacedDigit())
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Token Keeper status
                    if let lastRefresh = appState.lastRefreshTime {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Last refresh: \(lastRefresh, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .onAppear { loadData() }
    }
    
    private func loadData() {
        dailyUsage = (try? appState.usageTracker.parseDailyUsage()) ?? []
        todayBreakdown = (try? appState.usageTracker.modelBreakdown(
            forDate: UsageTracker.todayString()
        )) ?? [:]
        weeklyTotal = (try? appState.usageTracker.weeklySummary()) ?? 0
        monthlyTotal = (try? appState.usageTracker.monthlySummary()) ?? 0
    }
    
    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM tokens", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK tokens", Double(n) / 1_000) }
        return "\(n) tokens"
    }
}
```

- [ ] **Step 5: Update App entry to use DashboardView**

Modify `Sources/App/ClaudeProfileManagerApp.swift`:

```swift
import SwiftUI

@main
struct ClaudeProfileManagerApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra("Claude Profile Manager", systemImage: "person.2.circle") {
            MenuBarView(appState: appState)
        }
        .menuBarExtraStyle(.window)
        
        Window("Dashboard", id: "dashboard") {
            DashboardView(appState: appState)
        }
    }
    
    init() {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
```

- [ ] **Step 6: 빌드 확인**

```bash
swift build 2>&1 | tail -10
```

- [ ] **Step 7: 커밋**

```bash
git add ClaudeProfileManager/Sources/Dashboard/ ClaudeProfileManager/Sources/App/
git commit -m "feat: add Dashboard with profile cards, usage chart, model breakdown, summary"
```

---

### Task 10: Onboarding + App Polish

**Files:**
- Create: `Sources/Onboarding/OnboardingView.swift`
- Modify: `Sources/App/ClaudeProfileManagerApp.swift` (add onboarding trigger)

- [ ] **Step 1: Implement OnboardingView**

Create `Sources/Onboarding/OnboardingView.swift`:

```swift
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var keychainStatus: KeychainCheckStatus = .checking
    @State private var profileName = ""
    
    enum KeychainCheckStatus {
        case checking, success, failed
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("Welcome to Claude Profile Manager")
                .font(.title2.bold())
            
            Text("Manage multiple Claude Code accounts from your menu bar.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
            
            // Keychain status
            HStack {
                switch keychainStatus {
                case .checking:
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking Keychain access...")
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Keychain access granted")
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading) {
                        Text("Keychain access denied")
                        Text("When prompted by macOS, click 'Always Allow'")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if keychainStatus == .success {
                if appState.profiles.isEmpty {
                    VStack(spacing: 12) {
                        Text("Save your current account as the first profile:")
                            .font(.callout)
                        
                        TextField("Profile name (e.g. personal)", text: $profileName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                        
                        Button("Save Profile") {
                            saveFirstProfile()
                        }
                        .disabled(profileName.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("Found \(appState.profiles.count) existing profile(s):")
                            .font(.callout)
                        ForEach(appState.profiles) { p in
                            Text("  \(p.id) — \(p.meta.email)")
                                .font(.caption.monospaced())
                        }
                    }
                    
                    Button("Get Started") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            if keychainStatus == .failed {
                Button("Retry") {
                    checkKeychain()
                }
            }
        }
        .padding(40)
        .frame(width: 450)
        .onAppear { checkKeychain() }
    }
    
    private func checkKeychain() {
        keychainStatus = .checking
        let backend = KeychainBackend()
        do {
            _ = try backend.read()
            keychainStatus = .success
            appState.loadProfiles()
        } catch {
            keychainStatus = .failed
        }
    }
    
    private func saveFirstProfile() {
        Task {
            do {
                // Get email from claude auth status
                let email = getEmailFromCLI() ?? ""
                try appState.profileManager.saveCurrent(as: profileName, email: email)
                appState.loadProfiles()
                dismiss()
            } catch {
                appState.error = error.localizedDescription
            }
        }
    }
    
    private func getEmailFromCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "auth", "status", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["email"] as? String
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 2: Wire onboarding into App**

Modify `Sources/App/ClaudeProfileManagerApp.swift`:

```swift
import SwiftUI

@main
struct ClaudeProfileManagerApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra("Claude Profile Manager", systemImage: "person.2.circle") {
            MenuBarView(appState: appState)
                .onAppear {
                    if appState.isLoading {
                        appState.loadProfiles()
                        appState.startTokenKeeper()
                    }
                }
        }
        .menuBarExtraStyle(.window)
        
        Window("Dashboard", id: "dashboard") {
            DashboardView(appState: appState)
        }
        
        Window("Onboarding", id: "onboarding") {
            OnboardingView(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 450, height: 500)
    }
    
    init() {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
```

- [ ] **Step 3: 빌드 + 실행 테스트**

```bash
swift build 2>&1 | tail -10
```

- [ ] **Step 4: 커밋**

```bash
git add ClaudeProfileManager/Sources/
git commit -m "feat: add Onboarding flow + wire up App entry point with TokenKeeper"
```

---

### Task 11: GitHub Actions CI + README

**Files:**
- Create: `.github/workflows/build.yml`
- Modify: `README.md`

- [ ] **Step 1: Create CI workflow**

Create `.github/workflows/build.yml`:

```yaml
name: Build

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: |
          cd ClaudeProfileManager
          xcodebuild build -scheme ClaudeProfileManager -configuration Release 2>&1 | tail -20

      - name: Test
        run: |
          cd ClaudeProfileManager
          xcodebuild test -scheme ClaudeProfileManagerTests 2>&1 | tail -30

  release:
    needs: build
    runs-on: macos-14
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - uses: actions/checkout@v4

      - name: Build Release (Universal Binary)
        run: |
          cd ClaudeProfileManager
          xcodebuild archive \
            -scheme ClaudeProfileManager \
            -configuration Release \
            -archivePath build/ClaudeProfileManager.xcarchive \
            ONLY_ACTIVE_ARCH=NO

      - name: Package
        run: |
          cd ClaudeProfileManager/build/ClaudeProfileManager.xcarchive/Products/Applications
          zip -r ../../../../../ClaudeProfileManager-${GITHUB_REF_NAME}.zip "Claude Profile Manager.app"

      - name: Release
        uses: softprops/action-gh-release@v2
        with:
          files: ClaudeProfileManager-*.zip
```

- [ ] **Step 2: Update README**

Add app section to `README.md`:

```markdown
## macOS App (Claude Profile Manager)

메뉴바에서 Claude Code 계정을 관리하는 네이티브 macOS 앱.

### 설치

[GitHub Releases](https://github.com/wowoyong/claude-multi-account/releases)에서 최신 `.zip` 다운로드 → 압축 해제 → Applications에 드래그.

> **참고:** 첫 실행 시 macOS Gatekeeper 경고가 나타날 수 있습니다.
> System Settings → Privacy & Security → "Open Anyway" 클릭.

### 빌드 (개발자)

```bash
cd ClaudeProfileManager
swift build        # Debug
swift test         # Run tests
swift build -c release  # Release
```

### 기능
- 메뉴바에서 원클릭 계정 전환
- 토큰 잔여시간 실시간 표시
- 자동 토큰 갱신 (4시간 간격)
- 일별 사용량 차트 + 모델별 분석
- 주간/월간 사용량 요약
```

- [ ] **Step 3: 커밋**

```bash
git add .github/ README.md
git commit -m "feat: add GitHub Actions CI/CD + update README with app section"
```

---

### Task 12: Integration Test + Final Push

- [ ] **Step 1: 전체 테스트 실행**

```bash
cd /Users/chojaeyong/RSQUARE/claude-multi-account/ClaudeProfileManager
swift test 2>&1 | tail -30
```

Expected: All tests pass

- [ ] **Step 2: 릴리스 빌드 확인**

```bash
xcodebuild build -scheme ClaudeProfileManager -configuration Release 2>&1 | tail -10
```

Expected: Build complete

- [ ] **Step 3: git push**

```bash
cd /Users/chojaeyong/RSQUARE/claude-multi-account
git push origin main
```

- [ ] **Step 4: (선택) 첫 릴리스 태그**

```bash
git tag v0.1.0
git push origin v0.1.0
```

이렇게 하면 GitHub Actions가 자동으로 빌드 + Release 생성.
