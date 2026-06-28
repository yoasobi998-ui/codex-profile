#!/usr/bin/env bash
set -euo pipefail
umask 077

COD_DIR="${CODEX_HOME:-$HOME/.codex}"
PROFILE_DIR="$COD_DIR/profiles"
CURRENT_LINK="$COD_DIR/current"
USAGE_ENDPOINT="${CODEX_USAGE_ENDPOINT:-https://chatgpt.com/backend-api/codex/usage}"

mkdir -p "$PROFILE_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}$1${NC}"; }
echo_warn() { echo -e "${YELLOW}$1${NC}"; }
echo_err() { echo -e "${RED}$1${NC}"; }

read_input() {
    local prompt="$1"
    local default="$2"
    echo -n "$prompt [$default]: " >/dev/tty
    read -r input </dev/tty || true
    echo "${input:-$default}"
}

read_password() {
    local prompt="$1"
    echo -n "$prompt: " >/dev/tty
    read -rs input </dev/tty || true
    echo >/dev/tty
    echo "$input"
}

json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

normalize_url() {
    local url="$1"
    [[ ! "$url" =~ ^https?:// ]] && url="https://$url"
    [[ "$url" != */v1 ]] && url="${url%/}/v1"
    echo "$url"
}

require_profile_name() {
    local command="$1"
    local name="${2:-}"
    if [ -z "$name" ]; then
        echo_err "用法: $command <profile_name>"
        exit 1
    fi
}

create_profile() {
    local name="${1:-}"
    require_profile_name "new" "$name"

    local target="$PROFILE_DIR/$name"
    mkdir -p "$target"

    echo_warn "=== 创建 Codex Profile: $name ==="

    local raw_url
    raw_url=$(read_input "API基础地址(不带/v1)" "http://localhost:3000")
    local base_url
    base_url=$(normalize_url "$raw_url")

    local api_key
    api_key=$(read_password "API Key")
    api_key=$(echo "$api_key" | tr -d '\r\n')

    local model
    model=$(read_input "模型" "gpt-5-codex")

    cat > "$target/config.toml" <<EOF_CONFIG
model = "$model"
model_provider = "custom"
model_reasoning_effort = "medium"
disable_response_storage = true

[model_providers.custom]
name = "custom"
base_url = "$base_url"
wire_api = "responses"
EOF_CONFIG

    cat > "$target/auth.json" <<EOF_AUTH
{
  "OPENAI_API_KEY": "$(json_escape "$api_key")"
}
EOF_AUTH

    echo_info "✅ profile 创建完成: $name"
}

use_profile() {
    local name="${1:-}"
    require_profile_name "use" "$name"

    local target="$PROFILE_DIR/$name"
    if [ ! -d "$target" ]; then
        echo_err "profile 不存在: $name"
        exit 1
    fi

    rm -rf "$COD_DIR/auth.json" "$COD_DIR/config.toml"
    ln -sfn "$target/auth.json" "$COD_DIR/auth.json"
    ln -sfn "$target/config.toml" "$COD_DIR/config.toml"
    ln -sfn "$target" "$CURRENT_LINK"

    echo_info "✅ 已切换 profile: $name"
}

save_profile() {
    local name="${1:-}"
    require_profile_name "save" "$name"

    local target="$PROFILE_DIR/$name"
    mkdir -p "$target"

    cp "$COD_DIR/auth.json" "$target/" 2>/dev/null || true
    cp "$COD_DIR/config.toml" "$target/" 2>/dev/null || true

    echo_info "✅ 已保存当前配置到: $name"
}

list_profiles() {
    echo "📦 profiles:"
    find "$PROFILE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort || echo "empty"
}

delete_profile() {
    local name="${1:-}"
    require_profile_name "delete" "$name"
    rm -rf "$PROFILE_DIR/$name"
    echo_info "🗑 deleted: $name"
}

show_current() {
    echo "📍 current profile:"
    if [ -L "$CURRENT_LINK" ]; then
        echo "→ $(readlink "$CURRENT_LINK")"
    else
        echo "no active profile"
    fi
}

extract_json_value() {
    local file="$1"
    local key="$2"
    python3 - "$file" "$key" <<'PY' 2>/dev/null || true
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception:
    sys.exit(0)
for key in sys.argv[2:]:
    if isinstance(data, dict) and key in data:
        value = data[key]
        if isinstance(value, str):
            print(value)
            sys.exit(0)
PY
}

usage_auth_header() {
    local auth_file="$1"
    if [ -n "${CODEX_USAGE_BEARER:-}" ]; then
        printf 'Authorization: Bearer %s' "$CODEX_USAGE_BEARER"
        return 0
    fi

    local token
    token=$(extract_json_value "$auth_file" "access_token" "chatgpt_access_token" "OPENAI_ACCESS_TOKEN")
    if [ -n "$token" ]; then
        printf 'Authorization: Bearer %s' "$token"
        return 0
    fi

    local session
    session=$(extract_json_value "$auth_file" "__Secure-next-auth.session-token" "session_token")
    if [ -n "$session" ]; then
        printf 'Cookie: __Secure-next-auth.session-token=%s' "$session"
        return 0
    fi

    return 1
}

format_epoch() {
    local epoch="${1:-}"
    [ -z "$epoch" ] && { echo "unknown"; return; }
    date -d "@$epoch" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$epoch"
}

print_rate_limits_json() {
    local input
    input=$(cat)
    JSON_INPUT="$input" python3 -c '
import json, os, time

def pct(v):
    return "unknown" if v is None else f"{float(v):.1f}% used / {max(0.0, 100.0-float(v)):.1f}% left"

def reset(w):
    if not isinstance(w, dict):
        return "unknown"
    ts = w.get("resets_at") or w.get("reset_at")
    if ts:
        return time.strftime("%Y-%m-%d %H:%M:%S %Z", time.localtime(float(ts)))
    if w.get("resets_in_seconds") is not None:
        return time.strftime("%Y-%m-%d %H:%M:%S %Z", time.localtime(time.time()+float(w["resets_in_seconds"])))
    return "unknown"

data = json.loads(os.environ.get("JSON_INPUT", "{}"))
rl = data.get("rate_limits") if isinstance(data.get("rate_limits"), dict) else data
primary = rl.get("primary") if isinstance(rl, dict) else None
secondary = rl.get("secondary") if isinstance(rl, dict) else None
monthly = None
items = []
if isinstance(rl, dict):
    items = rl.get("limits") or rl.get("named_limits") or []
for item in items:
    name = str(item.get("name") or item.get("limit_name") or item.get("limit_id") or "").lower()
    secs = item.get("limit_window_seconds") or item.get("window_seconds")
    mins = item.get("window_minutes")
    if "month" in name or secs == 2592000 or mins == 43200:
        monthly = item
        break
print("📊 Codex usage")
plan = (rl.get("plan_type") or data.get("plan_type") or "unknown") if isinstance(rl, dict) else "unknown"
primary_used = (primary or {}).get("used_percent")
secondary_used = (secondary or {}).get("used_percent")
print("Plan: {}".format(plan))
print("5h:     {} (resets: {})".format(pct(primary_used), reset(primary)))
print("1 week: {} (resets: {})".format(pct(secondary_used), reset(secondary)))
if monthly:
    print("1 month:{} (resets: {})".format(pct(monthly.get("used_percent")), reset(monthly)))
else:
    print("1 month: not reported by this Codex usage source")
'
}

latest_local_rate_limits() {
    local sessions_dir="$COD_DIR/sessions"
    [ -d "$sessions_dir" ] || return 1
    local latest
    latest=$(find "$sessions_dir" -type f -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
    [ -n "$latest" ] || return 1
    python3 - "$latest" <<'PY'
import json, sys
last = None
for line in open(sys.argv[1], encoding='utf-8'):
    try:
        obj = json.loads(line)
    except Exception:
        continue
    payload = obj.get('payload') or {}
    rl = payload.get('rate_limits')
    if rl:
        last = {'rate_limits': rl}
if last:
    print(json.dumps(last))
PY
}

show_usage() {
    local name="${1:-}"
    local profile_dir auth_file header response
    if [ -n "$name" ]; then
        profile_dir="$PROFILE_DIR/$name"
        [ -d "$profile_dir" ] || { echo_err "profile 不存在: $name"; exit 1; }
    elif [ -L "$CURRENT_LINK" ]; then
        profile_dir=$(readlink "$CURRENT_LINK")
    else
        profile_dir="$COD_DIR"
    fi
    auth_file="$profile_dir/auth.json"

    echo_warn "=== Codex usage (${name:-current}) ==="
    if [ -f "$auth_file" ] && header=$(usage_auth_header "$auth_file"); then
        if response=$(curl -fsS -H "$header" -H 'Accept: application/json' "$USAGE_ENDPOINT" 2>/dev/null); then
            printf '%s' "$response" | print_rate_limits_json
            return 0
        fi
        echo_warn "⚠️ usage endpoint 请求失败，改用本地 session 快照。"
    else
        echo_warn "⚠️ 未找到 ChatGPT access token/cookie；API Key profile 通常不能查询 ChatGPT 订阅额度，改用本地 session 快照。"
    fi

    if response=$(latest_local_rate_limits); then
        printf '%s' "$response" | print_rate_limits_json
    else
        echo_err "没有可用 usage 数据。请先运行 Codex 产生 session 日志，或设置 CODEX_USAGE_BEARER 后重试。"
        exit 1
    fi
}

case "${1:-}" in
    new) create_profile "${2:-}" ;;
    use) use_profile "${2:-}" ;;
    save) save_profile "${2:-}" ;;
    list) list_profiles ;;
    delete) delete_profile "${2:-}" ;;
    current) show_current ;;
    usage) show_usage "${2:-}" ;;
    *)
        echo "用法:"
        echo "  new <name>       创建新账号(profile)"
        echo "  use <name>       切换账号(软链接)"
        echo "  save <name>      保存当前配置"
        echo "  list             列出所有账号"
        echo "  delete <name>    删除账号"
        echo "  current          当前使用的profile"
        echo "  usage [name]     查看 Codex usage: 5h / 1 week / 1 month(如果接口返回)"
        ;;
esac
