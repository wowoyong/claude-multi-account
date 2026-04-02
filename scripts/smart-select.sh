#!/bin/bash
# smart-select.sh — 사용량 기반 프로필 자동 선택
# 세션 시작 시 호출되어 가장 여유 있는 계정의 credentials를 적용
#
# Claude Code 2.x: macOS Keychain "Claude Code-credentials"에서 활성 인증 관리
#
# Usage: ./smart-select.sh [--dry-run] [--json]

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PROFILES_DIR="$CLAUDE_DIR/profiles"
USAGE_DB="$PROFILES_DIR/.usage.json"
KEYCHAIN_SERVICE="Claude Code-credentials"

DRY_RUN=false
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --json) JSON_OUTPUT=true ;;
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

# --- 유틸리티 ---

log() {
  if [ "$JSON_OUTPUT" = false ]; then
    echo "$1"
  fi
}

error_exit() {
  echo "ERROR: $1" >&2
  exit 1
}

# --- 프로필 목록 수집 ---

get_profiles() {
  local profiles=()
  for dir in "$PROFILES_DIR"/*/; do
    local name
    name=$(basename "$dir")
    if [ "$name" != "_previous" ] && [ -f "$dir/.credentials.json" ]; then
      profiles+=("$name")
    fi
  done
  echo "${profiles[@]}"
}

# --- 사용량 DB 관리 ---

init_usage_db() {
  if [ ! -f "$USAGE_DB" ]; then
    echo '{}' > "$USAGE_DB"
  fi
}

get_today_usage() {
  python3 -c "
import json, datetime

today = datetime.date.today().isoformat()
stats_file = '$CLAUDE_DIR/stats-cache.json'

try:
    stats = json.load(open(stats_file))
    daily = stats.get('dailyModelTokens', [])

    total_today = 0
    for day in daily:
        if day.get('date') == today:
            for model, tokens in day.get('tokensByModel', {}).items():
                total_today += tokens
            break

    print(total_today)
except Exception:
    print(0)
" 2>/dev/null
}

record_usage() {
  local profile_name="$1"
  local tokens="$2"

  python3 -c "
import json, datetime

db_file = '$USAGE_DB'
today = datetime.date.today().isoformat()

try:
    db = json.load(open(db_file))
except Exception:
    db = {}

if '$profile_name' not in db:
    db['$profile_name'] = {'daily': {}, 'total': 0}

profile = db['$profile_name']
profile['daily'][today] = int('$tokens')
profile['total'] = sum(profile['daily'].values())
profile['lastUsed'] = datetime.datetime.now().isoformat()

json.dump(db, open(db_file, 'w'), indent=2)
" 2>/dev/null
}

# --- 최적 프로필 선택 ---

select_best_profile() {
  python3 -c "
import json, datetime, os

profiles_dir = '$PROFILES_DIR'
db_file = '$USAGE_DB'
today = datetime.date.today().isoformat()

try:
    db = json.load(open(db_file))
except Exception:
    db = {}

candidates = []
for name in os.listdir(profiles_dir):
    cred_path = os.path.join(profiles_dir, name, '.credentials.json')
    if name == '_previous' or name.startswith('.') or not os.path.isfile(cred_path):
        continue

    try:
        cred = json.load(open(cred_path))
        expires = cred.get('claudeAiOauth', {}).get('expiresAt', 0)
        import time
        is_expired = expires < time.time() * 1000
    except Exception:
        is_expired = True

    today_tokens = db.get(name, {}).get('daily', {}).get(today, 0)
    total_tokens = db.get(name, {}).get('total', 0)

    candidates.append({
        'name': name,
        'todayTokens': today_tokens,
        'totalTokens': total_tokens,
        'expired': is_expired
    })

valid = [c for c in candidates if not c['expired']]
if not valid:
    valid = candidates

if not valid:
    print('NONE')
else:
    valid.sort(key=lambda c: (c['todayTokens'], c['totalTokens']))
    best = valid[0]

    if '$JSON_OUTPUT' == 'true':
        print(json.dumps({
            'selected': best['name'],
            'reason': 'lowest_today_usage',
            'candidates': candidates
        }))
    else:
        print(best['name'])
" 2>/dev/null
}

# --- 현재 활성 프로필 식별 (Keychain 기반) ---

identify_current_profile() {
  local active_json
  active_json=$(read_active_credentials)
  if [ -z "$active_json" ]; then
    echo "unknown"
    return
  fi

  ACTIVE_JSON="$active_json" python3 -c "
import json, os

current = json.loads(os.environ['ACTIVE_JSON'])
current_token = current.get('claudeAiOauth', {}).get('refreshToken', '')
profiles_dir = '$PROFILES_DIR'

if not current_token:
    print('unknown')
    exit()

for name in sorted(os.listdir(profiles_dir)):
    cred_path = os.path.join(profiles_dir, name, '.credentials.json')
    if name == '_previous' or name.startswith('.') or not os.path.isfile(cred_path):
        continue
    try:
        profile = json.load(open(cred_path))
        profile_token = profile.get('claudeAiOauth', {}).get('refreshToken', '')
        if profile_token == current_token:
            print(name)
            exit()
    except Exception:
        continue

print('unknown')
" 2>/dev/null
}

# --- 메인 ---

main() {
  init_usage_db

  profiles=($(get_profiles))

  if [ ${#profiles[@]} -lt 2 ]; then
    log "프로필이 2개 미만입니다. 밸런싱할 수 없습니다."
    log "'/profile save <name>'으로 프로필을 등록하세요."
    exit 0
  fi

  current=$(identify_current_profile)
  if [ "$current" != "unknown" ]; then
    today_usage=$(get_today_usage)
    record_usage "$current" "$today_usage"
    log "현재 프로필: $current (오늘 ${today_usage} tokens)"
  fi

  best=$(select_best_profile)

  if [ "$best" = "NONE" ]; then
    log "사용 가능한 프로필이 없습니다."
    exit 1
  fi

  if [ "$best" = "$current" ]; then
    log "현재 프로필($current)이 최적입니다. 변경 없음."
    exit 0
  fi

  log "추천 프로필: $best (사용량 가장 적음)"

  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] 실제 전환하지 않음"
    exit 0
  fi

  # 현재 인증 백업
  BACKUP_DIR="$PROFILES_DIR/_previous"
  mkdir -p "$BACKUP_DIR"
  local current_json
  current_json=$(read_active_credentials)
  if [ -n "$current_json" ]; then
    echo "$current_json" > "$BACKUP_DIR/.credentials.json"
    chmod 600 "$BACKUP_DIR/.credentials.json"
  fi

  # 프로필 적용 (Keychain에 쓰기)
  local new_cred
  new_cred=$(cat "$PROFILES_DIR/$best/.credentials.json")
  write_active_credentials "$new_cred"

  log "전환 완료: $current → $best"
  log "NOTE: 새 세션에서 적용됩니다."
}

main
