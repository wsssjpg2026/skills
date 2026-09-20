# 踩坑记录（现象 → 根因 → 解法）

来自 2026-09-20 的一次真实排障：双 WiFi（CATL_guest 外网 + TP-LINK_051D 内网）、Clash Verge (mihomo) TUN 模式、内网 API 请求失败 + 代理节点全部超时。按排障中出现的顺序记录。

---

## 坑 1：Clash TUN 三重锁死，绕不过去

**现象**：应用请求内网 API 失败（curl 报 `SSL routines::unexpected eof`）；无论怎么指定 DNS 服务器，域名都解析成 `198.18.0.x`。

**根因**：mihomo TUN 模式三层接管，缺一层都还会失败：
1. 环境变量代理 `http_proxy=127.0.0.1:7897`（clash-verge 设的系统代理）；
2. TUN `auto-route: true`：`Meta` 虚拟网卡 + `ip rule` 优先级 9000+ 指向 table 2022（default via Meta）；
3. `dns-hijack: any:53`：发往**任何** IP 的 53 端口查询都被截走，返回 fake-IP（198.18.0.0/16、fdfe:dcba:9876::/64）。

**解法**：不要试图在系统层面绕过（hosts 条目会被 TUN 路由抓回去；静态路由加在 main 表没用，因为 rule 9002 优先）。正确做法是让 mihomo 自己分流（SKILL.md 第二步）。

**诊断技巧**：fake-IP 段出现即中招；`dig @<任何DNS>` 返回 198.18.x.x 也是它。

---

## 坑 2：内网域名公网无记录，先确认域名性质再谈路由

**现象**：以为是路由问题，折腾半天出口。

**根因**：`fd-rosefinchapi.catl.com` 是纯内网域名，公网 DNS 返回 NXDOMAIN（Status:3），真实 IP（10.167.202.35）只有内网 DNS（192.168.3.254）知道。

**解法**：先用 `curl 'https://223.5.5.5/resolve?name=X&type=A'` 判定。NXDOMAIN → 必须配置"内网 DNS 经内网网卡出"的解析策略，单独配路由没用——mihomo 自己也要能解析这个域名才能建立连接。

---

## 坑 3：SO_BINDTODEVICE 在非 root + 自定义 fib 规则下不可靠

**现象**：python `setsockopt(SOL_SOCKET, 25, b'wlp0s20f3')` 后连百度都超时，但走 mihomo 的百度明明通。一度误导判断。

**根因**：非 root 下该调用行为不稳定，叠加 mihomo 的 ip rule（`from 0.0.0.0 iif lo lookup 2022` 等）后路由查找结果不可预期。

**解法**：测物理网卡连通性一律用**绑定源 IP**：
- curl：`curl --interface <网卡IP> --noproxy '*'`
- python：`s.bind(('10.167.178.211', 0))`（而不是 SO_BINDTODEVICE）

---

## 坑 4：企业访客网做目标级 TCP 过滤，"能不能出网"不是二值问题

**现象**：源 IP 绑定下，223.5.5.5:443 通、2096 通，但 8.8.8.8:443、119.29.29.29:443、部分百度 IP 全部超时；ICMP 却 100% 通。国内外、端口号都找不出统一规律。

**根因**：CATL_guest 网络有目标级防火墙策略（甚至存在 TLS 握手成功但应用层数据被掐的目标——机场 DoH 就是这种）。

**解法**：
- 判定要"同目标重复 5 次 + ping 对照"，单次结果不可信；
- 关键目标（代理节点入口、机场 DoH）要从**两张网卡分别测**，再决定架构：外网网卡可达 → 节点默认出站；只有内网网卡可达 → 节点加 `dialer-proxy: CATL-LAN`。

---

## 坑 5：判定 mihomo 流量实际出口——用网卡计数器，不要猜

**现象**：需要确认 mihomo 的 DIRECT 流量走哪张物理网卡。

**解法**：`/sys/class/net/<网卡>/statistics/tx_bytes`（注意：`ip -s link` 的 awk 解析容易写错，直接读 sys 文件最稳）。访问一个国内大站前后各读一次，哪张网卡数字涨就走哪张。

---

## 坑 6：Merge 的 append-proxies/prepend-rules 不被处理，重启后配置全空 ⚠️ 最大的坑

**现象**：手动改运行时配置一切正常；用户重启 Clash Verge 后弹窗"启动订阅配置校验失败，已使用默认配置启动"，代理组全空、TUN 关闭、整个网络断掉。

**根因**：该版本 clash-verge 不处理全局扩展配置(Merge)的 `append-proxies`/`prepend-rules` 特殊关键字——它们被**原样塞进最终配置**（校验文件里能看到孤立的 `append-proxies:` 顶级字段）。于是 `CATL-LAN` 出站从未进入 `proxies` 列表，而 Script.js 注入的 `dialer-proxy: CATL-LAN` 引用了它 → mihomo 校验报 `proxy [xx] dialer-proxy [CATL-LAN] not found` → clash-verge 回退默认空配置。

**解法**：
- **结构性修改（加出站、加规则）全部放 Script.js**——`main(config)` 直接 push/unshift，实测可靠执行；
- Merge 只用来覆盖普通顶级字段（如 `dns:` 整段替换是生效的）；保险起见 Merge 保持模板原样，全用 Script；
- 改完先 `verge-mihomo -t` 校验再重载；改前备份。

**教训**：GUI 生成链路（订阅 → Merge → Script → 基础字段）和手动改运行时文件是两条路，手动改通不代表 GUI 重新生成也通。**任何配置改动后，要模拟 GUI 重新生成的结果做一次校验。**

---

## 坑 7：Script 必须幂等

**现象**：重建运行时配置时报 `proxy CATL-LAN is the duplicate name`。

**根因**：对已含 CATL-LAN 的配置再次执行插入逻辑。

**解法**：插入前先查存在性（`proxies.some(p => p.name === LAN)`）、规则先 filter 去重再 unshift。手改配置文件时同样注意。

---

## 坑 8：机场公共 DNS 是假停放记录——"机场死了"是误判 ⚠️

**现象**：所有节点域名 `*.quandao.com` 在公共 DNS 解析为 `CNAME overdue.aliyun.com`（阿里云"欠费停放"），连到的 170.33.12.185 不响应代理协议，53 个节点全部超时。结论"机场停摆，无法修复"。

**根因**：**误判**。这是机场的防盗设计：公共 DNS 故意放假记录，真实入口 IP 只通过机场自建 DoH（`doh.dohcore.com:2096`）下发。实测该 DoH 从外网网卡完全可用（HTTP 200、0.15s），返回真实 IP（如台湾节点 122.118.142.90），且从外网网卡 TCP 可达。

**教训**：
- 公共 DNS 显示域名停放/过期 ≠ 服务死了。**订阅里如果配置了 nameserver-policy 指向自家 DoH，那就是真实解析的唯一来源**；
- 判断前先直接 curl 机场 DoH 拿一次真实解析对比。

---

## 坑 9：DoH 引导解析死锁——节点全部超时的真凶 ⚠️

**现象**：mihomo 通过机场 DoH 解析节点域名报 `context deadline exceeded` / `all DNS requests failed`，但用 curl 手动测同一个 DoH 却能通。

**根因**：mihomo 用 DoH 前要先解析 DoH 服务器自己的域名（`doh.dohcore.com`），引导用的是 `default-nameserver` 列表（含 8.8.8.8 等被墙服务器）→ 引导解析卡死 → DoH 永远拨不出去。curl 测试时用了 `--resolve` 绕过了引导，所以结果不同。

**解法**：`hosts:` 钉死 DoH 服务器域名 → IP：

```yaml
hosts:
  doh.dohcore.com: 118.89.197.205
```

修好后 53/53 节点全部复活（67ms 起）。

**通用教训**：**"用 curl --resolve 能通、但 mihomo 不通"——查引导 DNS**。任何 DoH/DoT 上游都可能踩这个。

---

## 坑 10：sed 改节点配置，流式/块式两种格式要分别处理

**现象**：给节点批量注入字段后 `verge-mihomo -t` 报 `yaml: line 158: mapping values are not allowed in this context`。

**根因**：订阅里节点混用两种 YAML 格式：
- 流式：`- { name: X, type: anytls, server: 12us.quandao.com, port: 4430 }`
- 块式：`server: 12us.quandao.com` 独占一行（hy2 节点多见）

对块式行执行 `s/\(server: X\)/\1, dialer-proxy: Y/` 会把字段拼进值里（`server: X, dialer-proxy: Y`），产生非法 YAML。

**解法**：块式行用独立行插入（`s/^\( *\)server: \([^,]*\), NEW$/\1server: \2\n\1NEW/`）；改完必跑 `-t` 校验。

---

## 坑 11：直连模式不评估规则

**现象**：配置了分流规则但不生效。

**根因**：`mode: direct` 下 mihomo 全部直连，规则被跳过。

**解法**：确认 `mode: rule`（API `GET /configs` 和运行时文件都要查——PUT 重载会回到文件里的值，改了运行时要同步改文件的 mode 行）。

---

## 坑 12：其他小坑

- **mihomo API 走 unix socket 免认证**（配置里有 secret 也不影响）：`curl --unix-socket /tmp/verge/verge-mihomo.sock http://localhost/...`。
- **重载配置**：`PUT /configs?force=true` + body `{"path": "<clash-verge.yaml 绝对路径>"}`，返回 204 即成功；TUN 会重建，网络瞬断 1-2 秒。
- **URL 编码组名/节点名**：含 emoji、中文、斜杠的名称（如 `♻️自动选择`、`5台湾-联通/移动(AnyTLS)`）必须 `urllib.parse.quote` 后再拼 API 路径，个别含 `/` 的名称即使编码也可能 404，用 group 批量接口替代单节点接口。
- **USB 网卡名**（`wlx<MAC>` 格式）换 USB 口可能变化，配置里的 `interface-name` 要同步更新。
- **节点域名 DNS 测试要用 mihomo 自己的视角**：`GET /dns/query?name=X` 返回的才是 mihomo 实际会用到的解析。
- **验证分流**：`GET /connections` 的 `chains` 字段显示每条连接的完整链路（`域名 -> 组 -> 节点`），是确认"到底走了哪条路"的最终证据。
