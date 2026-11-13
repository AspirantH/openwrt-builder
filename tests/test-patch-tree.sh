#!/bin/sh
set -eu
sc="$(dirname "$0")/../scripts/patch-tree.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
owrt="$tmp/owrt"

# fixture: minimal version.mk + luci-mod-system layout as current master has it
mkdir -p "$owrt/include" \
  "$owrt/feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/led-trigger" \
  "$owrt/feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d" \
  "$owrt/feeds/luci/modules/luci-mod-system/root/usr/share/ucitrack" \
  "$owrt/feeds/luci/modules/luci-mod-system/root/usr/share/rpcd/acl.d"

{ printf 'REVISION:=r28941-1a2b3c4d5e\n'
  printf 'VERSION_CODE:=24.10\n'
} > "$owrt/include/version.mk"

printf 'echo view\n' > "$owrt/feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/leds.js"
printf 'echo trigger\n' > "$owrt/feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/led-trigger/heartbeat.js"

{
  printf '{\n'
  printf '\t"admin/system/leds": {\n'
  printf '\t\t"title": "LED Configuration",\n'
  printf '\t\t"order": 70\n'
  printf '\t},\n'
  printf '\t"admin/system/other": {\n'
  printf '\t\t"title": "Custom Commands"\n'
  printf '\t}\n'
  printf '}\n'
} > "$owrt/feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json"

printf '{ "led": { "init": "led", "foo": 1 } }\n' \
  > "$owrt/feeds/luci/modules/luci-mod-system/root/usr/share/ucitrack/luci-mod-system-system.json"
printf '{ "read": { "uci": [ "getLEDs", "getSystemInfo" ] } }\n' \
  > "$owrt/feeds/luci/modules/luci-mod-system/root/usr/share/rpcd/acl.d/luci-mod-system.json"

sh "$sc" "$owrt"

# version.mk: date revision, and VERSION_CODE follows it
grep -qE '^REVISION:=[0-9]{2}\.[0-9]{2}\.[0-9]{4}$' "$owrt/include/version.mk" \
  || { echo "FAIL: REVISION not set to a date"; exit 1; }
grep -q '^VERSION_CODE:=\$(REVISION)$' "$owrt/include/version.mk" \
  || { echo "FAIL: VERSION_CODE not rewired"; exit 1; }

# LED menu gone, sibling menus intact
grep -q '"admin/system/leds"' "$owrt/feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json" \
  && { echo "FAIL: LED menu entry still present"; exit 1; }
grep -q '"admin/system/other"' "$owrt/feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json" \
  || { echo "FAIL: sibling menu entry was collateral damage"; exit 1; }
[ ! -e "$owrt/feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/leds.js" ] \
  || { echo "FAIL: leds.js not removed"; exit 1; }
[ ! -e "$owrt/feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/led-trigger" ] \
  || { echo "FAIL: led-trigger dir not removed"; exit 1; }
grep -q '"init": "led"' "$owrt/feeds/luci/modules/luci-mod-system/root/usr/share/ucitrack/luci-mod-system-system.json" \
  && { echo "FAIL: ucitrack led init still present"; exit 1; }
grep -q '"getLEDs"' "$owrt/feeds/luci/modules/luci-mod-system/root/usr/share/rpcd/acl.d/luci-mod-system.json" \
  && { echo "FAIL: getLEDs ACL still present"; exit 1; }

# a tree without the LED entry must fail loudly, not silently skip
sh "$sc" "$owrt" >/dev/null 2>&1 \
  && { echo "FAIL: re-run on a patched tree must fail (upstream assertion)"; exit 1; } || true
echo "PASS: test-patch-tree"
