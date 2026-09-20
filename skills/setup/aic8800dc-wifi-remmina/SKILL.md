---
name: aic8800dc-wifi-remmina
description: 在 Linux 上让 AICSemi AIC8800DC 芯片的免驱无线网卡（绿联 AX390/AX300、Tenda、MERCURY 等贴牌产品，USB ID a69c:5722 或 a69c:88de）连上 WiFi，并用 Remmina 配置 RDP/VNC 远程桌面连接到指定 IP。当用户遇到「网卡插上后变成 U 盘/光驱」「lsusb 显示 Aic MSC 或 a69c:5722」「有 a69c:88de 设备但没有 wlan 接口」「网卡搜不到 WiFi」「绿联/UGREEN 无线网卡在 Ubuntu 上不能用」，或需要用 Remmina 远程桌面连接某个 IP、远程桌面分辨率只有一小块、画面有黑边、RDP 登录凭据怎么填时使用。包含选驱动、模式切换、DKMS 安装、网络连接、Remmina 全流程配置和踩坑记录。
---

# AIC8800DC 免驱网卡 + Remmina 远程桌面

这张网卡的所有麻烦都来自两件事：**它插入时不是网卡**，以及**Linux 内核没有它的驱动**。
把这两件事处理掉，剩下就是普通的 NetworkManager 操作。

## 关键机制：为什么它插上像个 U 盘

AIC8800DC 是一颗 **Wi-Fi + 蓝牙二合一芯片**，被大量贴牌成「免驱版」USB 网卡。
「免驱」是 Windows 的说法——厂商把驱动做成了一个虚拟光驱：

| 阶段 | USB ID | 设备名 | 说明 |
| --- | --- | --- | --- |
| 出厂模式 | `a69c:5722`（也可能是 `5721` / `572a`） | `Aic MSC` | 只读 U 盘，里面只有 `ugreen_wifi_driver.exe` |
| 网卡模式 | `a69c:88de`（也有 `88dc` / `88dd`） | `AIC8800DC` | 真正的无线网卡 |

**必须把那个虚拟光驱弹出（eject）**，设备才会重新枚举成网卡。这一步是 Linux 上
一切问题的分水岭——先确认设备在哪个模式，再谈别的。

## 第一步：诊断（必做，先别急着装驱动）

跑技能自带的诊断脚本，它把 USB 模式、驱动、接口、路由、RDP 可达性一次查完，
每项都直接给出下一步动作：

```bash
scripts/diagnose.sh                    # 只查网卡
scripts/diagnose.sh 192.168.3.102      # 附带查这个 IP 的 RDP 可达性
```

脚本全程只读、不需要 root。**照着它标 [问题] 的项往下走**，比盲目装驱动快得多。

如果不想跑脚本，最小诊断是三行：

```bash
lsusb | grep -i a69c          # 5722=U盘模式, 88de=网卡模式
ip -br link                   # 有没有 wlx* 接口
lsmod | grep aic              # 驱动加载了没
```

## 第二步：把设备从 U 盘模式切到网卡模式

```bash
scripts/switch-to-wifi.sh      # 优先走 udisks2，免 root
```

脚本优先用 udisks2 的 D-Bus 接口（经 polkit 授权，**普通用户就能跑**），
失败才回退到 `eject`。

> **最反直觉的坑**：udisks2 的 Eject 调用**经常返回 "Error ejecting / 无法弹出" 的报错，
> 但设备其实已经切换成功了**。因为它发的 Start/Stop Unit 命令会让设备立刻断开重连，
> 命令本身拿不到正常响应。所以**不要看返回码，要看 `lsusb` 的 USB ID**。
> 详见 [references/pitfalls.md](references/pitfalls.md)。

手动方式（脚本不适用时）：

```bash
# 方式 A：图形界面点那个 U 盘的「弹出」按钮（最省事，走 polkit 授权）
# 方式 B：命令行
sudo eject /dev/aicudiskv2      # 或 /dev/sda
```

切换后等 5~10 秒接口才会出现：

```bash
watch -n1 'lsusb | grep a69c; ip -br link | grep wlx'
```

## 第三步：安装驱动（内核没有内置）

内核 6.8 及以下**不含** aic8800 驱动，必须编译安装。选对驱动版本是关键——
AIC8800 有多个变种（DC/DW/D80/D80N…），固件互不兼容，装错会失败且报错含糊。

**选型依据表在 [references/chipsets.md](references/chipsets.md)**，包含各变种对应的
USB ID、驱动仓库和一份「设备表缺项时如何打最小补丁」的说明。

以本技能的验证环境（Ubuntu 22.04 + 内核 6.8 + `a69c:88de`）为例：

```bash
# 1. 取驱动源码
git clone --depth 1 https://github.com/Kiborgik/aic8800dc-linux-patched.git
cd aic8800dc-linux-patched

# 2. 装依赖（dkms 用于内核升级后自动重编译）
sudo apt install -y dkms build-essential linux-headers-$(uname -r) eject

# 3. 一条命令装完（固件 + udev 规则 + DKMS 编译 + 加载模块）
sudo ./install.sh

# 4. 自检（仓库自带，11 项检查）
sudo ./test.sh
```

### 加载顺序不能颠倒

`aic8800_fdrv` **依赖** `aic_load_fw` 导出的 `get_fw_path` 符号。必须先加载前者所依赖的：

```bash
sudo modprobe aic_load_fw        # 先
sudo modprobe aic8800_fdrv       # 后
```

颠倒会报 `Unknown symbol get_fw_path`。

### 固件路径

驱动从 `/lib/firmware/aic8800DC/` 读固件（运行时会把 `aic_fw_path` 拼上 `/aic8800DC`）。
装完应该有十几个文件。缺失时的典型症状是 dmesg 里 `No such file or directory`。

### 装完就自动持久化了

正规的驱动仓库会同时装好这三样，**重启和插拔都不用再管**：

| 文件 | 作用 |
| --- | --- |
| `/etc/udev/rules.d/aic.rules` | 插上时自动 eject 虚拟光驱 → 直接进网卡模式 |
| `/etc/modules-load.d/aic8800.conf` | 开机自动加载模块 |
| `/etc/kernel/postinst.d/dkms` | 内核升级后自动重编译 |

## 第四步：连 WiFi

接口名通常是 `wlx` + MAC（如 `wlx6c1ff712bae3`），**每台机器/每个 USB 口可能不同**，
用 `ip -br link` 确认实际名字，不要照抄。

```bash
nmcli dev wifi list                                          # 扫描
nmcli dev wifi connect "SSID" password "密码"                  # 连接
nmcli dev wifi connect "SSID" password "密码" ifname wlxXXXX   # 指定走这张卡
nmcli --ask dev wifi connect "SSID" ifname wlxXXXX             # 密码不进 shell 历史
```

**多网卡机器务必加 `ifname`**：笔记本通常还有一块内置网卡，不指定时
NetworkManager 可能挑错，导致「连上了却上不了网」。

连上后验证（有 IP ≠ 能通，必须实测出口）：

```bash
nmcli dev status
ip -br addr show wlxXXXX
ping -I wlxXXXX -c 3 223.5.5.5      # -I 强制从这张卡出去
```

## 第五步：Remmina 远程桌面

### 先确认目标可达，再配 Remmina

顺序很重要——**网络不通时配 Remmina 是白费功夫**，会误以为是客户端问题：

```bash
ping -c 3 <目标IP>
timeout 4 bash -c "echo > /dev/tcp/<目标IP>/3389" && echo "RDP 开放" || echo "RDP 关闭"
ip route get <目标IP>               # 确认走的是期望的那张网卡
```

端口对应关系：**3389 = RDP（Windows）**、5900 = VNC、22 = SSH。
QQ/普通版 Windows 家庭版默认不开远程桌面，需要对方在「设置 → 系统 → 远程桌面」里启用。

### 建连接

**图形界面**：Remmina 左上角 `+` → 协议选 RDP → 填服务器/用户名/密码 → 保存并连接。

**命令行**（推荐，可复现）：

```bash
remmina -c rdp://用户名@目标IP                    # 临时连，不保存
remmina -c ~/.local/share/remmina/名字.remmina     # 连已保存的配置
```

### 配置文件模板（直接可用）

写到 `~/.local/share/remmina/<名字>.remmina`，**文件名要用 `.remmina` 结尾**：

```ini
[remmina]
name=192.168.3.102 (Windows RDP)
protocol=RDP
server=192.168.3.102
username=admin
domain=
password=
cert_ignore=1
colordepth=32
disableclipboard=0
multimon=0
disablepasswordstoring=0
resolution_mode=1
window_maximize=1
```

**两个关键项，漏了必出问题**：

- `resolution_mode=1` —— 让远程分辨率**跟随窗口自适应**。漏写这一项会默认成 `0`
  （锁定首次连接时的窗口尺寸），于是远程桌面永远渲染成一个小方块，窗口拉大后
  四周全是黑边。**这是最容易踩的坑**，详见 [references/remmina.md](references/remmina.md)。
- `cert_ignore=1` —— 跳过自签名证书警告，否则首次连接会弹「无法验证证书」。

`password` 留空即可：首次连接时 Remmina 会问你要，然后存进系统密钥环。

### 登录凭据怎么填

**域环境**（企业机器）是重灾区，用户名有多种写法，依次试：

| 情况 | 用户名 | 域 |
| --- | --- | --- |
| 本地账户 | `admin` | 留空 |
| 域账户（反斜杠） | `CATLBattery\账号` | 留空 |
| 域账户（分开填） | `账号` | `CATLBattery` |
| 本机账户（分开填） | `账号` | `计算机名` |
| 微软账户 | `MicrosoftAccount\邮箱` | 留空 |

不知道域名/计算机名时，反向解析一下就知道：

```bash
getent hosts <目标IP>      # 例：192.168.3.102 → CN01-I237005-A.CATLBattery.com
```

### 常用快捷键

| 快捷键 | 作用 |
| --- | --- |
| `Ctrl+Alt+Enter` | 全屏 / 窗口 切换 |
| `Ctrl+Alt+End` | 向远程机发送 `Ctrl+Alt+Del` |
| `Ctrl+Alt+T` | 切换键盘抓取（`Tab` 键跑到本机时用） |

## 验证清单

做完后逐条确认，**任何一条不满足都不算完成**：

```bash
lsusb | grep a69c                      # [1] 显示 a69c:88de（网卡模式）
lsmod | grep aic8800_fdrv              # [2] 驱动已加载
ip -br link | grep wlx                 # [3] 无线接口存在
nmcli -t dev status | grep wlx         # [4] 显示 connected:<SSID>
ping -I wlxXXXX -c 3 223.5.5.5         # [5] 从该网卡能出网
timeout 4 bash -c "echo > /dev/tcp/<目标IP>/3389"; echo $?   # [6] RDP 端口通
ss -tn | grep '<目标IP>:3389'          # [7] 连接后能看到 ESTAB 会话
```

第 [7] 条是**客户端真的连上了的铁证**——只看 Remmina 窗口出现不够，
它可能停在凭据输入框。

## 遇到问题

- **现象→根因→解法**的完整踩坑记录：[references/pitfalls.md](references/pitfalls.md)
  （假报错的 eject、假成功的连接、驱动装错变种、分辨率黑边、双网卡抢占默认路由等）
- 芯片变种与驱动选型：[references/chipsets.md](references/chipsets.md)
- Remmina 深入配置：[references/remmina.md](references/remmina.md)

修改或新增踩坑记录不需要任何注册操作，技能目录即生效。
