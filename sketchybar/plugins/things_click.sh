#!/bin/bash

TIMER_STATE_FILE="/tmp/parkinson_timer_state"
TASK_ID_FILE="/tmp/things_current_task_id"
TIMER_LOG_DIR="$HOME/Library/Mobile Documents/27N4MQEA55~pro~writer/Documents/notes"
TIMER_LOG_FILE="$TIMER_LOG_DIR/$(date +%Y%m%d)_timetrack.txt"
TIMER_DATA_FILE="$TIMER_LOG_DIR/$(date +%Y%m%d)_timetrack.data"
FOCUS_TIME_FILE="/tmp/parkinson_focus_time"
BREAK_THRESHOLD=5400  # 90分钟 = 5400秒

# 确保日志目录存在
mkdir -p "$TIMER_LOG_DIR"

# 快速打开时间追踪（可从外部直接调用）
if [ "$1" = "--timetrack" ]; then
  if [ ! -f "$TIMER_LOG_FILE" ]; then
    echo "# 📊 Time Tracking - $(date +%Y年%-m月%-d日)" > "$TIMER_LOG_FILE"
    echo "" >> "$TIMER_LOG_FILE"
    echo "暂无记录" >> "$TIMER_LOG_FILE"
  fi
  open -a "iA Writer" "$TIMER_LOG_FILE"
  exit 0
fi

# 更新时间追踪文件（Markdown 表格格式）
update_timetrack_file() {
  local time="$1"
  local task_name="$2"
  local duration_min="$3"
  local estimated_min="$4"
  local status="$5"  # ✓ / ⏸ / ❌

  # 追加到数据文件（CSV格式）
  echo "$time|$task_name|$duration_min|$estimated_min|$status" >> "$TIMER_DATA_FILE"

  # 重新生成 Markdown 文件
  generate_markdown_report
}

# 生成 Markdown 报告
generate_markdown_report() {
  local today=$(date +%Y年%-m月%-d日)
  local temp_file="/tmp/timetrack_temp.txt"

  # 如果数据文件不存在，退出
  [ ! -f "$TIMER_DATA_FILE" ] && return

  # 开始生成 Markdown
  {
    echo "# 📊 Time Tracking - $today"
    echo ""
    echo "## 📈 Summary"
    echo ""

    # 统计数据：任务名、总时长、完成次数
    awk -F'|' '
    BEGIN {
      total_time = 0
      completed_count = 0
      paused_count = 0
      abandoned_count = 0
    }
    {
      task = $2
      duration = $3
      status = $5

      # 累加任务时间
      task_time[task] += duration
      task_count[task]++

      # 统计状态
      if (status == "✓") {
        completed_count++
        task_completed[task]++
      } else if (status == "⏸") {
        paused_count++
      } else if (status == "❌") {
        abandoned_count++
      }

      total_time += duration
    }
    END {
      # 打印表格头
      print "| 任务 | 总时长 | 完成次数 | 平均时长 |"
      print "|------|--------|----------|----------|"

      # 按总时长排序打印
      for (task in task_time) {
        total_min = task_time[task]
        hours = int(total_min / 60)
        mins = total_min % 60
        count = task_completed[task] + 0
        avg = (count > 0) ? int(total_min / task_count[task]) : 0

        # 格式化时间显示
        if (hours > 0) {
          time_str = hours "h " mins "min"
        } else {
          time_str = mins "min"
        }

        if (avg >= 60) {
          avg_str = int(avg/60) "h " (avg%60) "min"
        } else {
          avg_str = avg "min"
        }

        printf "| %s | %s | %d | %s |\n", task, time_str, count, avg_str
      }

      # 打印总结
      print ""
      total_hours = int(total_time / 60)
      total_mins = total_time % 60
      if (total_hours > 0) {
        printf "**今日总时长**: %dh %dmin", total_hours, total_mins
      } else {
        printf "**今日总时长**: %dmin", total_mins
      }
      printf "  |  **完成**: %d  |  **中断**: %d  |  **放弃**: %d\n", completed_count, paused_count, abandoned_count
    }
    ' "$TIMER_DATA_FILE"

    echo ""
    echo "## 📅 24小时活动热力图"
    echo ""
    echo "| 时间 | 活动分布 (每格=5min) |"
    echo "|------|---------------------|"

    # 生成24小时热力图（整合空闲检测）
    # 先获取当前时间（分钟数）
    CURRENT_MIN=$(date +%H:%M | awk -F: '{print $1 * 60 + $2}')

    # 检测今天的屏幕活动时段（Display on/off events）
    # 获取今天所有的屏幕开关事件，用空格分隔（而不是换行）
    DISPLAY_EVENTS=$(pmset -g log | grep "$(date +%Y-%m-%d)" | grep -E "Display is turned on|Display is turned off" | awk '{
      split($2, t, ":")
      min = t[1] * 60 + t[2]
      if ($0 ~ /turned on/) printf "%d:ON ", min
      else if ($0 ~ /turned off/) printf "%d:OFF ", min
    }')

    # 获取应用追踪数据文件路径
    APP_TRACK_FILE="$TIMER_LOG_DIR/$(date +%Y%m%d)_apptrack.data"

    # 将屏幕活动时段信息和空闲数据传递给AWK
    # 格式：空格分隔的 "分钟数:ON" 或 "分钟数:OFF"
    awk -F'|' -v current_min="$CURRENT_MIN" -v display_events="$DISPLAY_EVENTS" -v app_file="$APP_TRACK_FILE" '
    BEGIN {
      # 获取当前时间
      curr_min = current_min + 0

      # 读取应用追踪数据，标记空闲时间
      # 格式：HH:MM|应用名或IDLE|空闲秒数
      while ((getline line < app_file) > 0) {
        n_fields = split(line, fields, "|")
        if (n_fields >= 2) {
          split(fields[1], t, ":")
          time_min = t[1] * 60 + t[2]
          app_or_status = fields[2]
          idle_seconds = (n_fields >= 3) ? (fields[3] + 0) : 0

          # 如果是IDLE或空闲超过5分钟（300秒），标记为空闲
          if (app_or_status == "IDLE" || idle_seconds >= 300) {
            # 标记对应的5分钟块为空闲
            block_idx = int(time_min / 5)
            if (block_idx >= 0 && block_idx < 288) {
              is_idle[block_idx] = 1
            }
          }
        }
      }
      close(app_file)

      # 解析屏幕事件，建立活动时段
      n_events = split(display_events, events, " ")
      display_on = 0  # 假设一开始屏幕是关的

      # 为每个5分钟块标记屏幕状态
      for (i = 0; i < 288; i++) {
        display_status[i] = 0  # 默认屏幕关闭
      }

      # 遍历所有屏幕事件
      for (e = 1; e <= n_events; e++) {
        split(events[e], parts, ":")
        event_min = parts[1] + 0
        event_type = parts[2]

        if (event_type == "ON") {
          # 从这个时间点开始，屏幕是开着的
          for (i = int(event_min / 5); i < 288; i++) {
            display_status[i] = 1
          }
        } else if (event_type == "OFF") {
          # 从这个时间点开始，屏幕是关着的
          for (i = int(event_min / 5); i < 288; i++) {
            display_status[i] = 0
          }
        }
      }

      # 初始化所有时间块（整合空闲检测）
      for (i = 0; i < 288; i++) {
        time_min = i * 5

        # 未来时间标记为间隙
        if (time_min > curr_min) {
          blocks[i] = "⬜"
        } else if (is_idle[i] == 1) {
          # 检测到空闲（5分钟无操作）- 标记为离开
          blocks[i] = "⬛"
        } else if (display_status[i] == 1) {
          # 过去时间，屏幕开且有活动，标记为间隙
          blocks[i] = "⬜"
        } else {
          # 过去时间，屏幕关着，标记为离开
          blocks[i] = "⬛"
        }
      }

      first_task_min = 9999
      last_task_min = 0
      task_count = 0
    }
    {
      split($1, parts, "-")
      split(parts[1], start_t, ":")
      split(parts[2], end_t, ":")

      start_min = start_t[1] * 60 + start_t[2]
      end_min = end_t[1] * 60 + end_t[2]

      # 记录第一个和最后一个任务的时间
      if (start_min < first_task_min) first_task_min = start_min
      if (end_min > last_task_min) last_task_min = end_min

      # 存储任务信息
      task_count++
      tasks[task_count,"start"] = start_min
      tasks[task_count,"end"] = end_min
      tasks[task_count,"name"] = $2
    }
    END {
      # 覆盖实际任务时间（橙色工作/绿色休息）
      if (task_count > 0) {
        for (i = 1; i <= task_count; i++) {
          task_name = tasks[i,"name"]
          # 只有完全匹配"休息"或以"休息"开头时才算休息（避免误判如"休息时间不能够及时的渲染"）
          is_rest = (task_name == "休息" || task_name == "Rest" || task_name == "rest" || task_name ~ /^休息[0-9 　]/ || task_name ~ /^Rest[0-9 ]/ || task_name ~ /^rest[0-9 ]/)
          block_char = is_rest ? "🟩" : "🟧"

          for (m = tasks[i,"start"]; m < tasks[i,"end"]; m += 5) {
            idx = int(m / 5)
            if (idx >= 0 && idx < 288) {
              blocks[idx] = block_char
            }
          }
        }
      }

      # 输出热力图
      for (h = 0; h < 24; h++) {
        printf "| %02d:00 | ", h
        for (b = 0; b < 12; b++) {
          idx = h * 12 + b
          printf "%s", blocks[idx]
        }
        print " |"
      }
      print ""
      print "**图例**: 🟧工作 🟩休息 ⬜间隙 ⬛离开"
    }
    ' "$TIMER_DATA_FILE"

    echo ""
    echo "---"
    echo ""

    # 分析应用使用情况
    APP_TRACK_FILE="$TIMER_LOG_DIR/$(date +%Y%m%d)_apptrack.data"

    if [ -f "$APP_TRACK_FILE" ]; then
      echo "## 🎯 应用使用分析"
      echo ""

      # 分析：在间隙时间（有屏幕活动但无任务）使用的应用
      # 改进：区分任务过渡期和真正的分心时间
      awk -F'|' -v app_file="$APP_TRACK_FILE" -v task_file="$TIMER_DATA_FILE" '
      BEGIN {
        TRANSITION_BUFFER = 5  # 任务间过渡缓冲时间（分钟）

        # 读取所有任务时间段
        task_count = 0
        while ((getline < task_file) > 0) {
          split($1, parts, "-")
          split(parts[1], start_t, ":")
          split(parts[2], end_t, ":")

          start_min = start_t[1] * 60 + start_t[2]
          end_min = end_t[1] * 60 + end_t[2]

          task_count++
          task_end[task_count] = end_min

          # 标记任务时间段
          for (m = start_min; m < end_min; m++) {
            has_task[m] = 1
          }

          # 标记任务结束后的过渡缓冲期
          for (m = end_min; m < end_min + TRANSITION_BUFFER; m++) {
            in_transition[m] = 1
          }
        }
        close(task_file)

        # 读取应用使用记录
        while ((getline < app_file) > 0) {
          split($1, t, ":")
          time_min = t[1] * 60 + t[2]
          app_name = $2

          # 统计总使用次数
          app_total[app_name]++

          # 分类统计
          if (has_task[time_min]) {
            # 在任务时间内
            app_work[app_name]++
          } else if (in_transition[time_min]) {
            # 在任务过渡期（任务结束后5分钟内）
            app_transition[app_name]++
          } else {
            # 真正的间隙时间 - 可能是分心
            app_distraction[app_name]++
          }
        }
        close(app_file)

        # 输出分析结果
        print "### 📊 应用使用时段分类"
        print ""
        print "| 应用 | 工作中 | 过渡期 | 分心时 | 分心率 |"
        print "|------|--------|--------|--------|--------|"

        # 遍历所有应用
        for (app in app_total) {
          work_count = app_work[app] + 0
          trans_count = app_transition[app] + 0
          dist_count = app_distraction[app] + 0
          total = app_total[app]

          # 计算分心率（分心时间 / 总时间）
          distraction_rate = (total > 0) ? int((dist_count / total) * 100) : 0

          # 只显示使用过的应用
          if (total > 0) {
            printf "| %s | %d | %d | %d | %d%% |\n", app, work_count, trans_count, dist_count, distraction_rate
          }
        }

        print ""
        print "**说明**:"
        print "- **工作中**: 在记录任务时使用"
        print "- **过渡期**: 任务结束后" TRANSITION_BUFFER "分钟内使用（切换任务的正常间隔）"
        print "- **分心时**: 过渡期之后的长时间间隙中使用 ⚠️"
        print "- **分心率**: 分心时使用次数 / 总使用次数 × 100%"
        print ""

        # 额外显示高分心率应用
        print "### ⚠️ 高分心应用（分心率 > 50%）"
        print ""
        has_high_distraction = 0
        for (app in app_total) {
          dist_count = app_distraction[app] + 0
          total = app_total[app]
          distraction_rate = (total > 0) ? int((dist_count / total) * 100) : 0

          if (distraction_rate > 50 && dist_count >= 2) {
            if (!has_high_distraction) {
              print "| 应用 | 分心次数 | 分心率 |"
              print "|------|----------|--------|"
              has_high_distraction = 1
            }
            printf "| %s | %d次 | %d%% |\n", app, dist_count, distraction_rate
          }
        }

        if (!has_high_distraction) {
          print "*暂无高分心应用，做得很好！* ✨"
        }

        print ""
      }
      '

      echo "---"
      echo ""
    fi

    echo "## 📝 Detailed Log"
    echo ""
    echo "| 时间 | 任务 | 耗时 | 预估 | 状态 |"
    echo "|------|------|------|------|:----:|"

    # 打印详细记录
    awk -F'|' '{
      time = $1
      task = $2
      duration = $3
      estimated = $4
      status = $5

      # 格式化预估时间
      est_str = (estimated > 0) ? estimated "min" : "-"

      printf "| %s | %s | %dmin | %s | %s |\n", time, task, duration, est_str, status
    }' "$TIMER_DATA_FILE"

  } > "$temp_file"

  # 移动临时文件到目标位置
  mv "$temp_file" "$TIMER_LOG_FILE"
}

# 标记Things任务为完成
complete_things_task() {
  local task_id="$1"
  osascript << END 2>/dev/null
try
  tell application "Things3"
    set aTodo to to do id "$task_id"
    set status of aTodo to completed
  end tell
  return "success"
on error errMsg
  return "error: " & errMsg
end try
END
}

# 获取累计专注时间
get_focus_time() {
  if [ -f "$FOCUS_TIME_FILE" ]; then
    cat "$FOCUS_TIME_FILE"
  else
    echo "0"
  fi
}

# 保存累计专注时间
save_focus_time() {
  echo "$1" > "$FOCUS_TIME_FILE"
}

# 重置累计专注时间
reset_focus_time() {
  echo "0" > "$FOCUS_TIME_FILE"
}

# 检查是否需要休息并显示提示
check_break_reminder() {
  local task_duration="$1"
  local cumulative_time=$(get_focus_time)
  local new_cumulative=$((cumulative_time + task_duration))

  # 保存新的累计时间
  save_focus_time "$new_cumulative"

  # 检查是否超过阈值
  if [ $new_cumulative -ge $BREAK_THRESHOLD ]; then
    local cumulative_mins=$((new_cumulative / 60))

    # 计算建议休息时间（专注时间的1/3）
    local suggested_break_mins=$((cumulative_mins / 3))
    # 最少3分钟，最多20分钟
    if [ $suggested_break_mins -lt 3 ]; then
      suggested_break_mins=3
    elif [ $suggested_break_mins -gt 20 ]; then
      suggested_break_mins=20
    fi

    # 显示休息提示
    local choice=$(osascript << END
set options to {"☕️ 休息 ${suggested_break_mins} 分钟", "🧘 拉伸运动 ${suggested_break_mins} 分钟", "🎵 音乐放松 ${suggested_break_mins} 分钟", "💪 继续工作"}
set selectedOption to choose from list options with prompt "已专注 ${cumulative_mins} 分钟，建议休息一下：" default items {"☕️ 休息 ${suggested_break_mins} 分钟"}

if selectedOption is false then
  return "continue"
else
  return item 1 of selectedOption
end if
END
)

    case "$choice" in
      "☕️ 休息 ${suggested_break_mins} 分钟")
        start_break_timer $suggested_break_mins false
        reset_focus_time
        ;;
      "🧘 拉伸运动 ${suggested_break_mins} 分钟")
        start_break_timer $suggested_break_mins false
        reset_focus_time
        ;;
      "🎵 音乐放松 ${suggested_break_mins} 分钟")
        start_break_timer $suggested_break_mins true
        reset_focus_time
        ;;
      "💪 继续工作")
        # 继续累计，不重置
        ;;
    esac
  fi
}

# 启动休息计时器
start_break_timer() {
  local break_minutes="$1"
  local play_music="$2"
  local break_seconds=$((break_minutes * 60))

  # 创建休息状态
  cat > "$TIMER_STATE_FILE" << EOF
RUNNING=true
START_TIME=$(date +%s)
TASK_ID=""
TASK_NAME="休息时间"
DISPLAY_NAME="休息时间"
ESTIMATED_MINUTES="$break_minutes"
IS_BREAK=true
PLAY_MUSIC="$play_music"
EOF

  # 如果选择音乐放松，启动Apple Music
  if [ "$play_music" = "true" ]; then
    osascript << 'END' 2>/dev/null
try
  tell application "Music"
    -- 如果有"放松"播放列表，播放它；否则播放当前播放列表
    set playlistExists to false
    repeat with p in playlists
      if name of p is "放松" or name of p is "Chill" or name of p is "Relax" then
        play p
        set playlistExists to true
        exit repeat
      end if
    end repeat

    if not playlistExists then
      -- 如果没有找到放松播放列表，播放当前播放列表
      play
    end if

    -- 设置合适的音量
    set sound volume to 40
  end tell
end try
END

    # 显示音乐通知
    osascript -e "display notification \"休息 $break_minutes 分钟，享受音乐\" with title \"🎵 音乐放松\""
  else
    # 播放开始休息音效
    afplay /System/Library/Sounds/Tink.aiff &

    # 显示通知
    osascript -e "display notification \"休息 $break_minutes 分钟，放松一下\" with title \"☕️ 休息时间\""
  fi

  # 刷新显示
  sketchybar --trigger things_update
}

# 显示选项菜单
show_options_menu() {
  osascript << 'END'
set options to {"✓ 完成并继续", "⏸ 暂停（记录中断）", "❌ 放弃任务", "📊 查看时间追踪"}
set selectedOption to choose from list options with prompt "当前任务未完成，要：" default items {"✓ 完成并继续"}

if selectedOption is false then
  return "cancel"
else
  return item 1 of selectedOption
end if
END
}

# 打开今天的时间追踪文件
open_timetrack() {
  local timetrack_file="$TIMER_LOG_FILE"

  # 如果文件不存在，创建一个空文件
  if [ ! -f "$timetrack_file" ]; then
    echo "# 📊 Time Tracking - $(date +%Y年%-m月%-d日)" > "$timetrack_file"
    echo "" >> "$timetrack_file"
    echo "暂无记录" >> "$timetrack_file"
  fi

  # 打开 iA Writer 并打开文件
  open -a "iA Writer" "$timetrack_file"
}

# 处理完成任务
handle_complete() {
  local task_id="$1"
  local task_name="$2"
  local start_time="$3"

  local end_time=$(date +%s)
  local elapsed=$((end_time - start_time))
  local mins=$((elapsed / 60))
  local secs=$((elapsed % 60))

  # 格式化时间
  local start_time_str=$(date -r $start_time +"%H:%M")
  local end_time_str=$(date +"%H:%M")
  local time_range="$start_time_str-$end_time_str"

  # 记录到时间追踪文件（表格格式）
  local est_min=${ESTIMATED_MINUTES:-0}
  update_timetrack_file "$time_range" "$DISPLAY_NAME" "$mins" "$est_min" "✓"

  # 标记Things任务完成
  if [ -n "$task_id" ]; then
    complete_things_task "$task_id"
  fi

  # 清除计时器状态
  rm -f "$TIMER_STATE_FILE"

  # 显示完成通知
  osascript -e "display notification \"Task completed in $duration\" with title \"✨ Well Done!\""

  # 播放提示音
  afplay /System/Library/Sounds/Glass.aiff &

  # 检查是否需要休息提醒（已禁用）
  # check_break_reminder "$elapsed"

  # 刷新显示（获取下一个任务）
  sketchybar --trigger things_update
}

# 处理暂停任务
handle_pause() {
  local task_id="$1"
  local task_name="$2"
  local start_time="$3"

  local end_time=$(date +%s)
  local elapsed=$((end_time - start_time))
  local mins=$((elapsed / 60))
  local secs=$((elapsed % 60))

  # 格式化时间
  local start_time_str=$(date -r $start_time +"%H:%M")
  local end_time_str=$(date +"%H:%M")
  local time_range="$start_time_str-$end_time_str"

  # 记录到时间追踪文件（标记为中断）
  local est_min=${ESTIMATED_MINUTES:-0}
  update_timetrack_file "$time_range" "$DISPLAY_NAME" "$mins" "$est_min" "⏸"

  # 清除计时器状态（不标记Things完成）
  rm -f "$TIMER_STATE_FILE"

  # 显示通知
  osascript -e "display notification \"Task paused after $duration\" with title \"⏸ Task Paused\""

  # 播放提示音
  afplay /System/Library/Sounds/Tink.aiff &

  # 暂停/中断时重置累计专注时间
  reset_focus_time

  # 刷新显示
  sketchybar --trigger things_update
}

# 处理放弃任务
handle_abandon() {
  local task_id="$1"
  local task_name="$2"
  local start_time="$3"

  local end_time=$(date +%s)
  local elapsed=$((end_time - start_time))
  local mins=$((elapsed / 60))
  local secs=$((elapsed % 60))

  # 格式化时间
  local start_time_str=$(date -r $start_time +"%H:%M")
  local end_time_str=$(date +"%H:%M")
  local time_range="$start_time_str-$end_time_str"

  # 记录到时间追踪文件（标记为放弃）
  local est_min=${ESTIMATED_MINUTES:-0}
  update_timetrack_file "$time_range" "$DISPLAY_NAME" "$mins" "$est_min" "❌"

  # 标记Things任务完成（从列表中移除）
  if [ -n "$task_id" ]; then
    complete_things_task "$task_id"
  fi

  # 清除计时器状态
  rm -f "$TIMER_STATE_FILE"

  # 显示通知
  osascript -e "display notification \"Task abandoned\" with title \"❌ Task Abandoned\""

  # 放弃任务时重置累计专注时间
  reset_focus_time

  # 刷新显示（获取下一个任务）
  sketchybar --trigger things_update
}

# 主逻辑
# 检查是否是Option+点击（通过环境变量MODIFIER）
IS_OPTION_CLICK="$MODIFIER"

# 检查计时器状态
if [ -f "$TIMER_STATE_FILE" ]; then
  source "$TIMER_STATE_FILE"

  if [ -n "$RUNNING" ] && [ "$RUNNING" = "true" ]; then
    # 计时器运行中
    TASK_ID=$(cat "$TASK_ID_FILE" 2>/dev/null)

    # 检查是否是休息计时器
    if [ "$IS_BREAK" = "true" ]; then
      # 休息结束
      local end_time=$(date +%s)
      local elapsed=$((end_time - START_TIME))
      local mins=$((elapsed / 60))
      local secs=$((elapsed % 60))

      # 如果在播放音乐，暂停音乐
      if [ "$PLAY_MUSIC" = "true" ]; then
        osascript << 'END' 2>/dev/null
tell application "Music"
  pause
end tell
END
      fi

      # 清除计时器状态
      rm -f "$TIMER_STATE_FILE"

      # ===== 记录休息时间到timetrack.data =====
      local start_time_str=$(date -r $START_TIME +"%H:%M")
      local end_time_str=$(date +"%H:%M")
      local time_range="$start_time_str-$end_time_str"
      local est_min=${ESTIMATED_MINUTES:-0}

      # 调用 update_timetrack_file 记录休息
      update_timetrack_file "$time_range" "休息" "$mins" "$est_min" "✓"
      # =========================================

      # 显示休息结束通知
      osascript -e "display notification \"休息结束，准备好继续工作了吗？\" with title \"💪 休息完成\""
      afplay /System/Library/Sounds/Glass.aiff &

      # 刷新显示
      sketchybar --trigger things_update
      exit 0
    fi

    # 验证任务是否还存在
    if [ -n "$TASK_ID" ]; then
      TASK_EXISTS=$(osascript << END 2>/dev/null
try
  tell application "Things3"
    set aTodo to to do id "$TASK_ID"
    return "exists"
  end tell
on error
  return ""
end try
END
)

      # 如果任务不存在，清除计时器并提示
      if [ -z "$TASK_EXISTS" ]; then
        rm -f "$TIMER_STATE_FILE"
        rm -f "$TASK_ID_FILE"
        osascript -e 'display notification "The task has been deleted or completed elsewhere" with title "⚠️ Task Not Found"'
        /opt/homebrew/bin/yabai -m space --focus 10 && open -a Things3
        exit 0
      fi
    fi

    # 如果是Option+点击，显示菜单
    if [ "$IS_OPTION_CLICK" = "alt" ] || [ "$1" = "--menu" ]; then
      CHOICE=$(show_options_menu)

      case "$CHOICE" in
        "✓ 完成并继续")
          handle_complete "$TASK_ID" "$TASK_NAME" "$START_TIME"
          ;;
        "⏸ 暂停（记录中断）")
          handle_pause "$TASK_ID" "$TASK_NAME" "$START_TIME"
          ;;
        "❌ 放弃任务")
          handle_abandon "$TASK_ID" "$TASK_NAME" "$START_TIME"
          ;;
        "📊 查看时间追踪")
          open_timetrack
          ;;
        *)
          # 取消或关闭
          exit 0
          ;;
      esac
    else
      # 普通点击 = 完成任务
      handle_complete "$TASK_ID" "$TASK_NAME" "$START_TIME"
    fi

    exit 0
  fi
fi

# 无计时器或计时器未运行 - 点击表示开始任务
TASK_ID=$(cat "$TASK_ID_FILE" 2>/dev/null)

# 验证任务是否在 Today 列表中且未完成
TASK_INFO=$(osascript << END 2>/dev/null
try
  tell application "Things3"
    set todayList to list "Today"
    set todayTodos to to dos of todayList

    repeat with aTodo in todayTodos
      if status of aTodo is open and id of aTodo is "$TASK_ID" then
        return name of aTodo
      end if
    end repeat

    return ""
  end tell
on error
  return ""
end try
END
)

# 如果任务不在 Today 列表中或已完成，清除并提示添加新任务
if [ -z "$TASK_ID" ] || [ -z "$TASK_INFO" ]; then
  rm -f "$TASK_ID_FILE"
  osascript -e 'display notification "Please add tasks to Today list" with title "✨ No Tasks"'
  /opt/homebrew/bin/yabai -m space --focus 10 && open -a Things3
  exit 0
fi

TASK_NAME="$TASK_INFO"

# 提取预估时间（分钟）
ESTIMATED_MINUTES=""
if [[ "$TASK_NAME" =~ [[:space:]]([0-9]+)[[:space:]]*$ ]]; then
  ESTIMATED_MINUTES="${BASH_REMATCH[1]}"
fi

# 移除任务名中的时间数字，得到显示名称
DISPLAY_NAME=$(echo "$TASK_NAME" | sed -E 's/[[:space:]]+[0-9]+[[:space:]]*$//')

# 创建计时器状态
cat > "$TIMER_STATE_FILE" << EOF
RUNNING=true
START_TIME=$(date +%s)
TASK_ID="$TASK_ID"
TASK_NAME="$TASK_NAME"
DISPLAY_NAME="$DISPLAY_NAME"
ESTIMATED_MINUTES="$ESTIMATED_MINUTES"
EOF

# 确保任务ID被保存（防止被覆盖）
echo "$TASK_ID" > "$TASK_ID_FILE"

# 播放开始音效
afplay /System/Library/Sounds/Tink.aiff &

# 立即更新显示
sketchybar --trigger things_update
