#!/usr/bin/env sh

HOST="localhost:9091"

AUTH="username:password"

CLIENTS="xunlei thunder gt[[:digit:]]\{4\} xl0012 xf dandanplay dl3760 qq libtorrent"

LIST="$HOME/.config/transmission-daemon/blocklists/leechers.txt"
BIN="$LIST.bin"

# Clear blocklist
# 0=disable
# TIMEOUT_SECONDS=$((60 * 60 * 24)) # 24 hours
TIMEOUT_SECONDS=0

# Restart related torrents immediately if leechers detected
RESTART_TORRENT=true

error() { echo "$@" >&2; }

HASH_SHORT=

error_with_hash_tag() { error "[$HASH_SHORT]" "$@"; }

pattern=$(echo "$CLIENTS" | xargs -0 | sed 's/ /\\)\\|\\(/g')
pattern="\(\($pattern\)\)"

trans_reload() {
  error "Reloading"
  # reload: https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md#reload-settings
  killall -HUP transmission-daemon
}

block_leechers() {
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
    error_with_hash_tag "Blocking leecher"
    if grep -qs -- "$line" "$LIST"; then
      error_with_hash_tag "Duplicate: $line"
    else
      echo "$line"
      echo "$line" >>"$LIST"
    fi
    result=0
  done <<EOF
$leechers
EOF

  return $result
}

trans_restart_torrent() {
  error_with_hash_tag "Restarting"
  retry_max=5
  for _ in $(seq 0 "$retry_max"); do
    if transmission-remote "$HOST" --auth "$AUTH" --torrent "$1" --stop | grep -qs success; then
      break
    fi
    sleep 1
  done
  stopped=false
  for _ in $(seq 0 "$retry_max"); do
    if transmission-remote "$HOST" --auth "$AUTH" --torrent "$1" --info | grep -qs 'State: Stopped'; then
      error_with_hash_tag "Stopped"
      stopped=true
      break
    fi
    sleep 1
  done
  if [ "$stopped" = false ]; then
    error_with_hash_tag "Unable to stop, skipping"
    return 1
  fi

  for _ in $(seq 0 "$retry_max"); do
    if transmission-remote "$HOST" --auth "$AUTH" --torrent "$1" --start | grep -qs success; then
      break
    fi
    sleep 1
  done
  for _ in $(seq 0 "$retry_max"); do
    if transmission-remote "$HOST" --auth "$AUTH" --torrent "$1" --info | grep -qs 'State: Stopped'; then
      sleep 1
      continue
    fi
    error_with_hash_tag "Started"
    stopped=false
    break
  done
  if [ "$stopped" = true ]; then
    error_with_hash_tag "Unable to start"
    error_with_hash_tag "You may have to start manually"
    return 1
  fi
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
    HASH_SHORT="$(echo "$h" | cut -c -8)"
    if block_leechers "$h"; then
      trans_reload
      if [ $RESTART_TORRENT = true ]; then
        trans_restart_torrent "$h"
      fi
    fi
  done

  sleep 30
done
