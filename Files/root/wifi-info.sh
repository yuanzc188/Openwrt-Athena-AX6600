#!/bin/sh
# 刷完机跑一次，看清楚三块射频到底是谁、支持哪些信道，再决定要不要手动定信道。
# 用法：ssh root@192.168.5.1 'sh /root/wifi-info.sh'

echo "===== UCI 里的无线设备 ====="
for dev in $(uci show wireless | sed -n 's/^wireless\.\([^.]*\)=wifi-device$/\1/p'); do
	path=$(uci -q get "wireless.$dev.path")
	[ -n "$path" ] || path="(phy=$(uci -q get "wireless.$dev.phy"))"

	case "$path" in
	*pci*) kind='QCN9074 / PCIe / 4x4' ;;
	*)     kind='IPQ6010 内置 / AHB / 2x2' ;;
	esac

	printf '%s  [%s]\n' "$dev" "$kind"
	printf '  band=%s  channel=%s  htmode=%s  country=%s  txpower=%s  disabled=%s\n' \
		"$(uci -q get "wireless.$dev.band")" \
		"$(uci -q get "wireless.$dev.channel")" \
		"$(uci -q get "wireless.$dev.htmode")" \
		"$(uci -q get "wireless.$dev.country")" \
		"$(uci -q get "wireless.$dev.txpower")" \
		"$(uci -q get "wireless.$dev.disabled")"
	printf '  path=%s\n' "$path"
done

echo
echo "===== 各 phy 实际支持的信道（按 path 和上面对号入座）====="
for p in /sys/class/ieee80211/phy*; do
	[ -d "$p" ] || continue
	name=$(basename "$p")
	printf '%s  path=%s\n' "$name" "$(readlink -f "$p/device" | sed 's|^/sys/devices/||')"
	iw phy "$name" info 2>/dev/null \
		| sed -n 's/^\s*\* \([0-9]\+\) MHz \[\([0-9]\+\)\]\(.*\)/    ch\2  \1MHz \3/p'
done

echo
echo "把 5G 固定到 149："
echo "  uci set wireless.radioX.channel=149 && uci commit wireless && wifi reload"
