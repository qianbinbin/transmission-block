#!/usr/bin/env sh

# Copyright (c) 2025 Binbin Qian
# All rights reserved. (MIT Licensed)
#
# transmission-block: Block leecher clients and bad IPs for Transmission
# https://github.com/qianbinbin/transmission-block

[ -z "${BL_SERVER+x}" ] && BL_SERVER="127.0.0.1:9098"
# https://github.com/transmission/transmission/blob/main/libtransmission/clients.cc
# https://github.com/PBH-BTN/quick-references/blob/main/peer_ids.md
[ -z "${LEECHER_CLIENTS+x}" ] && LEECHER_CLIENTS='%FF%1D%FF%FF%FF8I%FF,-GT0002-,-GT0003-,Baidu,libTorrent (Rakshasa) 0\.13\.8,libtorrent (Rasterbar) 2\.0\.7,QQDownload,Thunder,Xfplay,Xunlei'
[ -z "${WORK_DIR+x}" ] && WORK_DIR=./transmission-block
# [ -z "${EXTERNAL_BL+x}" ] && EXTERNAL_BL=
[ -z "${CHECK_INTERVAL+x}" ] && CHECK_INTERVAL=30
[ -z "${CLEAR_INTERVAL+x}" ] && CLEAR_INTERVAL=7d
[ -z "${RESTART_TORRENT+x}" ] && RESTART_TORRENT=true
[ -z "${RENEW_INTERVAL+x}" ] && RENEW_INTERVAL=1d

USAGE=$(
  cat <<-END
Usage: $0 [OPTION]...

Block leecher clients and bad IPs for Transmission.

The script maintains a blocklist for IPs of unwanted clients and/or IPs in
external blocklists, and sets up an HTTP service for Transmission to access it
via blocklist URL.

Enable remote access for Transmission before using. If authentication is
enabled, also set the TR_AUTH environment variable to username:password.

Examples:
  # block bad peers using default leecher clients, see --block
  $(basename "$0")

  # block bad clients and the IPs in the external blocklist
  $(basename "$0") --external-blocklist https://www.example.com/blocklist

  # don't block bad clients but the IPs in several blocklists
  $(basename "$0") -b '' \\
    -e https://www.example.com/blocklist \\
    -e https://www.example.com/blocklist.gzip

Options:
  -t, --tr-server <url>
                      connect to the Transmission session at <url>
                      (default: localhost:9091)
  -c, --check-interval <num>
                      set work interval in seconds for checking if the peers are
                      valid and/or blocklists are outdated, etc.; must be
                      greater than 0 (default: $CHECK_INTERVAL)
  -b, --block <clients>
                      clients to block; <clients> should be case-sensitive
                      regexes with BRE (POSIX) flavor separated by ','s; set to
                      '' to disable
$(echo "(default: '$LEECHER_CLIENTS')" | fmt -w 52 -s | sed "s/^/$(printf '%22s' '')/")
  -C, --clear-interval <num[suffix]>
                      clear the local blocklist generated with --block every
                      this period of time in seconds; setting to 0 means never;
                      suffix may be 's' for seconds (the default), 'm' for
                      minutes, 'h' for hours or 'd' for days (default: $CLEAR_INTERVAL)
  -e, --external-blocklist <url>
                      external blocklist URL with the file format of
                      text/gzip/zip; can be used several times
  -r, --renew-interval <num[suffix]>
                      interval of renewing external blocklists in seconds; for
                      suffix see --clear-interval (default: $RENEW_INTERVAL)
  -w, --work-dir <dir>
                      set working directory (default: $WORK_DIR)
  -s, --blocklist-server <host:port>
                      set up blocklist HTTP service at <host:port>; one of
                      nginx/busybox httpd/python3 is required
                      (default: $BL_SERVER)
  -n, --no-restart    do not restart the torrent if leechers detected, which
                      means the blocklist would not take effect immediately; see
                      issue #732 in the Transmission GitHub repo, which is
                      expected to be fixed in v4.1.0, hence this option will not
                      work for versions >= v4.1.0
  -h, --help          display this help and exit

Home page: <https://github.com/qianbinbin/transmission-block>
END
)

error() { echo "$@" >&2; }
_error() { printf "%s" "$@" >&2; }
exist() { command -v "$1" >/dev/null 2>&1; }
_exit() { error "$USAGE" && exit 2; }
proc_alive() { kill -0 "$1" 2>/dev/null; }

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# PARSE ARGS
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

while [ $# -gt 0 ]; do
  case "$1" in
  -t | --tr-server) { [ -n "$2" ] || _exit; } && TR_SERVER="$2" && shift 2 ;;
  -c | --check-interval) { [ -n "$2" ] || _exit; } && CHECK_INTERVAL="$2" && shift 2 ;;
  -b | --block) { [ -n "$2" ] || _exit; } && LEECHER_CLIENTS="$2" && shift 2 ;;
  -C | --clear-interval) { [ -n "$2" ] || _exit; } && CLEAR_INTERVAL="$2" && shift 2 ;;
  -e | --external-blocklist) { [ -n "$2" ] || _exit; } && EXTERNAL_BL="$EXTERNAL_BL $2" && shift 2 ;;
  -r | --renew-interval) { [ -n "$2" ] || _exit; } && RENEW_INTERVAL="$2" && shift 2 ;;
  -w | --work-dir) { [ -n "$2" ] || _exit; } && WORK_DIR="$2" && shift 2 ;;
  -s | --blocklist-server) { [ -n "$2" ] || _exit; } && BL_SERVER="$2" && shift 2 ;;
  -n | --no-restart) RESTART_TORRENT=false && shift ;;
  -h | --help) error "$USAGE" && exit ;;
  *) _exit ;;
  esac
done

# Allow authentication to be disabled
# [ -z "$TR_AUTH" ] && error "The TR_AUTH environment variable is not set" && exit 1
exist transmission-remote || { error "transmission-remote: command not found" && exit 127; }
# <host:port> is not necessary; allow reverse proxy
# echo "$TR_SERVER" | grep -qs -E '^.+:[0-9]+$' || { error "$TR_SERVER: invalid transmission server" && _exit; }
# Allow empty server (default to localhost:9091)
# [ -z "$TR_SERVER" ] && error "$TR_SERVER: no Transmission server specified" && _exit
echo "$BL_SERVER" | grep -qs -E '^.+:[0-9]+$' || { error "$BL_SERVER: invalid blocklist server" && _exit; }
[ -z "$LEECHER_CLIENTS" ] && [ -z "$EXTERNAL_BL" ] && error "Please specify --block and/or --external-blocklist" && _exit
EXTERNAL_BL=$(echo "$EXTERNAL_BL" | xargs | tr ' ' '\n' | sort -u | xargs)
{ echo "$CHECK_INTERVAL" | grep -qs -E '^[0-9]+$' && [ "$CHECK_INTERVAL" -ge 0 ]; } || { error "$CHECK_INTERVAL: invalid check interval" && _exit; }
echo "$CLEAR_INTERVAL" | grep -qs -E '^[0-9]+[smhd]?$' || { error "$CLEAR_INTERVAL: invalid clear interval" && _exit; }
echo "$RENEW_INTERVAL" | grep -qs -E '^[0-9]+[smhd]?$' || { error "$RENEW_INTERVAL: invalid renew interval" && _exit; }
mkdir -p "$WORK_DIR" || exit 1
{ [ -r "$WORK_DIR" ] && [ -w "$WORK_DIR" ]; } || { error "$WORK_DIR: permission denied" && exit 1; }

to_seconds() {
  case "$1" in
  *s) echo "$1" | sed -n -E 's/(.*)s/\1/p' ;;
  *m) echo $(($(echo "$1" | sed -n -E 's/(.*)m/\1/p') * 60)) ;;
  *h) echo $(($(echo "$1" | sed -n -E 's/(.*)h/\1/p') * 60 * 60)) ;;
  *d) echo $(($(echo "$1" | sed -n -E 's/(.*)d/\1/p') * 60 * 60 * 24)) ;;
  *) echo "$1" ;;
  esac
}
CLEAR_INTERVAL=$(to_seconds "$CLEAR_INTERVAL")
RENEW_INTERVAL=$(to_seconds "$RENEW_INTERVAL")
[ "$RENEW_INTERVAL" -eq 0 ] && error "Renew interval can not be 0" && _exit

# ------------------------------------------------------------------------------
# PARSE ARGS
# ------------------------------------------------------------------------------

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# LEECHER LIST
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

LEECHER_LIST="$WORK_DIR/leechers.p2p"

TR_REMOTE=transmission-remote
[ -n "$TR_SERVER" ] && TR_REMOTE="$TR_REMOTE $TR_SERVER"
[ -n "$TR_AUTH" ] && TR_REMOTE="$TR_REMOTE --authenv"
tr_remote() { $TR_REMOTE "$@"; }
_error "Connecting to $TR_SERVER... "
TR_VERSION=$(tr_remote --session-info | sed -n -E 's/.*Daemon version: ([^ ]*).*/\1/p')
[ -z "$TR_VERSION" ] && error "Could not connect" && exit 1
error "v$TR_VERSION"
TR_MAJOR_V=$(echo "$TR_VERSION" | awk -F '.' '{ print $1 }')
TR_MINOR_V=$(echo "$TR_VERSION" | awk -F '.' '{ print $2 }')
# '--torrent active' is not really active
tr_hashes() { tr_remote --torrent all --info | grep Hash: | awk '{ print $2 }'; }
tr_update_bl() {
  if res=$(tr_remote --blocklist-update 2>&1); then
    echo "$res" | grep -qs success && return 0
  fi
  error "$res" && return 1
}
# Address Flags Done Down Up Client
tr_tpeers() { tr_remote --torrent "$1" --info-peers | tail -n +2; }
tr_tstart() { tr_remote --torrent "$1" --start | grep -qs success; }
tr_tstop() { tr_remote --torrent "$1" --stop | grep -qs success; }
tr_tstopped() { tr_remote --torrent "$1" --info | grep -qs 'State: Stopped'; }
# Only apply to active torrents, not working for finished/will verify/verifying
tr_trestart() {
  hash_short="$(echo "$1" | cut -c -8)"
  _error "[$hash_short] Stopping... "
  tr_retry=$(seq 5)
  for _ in $tr_retry; do
    tr_tstop "$1"
    tr_tstopped "$1" && break
    sleep 1
  done
  tr_tstopped "$1" || { error "Could not stop" && return 1; }
  error 'Done'
  sleep 3 # Transmission tends to keep the connection
  _error "[$hash_short] Starting... "
  for _ in $tr_retry; do
    tr_tstart "$1"
    tr_tstopped "$1" || { error "Done" && return 0; }
    sleep 1
  done
  error "Could not start, you may need to restart manually"
  return 1
}

is_ipv4() { echo "$1" | grep -qs -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; }
LEECHER_RE="\(\($(echo "$LEECHER_CLIENTS" | sed 's/,/\\)\\|\\(/g')\)\)"
tr_tblock() {
  hash_short="$(echo "$1" | cut -c -8)"
  tr_tpeers "$1" | while IFS= read -r leecher; do
    # https://en.wikipedia.org/wiki/PeerGuardian#P2P_plaintext_format
    ip=$(echo "$leecher" | awk '{ print $1 }')
    grep -qs "$(echo "$ip" | sed 's/\./\\./g')" "$LEECHER_LIST" && {
      # libTorrent (Rakshasa) lingers like a ghost; simply restarting doesn't work
      error "[$hash_short] $ip: already in blocklist, skipping"
      continue
    }
    client=$(echo "$leecher" | sed -E 's/^([^ ]+ +){5}//')
    echo "$client" | grep -qs "$LEECHER_RE" || continue
    error "[$hash_short] Blocking $client: $ip"
    # Support IPv6 blocklist starting from v4.0.0
    # https://github.com/transmission/transmission/releases/tag/4.0.0
    ! is_ipv4 "$ip" && [ "$TR_MAJOR_V" -lt 4 ] && {
      error "[$hash_short] v$TR_VERSION doesn't support IPv6 blocklist"
      error "[$hash_short] at least v4.0.0 is required, skipping"
      continue
    }
    # Remove ':'s in the first field
    client=$(echo "$client" | tr ':' '_')
    echo "$client:$ip-$ip" | tee -a "$LEECHER_LIST"
  done
}

# ------------------------------------------------------------------------------
# LEECHER LIST
# ------------------------------------------------------------------------------

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# EXTERNAL LIST
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

EXTERNAL_DIR="$WORK_DIR/extern"
[ -n "$EXTERNAL_BL" ] && {
  mkdir -p "$EXTERNAL_DIR" || exit 1
  exist curl || { error "curl: command not found" exit 127; }
  exist file || { error "file: command not found" exit 127; }
}

_curl() { curl -fsSL --retry 5 "$@"; }

if exist md5; then
  do_md5() { md5; }
elif exist md5sum; then
  do_md5() { md5sum | awk '{ print $1 }'; }
elif exist openssl; then
  do_md5() { openssl md5 | awk '{ print $2 }'; }
else
  error "No md5 tool found" && exit 127
fi

hr_size() {
  wc -c "$1" | awk '{
    split("B KiB MiB", units, " ")
    size = $1
    for (i=1; size>=1024 && i<3; i++) size /= 1024
    printf "%.1f %s\n", size, units[i]
  }'
}

URL_HASHES=
for u in $EXTERNAL_BL; do URL_HASHES="$URL_HASHES $(printf '%s' "$u" | do_md5)"; done
URL_HASHES=$(echo "$URL_HASHES" | xargs | tr ' ' '\n')
cleanup_extern_dir() {
  ls "$EXTERNAL_DIR"/* >/dev/null 2>&1 || return 0
  ret_clean_extern=0
  for _f in "$EXTERNAL_DIR"/*; do
    fprefix=$(basename "$_f") && fprefix=${fprefix%.*}
    echo "$URL_HASHES" | grep -qs "^$fprefix$" && continue
    _error "Deleting '$_f'... "
    if rm "$_f"; then error "Done"; else ret_clean_extern=0; fi
  done
  return $ret_clean_extern
}

xcat() {
  ret_xcat=0
  for __f in "$@"; do
    case "$(file -b "$__f")" in
    gzip*) gzip -cd "$__f" || ret_xcat=1 ;;
    Zip*) unzip -p "$__f" || ret_xcat=1 ;; # 7z e -so "$__f"
    *text*) cat "$__f" || ret_xcat=1 ;;
    *) error "$__f: unknown file" && ret_xcat=1 ;;
    esac
  done
  return $ret_xcat
}

renew_external_lists() {
  ret_renew=1
  for url in $EXTERNAL_BL; do
    _error "Updating $url... "
    url_hash=$(printf '%s' "$url" | do_md5)
    etag=$(_curl --head "$url" | grep -i '^etag: ' | cut -c 7-)
    grep -qs "^$etag$" "$EXTERNAL_DIR/$url_hash.etag" && error "Already up to date" && continue
    _curl --compressed -o "$EXTERNAL_DIR/$url_hash.tmp" "$url" || {
      error "Could not download, skipping"
      rm -f "$EXTERNAL_DIR/$url_hash.tmp"
      continue
    }
    xcat "$EXTERNAL_DIR/$url_hash.tmp" >/dev/null || {
      error "Skipping unknown file"
      rm -f "$EXTERNAL_DIR/$url_hash"*
      continue
    }
    mv "$EXTERNAL_DIR/$url_hash.tmp" "$EXTERNAL_DIR/$url_hash.data" &&
      echo "$etag" >"$EXTERNAL_DIR/$url_hash.etag" && error "Done"
    error "Fetched $(hr_size "$EXTERNAL_DIR/$url_hash.data")"
    ret_renew=0
  done
  return $ret_renew
}

# ------------------------------------------------------------------------------
# EXTERNAL LIST
# ------------------------------------------------------------------------------

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# WEB SERVER
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

WEB_DIR="$WORK_DIR/web"
mkdir -p "$WEB_DIR" || exit 1

NGINX=
for exe in nginx /usr/sbin/nginx; do
  exist "$exe" && NGINX="$exe" && break
done
NGINX_CONF=$(
  cat <<-END
pid '$(realpath "$WORK_DIR/nginx.pid")';
events {}
http {
  server {
    listen $BL_SERVER;
    root '$(realpath "$WEB_DIR")';
    autoindex on;
    access_log off;
  }
}
END
)

start_web_server() {
  error "Starting web server, not recommended for public network"
  if [ -n "$NGINX" ]; then
    _error "Starting nginx... "
    echo "$NGINX_CONF" >"$WORK_DIR/nginx.conf"
    $NGINX -c "$(realpath "$WORK_DIR/nginx.conf")" -e stderr -g 'daemon off;' &
    WEBSERVER_PID=$! && proc_alive "$WEBSERVER_PID" && error "Done"
  elif busybox --list 2>/dev/null | grep -qs '^httpd$'; then
    _error "Starting busybox httpd... "
    busybox httpd -f -p "$BL_SERVER" -h "$WEB_DIR" &
    WEBSERVER_PID=$! && proc_alive "$WEBSERVER_PID" && error "Done"
  elif exist python3; then
    _error "Starting python3 http.server... "
    py_ver=$(python3 -V | awk '{ printf $2 }')
    if [ "$(echo "$py_ver" | awk -F '.' '{ print $2 }')" -ge 7 ]; then
      python3 -m http.server -b "${BL_SERVER%:*}" -d "$WEB_DIR" "${BL_SERVER#*:}" 2>/dev/null &
      WEBSERVER_PID=$! && proc_alive "$WEBSERVER_PID" && error "Done"
    else
      error "Python>=3.7 is required, but got $py_ver"
      return 1
    fi
  else
    error "No web server program found"
    return 127
  fi
}

stop_web_server() {
  _error "Stopping web server... "
  if proc_alive "$WEBSERVER_PID"; then
    kill "$WEBSERVER_PID" && error "Done"
  else
    error "Web server is not running" && return 1
  fi
}
# ------------------------------------------------------------------------------
# WEB SERVER
# ------------------------------------------------------------------------------

cleanup() {
  # Add the suffix '/' in case that $WORK_DIR is a symlink
  find "$WORK_DIR/" -type f \( -name '*.conf' -or -name '*.tmp' \) -delete
  [ -z "$LEECHER_CLIENTS" ] && rm -f "$LEECHER_LIST"
  if [ -z "$EXTERNAL_BL" ]; then rm -rf "$EXTERNAL_DIR"; else cleanup_extern_dir; fi
}

reload() {
  _error "Generating blocklist... "
  : >"$WEB_DIR/blocklist.p2p"
  [ -n "$LEECHER_CLIENTS" ] && [ -f "$LEECHER_LIST" ] && {
    cat "$LEECHER_LIST" >>"$WEB_DIR/blocklist.p2p" || return 1
  }
  [ -n "$EXTERNAL_BL" ] && ls "$EXTERNAL_DIR"/*.data >/dev/null 2>&1 &&
    xcat "$EXTERNAL_DIR"/*.data >>"$WEB_DIR/blocklist.p2p" # continue even error happened
  gzip -f "$WEB_DIR/blocklist.p2p" || return 1
  error "http://$BL_SERVER/blocklist.p2p.gz"
  _error "Requesting Transmission to update the blocklist... "
  tr_update_bl || return 1
  error "Done"
}

stop() {
  ret_stop=0
  # exist pstree && pstree -p $$
  stop_web_server || ret_stop=1
  cleanup || ret_stop=1
  exit $ret_stop
}

# trap reload HUP
trap stop INT TERM

cleanup
start_web_server || exit 1
reload

[ -n "$LEECHER_CLIENTS" ] && leech_start=$(date +%s)
[ -n "$EXTERNAL_BL" ] && extern_start=$((leech_start - RENEW_INTERVAL)) # ensure an update when starting
while proc_alive "$WEBSERVER_PID"; do                                   # curl -sS --head "$BL_SERVER" >/dev/null
  [ -n "$LEECHER_CLIENTS" ] && {
    [ "$CLEAR_INTERVAL" -ne 0 ] && [ $(($(date +%s) - leech_start)) -ge "$CLEAR_INTERVAL" ] && {
      _error "Clearing leecher blocklist... " && rm -f "$LEECHER_LIST" && error "Done"
      reload
      leech_start=$(date +%s)
    }
    for hash in $(tr_hashes); do
      [ -n "$(tr_tblock "$hash")" ] && reload && {
        [ "$RESTART_TORRENT" != true ] && continue
        [ "$TR_MAJOR_V" -gt 4 ] && continue
        { [ "$TR_MAJOR_V" -eq 4 ] && [ "$TR_MINOR_V" -ge 1 ]; } && continue
        # Let's hope reloading complete before restarting
        sleep 3
        tr_trestart "$hash"
      }
    done
  }
  [ -n "$EXTERNAL_BL" ] && {
    [ $(($(date +%s) - extern_start)) -ge "$RENEW_INTERVAL" ] && {
      renew_external_lists && reload
      extern_start=$(date +%s)
    }
  }
  sleep "$CHECK_INTERVAL"
done

error "Web server stopped unexpectedly, exiting" && exit 1
