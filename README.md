# 京东云雅典娜 AX6600 OpenWrt 云编译

设备：JDCloud RE-CS-02 / IPQ6010 + QCN9074 / 1GB DDR4 / 128GB eMMC

预装：PassWall2、点阵屏管理（athena-led）、Argon 主题、NSS 硬件加速。
没有 OpenClash / Docker / AdGuard 那一堆。

## 之前为什么不能用

`openwrt.ai` 在线编译的固件在雅典娜上跑不起来，是已知问题，不是配置写错。
表现有两种，取决于版本：机器直接无限重启，或者能开机、WiFi 能连但上不了网、IP 不对。
两种都是同一个根：**那个分支对 RE-CS-02 的适配不完整**。

设备在正确源码里的 image recipe 写死了三个必需件：

```
DEVICE_PACKAGES := ipq-wifi-jdcloud_re-cs-02 ath11k-firmware-qcn9074-ddwrt \
                   luci-app-athena-led luci-i18n-athena-led-zh-cn
```

- `ath11k-firmware-qcn9074-**ddwrt**`：雅典娜这块 QCN9074 要 DD-WRT 变体的固件，通用版加载不了
- `ipq-wifi-jdcloud_re-cs-02`：board-2.bin 射频校准数据

openwrt.ai 的分支这两样对不上 → QCN9074 probe 失败。它也没有 athena-led 和 NSS，
"点阵屏 + 稳定性能优"这个需求它本来就满足不了。

**"能开机但上不了网、IP 不对"还多一层**：网口映射。正确源码里 RE-CS-02 的
`board.d/02_network` 是

```
jdcloud,re-cs-02) ucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" "wan" ;;
```

分支里没这条时会走默认，WAN 口认不出来 → 路由器自己没外网、DHCP 也不对 →
WiFi 连上拿不到正确 IP、上不了网。跟你描述的一模一样。这条改配置改不出来，只能换源码。

## 你原来那段 uci 脚本的问题

`uci set wireless.radio0/1/2.*` 放在 uci-defaults 里是错的，两个原因：

1. **执行时机**：uci-defaults 跑在 `/etc/init.d/wireless` 之前，那时 `/etc/config/wireless`
   还不存在。直接 `uci set` 会凭空造出一份没有 `type` / `path` 的残缺配置；
   随后 `wifi config` 认不出这几个 section，会再追加 radio3/4/5。结果是 hostapd 起不来、
   wpad 反复重启 —— 看起来就像"刷完机崩溃"。
2. **编号不固定**：AHB（IPQ6010 内置）和 PCIe（QCN9074）的探测顺序不保证，
   radio0/1/2 谁是谁会变。你按编号关掉的"5.2G 游戏频段"，有可能正好是 QCN9074 那块
   4×4 160MHz 的主力射频 —— 跟"性能优"是反的。

改法见 `Files/etc/uci-defaults/99-athena-wifi`：先把 wireless 正常生成出来，
再按 **band + path** 匹配（PCIe 的一定是 QCN9074），跟编号无关。
本机跑 `bash Scripts/test-wifi-defaults.sh` 可以验证这段分类逻辑。

`passwd <<EOF` 也换掉了：改成编译期直接写 SHA-512 hash 进 `package/base-files/files/etc/shadow`，
不依赖首次启动，写错了编译日志里就能看到。

## 怎么用

1. 新建一个 GitHub 仓库，把这个目录的内容推上去
2. Settings → Actions → General → Workflow permissions 选 **Read and write**
3. Actions → `Build-AX6600` → Run workflow
   - 第一次建议先勾 `TEST`，只生成 `.config` 不编译（几分钟），确认配置没问题
   - 然后取消勾选正式编译（约 1.5～2 小时，带 cache 后半小时左右）
4. 产物在 Releases 里

改定制值：直接改 `.github/workflows/Build.yml` 顶部的 `env:` 段。

| 变量 | 当前值 | 作用 |
|---|---|---|
| `WRT_IP` | `192.168.5.1` | LAN 口地址 |
| `WRT_PW` | `qwertyuiop` | root 后台密码 |
| `WRT_NAME` | `Athena` | 主机名 |
| `WRT_WORD` | `11111111` | WiFi 密码 |
| `WRT_COUNTRY` | `US` | 国家码 |

信道 / 频宽 / SSID 在 `Files/etc/uci-defaults/99-athena-wifi` 顶部改。

## 刷机

- 从原厂或其它系统首刷：`*factory.bin`
- 已经是本固件升级：`*sysupgrade.bin`
- U-Boot / TTL / 9008 救砖流程参考
  [ones20250/Openwrt-AX6600 的刷机救砖教程](https://github.com/ones20250/Openwrt-AX6600/blob/main/Docs/刷机救砖教程.md)

## 刷完先做一件事

```sh
ssh root@192.168.5.1 'sh /root/wifi-info.sh'
```

打印三块射频各自的 path、band、以及**实际支持的信道**。
现在 5G 默认 `channel=auto`（让 ACS 自己选合法且最干净的信道）。
如果你确认那块射频支持 UNII-3，想固定到 149：

```sh
uci set wireless.radioX.channel=149
uci commit wireless && wifi reload
```

不要凭猜写死 149 —— QCN9074 在这台机器上覆盖哪个子频段取决于 board-2.bin 校准数据，
设了不支持的信道 hostapd 直接起不来，5G 就没了。

## 目录

```
Config/AX6600.txt                       编译配置
Scripts/Packages.sh                     拉 PassWall2（athena-led 源码已内置，不用拉）
Scripts/Settings.sh                     编译期定制：IP / 主机名 / root 密码 / WiFi 默认值 / 默认主题
Scripts/test-wifi-defaults.sh           射频分类逻辑自检
Files/etc/uci-defaults/99-athena-wifi   首启动无线配置
Files/root/wifi-info.sh                 射频实况查看
.github/workflows/Build.yml             云编译
```

上游源码：[ones20250/immortalwrt_ipq](https://github.com/ones20250/immortalwrt_ipq)
（athena-led 在 `package/emortal/luci-app-athena-led`，已内置）
