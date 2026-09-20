#!/bin/bash

# 站立提醒与每日时间轴的可调参数
# 插件脚本每次运行都会重新读取本文件，修改后无需 reload sketchybar

STANDUP_WORK_MIN=45                              # 工作多久后提醒站立（分钟）
STANDUP_BREAK_MIN=5                              # 站立/休息时长（分钟）
STANDUP_IDLE_SEC=180                             # 无键鼠活动达到 3 分钟后暂停/相机校准
STANDUP_CAMERA=1                                 # 0=仅键鼠；1=空闲时用本机人形检测校准
STANDUP_CAMERA_INTERVAL=60                       # 空闲时两次短暂检测至少相隔多少秒
STANDUP_SOUND=/System/Library/Sounds/Glass.aiff  # 到点提示音（/System/Library/Sounds 下有更多可选）

DAY_START=07:00                                  # 时间轴起点（起床）
DAY_END=23:00                                    # 时间轴终点（结束）

FOCUS_HEATMAP_WEEKS=20                           # 悬停时间轴显示的专注热力图周数
FOCUS_LEVEL_HOURS="1 2 4"                        # 热力图颜色档位阈值（小时）：>0 / ≥1h / ≥2h / ≥4h

THINGS_NAV_TIMEOUT=30                            # alt+k 清单键盘模式无操作多少秒后自动退出（避免占用 j/k 等按键）
THINGS_PANEL_LINES=14                            # alt+k 清单固定显示多少行（高度固定，超出后滚动）
THINGS_PANEL_WIDTH_PERCENT=33                    # alt+k 清单宽度占当前屏幕宽度的百分比
