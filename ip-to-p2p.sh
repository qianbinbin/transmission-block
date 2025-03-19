#!/usr/bin/env sh

# Copyright (c) 2025 Binbin Qian
# All rights reserved. (MIT Licensed)
#
# ip-to-p2p.sh: Download and convert IP addresses to P2P plaintext format
# transmission-block: Block leecher clients and bad IPs for Transmission
# https://github.com/qianbinbin/transmission-block

set -e

GZIP=false
IP_VER=all

USAGE=$(
  cat <<-END
Usage: $0 [OPTION]... [URL]...

Download and convert IP addresses to P2P plaintext format, with CIDR and IPv6
support, e.g.
'193.92.150.2/24' -> 'list@example.com:193.92.150.1-193.92.150.254'.
Requires ipcalc-ng.

Examples:

  # Convert and save files as ./blocklist.p2p.gz and ./blocklist-ipv4.p2p.gz
  $0 --prefix ./blocklist --gzip \\
    --ip-version all --ip-version 4 http://example.com/list

Options:
  -d, --desc <desc>   set the description, i.e. range name of the blocklist
  -g, --gzip          compress with gzip; see also --prefix
  -p, --prefix <path> save files to '<path>[-ipv4 | -ipv6].p2p[.gz]'; always
                      overwrite existing files; must be set
  -v, --ip-version <all | 4 | 6>
                      version of IP addersses; can be used several times; see
                      also --prefix
                      all   IPv4 and IPv6 addresses (default)
                      4     only IPv4 addresses
                      6     only IPv6 addresses
  -h, --help          display this help and exit

Home page: <https://github.com/qianbinbin/transmission-block>
END
)

_error() { printf '%s' "$@" >&2; }
error() { echo "$@" >&2; }
_exit() { error "$USAGE" && exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
  http://* | https://*) URL="$URL $1" && shift ;;
  -d | --desc) { [ -n "$2" ] || _exit; } && DESC="$2" && shift 2 ;;
  -g | --gzip) GZIP=true && shift ;;
  -p | --prefix) { [ -n "$2" ] || _exit; } && PREFIX="$2" && shift 2 ;;
  -v | --ip-version) { [ -n "$2" ] || _exit; } && IP_VER="$(echo "$IP_VER" "$2" | xargs)" && shift 2 ;;
  -h | --help) error "$USAGE" && exit ;;
  *) _exit ;;
  esac
done

[ -z "$PREFIX" ] && error "Please specify --prefix" && _exit
[ -z "$IP_VER" ] && error "No IP version specified" && _exit
URL=$(echo "$URL" | xargs | tr ' ' '\n' | sort -u)
[ -z "$URL" ] && error "No URL specified" && _exit

exist() { command -v "$1" >/dev/null 2>&1; }
exist ipcalc-ng || { error "ipcalc-ng: command not found" && exit 127; }

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
for v in $IP_VER; do
  case "$v" in
  all) OUT="$TMP_DIR/out" ;;
  4) OUT4="$TMP_DIR/out4" ;;
  6) OUT6="$TMP_DIR/out6" ;;
  *) error "$v: unknown IP version" && _exit ;;
  esac
done

cidr_to_p2p() { echo "$2:$(ipcalc-ng --no-decorate --minaddr "$1")-$(ipcalc-ng --no-decorate --maxaddr "$1")"; }
ipv4() { echo "$1" | grep -qs -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$'; }

get_desc() {
  domain=$(echo "$1" | sed -E 's|^https?://([^/:]+).*$|\1|')
  path=$(echo "$1" | sed -E 's|^https?://[^/]+([^?#]*).*$|\1|')
  case "$domain" in
  github.com | raw.githubusercontent.com) echo "$path" | awk -F/ '{ print $NF "@" $3 }' ;;
  *) echo "$(basename "$path")@$domain" ;;
  esac
}

IN="$TMP_DIR/in"
for url in $URL; do
  _error "Downloading $url... "
  curl -fsSL --retry 5 --compressed -o "$IN" "$url"
  error "Done"
  grep -E '^[0-9a-fA-F\.:/]+$' "$IN" >"$IN.tmp" && mv "$IN.tmp" "$IN"
  if [ -n "${DESC+x}" ]; then
    desc="$DESC"
  else
    desc=$(get_desc "$url" | tr ':' '_')
  fi
  count=0
  total=$(wc -l "$IN" | awk '{ print $1 }')
  [ "$total" -eq 0 ] && error "No IP address found, skipping" && continue
  while IFS= read -r cidr; do
    : $((count += 1))
    printf '\rConverting %s... ' "$count/$total" >&2
    entry=$(cidr_to_p2p "$cidr" "$desc") || { error "$cidr: could not convert" && continue; }
    [ -n "$OUT" ] && echo "$entry" >>"$OUT"
    if ipv4 "$cidr"; then
      [ -n "$OUT4" ] && echo "$entry" >>"$OUT4"
    else
      [ -n "$OUT6" ] && echo "$entry" >>"$OUT6"
    fi
    [ $count -eq "$total" ] && error "Done"
  done <"$IN"
done

if [ -n "$OUT" ]; then
  if [ "$GZIP" = true ]; then
    gzip -n "$OUT" && mv "$OUT.gz" "$PREFIX.p2p.gz"
  else
    mv "$OUT" "$PREFIX.p2p"
  fi
fi
if [ -n "$OUT4" ]; then
  if [ "$GZIP" = true ]; then
    gzip -n "$OUT4" && mv "$OUT4.gz" "$PREFIX-ipv4.p2p.gz"
  else
    mv "$OUT4" "$PREFIX-ipv4.p2p"
  fi
fi
if [ -n "$OUT6" ]; then
  if [ "$GZIP" = true ]; then
    gzip -n "$OUT6" && mv "$OUT6.gz" "$PREFIX-ipv6.p2p.gz"
  else
    mv "$OUT6" "$PREFIX-ipv6.p2p"
  fi
fi
