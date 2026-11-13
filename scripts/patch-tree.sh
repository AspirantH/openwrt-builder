#!/bin/sh
# patch-tree.sh <openwrt-dir> — source-tree patches that must land BEFORE
# defconfig/config generation, so build.yml runs this right after
# clone-packages.sh and before "Generate config". Unlike a preset hook this
# does not read .config: these edits apply to every build unconditionally.
# Every patch verifies its own effect and dies loudly when upstream moved —
# a silently skipped patch would ship a firmware that differs from this repo's
# declared state, which is the one failure mode this pipeline refuses.
set -eu
owrt=$1

# ---- firmware version: date-based revision -------------------------------
# REVISION normally comes from git-describe of the openwrt tree; here the
# build date is more meaningful. include/version.mk wires it into the banner.
vmk="$owrt/include/version.mk"
[ -f "$vmk" ] || { echo "patch-tree: $vmk missing" >&2; exit 1; }
rev=$(date +%m.%d.%Y)
sed -i -e "/\(# \)\?REVISION:=/c\REVISION:=$rev" \
       -e '/^VERSION_CODE:=/c\VERSION_CODE:=$(REVISION)' "$vmk"
grep -q "^REVISION:=$rev$" "$vmk" || { echo "patch-tree: REVISION patch did not take ($vmk)" >&2; exit 1; }
echo "patch-tree: version revision set to $rev"

# ---- luci-mod-system: strip the LED pages --------------------------------
# x86 has no LEDs; the menu, its JS, the rpcd ACL entries and the ucitrack
# hook are dead weight and a page a user can half-break. Upstream file layout
# is asserted below, so a luci restructure fails the build instead of
# shipping half-stripped menus.
leds="$owrt/feeds/luci/modules/luci-mod-system"
[ -d "$leds" ] || { echo "patch-tree: $leds missing (luci feed layout changed?)" >&2; exit 1; }
menu="$leds/root/usr/share/luci/menu.d/luci-mod-system.json"
grep -q '"admin/system/leds"' "$menu" \
  || { echo "patch-tree: LED menu entry not found in $menu (upstream changed?)" >&2; exit 1; }
rm -rf "$leds/htdocs/luci-static/resources/view/system/leds.js" \
       "$leds/htdocs/luci-static/resources/view/system/led-trigger/"
sed -i '/"admin\/system\/leds": {/,/^	},/d' "$menu"
sed -i '/"fs": { "\/sys\/class\/leds": "directory" }/,/^	},/d' "$menu"
sed -i '/"init": "led",/d' "$leds/root/usr/share/ucitrack/luci-mod-system-system.json"
sed -i 's/"getLEDs", //g' "$leds/root/usr/share/rpcd/acl.d/luci-mod-system.json"
if grep -q '"admin/system/leds"' "$menu"; then
  echo "patch-tree: LED menu survived its own deletion (menu.d layout changed?)" >&2
  exit 1
fi
echo "patch-tree: luci-mod-system LED pages removed"
