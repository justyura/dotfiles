#!/bin/bash

# Things 写回队列的消费者：things_enqueue（things_lib.sh）排进 spool 的操作在这里串行执行。
# 清单弹窗和 bar 上的进度已经先按乐观结果渲染过，这里只负责把状态真正落到 Things；
# 队列清空后再用 Things 的真实数据刷新一次 bar 上的 x/y。
# 单实例：拿不到锁说明已有消费者在跑，它会顺带消费掉刚排进来的操作。

export LC_ALL=en_US.UTF-8
set -f  # id 列表靠分词展开，关掉通配符展开

source "$HOME/.config/scripts/things/things_lib.sh"

mkdir -p "$(dirname "$THINGS_SYNC_SPOOL")"
things_sync_unstale                                  # 上一个消费者被杀掉时清掉残留的锁
mkdir "$THINGS_SYNC_LOCK" 2>/dev/null || exit 0
echo $$ > "$THINGS_SYNC_LOCK/pid"                    # 供 things_sync_unstale 判断锁是否还活着
trap 'rm -rf "$THINGS_SYNC_LOCK" 2>/dev/null' EXIT

did=0
while [ -s "$THINGS_SYNC_SPOOL" ]; do
  # 原子取走当前这一批（取走后新排进来的操作留在 spool 里，下一轮循环继续消费）
  mv "$THINGS_SYNC_SPOOL" "$THINGS_SYNC_SPOOL.work" 2>/dev/null || break
  while IFS=$'\t' read -r op a b; do
    case "$op" in
      status) things_set_status "$a" $b ;;
      delete) things_delete $a ;;
      order)  things_reorder "$a" "$b" ;;
      archive) things_log_completed ;;
      *) continue ;;
    esac
    did=1
  done < "$THINGS_SYNC_SPOOL.work"
  rm -f "$THINGS_SYNC_SPOOL.work"
done

rm -rf "$THINGS_SYNC_LOCK" 2>/dev/null
trap - EXIT

# 放锁和判空之间又有新操作排进来：交给新一轮（此时锁已放，不会自己等自己）
[ -s "$THINGS_SYNC_SPOOL" ] && exec "$0"

# 队列清空：bar 上的项目进度换成 Things 里的真实值
[ "$did" -eq 1 ] && NAME=timeline SENDER=sync "$HOME/.config/scripts/sketchybar/day_timeline.sh" >/dev/null 2>&1
exit 0
