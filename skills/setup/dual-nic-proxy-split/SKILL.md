---
name: dual-nic-proxy-split
description: 双网卡/双 WiFi 分流配置：一张网卡上外网（配合 Clash/mihomo 代理访问国内外网站），另一张网卡访问内网 API。当用户有两张网卡或两个 WiFi（一个能上外网、一个连内网）、内网域名请求失败、需要在 Clash TUN 环境下让特定域名走指定网卡出口、或 Clash 代理节点全部超时需要排查 DNS 引导问题时使用。包含完整诊断流程、Clash Verge 配置模板和踩坑记录。
---

# 双网卡分流：外网 WiFi + 代理访问国内外，内网 WiFi 访问内网 API

## 目标架构

```
应用请求
  └─> Clash/mihomo (TUN + 系统代理接管全部流量)
        ├─ 国内域名 ──────────── DIRECT ───> 外网网卡 (如 wlp0s20f3) ──> 国内网站
        ├─ 国外域名 ────> 代理节点 ──默认出站──> 外网网卡 ──> 国外网站
        └─ 内网域名(catl.com 等) ─> CATL-LAN ──> 内网网卡 (如 wlx...) ──> 内网 API

DNS:
  内网域名 → 内网DNS#CATL-LAN   （解析和查询都从内网网卡出）
  其他域名 → 公共 DNS / 机场自建 DoH
```

核心原则（都踩过坑，见 references/pitfalls.md）：

1. **先诊断后配置**——每台机器/网络的封锁策略不同，不诊断就配置大概率走弯路。
2. **不要对抗 Clash TUN，让它分流**——TUN + dns-hijack 已接管全局，试图绕过它（hosts、静态路由、绑定接口）都很脆；正确做法是在 mihomo 里加"绑定内网网卡的 direct 出站 + 域名规则 + DNS 策略"。
3. **结构性配置全部放 Script.js**——`append-proxies`/`prepend-rules` 这类 Merge 特殊关键字在部分 clash-verge 版本不被处理，会原样透传导致配置校验失败、Clash 回退空配置。
4. **脚本必须幂等**——防重复执行/手改配置后重跑造成 "duplicate name" 校验失败。

## 第一步：诊断（必做）

按顺序执行，每步都有明确的判定：

### 1.1 摸清网络拓扑

```bash
ip -br addr          # 两张物理网卡 + 可能有 Meta/clash TUN 虚拟网卡
ip route show        # 默认路由（注意 metric，谁是主出口）
ip rule show         # 有 9000+ 优先级/table 2022 规则 = mihomo TUN auto-route
env | grep -i proxy  # http_proxy=127.0.0.1:7897 之类 = 系统代理
resolvectl status    # 每张网卡的 DNS
```

判定：存在 `Meta`/`utun` 虚拟网卡 + fake-IP 段（198.18.0.0/16、fdfe:dcba:9876::/64）→ mihomo TUN 模式接管全局，**所有流量和所有明文 DNS 查询（无论指定哪个 DNS 服务器）都被劫持**。

### 1.2 判断内网域名性质

```bash
curl -s 'https://223.5.5.5/resolve?name=<内网域名>&type=A'
# Status:3 (NXDOMAIN) = 纯内网域名，公网解析不出来，必须用内网 DNS
# 有 Answer = 公网可解析，问题只在路由
```

### 1.3 绕过 TUN 劫持，拿内网域名的真实 IP

用 `scripts/dns-via-nic.py`（绑定源 IP 出指定物理网卡，绕开 TUN 的路由规则和 dns-hijack）：

```bash
python3 scripts/dns-via-nic.py <内网域名> <内网DNS IP> <内网网卡源IP>
# 成功输出真实 IP（如 10.x.x.x）后，下一步测连通性
```

**坑**：不要用 SO_BINDTODEVICE（非 root 下行为不可靠，实测会莫名超时），用绑定源 IP 的方式。

### 1.4 测两张网卡各自的出站能力

```bash
# 绑定源 IP 测 TCP 连通性（--noproxy 必须加，否则走系统代理）
curl -sv --interface <网卡源IP> --noproxy '*' --connect-timeout 4 -o /dev/null https://<目标IP>:<端口>/
```

注意企业访客网络可能做**目标级 TCP 过滤**（ICMP 全通、部分 TCP 目标被封、甚至 TLS 能握手但应用层数据被掐）。判定方法：同目标重复 5 次 + ping 对照。如果代理节点入口从外网网卡被封但内网网卡可达（或反之），架构要相应调整（节点加 dialer-proxy 指到可达网卡）。

### 1.5 判定 mihomo DIRECT 实际走哪张网卡

```bash
# 计数器差分法（不需要 root）
cat /sys/class/net/<网卡>/statistics/{tx,rx}_bytes   # 记录
curl -s https://www.baidu.com/ -o /dev/null            # 走 mihomo 的普通访问
cat /sys/class/net/<网卡>/statistics/{tx,rx}_bytes   # 哪张物理网卡数字涨，DIRECT 就走哪张
```

### 1.6 mihomo API（诊断和操作的入口）

```bash
S='curl -s --unix-socket /tmp/verge/verge-mihomo.sock'   # unix socket 免认证
$S http://localhost/configs                              # mode/tun 状态
$S http://localhost/proxies | python3 -m json.tool        # 节点/分组
$S 'http://localhost/dns/query?name=<域名>&type=A'        # mihomo 眼中的解析结果
$S 'http://localhost/group/<URL编码组名>/delay?url=http://www.gstatic.com/generate_204&timeout=5000'  # 批量测节点
```

## 第二步：配置（Clash Verge / mihomo）

### 2.1 写全局 Script.js

位置：`~/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/Script.js`

```javascript
function main(config, profileName) {
  const LAN = 'CATL-LAN';
  // 1. 内网出站（绑定内网网卡——USB 网卡名如 wlx6c1ff712bae3，换口可能变，注意核对）
  if (!Array.isArray(config.proxies)) config.proxies = [];
  if (!config.proxies.some((p) => p && p.name === LAN)) {
    config.proxies.push({ name: LAN, type: 'direct', 'interface-name': '<内网网卡名>' });
  }
  // 2. 内网域名分流（幂等：先去重再插到最前）
  if (!Array.isArray(config.rules)) config.rules = [];
  config.rules = config.rules.filter((r) => typeof r === 'string' && !r.startsWith('DOMAIN-SUFFIX,<内网域名>,'));
  config.rules.unshift('DOMAIN-SUFFIX,<内网域名>,' + LAN);
  // 3. DNS：内网域名用内网 DNS 解析，查询也经内网网卡出（#CATL-LAN 指定查询出口）
  config.dns = config.dns || {};
  config.dns['nameserver-policy'] = Object.assign({}, config.dns['nameserver-policy'] || {}, {
    '+.<内网域名>': ['<内网DNS IP>#' + LAN],
  });
  return config;
}
```

**机场节点相关（如果有代理订阅）**——节点域名解析是最大的坑：

```javascript
  // 4. 机场域名必须走机场自建 DoH（公共 DNS 返回的是假停放 IP，防盗设计）
  //    且 DoH 服务器自身域名要用 hosts 钉死，否则引导解析卡死、全部节点超时
  config.dns['nameserver-policy'] = Object.assign({}, config.dns['nameserver-policy'] || {}, {
    '+.<机场域名>': ['https://doh.<机场DoH>...#skip-cert-verify=true'],
  });
  config.hosts = Object.assign({}, config.hosts, {
    'doh.<机场DoH域名>': '<机场DoH的IP>',   // 用 curl 从公共DNS查这个IP
  });
```

**不要**给节点加 `dialer-proxy`（除非 1.4 诊断确认节点入口只从内网网卡可达）。

### 2.2 立即生效（不等 GUI 重新生成）

直接改运行时配置 `clash-verge.yaml`（同目录）加入相同内容，然后：

```bash
/usr/bin/verge-mihomo -t -d <配置目录> -f <配置目录>/clash-verge.yaml   # 必须先校验！
curl -s -X PUT --unix-socket /tmp/verge/verge-mihomo.sock 'http://localhost/configs?force=true' \
     -H 'Content-Type: application/json' -d '{"path": "<clash-verge.yaml绝对路径>"}'
```

**坑**：改 YAML 用 sed 时注意节点有流式（`- { name: ..., server: ... }`）和块式（多行）两种格式，简单的 `s/server: X/...` 会把块式条目改坏（"mapping values are not allowed"）。两种格式要分别处理。

### 2.3 确认模式

mihomo 必须是**规则模式**（`mode: rule`）——直连模式不评估规则，分流失效。PUT 重载会回到文件里的 mode 值，确保文件里也是 rule。

## 第三步：验证

```bash
# 1. 内网 API（走系统代理 + 绕过代理走 TUN 两条路径都测）
curl -s -o /dev/null -w '%{http_code}\n' https://<内网API地址>
curl -s --noproxy '*' -o /dev/null -w '%{http_code}\n' https://<内网API地址>
# 2. 国内
curl -s -o /dev/null -w '%{http_code}\n' https://www.baidu.com
# 3. 国外（走代理节点）
curl -s -o /dev/null -w '%{http_code}\n' https://www.github.com  # 等
# 4. 节点批量延迟（应大部分可用）
# 5. 确认分流路径：GET /connections 看 chains 字段
```

## 遇到问题先查踩坑记录

完整的踩坑记录（现象→根因→解法）在 **references/pitfalls.md**，覆盖：

- Clash TUN 三重锁死（系统代理/TUN 路由/DNS 劫持）的识别与绕过
- Merge 特殊关键字不被处理导致回退空配置（重启报错）
- 机场公共 DNS 假停放记录、DoH 引导死锁（节点全超时的真凶）
- SO_BINDTODEVICE 不可靠、企业网目标级过滤的判定方法
- YAML 流式/块式混合 sed 改坏、配置重复、校验失败回退
- 其他（详见文件内目录）

修改/新增坑记录后无需任何注册操作，技能目录即生效。
