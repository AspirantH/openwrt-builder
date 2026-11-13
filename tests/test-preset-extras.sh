#!/bin/sh
set -eu
sc="$(dirname "$0")/../scripts/preset-extras.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# fixture mirrors the workspace layout: openwrt/ and builder/ are siblings
mkdir -p "$tmp/openwrt/package/custom/fakesrc/openlist/files" \
         "$tmp/builder/firmware"
echo hi > "$tmp/openwrt/package/custom/fakesrc/openlist/Makefile"
owrt="$tmp/openwrt"

STUB="$tmp/bin"
mkdir -p "$STUB"
cat > "$STUB/7z" <<'EOF'
#!/bin/sh
case "$1" in
  a) : > "$3"; exit 0 ;;
esac
[ "$1" = x ] || exit 2
pass=$(printf '%s' "$2" | sed 's/^-p//')
[ "$pass" = "secret123" ] || exit 2
outdir=
for a in "$@"; do case "$a" in -o*) outdir=${a#-o} ;; esac; done
mkdir -p "$outdir"
printf 'SQLite format 3\x00payload' > "$outdir/data.db"
printf 'top\n' > "$outdir/shadow"
EOF
chmod +x "$STUB/7z"

printf 'stub' > "$tmp/builder/firmware/plain"
( cd "$tmp/builder/firmware" \
  && "$STUB/7z" a -psecret123 e.7z plain >/dev/null && mv e.7z etc.7z \
  && "$STUB/7z" a -psecret123 d.7z plain >/dev/null && mv d.7z data.db )
printf 'stale-from-source-repo' > "$owrt/package/custom/fakesrc/openlist/files/data.db"

# case 1: nothing to do
printf '%s\n' 'CONFIG_PACKAGE_luci=y' > "$owrt/.config"
mv "$tmp/builder/firmware/etc.7z" "$tmp/e.parked"
mv "$tmp/builder/firmware/data.db" "$tmp/d.parked"
env -u DB_PASS PATH="$STUB:$PATH" sh "$sc" "$owrt" >/dev/null 2>&1 \
  || { echo "FAIL: must no-op when nothing applies"; exit 1; }
mv "$tmp/e.parked" "$tmp/builder/firmware/etc.7z"
mv "$tmp/d.parked" "$tmp/builder/firmware/data.db"

# case 2
printf '%s\n' 'CONFIG_PACKAGE_openlist=y' > "$owrt/.config"
DB_PASS=secret123 PATH="$STUB:$PATH" sh "$sc" "$owrt" >/dev/null
[ -f "$owrt/files/etc/shadow" ] || { echo "FAIL: etc archive not extracted"; exit 1; }
[ "$(cat "$owrt/files/etc/shadow")" = "top" ] \
  || { echo "FAIL: extracted etc content is wrong"; exit 1; }
db="$owrt/package/custom/fakesrc/openlist/files/data.db"
grep -aq 'payload' "$db" || { echo "FAIL: preset db not installed"; exit 1; }
grep -q 'stale-from-source-repo' "$db" \
  && { echo "FAIL: package's own db was not replaced"; exit 1; }
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *) [ "$(stat -c %a "$owrt/files/etc/shadow")" = "600" ] \
       || { echo "FAIL: shadow not 600"; exit 1; } ;;
esac

# case 3
mv "$tmp/builder/firmware/data.db" "$tmp/d.parked"
printf 'stub' > "$db"
if DB_PASS=secret123 PATH="$STUB:$PATH" sh "$sc" "$owrt" >/dev/null 2>&1; then
  echo "FAIL: missing firmware/data.db must fail"; exit 1
fi
mv "$tmp/d.parked" "$tmp/builder/firmware/data.db"

# case 4
if DB_PASS=nope PATH="$STUB:$PATH" sh "$sc" "$owrt" >/dev/null 2>&1; then
  echo "FAIL: wrong password must fail"; exit 1
fi

# case 5
if env -u DB_PASS PATH="$STUB:$PATH" sh "$sc" "$owrt" >/dev/null 2>&1; then
  echo "FAIL: missing DB_PASS must fail"; exit 1
fi
echo "PASS: test-preset-extras"
