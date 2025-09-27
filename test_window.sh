#!/usr/bin/env bash
set -Eeuo pipefail

VIDEO="${1:?用法: $0 /path/to/video.(mp4|mov|...) }"

# 可自定义 MPV_OPTS（环境变量），默认如下：
MPV_OPTS="${MPV_OPTS:-"--no-config --no-audio --loop-file=inf --hwdec=auto --no-osc --no-osd-bar --panscan=1 --keep-open=yes --cursor-autohide=no --no-border"}"
CHECK_INTERVAL="${CHECK_INTERVAL:-2}"

need_cmd() { command -v "$1" >/dev/null || { echo "缺少命令: $1"; exit 1; }; }
for c in xrandr wmctrl xprop xdotool awk sed grep ps; do need_cmd "$c"; done

log() { printf '[wallpaper] %s\n' "$*" >&2; }

kill_painter() {
  # 干掉负责“涂背景”的实例：包含 -C 且 -d org.deepin.ds.desktop
  local pids
  pids=$(ps -eo pid,cmd | awk '/\/usr\/bin\/dde-shell/ && /-d org.deepin.ds.desktop/ && /-C/ {print $1}')
  [ -z "${pids:-}" ] || { log "kill painter: $pids"; kill $pids || true; }
}

find_icon_window() {
  # 在 X 树里拿 org.deepin.dde-shell 这层桌面窗口（图标层）
  xwininfo -root -tree | awk '/"org.deepin.dde-shell"/ {print $1; exit}'
}

ensure_icon_window() {
  ICON=$(find_icon_window || true)
  [ -n "${ICON:-}" ] || return 1
  # 类型设为 NORMAL，放在“below”，但仍高于 DESKTOP 层（mpv）
  xprop -id "$ICON" -f _NET_WM_WINDOW_TYPE 32a -set _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_NORMAL >/dev/null 2>&1 || true
  wmctrl -i -r "$ICON" -b remove,above || true
  wmctrl -i -r "$ICON" -b add,below,sticky,skip_taskbar,skip_pager || true
  xdotool windowraise "$ICON" || true
}

collect_geometries() {
  # 从 xrandr --listmonitors 解析每个显示器的 WxH+X+Y（去掉毫米分母）
  mapfile -t MON_LINES < <(xrandr --listmonitors | tail -n +2)
  [ "${#MON_LINES[@]}" -gt 0 ] || { echo "未发现显示器"; exit 1; }
  MON_GEOS=()
  for line in "${MON_LINES[@]}"; do
    g=$(awk '{print $(NF-1)}' <<<"$line" | sed -E 's:/[0-9]+::g') # 2520/338x1680/226+0+0 -> 2520x1680+0+0
    MON_GEOS+=("$g")
  done
}

start_mpv_for_geometry() {
  local idx="$1" geo="$2"
  local title="mpv-wallpaper-$idx"
  log "启动 mpv $idx @ $geo"
  mpv --title="$title" $MPV_OPTS --geometry="$geo" "$VIDEO" >/dev/null 2>&1 &
  local id=""
  for i in {1..50}; do
    id=$(wmctrl -l | awk -v t="$title" '$0 ~ t {print $1; exit}')
    [ -n "$id" ] && break
    sleep 0.1
  done
  [ -n "$id" ] || { log "获取 $title 窗口失败"; return 1; }
  # 设为 DESKTOP 层并置底、隐藏任务栏/分页器
  xprop -id "$id" -f _NET_WM_WINDOW_TYPE 32a -set _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_DESKTOP >/dev/null 2>&1 || true
  wmctrl -i -r "$id" -b add,below,sticky,skip_taskbar,skip_pager || true
  xdotool windowlower "$id" || true
  echo "$id"
}

# 退出清理（只杀本脚本起的 mpv）
trap 'pkill -f "^mpv .* --title=mpv-wallpaper-" || true' EXIT

# 1) 干掉涂背景的 dde-shell
kill_painter

# 2) 收集显示器几何
collect_geometries

# 3) 每个显示器起一个 mpv
declare -a MPV_WINS=()
for i in "${!MON_GEOS[@]}"; do
  id=$(start_mpv_for_geometry "$i" "${MON_GEOS[$i]}") || true
  MPV_WINS[$i]="${id:-}"
done

# 4) 确保图标层存在并正确分层
ensure_icon_window || true

# 5) 守护：定期重申分层、重杀涂背景、重拉起 mpv
while :; do
  kill_painter
  ensure_icon_window || true

  for i in "${!MON_GEOS[@]}"; do
    id="${MPV_WINS[$i]}"
    if [ -z "$id" ] || ! xprop -id "$id" >/dev/null 2>&1; then
      id=$(start_mpv_for_geometry "$i" "${MON_GEOS[$i]}") || true
      MPV_WINS[$i]="$id"
    else
      # 重申属性，防止被 WM 改回
      xprop -id "$id" -f _NET_WM_WINDOW_TYPE 32a -set _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_DESKTOP >/dev/null 2>&1 || true
      wmctrl -i -r "$id" -b add,below,sticky,skip_taskbar,skip_pager || true
      xdotool windowlower "$id" || true
    fi
  done

  # 图标层放在 mpv 之上，但仍低于普通窗口
  [ -n "${ICON:-}" ] && xdotool windowraise "$ICON" || true

  sleep "$CHECK_INTERVAL"
done
