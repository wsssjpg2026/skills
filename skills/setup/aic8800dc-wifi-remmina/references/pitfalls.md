# 踩坑记录：现象 → 根因 → 解法

按「你看到什么」组织，不按技术分类。每个坑都来自实际调试。

## 目录

- [A. 网卡模式切换](#a-网卡模式切换)
- [B. 驱动安装](#b-驱动安装)
- [C. 网络连接](#c-网络连接)
- [D. Remmina 远程桌面](#d-remmina-远程桌面)
- [E. 诊断方法本身的陷阱](#e-诊断方法本身的陷阱)

---

## A. 网卡模式切换

### A1. eject 报错说失败，但设备其实已经切换成功了 ⭐ 最坑

**现象**

```bash
$ gdbus call --system --dest org.freedesktop.UDisks2 \
    --object-path /org/freedesktop/UDisks2/drives/AIC_flash_20200203 \
    --method org.freedesktop.UDisks2.Drive.Eject '{}'
错误：GDBus.Error:org.freedesktop.UDisks2.Error.Failed:
Error ejecting /dev/sda: Command-line 'eject '/dev/sda'' exited with
non-zero exit status 1: eject: 无法弹出
```

但紧接着查 `lsusb`：

```bash
$ lsusb | grep a69c
Bus 003 Device 018: ID a69c:88de AICSemi AIC8800DC     ← 已经切换成功了！
```

**根因**

软件弹出（Start/Stop Unit SCSI 命令）会让设备**立刻断开 USB 并重新枚举**。
设备在完成命令握手前就消失了，主机侧只能收到「命令失败」。内核日志里能看到真相：

```text
sd 0:0:0:0: [sda] tag#0 FAILED Result: hostbyte=DID_ERROR driverbyte=DRIVER_OK
sd 0:0:0:0: [sda] tag#0 CDB: Start/Stop Unit 1b 00 00 00 02 00
usb 3-4: USB disconnect, device number 17
usb 3-4: new high-speed USB device number 18      ← 重新枚举
usb 3-4: New USB Device found, idVendor=a69c, idProduct=88de   ← 变成网卡了
```

**解法**

**永远用 `lsusb` 的 USB ID 判定成败，不要看命令返回码。** 脚本里尤其要注意：
如果按返回码判断，会在成功时误报失败，然后重复 eject 一个已经不在的设备。

### A2. 普通用户 eject 权限不足，但也不想给 sudo

**现象**

```bash
$ eject /dev/sda
eject: 打不开 /dev/sda: 权限不够
$ id
uid=1000(administrator) gid=1000(administrator) groups=...,plugdev,...   ← 不在 disk 组
```

**根因**

`eject` 需要写块设备节点。但 **udisks2 的 D-Bus 接口走 polkit 授权**，
桌面会话的普通用户默认被允许弹出可移动设备。

**解法**

走 udisks2（无需 sudo、无需加组）：

```bash
# 1. 找到驱动器对象路径（注意：GetManagedObjects 在根对象 /org/freedesktop/UDisks2 上）
gdbus call --system --dest org.freedesktop.UDisks2 \
  --object-path /org/freedesktop/UDisks2 \
  --method org.freedesktop.DBus.ObjectManager.GetManagedObjects \
  | grep -oE '/org/freedesktop/UDisks2/drives/[A-Za-z0-9_]+' | sort -u

# 2. 调用 Eject（路径形如 .../drives/AIC_flash_20200203）
gdbus call --system --dest org.freedesktop.UDisks2 \
  --object-path /org/freedesktop/UDisks2/drives/AIC_flash_20200203 \
  --method org.freedesktop.UDisks2.Drive.Eject '{}'

# 3. 或者直接用文件管理器里那个 U 盘的「弹出」按钮，效果一样
```

**为什么不用 udisksctl**：`udisksctl unmount` 只卸载文件系统，
**不会触发设备的模式切换**。必须是 `Drive.Eject`（对应弹出整块设备）。

如果不介意加组（一次性，需重新登录）：`sudo usermod -aG disk $USER`。

### A3. 拔掉重插后又变回 U 盘模式

**现象**

好不容易切换成功了，拔下来插到另一个口，又变回 `a69c:5722`。

**根因**

模式切换是**每次上电都要重做**的，设备本身不记忆。这也是为什么必须装 udev 规则。

**解法**

装好驱动仓库的 `aic.rules` 后，插入时自动完成，不用手动干预：

```bash
cat /etc/udev/rules.d/aic.rules
# KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5722", SYMLINK+="aicudiskv2", RUN+="/usr/bin/eject /dev/%k"
```

规则里的 `RUN+=` 依赖 `/usr/bin/eject` 存在。**该包缺失时规则静默失效**
（不报错，就是没反应）——这是常见漏装项：`sudo apt install eject`。

新增规则后刷新：

```bash
sudo udevadm control --reload
sudo udevadm trigger
```

---

## B. 驱动安装

### B1. AIC8800 有多个变种，装错了会失败且报错含糊 ⭐

**现象**

装完某个 AIC8800 驱动后，模块加载了，但设备没有网络接口，或者 dmesg 里
固件相关报错，且错误信息看不出是「芯片不匹配」。

**根因**

AIC8800 是一个**系列**，不是单一型号：DC / DW / D80 / D80N / D80X2 / DLN …
**固件互不兼容**。驱动源码结构相似、都能编译通过，所以「编译成功」不代表选对了。

**解法**

**先确定芯片变种，再选驱动。** 三个可靠的判定途径：

1. **看切换后的 USB ID** —— 最可靠，ID 直接对应变种（见 [chipsets.md](chipsets.md)）。
   `a69c:88de` → AIC8800DC/DW 系。
2. **看驱动仓库的 udev 规则** —— 哪个仓库的 `aic.rules` 里有你设备的 `5722`，
   就说明它认这个设备。例：
   - DC 系仓库：有 `5722 → aicudiskv2`
   - D80 系仓库：只有 `5724 → ugreenax900`（那是 AX900，不是 AX390）
3. **验证 module alias** —— 编译后确认设备的 USB ID 在 alias 表里：

```bash
modinfo aic8800_fdrv.ko | grep alias | grep -i 88de
# 有 usb:vA69Cp88DEd* 才说明能匹配
```

### B2. Unknown symbol get_fw_path

**现象**

`sudo modprobe aic8800_fdrv` 报 `Unknown symbol get_fw_path (err -2)`。

**根因**

`aic8800_fdrv` 依赖 `aic_load_fw` 导出的 `get_fw_path` 符号（用于定位固件目录）。
`modinfo` 会显示依赖关系：`depends: cfg80211,aic_load_fw`。

**解法**

```bash
sudo modprobe aic_load_fw      # 先加载被依赖的
sudo modprobe aic8800_fdrv
```

开机自动加载的配置文件也要注意顺序（`/etc/modules-load.d/aic8800.conf` 里
`aic_load_fw` 写在前面）。

### B3. 固件 No such file or directory

**现象**

`dmesg | grep -i aic` 或日志里有 `No such file or directory` / `wrong size of firmware file`。

**根因**

驱动运行时把固件基础路径拼上 `/aic8800DC`（源码里 `strcat(aic_fw_path, "/aic8800DC")`），
默认基础路径是 `/lib/firmware`，所以最终要找的是 `/lib/firmware/aic8800DC/`。
仓库的 `install.sh` 会执行 `cp -rf fw/aic8800DC /lib/firmware/`。

**解法**

```bash
ls /lib/firmware/aic8800DC/ | head        # 应有 17 个左右文件
# 缺失就手动补：
sudo cp -rf <驱动仓库>/fw/aic8800DC /lib/firmware/
```

注意 `fw/` 下可能有多个变种目录（D80/DC/DLN…），**只拷对应变种那个**。

### B4. 装完当时能用，内核升级后失效

**根因**

内核升级后旧的 `.ko` 对不上新内核的 `vermagic`，模块拒绝加载。

**解法**

DKMS 会通过 `/etc/kernel/postinst.d/dkms` 自动重编译，正常情况下无需干预。失效时：

```bash
dkms status                    # 看是否掉到 added/built 状态
sudo dkms autoinstall          # 手动补编译
```

---

## C. 网络连接

### C1. 连上了 WiFi 却上不了网 / 走错网卡 ⭐

**现象**

`nmcli` 显示新网卡 connected，但访问网络仍走内置网卡，或内网地址不通。

**根因**

笔记本常有**两块无线网卡**（内置 + USB），可能同时连着不同网络，产生**多条默认路由**：

```bash
$ ip route
default via 10.167.178.1 dev wlp0s20f3 proto dhcp metric 601     ← 内置
default via 192.168.3.254 dev wlx6c1ff712bae3 proto dhcp metric 20601
```

metric 小的优先。目标网段如果只有一条明细路由，则走明细：

```bash
$ ip route get 192.168.3.102
192.168.3.102 dev wlx6c1ff712bae3 src 192.168.3.5 uid 1000      ← 正确走 USB 网卡
```

**解法**

```bash
ip route get <目标IP>                              # 先确认实际出口
nmcli con mod "<连接名>" ipv4.route-metric 100     # 调整优先级
nmcli con up "<连接名>"
```

### C2. 接口刚出现时 nmcli 说「找不到设备」

**现象**

`nmcli dev wifi list ifname wlxXXXX` 报「错误：没有找到设备 "wlxXXXX"」，
但 `ip -br link` 里明明有。

**根因**

设备从 `wlan0` 重命名成 `wlx<MAC>`，再到 NetworkManager 接管，
有**几秒钟的窗口期**。这期间接口存在但 NM 还没纳管。

**解法**

等 5~10 秒再操作。开机脚本里要加轮询等待，不要假设接口立即可用：

```bash
for i in $(seq 1 20); do
  nmcli -t -f GENERAL.STATE dev show "$IF" 2>/dev/null | grep -q '100 (connected)' && break
  sleep 2
done
```

### C3. WiFi 突然断开，且扫描列表里找不到该网络

**现象**

`journalctl -u NetworkManager` 显示：

```text
supplicant interface state: completed -> disconnected
device: link timed out.
state change: activated -> failed (reason 'ssid-not-found')
```

**根因**

**路由器那一侧下线了**（关机/重启/故障），不是网卡问题。

**解法**

关键是**区分责任方**——不要急着重装驱动：

```bash
nmcli dev wifi list          # 能看到别的 AP 吗？
lsusb | grep a69c            # 设备还在吗？
lsmod | grep aic8800_fdrv    # 驱动还在吗？
```

**只要能看到其他 AP，就说明网卡完全正常**，等路由器恢复即可。
`connection.autoconnect yes` 会让它自动重连，无需手动干预。

---

## D. Remmina 远程桌面

### D1. 远程桌面只有一小块，四周全是黑边 ⭐ 最坑

**现象**

连上后画面挤在窗口中间一小块，拉伸窗口也不变大，周围全是黑的。

**根因**

Remmina 的 `resolution_mode` 有三个值，**配置文件里不写这一项时默认是 `0`**：

| 值 | 含义 |
| --- | --- |
| `0` | Use initial window size —— **锁定首次连接那一刻的窗口尺寸** |
| `1` | Use client resolution —— 跟随窗口自适应 |
| `2` | Custom —— 固定分辨率 |

默认 `0` 会把远程分辨率钉死在首次连接的窗口大小（比如 640x483），
之后窗口怎么变都不重新协商，于是出现黑边。

**解法**

```bash
pkill -x remmina        # 必须先关，否则退出时会覆盖你的修改
# 编辑 ~/.local/share/remmina/<名字>.remmina，确保有：
#   resolution_mode=1
#   window_maximize=1
```

图形界面等价操作：右键连接 → 编辑 → 基本 → 分辨率 → 选 **Use client resolution**。

**先关 Remmina 再改配置**这一点很重要：Remmina 退出时会把窗口尺寸等
运行时状态写回配置文件，不关掉的话改动会被覆盖。

### D2. 只看窗口出现，以为连上了，其实停在凭据框

**现象**

Remmina 窗口弹出来了，看起来正常，但实际上停在「输入 RDP 身份验证凭据」
对话框，并没有真正登录。

**根因**

RDP 的 TLS 握手和协议协商在**凭据输入之前**就完成了，所以
能建立 TCP 会话 ≠ 登录成功。

**解法**

用 TCP 会话作为「真的连上了」的判据：

```bash
ss -tn | grep '<目标IP>:3389'
# ESTAB ... 192.168.3.5:51910  192.168.3.102:3389   ← 有这条才算连上
```

排查时也可以截图看实际画面（X11 会话下）：

```bash
export DISPLAY=:1
import -window "$(xwininfo -root -tree | grep '<窗口标题>' | awk '{print $1}' | head -1)" /tmp/shot.png
```

### D3. 后台启动的 Remmina 一会儿就自己退了

**现象**

脚本里用后台符号启动 Remmina，过一会儿进程没了，会话也断了。

**根因**

进程留在启动它的 shell 的**进程组/会话**里，父任务结束时被一起清理。

**解法**

用 `setsid` 完全脱离：

```bash
setsid nohup remmina -c ~/.local/share/remmina/名字.remmina </dev/null >/tmp/rm.log 2>&1 &
disown
```

### D4. 域环境的用户名怎么填

**根因**

RDP 的凭据有「用户名」和「域」两个独立字段，不同填法对应不同的账户类型。

**解法**

| 情况 | 用户名 | 域 |
| --- | --- | --- |
| 本地账户 | `admin` | 留空 |
| 域账户 | `DOMAIN\账号` | 留空 |
| 域账户（分开） | `账号` | `DOMAIN` |
| 本机账户（分开） | `账号` | `计算机名` |
| 微软账户 | `MicrosoftAccount\邮箱` | 留空 |

不知道域名时反查：

```bash
getent hosts <目标IP>
# → 192.168.3.102  CN01-I237005-A.CATLBattery.com
#   计算机名 = CN01-I237005-A, 域 = CATLBattery.com
```

### D5. 弹「无法验证证书」

**根因**

RDP 服务端用自签名证书，客户端默认校验失败。

**解法**

配置文件加 `cert_ignore=1`，或在弹窗里勾选「记住」后点「是」继续。
局域网内自建 RDP 这是正常现象。

---

## E. 诊断方法本身的陷阱

### E1. 用 pkill -f 匹配时会把自己的 shell 也杀掉

**现象**

`pkill -f 'remmina -c /path/to/x.remmina'` 执行后命令返回异常
（`exit null`），后续命令没执行。

**根因**

`pkill -f` 匹配**完整命令行**，而当前执行的 bash 命令行里就包含这个字符串，
于是把自己匹配上了。

**解法**

用精确的进程名匹配，或用 `pgrep` 先取 PID 再杀：

```bash
# 推荐：按可执行文件名精确匹配
pkill -x remmina

# 或者先看再杀
ps -eo pid,comm | awk '$2=="remmina"{print $1}'
kill -TERM <PID>
```

### E2. 在 shell 里统计反引号会被解析

**现象**

在 bash 里写 `grep -c '^```' file` 这类命令，报
「寻找匹配的 `"` 时遇到了未预期的 EOF」。

**根因**

bash 会解析命令替换符号，即使写在引号里，嵌套引号的处理也容易出错。

**解法**

要统计 markdown 代码块这类含反引号的内容，写成 Python 脚本再执行：

```python
BT = chr(96) * 3          # 用 chr(96) 构造反引号，避开转义
fence = sum(1 for l in open(p, encoding='utf-8') if l.startswith(BT))
print('代码块标记数:', fence, '(偶数=配对正常)' if fence % 2 == 0 else '(奇数=有未闭合!)')
```

用 `chr(96)` 构造反引号，彻底避开 shell 和 Python 的双重转义问题。

### E3. 判断「网卡是否有问题」时不要只看一个信号

**教训**

本次调试中出现过：接口存在但 `nmcli` 不认、接口消失、能扫描但连不上——
都是不同原因（初始化窗口期、路由器下线、驱动没加载）。

**可靠的判定组合**（四个都查，互相印证）：

```bash
lsusb | grep a69c                             # 硬件在不在、什么模式
lsmod | grep -E 'aic8800_fdrv|aic_load_fw'    # 驱动在不在
ip -br link | grep wlx                        # 接口在不在
nmcli dev wifi list                           # 射频能不能收到 AP
```

**能扫到其他 AP** 是最有力的证据：说明硬件、固件、驱动、射频链路全部正常，
问题在网络侧（路由器、密码、认证）。
