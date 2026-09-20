#!/bin/bash

# 显示 Claude Code 的 5 小时 / 周窗口，以及 Codex Pro 的周窗口。
# 优先请求官方用量接口（含网页版 / App 用量），失败时回退：
# - claude_usage: 读取 statusline.sh 缓存的 rate_limits（~/.cache/sketchybar/claude_usage.json）
# Codex 只使用官方接口；本地 rollout 快照不包含 App / 网页端用量，不能作为可靠回退。

GREEN=0xff879aad
ORANGE=0xffc9a574
RED=0xffcc7d87
GREY=0xff565f89

CLAUDE_CACHE="$HOME/.cache/sketchybar/claude_usage.json"
USAGE_HELPER="$HOME/.config/scripts/sketchybar/helpers/usage_bars"
USAGE_HELPER_SRC="$USAGE_HELPER.swift"
USAGE_IMAGE_DIR="$HOME/.cache/sketchybar/usage_bars"

# 定时与 hook 可能同时到达；每个 provider 只允许一轮刷新。
case "$NAME" in claude_usage|codex_usage) ;; *) exit 0 ;; esac
mkdir -p "$USAGE_IMAGE_DIR"
LOCK="$USAGE_IMAGE_DIR/$NAME.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  lock_pid=$(cat "$LOCK/pid" 2>/dev/null)
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
    rm -f "$LOCK/pid"
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
echo $$ > "$LOCK/pid"
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null' EXIT

render_usage_bars() {
  [ -x "$USAGE_HELPER" ] && [ "$USAGE_HELPER_SRC" -ot "$USAGE_HELPER" ] || \
    swiftc -O "$USAGE_HELPER_SRC" -o "$USAGE_HELPER" >/dev/null 2>&1 || return 1
  mkdir -p "$USAGE_IMAGE_DIR"
  local mode="${5:-dual}"
  local image="$USAGE_IMAGE_DIR/${NAME}-v4-${mode}-${1}-${2}.png"
  if [ ! -s "$image" ] || [ "$USAGE_HELPER" -nt "$image" ]; then
    "$USAGE_HELPER" "$image.tmp" "$1" "$2" "$3" "$4" "$mode" || return 1
    mv "$image.tmp" "$image" || return 1
  fi
  printf '%s' "$image"
}

# jq 片段：把 epoch（秒/毫秒）或 ISO8601 统一成 epoch 秒；输出剩余百分比，窗口已重置则剩余视为 100
JQ_DEFS='
def epoch:
  if . == null then null
  elif type == "number" then (if . > 1e12 then . / 1000 else . end | floor)
  else (tostring | sub("\\.[0-9]+"; "") | sub("(\\+00:00|Z)$"; "Z") | fromdateiso8601)
  end;
def win($pct; $reset):
  ($reset | epoch) as $r
  | if $pct == null then "- -"
    elif $r != null and $r <= now then "100 \($r)"
    else "\([100 - $pct, 0] | max | round) \($r // "-")"
    end;
'

# 官方用量接口：网页版 / 桌面 App 的用量也会算进去（本地日志只覆盖 CLI）。
# 接口会限流（429）：成功结果缓存 3 分钟；失败后 5 分钟内不再请求，期间沿用 15 分钟内的上次成功结果。
API_CACHE_DIR="$HOME/.cache/sketchybar/usage_api"
age() { echo $(($(date +%s) - $(stat -f %m "$1" 2>/dev/null || echo 0))); }
fetch_api() {
  local cache="$API_CACHE_DIR/$1.json" fail="$API_CACHE_DIR/$1.fail" body
  mkdir -p "$API_CACHE_DIR"
  if [ -s "$cache" ] && [ "$(age "$cache")" -lt 180 ]; then
    cat "$cache"; return
  fi
  if [ -f "$fail" ] && [ "$(age "$fail")" -lt 300 ]; then
    [ -s "$cache" ] && [ "$(age "$cache")" -lt 900 ] && { cat "$cache"; return; }
    return 1
  fi
  fetch_api_request "$1" && { rm -f "$fail"; return; }
  touch "$fail"
  [ -s "$cache" ] && [ "$(age "$cache")" -lt 900 ] && { cat "$cache"; return; }
  return 1
}
fetch_api_request() {
  local cache="$API_CACHE_DIR/$1.json" body
  case "$1" in
    claude)
      local token
      token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty')
      [ -n "$token" ] || return 1
      body=$(curl -sf -m 8 https://api.anthropic.com/api/oauth/usage \
        -H "Authorization: Bearer $token" -H "anthropic-beta: oauth-2025-04-20") || return 1
      echo "$body" | jq -e '.seven_day' >/dev/null 2>&1 || return 1
      ;;
    codex)
      local auth="$HOME/.codex/auth.json"
      [ -f "$auth" ] || return 1
      body=$(curl -sf -m 8 https://chatgpt.com/backend-api/wham/usage \
        -H "Authorization: Bearer $(jq -r '.tokens.access_token' "$auth")" \
        -H "ChatGPT-Account-Id: $(jq -r '.tokens.account_id' "$auth")" \
        -H "User-Agent: codex_cli_rs") || return 1
      # Plus 把周窗口放在 secondary，Pro/prolite 放在 primary；按窗口长度识别。
      echo "$body" | jq -e '
        [.rate_limit.primary_window, .rate_limit.secondary_window]
        | map(select(. != null and (.limit_window_seconds // 0) >= 86400))
        | length > 0
      ' >/dev/null 2>&1 || return 1
      ;;
  esac
  printf '%s' "$body" > "$cache.tmp" && mv "$cache.tmp" "$cache"
  printf '%s' "$body"
}

case "$NAME" in
  claude_usage)
    # 接口结果和 statusline 缓存合并：多个 Claude Code 会话会写入各自（可能过时）的快照，接口又可能限流，
    # 只用其中一个来源数字会来回跳。同一窗口（resets_at 相差 < 2 分钟）内用量只增不减，取较大值；
    # 窗口不同时取 resets_at 更晚的（新窗口）。
    API=$(fetch_api claude) || API='{}'
    LOCAL='{}'; [ -f "$CLAUDE_CACHE" ] && LOCAL=$(cat "$CLAUDE_CACHE")
    DATA=$(jq -rn --argjson api "$API" --argjson loc "$LOCAL" "$JQ_DEFS"'
      def w($u; $r): if $u == null then null else {u: $u, r: ($r | epoch)} end;
      def pick($a; $b):
        if $a == null then $b elif $b == null then $a
        elif ($a.r // 0) - ($b.r // 0) > 120 then $a
        elif ($b.r // 0) - ($a.r // 0) > 120 then $b
        elif $a.u >= $b.u then $a else $b end;
      (pick(w($api.five_hour.utilization; $api.five_hour.resets_at);
            w($loc.rate_limits.five_hour.used_percentage; $loc.rate_limits.five_hour.resets_at))
        ) as $five
      | pick(w($api.seven_day.utilization; $api.seven_day.resets_at);
             w($loc.rate_limits.seven_day.used_percentage; $loc.rate_limits.seven_day.resets_at)) as $seven
      # 缺失数据保留未知，不能推断为额度充足。
      | if $seven == null then empty
        else "\(win($five.u; $five.r)) \(win($seven.u; $seven.r)) \(now | floor)" end
    ' 2>/dev/null)
    ;;
  codex_usage)
    # Pro 账户只在栏中显示周额度。Plus / Pro 的周窗口字段位置不同，按时长选择。
    # 官方接口不可用时显示未知，避免拿只覆盖本地 CLI 的 rollout 快照冒充完整用量。
    API=$(fetch_api codex) && DATA=$(echo "$API" | jq -r "$JQ_DEFS"'
      .rate_limit as $rl
      | [$rl.primary_window, $rl.secondary_window]
      | map(select(. != null and (.limit_window_seconds // 0) >= 86400))
      | if length == 0 then empty else max_by(.limit_window_seconds) as $week
        | "- - \(win($week.used_percent; $week.reset_at)) \(now | floor)" end
    ' 2>/dev/null)
    ;;
  *) exit 0 ;;
esac

# 常态灰蓝，剩余不足 20% 才提示，低于 10% 使用柔和红色。
color_for() {
  if ! [[ "$1" =~ ^[0-9]+$ ]]; then echo $GREY
  elif [ "$1" -lt 10 ]; then echo $RED
  elif [ "$1" -lt 20 ]; then echo $ORANGE
  else echo $GREEN; fi
}

if [ -z "$DATA" ]; then
  if [ "$NAME" = codex_usage ]; then
    sketchybar --set "$NAME" background.image="" \
      --set "$NAME.reset_5h" icon.drawing=off label="--" label.width=52 label.color=$GREY
  else
    sketchybar --set "$NAME" background.image="" \
      --set "$NAME.reset_5h" icon.drawing=on icon="--" icon.color=$GREY label="--" label.width=26 label.color=$GREY
  fi
  exit 0
fi

read -r FIVE_LEFT FIVE_RESET WEEK_LEFT WEEK_RESET UPDATED <<< "$DATA"
NOW=$(date +%s)

pct_num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo -1; }

compact_reset() {
  local reset="$1" seconds days hours minutes
  if ! [[ "$reset" =~ ^[0-9]+$ ]] || [ "$reset" -le "$NOW" ]; then echo "--"; return; fi
  seconds=$((reset - NOW))
  days=$((seconds / 86400))
  hours=$(((seconds % 86400) / 3600))
  minutes=$(((seconds % 3600) / 60))
  if [ "$days" -gt 0 ]; then echo "${days}d${hours}h"
  elif [ "$hours" -gt 0 ]; then echo "${hours}h${minutes}m"
  else echo "${minutes}m"; fi
}

FIVE_COLOR=$(color_for "$FIVE_LEFT")
WEEK_COLOR=$(color_for "$WEEK_LEFT")
MODE=dual
[ "$NAME" = codex_usage ] && MODE=week
BAR_IMAGE=$(render_usage_bars "$(pct_num "$FIVE_LEFT")" "$(pct_num "$WEEK_LEFT")" "$FIVE_COLOR" "$WEEK_COLOR" "$MODE")
[ -n "$BAR_IMAGE" ] || exit 0

if [ "$NAME" = codex_usage ]; then
  sketchybar --set "$NAME" background.image="$BAR_IMAGE" \
    --set "$NAME.reset_5h" icon.drawing=off label="$(compact_reset "$WEEK_RESET")" label.width=52 label.color=0xff9aa5ce
else
  sketchybar --set "$NAME" background.image="$BAR_IMAGE" \
    --set "$NAME.reset_5h" icon.drawing=on icon="$(compact_reset "$FIVE_RESET")" icon.color=0xff9aa5ce label="$(compact_reset "$WEEK_RESET")" label.width=26 label.color=0xff9aa5ce
fi
