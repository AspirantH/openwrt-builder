#!/bin/sh
set -eu
owrt=$1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

fw="$owrt/../builder/firmware"
need=0
[ -f "$fw/etc.7z" ] && need=1
[ -f "$fw/data.db" ] && need=1
grep -qE '^CONFIG_PACKAGE_openlist=[ym]$' "$owrt/.config" 2>/dev/null && need=1
[ "$need" = 1 ] || exit 0

command -v 7z >/dev/null || sudo apt-get -yqq install p7zip-full >/dev/null 2>&1
command -v 7z >/dev/null || { echo "preset-extras: 7z unavailable" >&2; exit 1; }
[ -n "${DB_PASS:-}" ] || { echo "preset-extras: DB_PASS secret is not set" >&2; exit 1; }

if [ -f "$fw/etc.7z" ]; then
  7z x -p"$DB_PASS" -y -o"$tmp/etc" "$fw/etc.7z" >/dev/null \
    || { echo "preset-extras: etc.7z decrypt failed (wrong DB_PASS?)" >&2; exit 1; }
  mkdir -p "$owrt/files/etc"
  cp -a "$tmp/etc/." "$owrt/files/etc/"
  [ -e "$owrt/files/etc/shadow" ] && chmod 600 "$owrt/files/etc/shadow"
  echo "preset-extras: etc.7z -> files/etc/"
fi

grep -qE '^CONFIG_PACKAGE_openlist=[ym]$' "$owrt/.config" 2>/dev/null || exit 0
mk=$(find "$owrt/package/custom" -path '*/openlist/Makefile' 2>/dev/null | head -n1)
[ -n "$mk" ] || { echo "preset-extras: openlist is enabled but its package was not cloned (check packages.ini)" >&2; exit 1; }
[ -f "$fw/data.db" ] \
  || { echo "preset-extras: openlist is enabled but firmware/data.db (the encrypted preset db) is missing" >&2; exit 1; }
7z x -p"$DB_PASS" -y -o"$tmp/db" "$fw/data.db" >/dev/null \
  || { echo "preset-extras: data.db decrypt failed (wrong DB_PASS or not a 7z archive?)" >&2; exit 1; }
[ -f "$tmp/db/data.db" ] || { echo "preset-extras: archive in data.db holds no data.db" >&2; exit 1; }
[ "$(head -c 6 "$tmp/db/data.db")" = "SQLite" ] \
  || { echo "preset-extras: decrypted data.db is not a SQLite database" >&2; exit 1; }
cp "$tmp/db/data.db" "$(dirname "$mk")/files/data.db"
echo "preset-extras: preset openlist db installed from firmware/data.db"
