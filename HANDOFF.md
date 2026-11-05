# 多 AI 交接

## 2026-11-05 — pi（gpt-6.1-sol）→ 无

- **状态：** 已上传 https://github.com/neomikanagi/phicomm-k3-openwrt 。修复首次 CI 的无关 weechat Kconfig 循环和隐藏翻译丢失后，双版本已通过实际 make defconfig 和选包闸、进入下载源码。补齐双栈 DNS、升级初始化标记，并为 Xray 26.10.31 选择同一官方 feed 已内置的 Go 1.27（默认 1.26 不满足其 go.mod），推送最新构建；旧任务取消避免重复。没有 K3 真机，不能声称无线稳定或刷机已验收。
- **改了：** 官方 OpenWrt 25.12.6 / 固定 feeds + PassWall2/Xray/nftables + 官方 AdGuard Home。Actions 并行编译 official/ac88；AC88 只替换芯片 firmware，不混装旧梅林内核模块。源码提交、第三方二进制哈希锁在 sources.lock.json。编译后从 profiles.json 核对型号/版本并取实际文件名（本地构建不一定有版本前缀），再检查选包、TRX、rootfs、blob 和生成来源清单。
- **为什么·思路：** BCM4366 无线无法通过拷贝闭源 wl/dhd.ko 解决新内核 ABI；保留官方内核，提供原版和有 K3 使用案例的 AC88 firmware 两条候选作 A/B。单核心、无 offloading、不设共享 Wi-Fi 密码、保留官方 WAN/分区，优先降低故障面。AC88 再分发许可未审定，不往 git 放二进制。
- **DNS：** 初始 dnsmasq:53、AGH 禁自启；向导先设 AGH:5353 和个人密码，再 k3-adguard enable 安全接管为双栈 AGH:53 → dnsmasq:5053 → PassWall2 DNS，避免 RA/DHCPv6 广告的 DNS 失联。拒绝无密码/ACL/自定义端口，故障恢复原配置；日志/统计关闭，运行数据 tmpfs；AGH memlimit 写 104857600（官方 init 原样传给 GOMEMLIMIT，实际是字节，不能按错误注释改成 100）。不要把 PW 的 direct DNS 指回 AGH:53，也不要打开 PW DNS 重定向/ACL 后声称全流量已过滤。首次默认值设 /etc/config/k3 标记，保留配置升级时不重关用户无线/代理。
- **验收：** Shell 语法、ShellCheck、16 项 Python 契约/启停回退/成品收集测试、原生 Lua 5.1 + lyaml round-trip 通过；转换后样例也通过官方 AdGuard Home 0.107.79 --check-config（绝对路径、离线，无常驻服务）。CI 独立重跑。真实启动、端口、双频、代理节点、过滤及 72h 长稳全部未测，见 docs/acceptance.md。
- **请你：** 无。后续真实刷机前必须核对 K3/K3C、当前 CFE/分区及恢复路径，不允许 -F 强刷；编译成功不能改称“硬件已稳定”。
