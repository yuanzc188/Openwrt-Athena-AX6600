#!/bin/bash
# 在 wrt/ 根目录执行：编译期写死默认值。
# 放这里而不是 uci-defaults 的理由：编译期改源码不受首次启动的执行顺序影响，
# 出错会直接体现在编译日志里，比刷完机才发现要好排查。

set -e

# ---------- LAN 地址与主机名 ----------
CFG_GEN="./package/base-files/files/bin/config_generate"
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_GEN"
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_GEN"
echo "LAN IP -> $WRT_IP, hostname -> $WRT_NAME"

# ---------- root 密码 ----------
# 直接写 SHA-512 hash 进 shadow，不依赖首次启动跑 passwd。
# 用 awk 按字段替换：hash 里含 $ 和 /，sed 转义太容易出错。
SHADOW="./package/base-files/files/etc/shadow"
HASH=$(openssl passwd -6 "$WRT_PW")
awk -v h="$HASH" 'BEGIN { FS = OFS = ":" } $1 == "root" { $2 = h } 1' "$SHADOW" > "$SHADOW.new"
mv -f "$SHADOW.new" "$SHADOW"
echo "root password set"

# ---------- WiFi 默认值（兜底） ----------
# 每台 radio 不同的参数（信道/频宽/关哪个）在 Files/etc/uci-defaults/99-athena-wifi 里做，
# 这里只改所有 radio 共用的默认值，作为那个脚本万一没跑成时的兜底。
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_UC" ]; then
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g"        "$WIFI_UC"
	sed -i "s/key='.*'/key='$WRT_WORD'/g"          "$WIFI_UC"
	sed -i "s/country || 'CN'/country || '$WRT_COUNTRY'/g" "$WIFI_UC"
	echo "wifi defaults patched: $WIFI_UC"
else
	echo "WARN: $WIFI_UC not found, wifi defaults left untouched" >&2
fi

# ---------- 默认主题设为 Argon ----------
# 光在 .config 里选 argon 不够：luci 集合包仍然会拉 bootstrap，
# 谁的 postinst 后跑谁就是默认主题。这里直接把集合里的 bootstrap 换成 argon。
find ./feeds/luci/collections/ -type f -name Makefile \
	-exec sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' {} +
echo "default theme -> argon"

# ---------- 去掉 attendedsysupgrade ----------
find ./feeds/luci/collections/ -type f -name Makefile -exec sed -i '/attendedsysupgrade/d' {} +

# ---------- 状态页加上编译标识 ----------
find ./feeds/luci/modules/luci-mod-status/ -type f -name 10_system.js \
	-exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +

# ---------- 内存水位线 ----------
# IPQ60xx + NSS 在 1GB 机器上默认水位偏低，高负载时容易 OOM。抬到 16MB。
SYSCTL="./package/base-files/files/etc/sysctl.conf"
if grep -q '^vm\.min_free_kbytes=' "$SYSCTL"; then
	sed -i 's/^vm\.min_free_kbytes=.*/vm.min_free_kbytes=16384/' "$SYSCTL"
else
	echo "vm.min_free_kbytes=16384" >> "$SYSCTL"
fi

# ---------- 移除国内镜像源（Actions 在境外，走国内源反而慢/失败） ----------
[ -f ./scripts/projectsmirrors.json ] && sed -i '/\.cn\//d; /tencent/d; /aliyun/d' ./scripts/projectsmirrors.json

echo "Settings.sh done"
