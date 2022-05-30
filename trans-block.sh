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

# Restart related torrents immediately if leechers detected
RESTART_TORRENT=true

error() { echo "$@" >&2; }

pattern=$(echo "$CLIENTS" | xargs | sed 's/ /\\)\\|\\(/g')
pattern="\(\($pattern\)\)"

trans_reload() {
  error "Reloading"
  # reload: https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md#reload-settings
  killall -HUP transmission-daemon
}

block_leechers() {
  # error "Checking leechers for: $(echo "$1" | cut -c -8)"
  peers=$(transmission-remote "$HOST" --auth "$AUTH" --torrent "$1" --info-peers)
  leechers=$(echo "$peers" | grep -i "$pattern")
  result=1

  while IFS= read -r leecher; do
    [ -z "$leecher" ] && continue
    # https://en.wikipedia.org/wiki/PeerGuardian#P2P_plaintext_format
    client=$(echo "$leecher" | awk '{ print $6 }')
    client=$(echo "$leecher" | grep -o -- "$client.*$")
    ip=$(echo "$leecher" | awk '{ print $1 }')
    line="$client:$ip-$ip"
    grep -qs -- "$line" "$LIST" && continue
    error "Blocking for $(echo "$1" | cut -c -8):"
    echo "$line"
    echo "$line" >>"$LIST"
    result=0
  done <<EOF
$leechers
EOF

  return $result
}

trans_restart_torrent() {
  error "Restarting torrent: $(echo "$1" | cut -c -8)"
  retry=0
  while [ $retry -lt 3 ]; do
    if transmission-remote "$HOST" --auth "$AUTH" --torrent "$1" --stop | grep -qs success; then
      break
    fi
    sleep 1
    : $((retry += 1))
  done
  sleep 3
  retry=0
  while [ $retry -lt 3 ]; do
    if transmission-remote "$HOST" --auth "$AUTH" --torrent "$1" --start | grep -qs success; then
      break
    fi
    sleep 1
    : $((retry += 1))
  done
}

start=$(date +%s)
while true; do
  diff=$(($(date +%s) - start))
  if [ $TIMEOUT_SECONDS -ne 0 ] && [ $diff -ge $TIMEOUT_SECONDS ]; then
    error "Clearing blocklist"
    rm -f "$LIST"
    rm -f "$BIN"
    start=$(date +%s)
    trans_reload
  fi

  hashes=$(transmission-remote "$HOST" --auth "$AUTH" --torrent all --info | grep Hash | awk '{ print $2 }')
  for h in $hashes; do
    if block_leechers "$h"; then
      trans_reload
      if [ $RESTART_TORRENT = true ]; then
        trans_restart_torrent "$h"
      fi
    fi
  done

  sleep 30
done
