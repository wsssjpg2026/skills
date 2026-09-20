# 芯片变种、USB ID 与驱动选型

AIC8800 是一个**芯片系列**，不是一个型号。选错变种会编译成功但跑不起来，
而且报错含糊，所以这一步值得花时间确认。

## 变种对照表

| 芯片变种 | 网卡模式 USB ID | U 盘模式 USB ID | 常见贴牌产品 |
| --- | --- | --- | --- |
| **AIC8800DC** | `a69c:88dc` | `a69c:5722` / `5721` / `572a` | 绿联 AX300/AX390、Tenda、MERCURY |
| **AIC8800DW** | `a69c:88dd` / `368b:88de` | 同上 | 绿联、AIC 参考设计 |
| AIC8800FC | `a69c:88de` / `368b:88df` | 同上 | 绿联 AX300 部分批次 |
| AIC8800D80 | `a69c:8d80` | `1111:1111` / `a69c:5724` | 绿联 AX900、Tenda U11 |
| AIC8800D80N | `a69c:8870` | — | — |
| AIC8800DLN | `a69c:8871` | — | — |

> **注意 `a69c:88de` 的归属有歧义**：不同仓库把它标成 DC、DW 或 FC。
> 实际操作上不必纠结命名——**看驱动仓库的 udev 规则里有没有你的 U 盘模式 PID**
> 更可靠（见下面的判定法）。

## 判定顺序（按可靠性排序）

### 1. 看 U 盘模式的 PID —— 最有信息量

这一步在**切换模式之前**就能做，而且能直接区分驱动家族：

```bash
lsusb | grep -i a69c
# ID a69c:5722 → DC/DW/FC 家族（本技能覆盖的情况）
# ID a69c:5724 → D80 家族（绿联 AX900）
```

### 2. 看驱动仓库的 udev 规则

克隆驱动后，检查它的 `tools/aic.rules` 或 `aic.rules` 里有没有你的 PID：

```bash
grep '5722' <驱动仓库>/tools/aic.rules
```

有 → 这个仓库认你的设备。没有 → 换一个家族试。

实例对比：

| 仓库 | 规则里的 PID | 对应产品 |
| --- | --- | --- |
| Kiborgik/aic8800dc-linux-patched | `5721` `5722` `572a` | 绿联 AX300/AX390 ✅ |
| RicknotDev/aic8800d80 | `5721` `5723` `5724`(ugreenax900) `5725`… | 绿联 AX900 ❌ |

注意 D80 仓库里 `5724` 的 symlink 名字直接叫 `ugreenax900`——名字就暴露了目标产品。

### 3. 看驱动源码的 USB ID 表

```bash
grep -n 'USB_PRODUCT_ID' <驱动仓库>/drivers/aic8800/aic8800_fdrv/aicwf_usb.h
```

### 4. 编译后用 modinfo 交叉验证

最硬的证据——确认设备 ID 真的在模块的匹配表里：

```bash
modinfo drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko | grep alias
# 期望看到: alias: usb:vA69Cp88DEd*dc*dsc*dp*ic*isc*ip*in*
```

没有对应 alias，模块就不会绑定到这个设备。

## 驱动仓库一览

| 仓库 | 覆盖变种 | 说明 |
| --- | --- | --- |
| [Kiborgik/aic8800dc-linux-patched](https://github.com/Kiborgik/aic8800dc-linux-patched) | DC/DW | **本技能验证过的**，DKMS、有 udev 规则和自检脚本，对新内核兼容性好 |
| [shenmintao/aic8800d80](https://github.com/shenmintao/aic8800d80) | D80 系 | D80 主力仓库 |
| [RicknotDev/aic8800d80](https://github.com/RicknotDev/aic8800d80) | D80 系 + DC/DLN | 多发行版支持，安装脚本较复杂 |
| [goecho/aic8800_linux_drvier](https://github.com/goecho/aic8800_linux_drvier) | DC | 较早期，注意仓库名有拼写错误 |

选仓库时优先看：**是否有 DKMS 支持**、**是否有 udev 自动模式切换规则**、
**最近的提交时间**。前两项决定了装完之后要不要每次开机手动折腾。

## 设备表缺项：如何加一个最小条目

如果确认变种正确，但模块死活不绑定（`modinfo` 里没有你的 ID），
可能是驱动表里缺你这个 PID。加一个条目需要**三处**同时改（AIC 驱动的
设计如此，不是一处配置能解决的）：

1. `aicwf_usb.h` 里加 `#define` PID
2. `aicwf_usb.c` 的 `aicwf_usb_id_table[]` 里加 `USB_DEVICE(...)`
3. 固件选择分支（`aicwf_compat_*.c` 里按 VID/PID 选 `aic_userconfig` 文件的地方），
   让新 PID 走到正确的固件分支

第 3 步最容易漏——前两步加完能绑定、能创建接口，但固件加载会失败或行为异常。

**优先顺序**：先用 `modinfo` 确认是不是真的缺条目。多数情况是**选错了驱动家族**，
而不是设备表缺项。别急着改源码。

## 本技能的验证环境

供参考的已知可用组合：

| 项目 | 值 |
| --- | --- |
| 发行版 | Ubuntu 22.04.5 LTS |
| 内核 | 6.8.0-138-generic |
| 网卡 | 绿联 AX390 |
| U 盘模式 ID | `a69c:5722` |
| 网卡模式 ID | `a69c:88de` |
| 驱动 | Kiborgik/aic8800dc-linux-patched，DKMS 版本 `6.4.3.0-patched.15` |
| 编译结果 | `aic_load_fw.ko` + `aic8800_fdrv.ko`，零错误 |
| 接口名 | `wlx6c1ff712bae3`（wlx + MAC） |
| 实测速率 | 2.4GHz 40MHz VHT-NSS1，tx 135 Mbit/s |
