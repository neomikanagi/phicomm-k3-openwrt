# 斐讯 K3：官方 OpenWrt + PassWall2 + AdGuard Home

**这是可追溯的候选固件工程，不是已经真机验证的“稳定版”。** 官方 OpenWrt 25.12.6 / Linux 6.12，保留官方 LuCI、网络栈及 brcmfmac 内核驱动；只添加必要插件和保守默认值。仅用于 **K3，不能用于 K3C**。

[云编译与下载](https://github.com/neomikanagi/phicomm-k3-openwrt/actions/workflows/build.yml) · [真机验收](docs/acceptance.md)

## 两种无线版本

| 成品 | 无线芯片固件 | 用途 |
|---|---|---|
| `official` | 官方 OpenWrt 的 BCM4366C0 固件 | 基线、排错和回退 |
| `ac88` | AC88U 3.0.0.4.386.48260 提取固件，固定 SHA-256 | 改善 K3 无线表现的实验候选，与基线实测对比 |

**AC88 版不是把梅林的 `wl/dhd.ko` 移植进 OpenWrt。** 新内核与梅林闭源内核驱动 ABI 不兼容；这里换的是无线芯片内部运行的 firmware，仍由官方 brcmfmac 驱动。已有 K3 使用案例不等于本机验证，不能承诺梅林同等性能、满速、漫游或不掉线。

AC88 二进制不提交进本仓库，构建时从固定上游提交下载并校验；保留来源，不声称拥有其再分发授权。对外再分发该版本前应核对上游/厂商许可。自写代码使用 GPL-2.0-only，各上游包及二进制继续适用各自许可证。

## 构建与下载

GitHub Actions 使用公开仓库的标准 Linux runner，不配置付费 runner、不需要 Secrets。`main` 的构建相关改动自动编译，也可点 **Run workflow**；没有定时任务、不自动刷机。

工作流先跑离线测试，再并行从固定源码编译 `official` / `ac88`。首次完整编译通常需要数小时。只在配置、包清单、rootfs、TRX 头和固件哈希检查通过后上传 candidate artifact；编译失败只有诊断附件，不冒充成品。

在成功任务底部 **Artifacts** 下载对应 ZIP，解压后：

```sh
sha256sum -c SHA256SUMS
```

每包含 `.trx`、包清单、完整构建配置、上游提交和芯片固件哈希。官方 feeds 由正式发行版自带提交锁定，第三方源在 `sources.lock.json` 锁定；不会随上游 main 悄悄漂移。更新需修改锁文件并重新验收。

## 首次刷机：先确认救援路径

1. 确认机身是 K3；备份当前配置、CFE/引导环境、NVRAM/无线校准和分区信息到另一台电脑，并确认当前机型对应的串口/CFE/TFTP 救援方法。**本工程不改引导器、不擦 NVRAM、不写校准分区。**
2. 已运行官方 OpenWrt：有线直连、断开非必要设备，先用 `ubus call system board`、`cat /proc/mtd` 核对型号/分区，再 `sysupgrade -T /tmp/固件.trx`。兼容性检查不过就停止，**不能用 `-F` 强刷**。
3. 确认备份和救援可用后，按官方 sysupgrade 流程安装，首次跨固件不保留旧配置（`-n`）。`sysupgrade -T` 通过不代表救援或无线已验证。
4. 当前是原厂、梅林、LEDE 魔改或未知 CFE：不要直接往原系统升级页塞本 `.trx`；需先按当前引导器/分区确定迁移方式。本仓库不提供猜测性的通刷命令。

首次管理地址沿用官方 `192.168.1.1`。先有线连接设置 root 密码，再配置 WAN；上游同网段时先改 LAN。没有内置用户节点、订阅、账号或通用 Wi-Fi 密码。

## 无线设置

默认关闭无线，避免无密码广播。LuCI 中设置**实际使用国家/地区**和独立强密码，选择 WPA2-PSK / AES 后开启；不伪造国家、不解锁功率。2.4G 起点为 HT20 / 信道 1，5G 为 VHT80 / 信道 36，需结合当地法规和干扰调整。

每个射频只保留一个 AP，固定 `wlan0/wlan1` 接口名以规避已报告的 brcmfmac 接口问题。不要一开始加多 SSID、无线中继、802.11r 或 WPA3；先跑完双频验收。默认关闭软/硬流量卸载，先确保透明代理路径正确，不承诺千兆代理。

## PassWall2

菜单：**服务 → PassWall2**。内置单个 Xray 核心及 nftables 透明代理，避免双核心/iptables 混装占用 K3 的 512 MB RAM。没有节点时默认不启用；导入自己的节点并测试后再开启。

此精简组合不包含 sing-box、Hysteria2/TUIC 或额外 SSR 插件。AdGuard 联用时保持 **DNS 重定向关闭、访问控制 ACL 关闭**；默认全局规则/分流仍可使用。ACL 会生成独立 DNS 路径，可能绕过广告过滤，本工程不把这种配置冒充已支持。

## AdGuard Home：首次初始化后再接管 DNS

首次不自动接管 DNS，未完成设置时普通上网不受影响。SSH 执行：

```sh
/etc/init.d/adguardhome start
```

打开 `http://192.168.1.1:3000` 完成官方向导：设置自己的管理员账号/密码；管理端口保持 `3000`；DNS 监听 `0.0.0.0`、**端口 `5353`**（初始化临时端口，不与 dnsmasq 冲突）。不要启用 AdGuard 的 DHCP。

完成向导、WAN DNS 正常后执行：

```sh
k3-adguard enable
```

它在停服状态解析 YAML，确认已有密码，把 AdGuard 改为端口 53、dnsmasq 移到 5053；关闭 PassWall2 DNS 劫持并保留其 DNS 分流，验证前后端均能解析。失败自动恢复原 DNS 配置。最终路径：

```text
客户端 :53 → AdGuard 广告过滤 → dnsmasq :5053 → PassWall2 DNS 分流 / WAN DNS
```

AdGuard 不回指自己，PassWall2 的直连 DNS 也不要填 `127.0.0.1:53`。查询日志和统计默认关闭，缓存 4 MiB，运行数据放 tmpfs，避免频繁写 NAND；重启后规则缓存需重新下载。Go 内存值是软目标，不是总内存保证。首次保留 AdGuard 默认轻量过滤列表，不叠加百万条大规则。域名级过滤无法去掉同域的视频贴片、App 内嵌或客户端自带 DoH 绕过的广告。

检查与回退（无需重刷）：

```sh
k3-check
k3-adguard disable    # 关闭 AGH，恢复 dnsmasq :53；不删除账号与规则配置
```

未配置 WAN、节点失效或主动修改 DNS 拓扑时，不能仅凭“服务正在运行”判断联网成功。

## 来源与验收边界

- [OpenWrt 25.12.6 正式版](https://github.com/openwrt/openwrt/releases/tag/v25.12.6)
- [官方 K3 profile](https://downloads.openwrt.org/releases/25.12.6/targets/bcm53xx/generic/profiles.json)
- [PassWall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) / [依赖包](https://github.com/Openwrt-Passwall/openwrt-passwall-packages)
- [K3 无线固件来源及提取版本](https://github.com/xiangfeidexiaohuo/Phicomm-K3_Wireless-Firmware)
- [OpenWrt 无线接口问题 #11466](https://github.com/openwrt/openwrt/issues/11466)

CI 通过只能证明工程/构建检查通过；**启动、交换机端口、双频稳定、代理、广告过滤、断电恢复与救援，必须在真机验证**。至少按验收表连续运行 72 小时后，再决定实际采用哪版。
