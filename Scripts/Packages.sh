#!/bin/bash
# 在 wrt/package/ 目录下执行：拉取源码树里没有的外部插件。
# athena-led 已内置于 ones20250/immortalwrt_ipq 的 package/emortal/，无需拉取。

set -e

# 拉取插件，同时清掉 feeds 里的同名包，避免重复定义导致 make 失败
UPDATE_PACKAGE() {
	local PKG_NAME=$1 PKG_REPO=$2 PKG_BRANCH=$3 PKG_SPECIAL=$4
	local REPO_NAME=${PKG_REPO#*/}

	echo ">>> $PKG_NAME <- $PKG_REPO@$PKG_BRANCH"

	find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$PKG_NAME*" \
		-exec rm -rf {} + 2>/dev/null || true

	rm -rf "./$REPO_NAME"
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"

	if [ -n "$GITHUB_WORKSPACE" ]; then
		echo "$PKG_NAME $PKG_REPO $PKG_BRANCH $(git -C "$REPO_NAME" rev-parse --short HEAD)" \
			>> "$GITHUB_WORKSPACE/package-versions.txt"
	fi

	# pkg: 从大杂烩仓库里只抽出目标插件目录
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "./$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf "./$REPO_NAME/"
	fi
}

# PassWall2 本体；xray / sing-box / geodata 等依赖由 passwall_packages feed 提供
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"
