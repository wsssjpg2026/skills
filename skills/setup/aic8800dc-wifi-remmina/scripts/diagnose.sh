#!/usr/bin/env bash
# ============================================================
# AIC8800DC 免驱无线网卡 + RDP 可达性 一键诊断
#
# 用法:
#   ./diagnose.sh                  # 只诊断网卡
#   ./diagnose.sh 192.168.3.102    # 附带诊断到该 IP 的 RDP 可达性
#
# 特点: 全程只读、不需要 root、每一项判定都直接给出下一步动作。
# ============================================================
set -uo pipefail

TARGET="${1:-}"

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_H=$'\033[1;34m'; C_R=$'\033[0m'
ok()   { printf '  %s[正常]%s %s\n' "$C_OK" "$C_R" "$1"; }
warn() { printf '  %s[注意]%s %s\n' "$C_WARN" "$C_R" "$1"; }
err()  { printf '  %s[问题]%s %s\n' "$C_ERR" "$C_R" "$1"; }
act()  { printf '         %s→ %s%s\n' "$C_H" "$1" "$C_R"; }
hdr()  { printf '\n%s=== %s ===%s\n' "$C_H" "$1" "$C_R"; }

# 找出由 aic8800_fdrv 驱动的网络接口（比按名字猜 wlx* 可靠）
find_aic_iface() {
  local d ifn drv
  for d in /sys/class/net/*; do
    [ -e "$d" ] || continue
    ifn="${d##*/}"
    drv="$(readlink -f "$d/device/driver" 2>/dev/null)"
    [ "${drv##*/}" = "aic8800_fdrv" ] && { printf '%s' "$ifn"; return 0; }
  done
  return 1
}

printf '%s\n' "AIC8800DC 网卡诊断  ($(date '+%F %T'))"

# ---------- 1. USB 设备处于哪个模式 ----------
hdr "1. USB 设备模式"
USB_LINE="$(lsusb 2>/dev/null | grep -i 'a69c' | head -1)"
if [ -z "$USB_LINE" ]; then
  err "没有找到 AIC 设备（VID a69c）"
  act "把网卡换个 USB 口重新插入；USB 3.0 口（蓝色）优先"
elif printf '%s' "$USB_LINE" | grep -q '5722\|5721\|572a'; then
  warn "设备停在 U 盘模式（出厂状态）"
  printf '         %s\n' "$USB_LINE"
  act "运行同目录的 switch-to-wifi.sh 切换到网卡模式"
  act "或：sudo eject /dev/aicudiskv2"
elif printf '%s' "$USB_LINE" | grep -q '88de\|88dd\|88dc\|8d80'; then
  ok "设备已处于网卡模式"
  printf '         %s\n' "$USB_LINE"
else
  warn "设备在线，但 PID 不在已知列表里"
  printf '         %s\n' "$USB_LINE"
  act "把上面这行 USB ID 记下来，可能是不在支持列表里的新型号"
fi

# ---------- 2. 驱动 ----------
hdr "2. 驱动与固件"
if lsmod 2>/dev/null | grep -q '^aic8800_fdrv'; then
  ok "模块 aic8800_fdrv 已加载 ($(lsmod | awk '/^aic8800_fdrv/{print "占用 " $2 " 字节, 被引用 " $3 " 次"}' | head -1))"
else
  err "aic8800_fdrv 未加载"
  if [ -d /lib/modules/"$(uname -r)"/updates/dkms ] && \
     ls /lib/modules/"$(uname -r)"/updates/dkms/aic*.ko* >/dev/null 2>&1; then
    act "模块已安装但没加载，试：sudo modprobe aic_load_fw && sudo modprobe aic8800_fdrv"
  else
    act "模块尚未安装，需要先跑驱动安装脚本（见 SKILL.md 第三步）"
  fi
fi

if lsmod 2>/dev/null | grep -q '^aic_load_fw'; then
  ok "依赖模块 aic_load_fw 已加载"
else
  warn "aic_load_fw 未加载（aic8800_fdrv 依赖它导出的 get_fw_path 符号）"
  act "必须先加载它：sudo modprobe aic_load_fw"
fi

DKMS="$(dkms status 2>/dev/null | grep -i aic | head -1)"
if [ -n "$DKMS" ]; then
  ok "DKMS: $DKMS"
else
  warn "DKMS 里没有 aic8800 记录（内核升级后不会自动重编译）"
fi

FW=/lib/firmware/aic8800DC
if [ -d "$FW" ]; then
  ok "固件目录存在: $FW ($(find "$FW" -type f | wc -l) 个文件)"
else
  err "固件目录缺失: $FW"
  act "驱动装好后会自动铺上；缺失时驱动会报 'No such file or directory'"
fi

# ---------- 3. 网络接口 ----------
hdr "3. 网络接口"
IFACE="$(find_aic_iface || true)"
if [ -n "$IFACE" ]; then
  ok "找到 AIC 网卡接口: $IFACE"
  STATE="$(nmcli -t -f GENERAL.STATE dev show "$IFACE" 2>/dev/null | cut -d: -f2)"
  CONN="$(nmcli -t -f GENERAL.CONNECTION dev show "$IFACE" 2>/dev/null | cut -d: -f2)"
  IP4="$(ip -4 -br addr show "$IFACE" 2>/dev/null | awk '{print $3}')"
  [ "$STATE" = "100 (connected)" ] && ok "已连接: $CONN" || warn "未连接 (状态: ${STATE:-未知})"
  [ -n "$IP4" ] && ok "IPv4 地址: $IP4" || act "没有 IP，用 nmcli con up '<SSID>' 连接"
  # 信号质量（只有连着才有意义）
  if command -v iw >/dev/null 2>&1 && [ "$STATE" = "100 (connected)" ]; then
    SIG="$(iw dev "$IFACE" link 2>/dev/null | awk '/signal:/{print $2" "$3}')"
    [ -n "$SIG" ] && printf '         信号: %s\n' "$SIG"
  fi
else
  err "没有找到由 aic8800_fdrv 驱动的网络接口"
  act "若上面第 1 项显示 U 盘模式，先切换模式；切换后等 5~10 秒再跑一次"
  act "若已是网卡模式，试：sudo modprobe aic_load_fw && sudo modprobe aic8800_fdrv"
fi

# 射频是否被软/硬屏蔽
if command -v rfkill >/dev/null 2>&1; then
  BLOCKED="$(rfkill list 2>/dev/null | grep -A2 -i 'phy' | grep -c 'yes')"
  if [ "${BLOCKED:-0}" -gt 0 ]; then
    err "有无线设备被 rfkill 屏蔽"
    act "解除：sudo rfkill unblock all"
  else
    ok "rfkill 未屏蔽无线设备"
  fi
fi

# ---------- 4. 默认路由（多网卡时最容易踩的坑）----------
hdr "4. 路由与出口"
DEF="$(ip route show default 2>/dev/null)"
if [ -n "$DEF" ]; then
  printf '%s\n' "$DEF" | sed 's/^/         /'
  N="$(printf '%s\n' "$DEF" | grep -c .)"
  [ "$N" -gt 1 ] && warn "有 $N 条默认路由（多网卡并存）。访问内网目标时确认走对网卡，见下。" \
                 || ok "只有一条默认路由"
else
  err "没有默认路由（可能没连上任何网络）"
fi

# ---------- 5. RDP 目标可达性（可选参数）----------
if [ -n "$TARGET" ]; then
  hdr "5. RDP 目标 $TARGET"

  if ping -c 2 -W 2 "$TARGET" >/dev/null 2>&1; then
    RTT="$(ping -c 2 -W 2 "$TARGET" 2>/dev/null | awk -F'/' '/rtt|round-trip/{print $5" ms"}')"
    TTL="$(ping -c 1 -W 2 "$TARGET" 2>/dev/null | awk -F'ttl=' '/ttl=/{print $2}' | cut -d' ' -f1)"
    ok "ICMP 可达（${RTT:-延迟未知}）"
    case "${TTL:-}" in
      12[0-8]) printf '         TTL=%s 提示这是一台 Windows 主机\n' "$TTL" ;;
      6[0-4])  printf '         TTL=%s 提示这是一台 Linux/Unix 主机\n' "$TTL" ;;
    esac
  else
    err "ICMP 不通"
    act "确认网卡连的是目标所在的网络；有些主机禁 ping，继续看 3389 端口"
  fi

  ROUTE="$(ip route get "$TARGET" 2>/dev/null | head -1)"
  [ -n "$ROUTE" ] && { printf '         出口: %s\n' "$ROUTE"; }

  if timeout 4 bash -c "echo > /dev/tcp/$TARGET/3389" 2>/dev/null; then
    ok "RDP 端口 3389 开放——目标已启用远程桌面，可以直接用 Remmina 连"
  else
    err "RDP 端口 3389 不通"
    act "目标机没开远程桌面、防火墙拦截、或网络不通（依次排查）"
    if timeout 3 bash -c "echo > /dev/tcp/$TARGET/445" 2>/dev/null; then
      warn "但 445 端口是通的——说明主机在线且网络可达，问题在远程桌面服务/防火墙"
    fi
  fi

  if command -v ss >/dev/null 2>&1; then
    LIVE="$(ss -tn 2>/dev/null | grep -c "$TARGET:3389")"
    [ "${LIVE:-0}" -gt 0 ] && ok "当前有 $LIVE 条活动的 RDP 连接" \
                           || printf '         当前没有活动的 RDP 连接（正常，未连接时就是没有）\n'
  fi
fi

printf '\n%s诊断结束。%s对照上面标 [问题]/[注意] 的项逐条处理。\n' "$C_H" "$C_R"
