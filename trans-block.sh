#!/usr/bin/env sh

HOST="localhost:9091"

AUTH="username:password"

CLIENTS="xunlei thunder gt0002 xl0012 xfplay dandanplay dl3760 qq"

LIST="$HOME/.config/transmission-daemon/blocklists/leechers.txt"
BIN="$LIST.bin"

# Clear blocklist
# 0=disable
# TIMEOUT_SECONDS=$((60 * 60 * 24)) # 24 hours
TIMEOUT_SECONDS=0

error() { echo "$@" >&2; }

pattern=$(echo "$CLIENTS" | xargs | sed 's/ /\\)\\|\\(/g')
pattern="\(\($pattern\)\)"

start=$(date +%s)
while true; do
  diff=$(($(date +%s) - start))
  if [ $TIMEOUT_SECONDS -ne 0 ] && [ $diff -ge $TIMEOUT_SECONDS ]; then
    echo "Clearing blocklist"
    rm -f "$LIST"
    rm -f "$BIN"
    start=$(date +%s)
  fi

  peers=$(transmission-remote "$HOST" --auth "$AUTH" --torrent all --info-peers)
  leechers=$(echo "$peers" | grep -i "$pattern")
  stamp=$(stat -c %y "$LIST")
  echo "$leechers" | while read -r leecher; do
    [ -z "$leecher" ] && continue
    # https://en.wikipedia.org/wiki/PeerGuardian#P2P_plaintext_format
    client=$(echo "$leecher" | grep -i "[^[:space:]]*$pattern.*$" -o)
    ip=$(echo "$leecher" | awk '{ print $1 }')
    line="$client:$ip-$ip"
    grep -qs "$line" "$LIST" && continue
    echo "Blocking: $line"
    echo "$line" >>"$LIST"
  done

  if [ "$(stat -c %y "$LIST")" != "$stamp" ]; then
    # reload: https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md#reload-settings
    echo "Reloading"
    killall -HUP transmission-daemon
  fi
  sleep 30
done
