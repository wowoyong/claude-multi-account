#!/bin/bash
# token-keeper.sh — 모든 프로필의 OAuth 토큰을 자동 갱신
# 크론으로 주기적 실행: 매 4시간마다
#
# Claude Code 2.x OAuth refresh flow:
#   POST https://platform.claude.com/v1/oauth/token
#   Body (JSON): { grant_type, refresh_token, client_id, scope }
#
# Usage: ./token-keeper.sh [--check-only] [--profile <name>]

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PROFILES_DIR="$CLAUDE_DIR/profiles"
LOG_FILE="$PROFILES_DIR/.token-keeper.log"
KEYCHAIN_SERVICE="Claude Code-credentials"

# Claude Code OAuth 설정 (cli.js에서 추출)
TOKEN_URL="https://platform.claude.com/v1/oauth/token"
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"

CHECK_ONLY=false
TARGET_PROFILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=true; shift ;;
    --profile) shift; TARGET_PROFILE="${1:-}"; shift ;;
    *) shift ;;
  esac
done

# --- Keychain 헬퍼 ---

read_active_credentials() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null
}

write_active_credentials() {
  local json_data="$1"
  security delete-generic-password -s "$KEYCHAIN_SERVICE" 2>/dev/null || true
  security add-generic-password -s "$KEYCHAIN_SERVICE" -a "" -w "$json_data" 2>/dev/null
}

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- 토큰 만료 확인 ---

check_token_expiry() {
  local cred_file="$1"
  python3 -c "
import json, time, datetime

cred = json.load(open('$cred_file'))
oauth = cred.get('claudeAiOauth', {})
expires_ms = oauth.get('expiresAt', 0)
now_ms = time.time() * 1000
remaining_hours = (expires_ms - now_ms) / 1000 / 3600

status = 'ok'
if remaining_hours <= 0:
    status = 'expired'
elif remaining_hours <= 6:
    status = 'expiring_soon'

exp_dt = datetime.datetime.fromtimestamp(expires_ms / 1000)
print(f'{status}|{remaining_hours:.1f}|{exp_dt.isoformat()}')
" 2>/dev/null
}

check_token_expiry_from_json() {
  local json_data="$1"
  CRED_JSON="$json_data" python3 -c "
import json, time, datetime, os

cred = json.loads(os.environ['CRED_JSON'])
oauth = cred.get('claudeAiOauth', {})
expires_ms = oauth.get('expiresAt', 0)
now_ms = time.time() * 1000
remaining_hours = (expires_ms - now_ms) / 1000 / 3600

status = 'ok'
if remaining_hours <= 0:
    status = 'expired'
elif remaining_hours <= 6:
    status = 'expiring_soon'

exp_dt = datetime.datetime.fromtimestamp(expires_ms / 1000)
print(f'{status}|{remaining_hours:.1f}|{exp_dt.isoformat()}')
" 2>/dev/null
}

# --- OAuth 토큰 갱신 ---

refresh_profile_token() {
  local cred_file="$1"
  local profile_name="$2"

  CRED_FILE="$cred_file" TOKEN_URL="$TOKEN_URL" CLIENT_ID="$CLIENT_ID" python3 << 'PYEOF' 2>&1 || true
import json, urllib.request, time, os

cred_file = os.environ['CRED_FILE']
token_url = os.environ['TOKEN_URL']
client_id = os.environ['CLIENT_ID']

cred = json.load(open(cred_file))
oauth = cred.get('claudeAiOauth', {})
refresh_tok = oauth.get('refreshToken', '')
scopes = oauth.get('scopes', [])

if not refresh_tok:
    print('ERROR: no refresh token')
    exit(1)

# Claude Code 2.x OAuth: JSON body with client_id and scope
payload = json.dumps({
    'grant_type': 'refresh_token',
    'refresh_token': refresh_tok,
    'client_id': client_id,
    'scope': ' '.join(scopes) if scopes else 'user:inference user:profile user:sessions:claude_code'
}).encode()

req = urllib.request.Request(
    token_url,
    data=payload,
    headers={
        'Content-Type': 'application/json',
        'User-Agent': 'claude-code/2.1.90',
    },
    method='POST'
)

try:
    resp = urllib.request.urlopen(req, timeout=30)
    result = json.loads(resp.read())

    if 'access_token' in result:
        oauth['accessToken'] = result['access_token']
    if 'refresh_token' in result:
        oauth['refreshToken'] = result['refresh_token']
    if 'expires_in' in result:
        oauth['expiresAt'] = int(time.time() * 1000) + (result['expires_in'] * 1000)

    # subscriptionType, rateLimitTier 보존
    cred['claudeAiOauth'] = oauth
    json.dump(cred, open(cred_file, 'w'), indent=2)
    os.chmod(cred_file, 0o600)

    print('REFRESHED')

except urllib.error.HTTPError as e:
    body = e.read().decode() if e.fp else ''
    print(f'HTTP_ERROR:{e.code}:{body[:200]}')
except Exception as e:
    print(f'ERROR:{e}')
PYEOF
}

# --- 프로필별 처리 ---

process_profile() {
  local name="$1"
  local cred_file="$PROFILES_DIR/$name/.credentials.json"

  if [ ! -f "$cred_file" ]; then
    return
  fi

  local result
  result=$(check_token_expiry "$cred_file")
  local status=$(echo "$result" | cut -d'|' -f1)
  local hours=$(echo "$result" | cut -d'|' -f2)
  local expiry=$(echo "$result" | cut -d'|' -f3)

  case "$status" in
    ok)
      log "[$name] OK — ${hours}h remaining (expires $expiry)"
      ;;
    expiring_soon)
      log "[$name] EXPIRING SOON — ${hours}h remaining"
      if [ "$CHECK_ONLY" = false ]; then
        log "[$name] Refreshing token..."
        local refresh_result
        refresh_result=$(refresh_profile_token "$cred_file" "$name")
        log "[$name] Result: $refresh_result"

        if [ "$refresh_result" = "REFRESHED" ]; then
          update_active_if_current "$name" "$cred_file"
        fi
      fi
      ;;
    expired)
      log "[$name] EXPIRED — /login 필요"
      if [ "$CHECK_ONLY" = false ]; then
        log "[$name] Attempting refresh anyway..."
        local refresh_result
        refresh_result=$(refresh_profile_token "$cred_file" "$name")
        log "[$name] Result: $refresh_result"

        if [ "$refresh_result" = "REFRESHED" ]; then
          update_active_if_current "$name" "$cred_file"
        fi
      fi
      ;;
  esac
}

# 현재 활성 프로필이면 Keychain의 active credentials도 같이 업데이트
update_active_if_current() {
  local profile_name="$1"
  local profile_cred="$2"

  local active_json
  active_json=$(read_active_credentials)
  if [ -z "$active_json" ]; then
    return
  fi

  local is_match
  is_match=$(ACTIVE_JSON="$active_json" PROFILE_CRED="$profile_cred" python3 -c "
import json, os

active = json.loads(os.environ['ACTIVE_JSON'])
profile = json.load(open(os.environ['PROFILE_CRED']))

# refreshToken으로 매칭 (가장 정확)
active_rt = active.get('claudeAiOauth', {}).get('refreshToken', '')
profile_rt = profile.get('claudeAiOauth', {}).get('refreshToken', '')

# refreshToken이 갱신되었을 수 있으므로 subscriptionType+rateLimitTier로 fallback
active_sub = active.get('claudeAiOauth', {}).get('subscriptionType', '')
profile_sub = profile.get('claudeAiOauth', {}).get('subscriptionType', '')
active_tier = active.get('claudeAiOauth', {}).get('rateLimitTier', '')
profile_tier = profile.get('claudeAiOauth', {}).get('rateLimitTier', '')

if active_rt == profile_rt or (active_sub == profile_sub and active_tier == profile_tier):
    print('MATCH')
else:
    print('DIFFERENT')
" 2>/dev/null)

  if [ "$is_match" = "MATCH" ]; then
    local new_cred
    new_cred=$(cat "$profile_cred")
    write_active_credentials "$new_cred"
    log "[$profile_name] Keychain active credentials도 갱신됨"
  fi
}

# --- 메인 ---

main() {
  mkdir -p "$PROFILES_DIR"

  log "=== Token Keeper 실행 ==="

  # 활성 credentials (Keychain) 체크
  local active_json
  active_json=$(read_active_credentials)
  if [ -n "$active_json" ]; then
    log "[active] 현재 활성 토큰 확인..."
    local result
    result=$(check_token_expiry_from_json "$active_json")
    local status=$(echo "$result" | cut -d'|' -f1)
    local hours=$(echo "$result" | cut -d'|' -f2)
    log "[active] Status: $status (${hours}h remaining)"
  fi

  # 프로필별 처리
  if [ -n "$TARGET_PROFILE" ]; then
    process_profile "$TARGET_PROFILE"
  else
    for dir in "$PROFILES_DIR"/*/; do
      local name
      name=$(basename "$dir")
      [ "$name" = "_previous" ] && continue
      [ "$name" = "." ] && continue
      process_profile "$name"
    done
  fi

  log "=== Token Keeper 완료 ==="
}

main
