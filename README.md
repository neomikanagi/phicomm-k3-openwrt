# 斐讯 K3：OpenWrt + AC88U 无线固件 + PassWall2 + AdGuard Home

官方 OpenWrt 25.12.6，只加了 PassWall2（Xray + nftables）、AdGuard Home 和 USB 上网驱动。**未经真机验证**，刷之前先备好救砖手段。只能刷 K3，不能刷 K3C。

[下载固件](https://github.com/neomikanagi/phicomm-k3-openwrt/actions/workflows/build.yml)：打开最新成功的任务，在页面底部 Artifacts 下载，解压后 `sha256sum -c SHA256SUMS`。保留 90 天，过期后点 Run workflow 重新编译。

## 刷机

已是 OpenWrt（管理地址 `192.168.1.1`）：

```sh
sysupgrade -T k3-openwrt-25.12.6-squashfs.trx   # 不通过就停，不要加 -F
sysupgrade -n k3-openwrt-25.12.6-squashfs.trx
```

原厂或梅林：用你现有的 TTL/CFE 方式刷这个 `.trx`，别往原系统的升级页上传。不要擦 NVRAM，无线校准数据在里面。

## 无线

驱动是 OpenWrt 自带的 brcmfmac，芯片固件换成 AC88U 提取的 `10.10.122.303`，和 Lean LEDE 内置的是同一个文件。OpenWrt 自带的固件停在 2018 年，不提供该版本。梅林的 `dhd.ko` 绑定旧内核，用不到 6.12 上，所以这不是梅林驱动，能否达到梅林的表现要实测。

Wi-Fi 默认关闭，在 LuCI 里设好国家和 WPA2 密码后开启。信道不要留 auto：2.4G 选 1/6/11，5G 选 36。国家码不会下发到无线固件（驱动没有 BCM4366 的映射表），实际可用信道以 `iw phy` 为准。

不重刷也能换芯片固件，[其他版本在这里](https://github.com/xiangfeidexiaohuo/Phicomm-K3_Wireless-Firmware)：

```sh
scp -O brcmfmac4366c-pcie.bin root@192.168.1.1:/lib/firmware/brcm/   # 然后重启
cp /rom/lib/firmware/brcm/brcmfmac4366c-pcie.bin /lib/firmware/brcm/  # 恢复内置版本，然后重启
```

## USB 上网

插 SIM 卡的上网棒、4G/5G modem、安卓共享、iPhone 共享的驱动都已内置。插上后在 LuCI → 网络 → 接口 → 添加新接口，防火墙区域选 `wan`，设备在下拉框里选：

| 设备 | 协议 |
|---|---|
| HiLink / RNDIS 上网棒、安卓共享、iPhone 共享 | DHCP 客户端 |
| QMI 或 MBIM 上网棒 | QMI 蜂窝 / MBIM 蜂窝，填 APN |
| 华为 NCM 上网棒 | NCM，填 APN |
| 老式串口拨号棒 | UMTS/GPRS/EV-DO，填 APN |

iPhone 要先解锁、点信任、打开个人热点。上网棒自身也是 `192.168.1.x` 时，先把 LAN 改到别的网段。

## PassWall2

服务 → PassWall2，导入自己的节点后开启，默认不启用。开了访问控制（ACL）的话，下面的 `k3-adguard enable` 会拒绝执行，因为 ACL 会绕过 AdGuard。

## AdGuard Home

默认不启用，普通上网不受影响。WAN 通了之后：

```sh
/etc/init.d/adguardhome start
```

打开 `http://192.168.1.1:3000` 走向导：设账号密码，管理端口留 `3000`，DNS 端口填 `5353`，不要开它的 DHCP。然后：

```sh
k3-adguard enable    # 接管 53 端口，验证失败自动回滚
k3-adguard disable   # 关闭并恢复 dnsmasq，账号和规则保留
```

接管后的路径是 `客户端 → AdGuard :53 → dnsmasq :5053 → PassWall2 / WAN DNS`。规则缓存放在内存里减少 NAND 写入，重启后会重新下载。

## 其他

排查问题跑 `k3-check`，会输出板型、无线固件、USB、DNS 状态。上机验证按[验收表](docs/acceptance.md)。

无线固件是厂商闭源文件，不在本仓库，构建时从固定提交下载并校验 SHA-256，再分发许可未审定。版本锁定在 [sources.lock.json](sources.lock.json)；本仓库代码以 GPL-2.0-only 发布。
