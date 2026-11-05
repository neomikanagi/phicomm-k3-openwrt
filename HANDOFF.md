# 多 AI 交接

## 2026-11-05 — claudecode → 无

- **状态：** 审查并修正上一棒的工程。云编译成功：https://github.com/neomikanagi/phicomm-k3-openwrt/actions/runs/42029161396 ，`k3-openwrt-25.12.6-squashfs.trx` 38.6 MiB，SHA-256 `fbeecc49100520960cc5345df4d444a044ddb039cff6aa3f3d0d3a96408a4231`。已解开镜像核对：无线固件哈希和版本正确，USB 驱动及自动加载、usbmuxd、四种 LuCI 协议都在。没有 K3 真机，启动、无线、USB、代理均未上机验证。失败的 run 42014346526 里留有一个 `official` 包，是旧产物，不要用。
- **改了：** 去掉 OpenWrt 自带无线固件版，只出一个镜像；无线固件从 `ac88.48260` 换成 `ac88_3`；加入 SIM 上网棒、modem、安卓和 iPhone 共享驱动及 LuCI 协议；修 `k3-adguard` 的 DHCP DNS；删掉首次启动的无线设置；去掉 htop、USB 存储、ext4；README 和验收表重写。`config/k3.config` 现在是唯一包清单，`validate-config.sh` 和 `collect.sh` 都从它读。CI 改为 nproc 并行、失败后串行重试，新推送取消旧任务，固件保留 90 天。
- **为什么·思路：**
  - **AC88 替换此前从未生效：** 上一棒的 `perl -0pi 's#\Q\$(...)\E#...#'` 里 `\Q\$` 匹配字面反斜杠，退出 0 但不改文件。run 42014346526 的 ac88 编译 1.5 小时后才被 `collect.sh` 的哈希校验拦下，镜像里是 linux-firmware 原版。改为 `scripts/patch-wifi-firmware.sh`（前后置校验 + 离线测试）。**不要删 `collect.sh` 的 rootfs 哈希校验**，它是最后一道防线。
  - **开源无线没追平：** linux-firmware 的 4366c 固件从 2018-12 起没更新（10.28.2）；开源的只有 brcmfmac 这层，MAC/PHY 都在闭源固件里；K3 用户对自带固件的反馈偏差。论坛对换 AC88 固件也有一例「仍不稳定」（2020），所以不能承诺追平梅林。
  - **固件选 `ac88_3`：** 与 Lean LEDE `k3wifi` 字节相同，Lean 的 bcm53xx 默认内核已是 6.18，是目前查到的最强实测证据。`.48260` 同为 10.10.122.303（r666429），只是 2021 年的重编译版，没查到 K3 实测，留作上机对比的备选。未核实 `.48260` 是否含 FragAttacks 修复，这是 `ac88_3` 的潜在代价。
  - **DHCP：** dnsmasq 离开 53 端口后不再下发 DNS（`rfc2131.c`：`daemon->port == NAMESERVER_PORT`），旧版 `enable` 后客户端续租就断 DNS，而健康检查只查路由器本机发现不了。已在隔离 netns 用真 dnsmasq + udhcpc 复现并验证 `dhcp_option=6,0.0.0.0`（0.0.0.0 表示 dnsmasq 本机地址，LAN 改 IP 也不用动）。
  - **不要还原 `ifname=wlan0/wlan1`：** 25.12 的 `common.uc` `wdev_create` 已通过 `find_reusable_wdev` 复用并重命名 FullMAC 主接口。旧写法还有两个问题：`99-k3` 跑时 brcmfmac 可能还没注册无线设备（固件异步加载），设置被跳过却已写标记；phy/wlan 序号互换时 `ifname` 会指错网卡。无线默认值全交官方，接口默认就是 disabled。
  - **国家码：** BCM4366 不在 `brmcf_use_iso3166_ccode_fallback` 名单，K3 也没有 ccode 映射，UCI `country` 到不了固件，固件的 ccode 来自 NVRAM。没真机不敢打内核补丁改射频行为，README 已写明。
- **已验证：** 22 项 Python 测试、ShellCheck、Lua 配置转换；AdGuard 0.107.79 在隔离 netns 同时绑定 `0.0.0.0` 和 `::` 能正常启动；`dns_redirect=0` 时 PassWall2 不生成 53 重定向（`dns_redirect_port` 为空），不会绕过 AdGuard。
- **请你：** 无。

## 2026-11-05 — pi（gpt-6.1-sol）→ 无

- **状态：** 工程已上传 https://github.com/neomikanagi/phicomm-k3-openwrt 。最新构建 https://github.com/neomikanagi/phicomm-k3-openwrt/actions/runs/42014346526 ：云端测试成功，official/ac88 都已通过实际 make defconfig、选包检查和准备阶段，正在下载/构建依赖；最终镜像尚未产出。旧任务已取消避免重复。没有 K3 真机，不能声称无线稳定或刷机已验收。
- **构建注意：** 仅安装所需 feed 闭包，避免无关 weechat Kconfig 循环；开启 LUCI_LANG_zh_Hans 才能保留隐藏翻译包。Xray 26.10.31 要 Go 1.27，选同一官方 feed 内置的编译器；改 golang-values.mk 后必须 touch stub Makefile、刷新 index 并显式安装 golang1.27，不能退回默认 1.26 或沿用缓存 metadata。
- **改了：** 官方 OpenWrt 25.12.6 / 固定 feeds + PassWall2/Xray/nftables + 官方 AdGuard Home。Actions 并行编译 official/ac88；AC88 只替换芯片 firmware，不混装旧梅林内核模块。源码提交、第三方二进制哈希锁在 sources.lock.json。编译后从 profiles.json 核对型号/版本并取实际文件名（本地构建不一定有版本前缀），再检查选包、TRX、rootfs、blob 和生成来源清单。
- **为什么·思路：** BCM4366 无线无法通过拷贝闭源 wl/dhd.ko 解决新内核 ABI；保留官方内核，提供原版和有 K3 使用案例的 AC88 firmware 两条候选作 A/B。单核心、无 offloading、不设共享 Wi-Fi 密码、保留官方 WAN/分区，优先降低故障面。AC88 再分发许可未审定，不往 git 放二进制。
- **DNS：** 初始 dnsmasq:53、AGH 禁自启；向导先设 AGH:5353 和个人密码，再 k3-adguard enable 安全接管为双栈 AGH:53 → dnsmasq:5053 → PassWall2 DNS，避免 RA/DHCPv6 广告的 DNS 失联。拒绝无密码/ACL/自定义端口，故障恢复原配置；日志/统计关闭，运行数据 tmpfs；AGH memlimit 写 104857600（官方 init 原样传给 GOMEMLIMIT，实际是字节，不能按错误注释改成 100）。不要把 PW 的 direct DNS 指回 AGH:53，也不要打开 PW DNS 重定向/ACL 后声称全流量已过滤。首次默认值设 /etc/config/k3 标记，保留配置升级时不重关用户无线/代理。
- **验收：** Shell 语法、ShellCheck、16 项 Python 契约/启停回退/成品收集测试、原生 Lua 5.1 + lyaml round-trip 通过；转换后样例也通过官方 AdGuard Home 0.107.79 --check-config（绝对路径、离线，无常驻服务）。CI 独立重跑。真实启动、端口、双频、代理节点、过滤及 72h 长稳全部未测，见 docs/acceptance.md。
- **请你：** 无。后续真实刷机前必须核对 K3/K3C、当前 CFE/分区及恢复路径，不允许 -F 强刷；编译成功不能改称“硬件已稳定”。
