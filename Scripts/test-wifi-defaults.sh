#!/bin/bash
# 99-athena-wifi 的自检：射频分类逻辑一旦写错，表现是刷完机 5G 全瞎，
# 而那时候已经在路由器上了、很难查。所以在本机先跑一遍。
#
#   bash Scripts/test-wifi-defaults.sh
#
# 做法：把脚本里的绝对路径重定向到临时目录，用假的 uci / sysfs 喂进去。

set -eu
SRC="$(cd "$(dirname "$0")/.." && pwd)/Files/etc/uci-defaults/99-athena-wifi"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---- 假 uci：一行一个 key=value ----
mkdir -p "$WORK/bin"
cat > "$WORK/bin/uci" <<'STUB'
#!/bin/sh
[ "$1" = "-q" ] && shift
cmd=$1; shift
case "$cmd" in
show)   cat "$UCI_DB" ;;
get)    v=$(grep "^$1=" "$UCI_DB" | head -1 | cut -d= -f2-)
        [ -n "$v" ] || exit 1
        echo "$v" ;;
set)    k=${1%%=*}
        grep -v "^$k=" "$UCI_DB" > "$UCI_DB.t" || true
        echo "$1" >> "$UCI_DB.t"
        mv "$UCI_DB.t" "$UCI_DB" ;;
commit) : ;;
esac
STUB
cat > "$WORK/bin/sleep" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$WORK/bin/uci" "$WORK/bin/sleep"
export PATH="$WORK/bin:$PATH"

# ---- 把绝对路径改到沙箱里 ----
ROOT="$WORK/root"
mkdir -p "$ROOT/etc/config" "$ROOT/sbin"
sed -e "s#/etc/config/wireless#$ROOT/etc/config/wireless#g" \
    -e "s#/sys/class/ieee80211#$ROOT/sys/class/ieee80211#g" \
    -e "s#/sbin/wifi#$ROOT/sbin/wifi#g" "$SRC" > "$WORK/script.sh"
printf '#!/bin/sh\nexit 0\n' > "$ROOT/sbin/wifi"
chmod +x "$ROOT/sbin/wifi"

PASS=0
FAIL=0
check() { # check <说明> <期望> <实际>
	if [ "$2" = "$3" ]; then
		PASS=$((PASS + 1))
		printf '  ok   %s\n' "$1"
	else
		FAIL=$((FAIL + 1))
		printf '  FAIL %s: 期望 %s, 实际 %s\n' "$1" "$2" "$3"
	fi
}
run() { UCI_DB="$WORK/db" sh "$WORK/script.sh"; }
val() { grep "^$1=" "$WORK/db" | head -1 | cut -d= -f2-; }

# ---- 用例 1：三块射频齐全，QCN9074 在 PCIe 上 ----
echo "用例1 三射频齐全"
cat > "$WORK/db" <<'EOF'
wireless.radio0=wifi-device
wireless.radio0.band=2g
wireless.radio0.path=platform/soc/c000000.wifi
wireless.radio1=wifi-device
wireless.radio1.band=5g
wireless.radio1.path=platform/soc/c000000.wifi+1
wireless.radio2=wifi-device
wireless.radio2.band=5g
wireless.radio2.path=pci0000:00/0000:00:00.0/0000:01:00.0
wireless.default_radio0=wifi-iface
wireless.default_radio1=wifi-iface
wireless.default_radio2=wifi-iface
EOF
touch "$ROOT/etc/config/wireless"
echo x > "$ROOT/etc/config/wireless"
run
check "2.4G 启用"          "0"      "$(val wireless.radio0.disabled)"
check "2.4G 信道 11"       "11"     "$(val wireless.radio0.channel)"
check "2.4G HT20"          "HT20"   "$(val wireless.radio0.htmode)"
check "2.4G SSID"          "N_2.4G" "$(val wireless.default_radio0.ssid)"
check "内置 5G 启用"        "0"      "$(val wireless.radio1.disabled)"
check "内置 5G 信道 149"    "149"    "$(val wireless.radio1.channel)"
check "内置 5G SSID"        "N_5G"   "$(val wireless.default_radio1.ssid)"
check "QCN9074 启用"       "0"        "$(val wireless.radio2.disabled)"
check "QCN9074 信道 44"    "44"       "$(val wireless.radio2.channel)"
check "QCN9074 HE80"       "HE80"     "$(val wireless.radio2.htmode)"
check "QCN9074 SSID"       "N_5G_QCN" "$(val wireless.default_radio2.ssid)"
check "QCN9074 功率"       "24"       "$(val wireless.radio2.txpower)"
check "QCN9074 国家码"     "US"       "$(val wireless.radio2.country)"

# 回归点：早先版本会自动关掉一块 5G，结果把唯一能用的那块关了。
check "没有任何射频被禁用" "" "$(grep -h '\.disabled=1$' "$WORK/db")"

# 回归点：ACS 会选到 DFS 信道(52-144)，ath11k 的 CAC 起不来 → SSID 完全搜不到
for r in radio0 radio1 radio2; do
	ch=$(val wireless.$r.channel)
	dfs=no
	[ "$ch" -ge 52 ] 2>/dev/null && [ "$ch" -le 144 ] && dfs=yes
	check "$r 信道 $ch 非 DFS" "no" "$dfs"
done

# ---- 用例 2：QCN9074 没起来，只剩内置 5G ----
echo "用例2 QCN9074 缺席，内置 5G 照常配置"
cat > "$WORK/db" <<'EOF'
wireless.radio0=wifi-device
wireless.radio0.band=2g
wireless.radio0.path=platform/soc/c000000.wifi
wireless.radio1=wifi-device
wireless.radio1.band=5g
wireless.radio1.path=platform/soc/c000000.wifi+1
wireless.default_radio0=wifi-iface
wireless.default_radio1=wifi-iface
EOF
run
check "内置 5G 启用"        "0"      "$(val wireless.radio1.disabled)"
check "内置 5G 信道 149"    "149"    "$(val wireless.radio1.channel)"
check "内置 5G SSID"        "N_5G"   "$(val wireless.default_radio1.ssid)"

# ---- 用例 3：wireless 配置生不出来，必须返回非 0 让 uci-defaults 保留脚本重试 ----
echo "用例3 wireless 配置缺失时退出码非 0"
: > "$ROOT/etc/config/wireless"
: > "$WORK/db"
set +e
UCI_DB="$WORK/db" sh "$WORK/script.sh" >/dev/null 2>&1
RC=$?
set -e
check "退出码非 0" "1" "$([ $RC -ne 0 ] && echo 1 || echo 0)"

echo
echo "通过 ${PASS}，失败 ${FAIL}"
[ "$FAIL" -eq 0 ]
