# Remmina 深入配置

本文件补充 SKILL.md 里没展开的部分。日常使用看 SKILL.md 的第五步就够了。

## 目录

- [配置文件在哪](#配置文件在哪)
- [手工写配置文件的注意事项](#手工写配置文件的注意事项)
- [配置项逐个说明](#配置项逐个说明)
- [分辨率三个模式详解](#分辨率三个模式详解)
- [协议选择](#协议选择)
- [连接方式与验证](#连接方式与验证)
- [无头/脚本环境下操作 Remmina](#无头脚本环境下操作-remmina)

---

## 配置文件在哪

| 内容 | 路径 |
| --- | --- |
| 连接配置 | `~/.local/share/remmina/<名字>.remmina` |
| 全局首选项 | `~/.config/remmina/remmina.pref` |
| 密码 | 系统密钥环（GNOME Keyring），不在配置文件里 |
| 插件 | `/usr/lib/x86_64-linux-gnu/remmina/plugins/` |

**密码存在密钥环**这一点很重要：`disablepasswordstoring=0` 时，
首次连接输入的密码会被保存，之后启动**不再询问**——这就是为什么
自动化场景下 Remmina 能直接连上而不弹凭据框。

要清除已保存的密码：Remmina 里右键连接 → 编辑 → 把密码栏清空并保存，
或用 `seahorse`（密码和密钥）图形工具删除对应条目。

## 手工写配置文件的注意事项

配置是 **INI 格式**，section 必须叫 `[remmina]`。

**文件名必须以 `.remmina` 结尾**，否则 Remmina 不会把它识别成连接配置。

**改配置前必须先关掉 Remmina**：

```bash
pkill -x remmina        # 用 -x 精确匹配，别用 -f（会杀到自己，见 pitfalls.md E1）
```

原因：Remmina 退出时会把运行时状态（窗口尺寸、位置、缩放）写回配置文件。
先改后关，改动会被覆盖。这个坑导致过「改了 `resolution_mode` 却没生效」的假象。

改完权限收一下（配置里可能含用户名等）：

```bash
chmod 600 ~/.local/share/remmina/<名字>.remmina
```

## 配置项逐个说明

以下键名**已在 Remmina 1.4.25 的二进制里验证存在**，不是猜的：

| 键 | 取值 | 说明 |
| --- | --- | --- |
| `name` | 字符串 | 显示在列表里的名字 |
| `protocol` | `RDP` / `VNC` / `SSH` / `SPICE` | 协议 |
| `server` | IP 或主机名，可带 `:端口` | 端口省略时用协议默认端口 |
| `username` | 字符串 | 可留空，连接时再问 |
| `domain` | 字符串 | 域环境用，见 SKILL.md 的凭据表 |
| `password` | 加密串 | **留空**，交给密钥环 |
| `cert_ignore` | `0`/`1` | `1` = 跳过证书校验（自签名证书必需） |
| `colordepth` | `8`/`15`/`16`/`24`/`32` | 色深，`32` 真彩；网络慢可降 |
| `quality` | `0`/`1`/`2`/`9` | `0`=自动；数值越大画质越低、越流畅 |
| `disableclipboard` | `0`/`1` | `0` = 启用剪贴板双向同步 |
| `multimon` | `0`/`1` | 多显示器（需服务端支持） |
| `resolution_mode` | `0`/`1`/`2` | **见下节** |
| `window_maximize` | `0`/`1` | 启动即最大化 |
| `disablepasswordstoring` | `0`/`1` | `0` = 允许保存密码 |
| `viewmode` | 整数 | 视图模式，Remmina 自己维护 |

> 注意：`server` / `username` / `password` 这几个键在 RDP 插件二进制里
> `grep` 不到（它们由 Remmina 主程序统一处理），但**确实是有效的配置键**。
> 判断某个键是否有效，看主程序 `/usr/bin/remmina` 而不是插件 `.so`。

## 分辨率三个模式详解

`resolution_mode` 的取值来自 Remmina 二进制里的 UI 定义，
三个选项原文是：`Use initial window size` / `Use client resolution` / `Custom`。

| 值 | 名称 | 行为 | 什么时候用 |
| --- | --- | --- | --- |
| `0` | Use initial window size | **锁定首次连接时的窗口尺寸**，之后窗口变化不再重新协商 | 几乎不要用（默认值，黑边的元凶） |
| `1` | Use client resolution | 远程分辨率跟随窗口大小动态调整 | **推荐**，日常使用 |
| `2` | Custom | 固定分辨率 | 远程机性能有限、不想每次缩放重绘时 |

### 推荐配置

```ini
resolution_mode=1
window_maximize=1
```

即：启动即最大化，远程桌面按本地屏幕分辨率（如 1920x1080）渲染。

### 固定分辨率的写法

```ini
resolution_mode=2
resolution=1440x900
```

`resolution` 键由插件的 `remmina_public_resolution_validation_func` 校验格式，
必须是 `宽x高` 形式。全局首选项里还有个 `resolutions` 列表，
定义下拉框里可选的档位（默认 `640x480,800x600,1024x768,…`），
和这里的 `resolution` **不是一回事**，别混。

### 运行时也能调

连上后按 `Ctrl+Alt+Enter` 切全屏，`resolution_mode=1` 会跟着重新协商；
用 `resolution_mode=0` 时全屏也不变。

## 协议选择

| 协议 | 默认端口 | 目标系统 | 备注 |
| --- | --- | --- | --- |
| RDP | 3389 | Windows | 需要目标开启「远程桌面」 |
| VNC | 5900 | Linux/macOS | 需目标跑 VNC server |
| SSH | 22 | Linux | 只有命令行 |
| SPICE | 5900/5930 | KVM 虚拟机 | 少用 |

### 判断目标开了什么

```bash
for p in 3389 5900 5901 22 445; do
  timeout 2 bash -c "echo > /dev/tcp/<目标IP>/$p" 2>/dev/null && echo "[开放] $p"
done
```

Windows 家用版默认**没有** RDP 服务端，需要目标在
「设置 → 系统 → 远程桌面」里手动开启（专业版/企业版才有这个选项）。

### RDP 服务端是否真的在跑

开放 3389 端口不一定说明服务正常。可以看 RDP 协商响应：

```bash
timeout 5 bash -c 'exec 3<>/dev/tcp/<目标IP>/3389; \
  printf "\x03\x00\x00\x13\x0e\xe0\x00\x00\x00\x00\x00\x01\x00\x08\x00\x03\x00\x00\x00" >&3; \
  timeout 3 head -c 19 <&3 | xxd'
# 返回 0300 0013 0ed0 ... → 这是 X.224 连接确认，说明 RDP 服务端在正常应答
# （若端口开着但服务没起，这里会超时或返回错误响应）
```

## 连接方式与验证

### 三种启动方式

```bash
remmina                                            # 打开主界面
remmina -c ~/.local/share/remmina/名字.remmina      # 直连已保存配置
remmina -c rdp://用户名@目标IP                      # 临时连，不保存
```

URI 形式也支持在 URL 里带加密后的密码（`remmina --encrypt-password` 生成），
但不建议——明文历史里有加密串同样是泄露面。

### 验证「真的连上了」

**窗口出现不算连上**，可能停在凭据框。看 TCP 会话才是铁证：

```bash
ss -tn | grep '<目标IP>:3389'
# ESTAB 0 0 192.168.3.5:51910 192.168.3.102:3389   ← 有 ESTAB 才算
```

进一步确认画面（X11 会话）：

```bash
export DISPLAY=:1                    # 先确认: echo $DISPLAY
WID=$(xwininfo -root -tree | grep '<窗口标题>' | awk '{print $1}' | head -1)
import -window "$WID" /tmp/rdp.png   # 需要 imagemagick
```

窗口标题就是配置里的 `name`，所以名字起得有辨识度会方便脚本定位。

## 无头/脚本环境下操作 Remmina

### 后台稳定运行

必须用 `setsid` 脱离进程组，否则父任务结束时会把它一起带走：

```bash
setsid nohup remmina -c ~/.local/share/remmina/名字.remmina \
  </dev/null >/tmp/remmina.log 2>&1 &
disown
```

### 关闭

```bash
pkill -x remmina        # 精确匹配可执行文件名
```

**不要用 `pkill -f 'remmina -c'`**——当前 shell 的命令行里就含这个字符串，
会把自己也杀掉（见 pitfalls.md E1）。

### 会话类型

Remmina 在 **X11** 下工作最正常。Wayland 下 RDP 也能用，但截图、窗口定位
这类操作会受限（`xwininfo`/`import` 拿不到窗口）。

判断当前会话：

```bash
echo "$XDG_SESSION_TYPE"        # x11 或 wayland
loginctl show-session $(loginctl | awk '/'"$USER"'/{print $1; exit}') -p Type
```

### 调试

```bash
G_MESSAGES_DEBUG=all remmina -c 名字.remmina 2>&1 | grep -vE 'GLib-Net-DEBUG' | tail -40
```

日志里 `Resolution set by the user: WxH` 这行会显示实际协商的分辨率，
排查黑边问题很有用。日志中的
`[ERROR][com.freerdp.common.settings] - Invalid key index` 是无害噪音，
可以忽略。
