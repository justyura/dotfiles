#!/bin/bash

# 获取Things Today的第一个未完成任务
get_first_task() {
  osascript << 'END' 2>/dev/null
try
  tell application "Things3"
    set todayTodos to to dos of list "Today"
    repeat with aTodo in todayTodos
      if status of aTodo is open then
        set taskName to name of aTodo
        set taskId to id of aTodo
        return taskId & "|" & taskName
      end if
    end repeat
    return ""
  end tell
on error
  return ""
end try
END
}

# 从任务名提取预估时间（分钟）
extract_estimated_time() {
  local task_name="$1"
  # 匹配末尾的数字（如：写代码 25 → 25）
  if [[ "$task_name" =~ [[:space:]]([0-9]+)[[:space:]]*$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# 移除任务名中的时间数字
remove_time_from_name() {
  local task_name="$1"
  # 移除末尾的数字和空格
  echo "$task_name" | sed -E 's/[[:space:]]+[0-9]+[[:space:]]*$//'
}

# 获取Things Today未完成任务数
get_task_count() {
  osascript << 'END' 2>/dev/null
try
  tell application "Things3"
    set todayTodos to to dos of list "Today"
    set openCount to 0
    repeat with aTodo in todayTodos
      if status of aTodo is open then
        set openCount to openCount + 1
      end if
    end repeat
    return openCount
  end tell
on error
  return 0
end try
END
}

# 检查是否有活动的计时器（通过临时文件）
TIMER_STATE_FILE="/tmp/parkinson_timer_state"

# 获取任务信息
TASK_INFO=$(get_first_task)

if [ -z "$TASK_INFO" ]; then
  # 没有待办任务 - 提醒规划今天
  sketchybar --set things_task \
    label="✨ Time to shape today" \
    label.color=0xffffab40 \
    drawing=on \
    click_script="/opt/homebrew/bin/yabai -m space --focus 10 && open -a Things3"
  exit 0
fi

# 解析任务ID和名称
TASK_ID="${TASK_INFO%%|*}"
TASK_NAME="${TASK_INFO#*|}"

# 检查是否有活动计时器
if [ -f "$TIMER_STATE_FILE" ]; then
  # 读取计时器状态
  source "$TIMER_STATE_FILE"

  if [ -n "$RUNNING" ] && [ "$RUNNING" = "true" ]; then
    # 计时器运行中 - 不更新任务ID，使用计时器中保存的任务
    ELAPSED=$(($(date +%s) - START_TIME))

    # 检查是否有预估时间
    if [ -n "$ESTIMATED_MINUTES" ] && [ "$ESTIMATED_MINUTES" -gt 0 ]; then
      ESTIMATED_SECONDS=$((ESTIMATED_MINUTES * 60))

      if [ $ELAPSED -lt $ESTIMATED_SECONDS ]; then
        # 倒计时阶段
        REMAINING=$((ESTIMATED_SECONDS - ELAPSED))
        MINS=$((REMAINING / 60))
        SECS=$((REMAINING % 60))
        EST_MINS=$((ESTIMATED_SECONDS / 60))
        EST_SECS=$((ESTIMATED_SECONDS % 60))
        TIME_DISPLAY=$(printf "%02d:%02d / %02d:%02d" $MINS $SECS $EST_MINS $EST_SECS)

        sketchybar --set things_task \
          label="⏱ $DISPLAY_NAME • $TIME_DISPLAY" \
          label.color=0xffa6e3a1 \
          drawing=on
      else
        # 超时阶段 - 显示总时长 + 超时
        MINS=$((ELAPSED / 60))
        SECS=$((ELAPSED % 60))
        OVERTIME=$((ELAPSED - ESTIMATED_SECONDS))
        OVERTIME_MINS=$((OVERTIME / 60))
        OVERTIME_SECS=$((OVERTIME % 60))
        EST_MINS=$((ESTIMATED_SECONDS / 60))
        EST_SECS=$((ESTIMATED_SECONDS % 60))
        TIME_DISPLAY=$(printf "%02d:%02d / %02d:%02d +%02d:%02d" $MINS $SECS $EST_MINS $EST_SECS $OVERTIME_MINS $OVERTIME_SECS)

        sketchybar --set things_task \
          label="⏱ $DISPLAY_NAME • $TIME_DISPLAY" \
          label.color=0xffff6b6b \
          drawing=on
      fi
    else
      # 无预估时间 - 正常正计时
      MINS=$((ELAPSED / 60))
      SECS=$((ELAPSED % 60))
      TIME_DISPLAY=$(printf "%02d:%02d" $MINS $SECS)

      sketchybar --set things_task \
        label="⏱ $DISPLAY_NAME • $TIME_DISPLAY" \
        label.color=0xffcad3f5 \
        drawing=on
    fi
  else
    # 无计时器，显示任务名并保存任务ID
    echo "$TASK_ID" > /tmp/things_current_task_id
    sketchybar --set things_task \
      label="$TASK_NAME" \
      label.color=0xffffab40 \
      drawing=on
  fi
else
  # 无计时器，显示任务名并保存任务ID
  echo "$TASK_ID" > /tmp/things_current_task_id
  sketchybar --set things_task \
    label="$TASK_NAME" \
    label.color=0xffffab40 \
    drawing=on
fi
