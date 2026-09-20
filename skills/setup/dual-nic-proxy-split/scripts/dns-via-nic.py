#!/usr/bin/env python3
"""绕过 Clash TUN 的 dns-hijack，从指定物理网卡直接查询 DNS。

用法: python3 dns-via-nic.py <域名> <DNS服务器IP> <网卡源IP> [查询类型]
示例: python3 dns-via-nic.py fd-rosefinchapi.catl.com 192.168.3.254 192.168.3.5

原理: 绑定源 IP 的 socket 走 main 路由表（源 IP 已绑定时 mihomo 的
      `from 0.0.0.0 lookup 2022` 规则不匹配），从而绕开 TUN 劫持。
      不要改成 SO_BINDTODEVICE —— 非 root 下不可靠（见 pitfalls.md 坑 3）。
"""
import socket, struct, sys

def build_query(name, qtype=1):
    hdr = struct.pack('>HHHHHH', 0x1234, 0x0100, 1, 0, 0, 0)
    q = b''.join(bytes([len(p)]) + p.encode() for p in name.split('.')) + b'\x00'
    return hdr + q + struct.pack('>HH', qtype, 1)

def parse_a(data):
    qd = struct.unpack('>H', data[4:6])[0]
    an = struct.unpack('>H', data[6:8])[0]
    rcode = data[3] & 0xF
    off = 12
    for _ in range(qd):  # 跳过 question 段
        while data[off]:
            off += data[off] + 1
        off += 5
    ips = []
    for _ in range(an):
        while True:  # 域名可能是压缩指针
            l = data[off]
            if l & 0xC0:
                off += 2; break
            off += 1
            if l == 0:
                break
        typ, _, _, rdl = struct.unpack('>HHIH', data[off:off + 10]); off += 10
        if typ == 1 and rdl == 4:
            ips.append('.'.join(map(str, data[off:off + 4])))
        elif typ == 5:
            ips.append('(CNAME)')
        off += rdl
    return rcode, ips

def main():
    if len(sys.argv) < 4:
        print(__doc__); sys.exit(1)
    name, server, src = sys.argv[1], sys.argv[2], sys.argv[3]
    qtype = {'A': 1, 'AAAA': 28, 'PTR': 12}.get(sys.argv[4].upper() if len(sys.argv) > 4 else 'A', 1)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3)
    try:
        s.bind((src, 0))  # 绑定源 IP（不是 SO_BINDTODEVICE）
    except OSError as e:
        print(f'绑定源 IP {src} 失败（{e}）：该 IP 不在任何网卡上。'
              f'先跑 ip -br addr 确认网卡在线且 IP 没变——USB 网卡拔掉/换口后会消失或改名。')
        sys.exit(3)
    try:
        s.sendto(build_query(name, qtype), (server, 53))
        data, _ = s.recvfrom(4096)
    except socket.timeout:
        print(f'超时：{server} 未应答（检查源 IP 是否属于可达该 DNS 的网卡）'); sys.exit(2)
    rcode, ips = parse_a(data)
    print(f'{name} @ {server} (from {src}): rcode={rcode} (0=OK,3=NXDOMAIN) -> {ips or "无记录"}')

if __name__ == '__main__':
    main()
