#!/usr/bin/env bash
# ============================================================
# 把 AIC 免驱网卡从「U 盘模式」切换到「网卡模式」
#
# 背景: 这类网卡插入后先以只读 U 盘身份枚举(a69c:5722)，
#       必须弹出(eject)才会重新枚举成真正的无线网卡(a69c:88de)。
#
# 本脚本优先走 udisks2 的 D-Bus 接口 —— 它经 polkit 授权，
# 普通用户即可执行，不需要 sudo、不需要加入 disk 组。
#
# 用法: ./switch-to-wifi.sh
# ============================================================
set -uo pipefail

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_H=$'\033[1;34m'; C_R=$'\033[0m'

show_usb() { lsusb 2>/dev/null | grep -i 'a69c' | head -1; }

echo "当前 USB 状态: $(show_usb || echo '(未找到 AIC 设备)')"

if ! lsusb 2>/dev/null | grep -qi 'a69c'; then
  printf '%s[中止]%s 没有找到 AIC 设备(VID a69c)。请先插好网卡。\n' "$C_ERR" "$C_R"
  exit 1
fi

if lsusb 2>/dev/null | grep -qi 'a69c:88'; then
  printf '%s[跳过]%s 设备已经是网卡模式，无需切换。\n' "$C_OK" "$C_R"
  exit 0
fi

# ---------- 方式一：udisks2（推荐，免 root）----------
DRIVE=""
if command -v gdbus >/dev/null 2>&1; then
  echo "正在通过 udisks2 查找虚拟光驱..."
  DRIVE="$(gdbus call --system --dest org.freedesktop.UDisks2 \
      --object-path /org/freedesktop/UDisks2 \
      --method org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null \
    | grep -oE '/org/freedesktop/UDisks2/drives/(AIC|aic)[A-Za-z0-9_]*' | head -1)"
fi

if [ -n "$DRIVE" ]; then
  echo "找到驱动器对象: $DRIVE"
  OUT="$(gdbus call --system --dest org.freedesktop.UDisks2 \
      --object-path "$DRIVE" \
      --method org.freedesktop.UDisks2.Drive.Eject '{}' 2>&1 | head -3)"

  # 关键的坑：这个调用经常会返回 "Error ejecting ..." 之类的报错，
  # 但设备其实已经完成切换了。所以不要看返回码，要看 USB ID。
  if printf '%s' "$OUT" | grep -qi 'error\|错误'; then
    printf '%s[提示]%s udisks2 返回了报错，但这很可能是假警报（见下）。\n' "$C_WARN" "$C_R"
    printf '         %s\n' "$OUT"
  fi
else
  printf '%s[注意]%s 没能定位到 udisks2 的驱动器对象。\n' "$C_WARN" "$C_R"
fi

# ---------- 等待重新枚举 ----------
echo "等待设备重新枚举..."
for _ in $(seq 1 15); do
  sleep 1
  lsusb 2>/dev/null | grep -qi 'a69c:88' && break
done

NEW="$(show_usb || true)"
echo "切换后 USB 状态: $NEW"

# ---------- 判定 ----------
if lsusb 2>/dev/null | grep -qi 'a69c:88'; then
  printf '\n%s[成功]%s 设备已进入网卡模式。\n' "$C_OK" "$C_R"
  printf '        等一下无线接口才会出现(通常 5~10 秒)，然后：\n'
  printf '          nmcli dev status\n'
  printf '          nmcli dev wifi list\n'
  printf '          nmcli dev wifi connect "SSID" password "密码"\n'
  exit 0
fi

# ---------- 方式二：eject（需要权限）----------
printf '\n%s[回退]%s udisks2 方式没成功，改试 eject 命令。\n' "$C_WARN" "$C_R"
NODE=""
for n in /dev/aicudisk*; do [ -e "$n" ] && { NODE="$n"; break; }; done
[ -z "$NODE" ] && for n in /dev/sd?; do
  [ -e "$n" ] && [ "$(lsblk -no MODEL "$n" 2>/dev/null | tr -d ' ')" = "AICflash" ] && { NODE="$n"; break; }
done

if [ -n "$NODE" ]; then
  echo "尝试弹出 $NODE ..."
  if eject "$NODE" 2>/dev/null; then
    printf '%s[成功]%s 已弹出 $NODE\n' "$C_OK" "$C_R"
  else
    printf '%s[失败]%s 权限不足。两种办法：\n' "$C_ERR" "$C_R"
    printf '         1) sudo eject %s\n' "$NODE"
    printf '         2) 在文件管理器里点那个 U 盘的「弹出」按钮（走图形界面授权）\n'
  fi
else
  printf '%s[失败]%s 找不到对应的块设备节点。\n' "$C_ERR" "$C_R"
  printf '         在文件管理器里点那个 U 盘的「弹出」按钮试试。\n'
fi

sleep 5
FINAL="$(show_usb || true)"
echo
echo "最终 USB 状态: $FINAL"
if lsusb 2>/dev/null | grep -qi 'a69c:88'; then
  printf '%s[成功]%s 设备已进入网卡模式。\n' "$C_OK" "$C_R"
else
  printf '%s[仍未切换]%s 拔下网卡重新插入，装好 udev 规则后会自动切换。\n' "$C_ERR" "$C_R"
  exit 1
fi
