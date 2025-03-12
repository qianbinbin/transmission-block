#!/usr/bin/env sh

# Copyright (c) 2025 Binbin Qian
# All rights reserved. (MIT Licensed)
#
# transmission-block: Block leecher clients and bad IPs for Transmission
# https://github.com/qianbinbin/transmission-block

[ -z "$TR_SERVER" ] && TR_SERVER="127.0.0.1:9091"
[ -z "$BL_SERVER" ] && BL_SERVER="127.0.0.1:9098"
# https://github.com/transmission/transmission/blob/main/libtransmission/clients.cc
[ -z "$LEECHER_CLIENTS" ] && LEECHER_CLIENTS='-GT0002-,-GT0003-,Baidu,libTorrent (Rakshasa),libtorrent (Rasterbar),QQDownload,Thunder,Xfplay,Xunlei'
[ -z "$WORK_DIR" ] && WORK_DIR=./transmission-block
# [ -z "$EXTERNAL_BL" ] && EXTERNAL_BL=
[ -z "$CHECK_INTERVAL" ] && CHECK_INTERVAL=30
[ -z "$CLEAR_INTERVAL" ] && CLEAR_INTERVAL=7d
[ -z "$RESTART_TORRENT" ] && RESTART_TORRENT=true
[ -z "$RENEW_INTERVAL" ] && RENEW_INTERVAL=1d

USAGE=$(
  cat <<-END
Usage: $0 [OPTION]...

Block leecher clients and bad IPs for Transmission.

The script maintains a blocklist for unwanted clients and/or external
blocklists, and sets up an HTTP service, so that Transmission can access it via
"blocklist-url".

Set the TR_AUTH environment variable to username:password before using.

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
                      (default: $TR_SERVER)
  -c, --check-interval <num>
                      check the peers and/or external blocklists every this
                      period of time in seconds; must be greater than 0
                      (default: $CHECK_INTERVAL)
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
                      expected to be fixed in v4.1.0, and this option will not
                      work for versions >= v4.1.0
  -h, --help          display this help and exit

Home page: <https://github.com/qianbinbin/transmission-block>
END
)

error() { echo "$@" >&2; }
exist() { command -v "$1" >/dev/null 2>&1; }
_exit() { error "$USAGE" && exit 2; }

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# PARSE ARGS
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

while [ $# -gt 0 ]; do
  case "$1" in
  -t | --tr-server)
    [ -n "$2" ] || _exit
    TR_SERVER="$2" && shift 2
    ;;
  -c | --check-interval)
    [ -n "$2" ] || _exit
    CHECK_INTERVAL="$2" && shift 2
    ;;
  -b | --block)
    [ -n "$2" ] || _exit
    LEECHER_CLIENTS="$2" && shift 2
    ;;
  -C | --clear-interval)
    [ -n "$2" ] || _exit
    CLEAR_INTERVAL="$2" && shift 2
    ;;
  -e | --external-blocklist)
    [ -n "$2" ] || _exit
    EXTERNAL_BL="$EXTERNAL_BL $2" && shift 2
    ;;
  -r | --renew-interval)
    [ -n "$2" ] || _exit
    RENEW_INTERVAL="$2" && shift 2
    ;;
  -w | --work-dir)
    [ -n "$2" ] || _exit
    WORK_DIR="$2" && shift 2
    ;;
  -s | --blocklist-server)
    [ -n "$2" ] || _exit
    BL_SERVER="$2" && shift 2
    ;;
  -n | --no-restart) RESTART_TORRENT=false && shift ;;
  -h | --help) error "$USAGE" && exit ;;
  *) _exit ;;
  esac
done

[ -z "$TR_AUTH" ] && error "the TR_AUTH environment variable is not set" && exit 1
exist transmission-remote || { error "transmission-remote: command not found" && exit 127; }
# <host:port> is not necessary; allow reverse proxy
# echo "$TR_SERVER" | grep -qs -E '^.+:[0-9]+$' || { error "$TR_SERVER: invalid transmission server" && _exit; }
[ -z "$TR_SERVER" ] && error "$TR_SERVER: no Transmission server specified" && _exit
echo "$BL_SERVER" | grep -qs -E '^.+:[0-9]+$' || { error "$BL_SERVER: invalid blocklist server" && _exit; }
[ -z "$LEECHER_CLIENTS" ] && [ -z "$EXTERNAL_BL" ] && error "please specify --block and/or --external-blocklist" && _exit
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
[ "$RENEW_INTERVAL" -eq 0 ] && error "renew interval can not be 0" && _exit

# ------------------------------------------------------------------------------
# PARSE ARGS
# ------------------------------------------------------------------------------

error() { echo "$@" | sed 's/^/[main] /g' >&2; }
proc_alive() { kill -0 "$1" 2>/dev/null; }
request_reload() { kill -s HUP $$; }
acquire_file() {
  for attempt in $(seq 20); do
    [ -d "$1.lock" ] && error "attempt $attempt: waiting for '$1'" && sleep 5 && continue
    mkdir "$1.lock" && return 0
    error "could not create lock file for '$1'" && return 2
  done
  error "timeout when waiting for '$1'"
  return 1
}
release_file() { rmdir "$1.lock"; }

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# LEECHER LIST
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

LEECHER_LIST="$WORK_DIR/leechers.p2p"

tr_remote() { transmission-remote "$TR_SERVER" --authenv "$@"; }
TR_VERSION=$(tr_remote --session-info | sed -n -E 's/.*Daemon version: ([^ ]*).*/\1/p')
TR_MAJOR_V=$(echo "$TR_VERSION" | awk -F '.' '{ print $1 }')
TR_MINOR_V=$(echo "$TR_VERSION" | awk -F '.' '{ print $2 }')
[ -z "$TR_VERSION" ] && error "could not connect to $TR_SERVER" && exit 1
error "connected to $TR_SERVER, v$TR_VERSION"
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
  error "[$hash_short] restarting"
  tr_retry=$(seq 10)
  for _ in $tr_retry; do
    tr_tstop "$1"
    tr_tstopped "$1" && break
    sleep 1
  done
  tr_tstopped "$1" || { error "[$hash_short] could not stop" && return 1; }
  sleep 5 # transmission tends to keep the connection
  error "[$hash_short] stopped, starting"
  for _ in $tr_retry; do
    tr_tstart "$1"
    tr_tstopped "$1" || { error "[$hash_short] started" && return 0; }
    sleep 1
  done
  error "[$hash_short] could not start, you may have to restart manually"
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
      error "[$hash_short] '$ip': already in blocklist, skipping"
      continue
    }
    client=$(echo "$leecher" | sed -E 's/^([^ ]+ +){5}//')
    echo "$client" | grep -qs "$LEECHER_RE" || continue
    error "[$hash_short] blocking $client: $ip"
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

update_leechers() (
  error() { echo "$@" | sed 's/^/[leecher] /g' >&2; }
  start=$(date +%s)
  while true; do
    diff=$(($(date +%s) - start))
    [ "$CLEAR_INTERVAL" -ne 0 ] && [ $diff -ge "$CLEAR_INTERVAL" ] && {
      error "clearing leecher blocklist"
      acquire_file "$LEECHER_LIST" && {
        : >"$LEECHER_LIST"
        release_file "$LEECHER_LIST"
      }
      request_reload
      start=$(date +%s)
    }
    for hash in $(tr_hashes); do
      rl=1
      acquire_file "$LEECHER_LIST" && {
        [ -n "$(tr_tblock "$hash")" ] && rl=0
        release_file "$LEECHER_LIST"
      }
      [ $rl -eq 0 ] && {
        request_reload
        if [ "$RESTART_TORRENT" = true ]; then
          if [ "$TR_MAJOR_V" -lt 4 ] || { [ "$TR_MAJOR_V" -eq 4 ] && [ "$TR_MINOR_V" -lt 1 ]; }; then
            # Let's hope reloading complete before restarting
            sleep 3
            tr_trestart "$hash"
          fi
        fi
      }
    done
    sleep "$CHECK_INTERVAL"
  done
)

# ------------------------------------------------------------------------------
# LEECHER LIST
# ------------------------------------------------------------------------------

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# EXTERNAL LIST
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

EXTERNAL_DIR="$WORK_DIR/external"
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
  error "no md5 tool found" && exit 127
fi

URL_HASHES=
for u in $EXTERNAL_BL; do URL_HASHES="$URL_HASHES $(printf '%s' "$u" | do_md5)"; done
URL_HASHES=$(echo "$URL_HASHES" | xargs | tr ' ' '\n')
cleanup_extern_dir() {
  ls "$EXTERNAL_DIR"/* >/dev/null 2>&1 || return 0
  _ret=1
  for _f in "$EXTERNAL_DIR"/*; do
    fprefix=$(basename "$_f") && fprefix=${fprefix%.*}
    echo "$URL_HASHES" | grep -qs "^$fprefix$" && continue
    error "deleting '$_f'" && rm "$_f"
    _ret=0
  done
  return $_ret
}

xcat() {
  __ret=0
  for __f in "$@"; do
    case "$(file -b "$__f")" in
    gzip*) gzip -cd "$__f" || __ret=1 ;;
    Zip*) unzip -p "$__f" || __ret=1 ;; # 7z e -so "$__f"
    *text*) cat "$__f" || __ret=1 ;;
    *) error "'$__f': unknown file" && __ret=1 ;;
    esac
  done
  return $__ret
}

update_external_lists() (
  error() { echo "$@" | sed 's/^/[external] /g' >&2; }
  while true; do
    rl=1
    acquire_file "$EXTERNAL_DIR" && {
      for url in $EXTERNAL_BL; do
        error "updating '$url'"
        url_hash=$(printf '%s' "$url" | do_md5)
        etag=$(_curl --head "$url" | grep -i '^etag: ' | cut -c 7-)
        grep -qs "^$etag$" "$EXTERNAL_DIR/$url_hash.etag" && {
          error "no need to update '$url'"
          continue
        }
        error "downloading '$url'"
        _curl --compressed -o "$EXTERNAL_DIR/$url_hash.tmp" "$url" || {
          error "unable to download '$url', skipping"
          rm -f "$EXTERNAL_DIR/$url_hash.tmp"
          continue
        }
        xcat "$EXTERNAL_DIR/$url_hash.tmp" >/dev/null || {
          error "unknown file from '$url', skipping"
          rm -f "$EXTERNAL_DIR/$url_hash"*
          continue
        }
        mv "$EXTERNAL_DIR/$url_hash.tmp" "$EXTERNAL_DIR/$url_hash.data"
        echo "$etag" >"$EXTERNAL_DIR/$url_hash.etag"
        error "updated"
        rl=0
      done
      cleanup_extern_dir && rl=0
      release_file "$EXTERNAL_DIR"
    }
    [ $rl -eq 0 ] && request_reload
    sleep "$RENEW_INTERVAL"
  done
)

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

run_web_server() (
  error() { echo "$@" | sed 's/^/[server] /g' >&2; }
  if [ -n "$NGINX" ]; then
    error "using nginx"
    echo "$NGINX_CONF" >"$WORK_DIR/nginx.conf"
    $NGINX -c "$(realpath "$WORK_DIR/nginx.conf")" -e stderr -g 'daemon off;'
  elif busybox --list 2>/dev/null | grep -qs '^httpd$'; then
    error "using busybox httpd"
    busybox httpd -f -p "$BL_SERVER" -h "$WEB_DIR"
  elif exist python3; then
    error "using python3"
    py_minor_v=$(python3 -V | sed -n -E 's/^Python 3\.([0-9]+)\.[0-9]+/\1/p')
    if [ "$py_minor_v" -ge 7 ]; then
      python3 -m http.server -b "${BL_SERVER%:*}" -d "$WEB_DIR" "${BL_SERVER#*:}" 2>/dev/null
    else
      error "require Python >= 3.7, but got $(python3 -V | awk '{ printf $2 }')"
    fi
  else
    error "no web server program found"
  fi
  error "exiting unexpectedly"
  kill $$
)

# ------------------------------------------------------------------------------
# WEB SERVER
# ------------------------------------------------------------------------------

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN PROCESS
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

# Call this before starting background processes
cleanup_pre() {
  # Add the suffix '/' in case that $WORK_DIR is a symlink
  find "$WORK_DIR/" -type f \( -name '*.conf' -or -name '*.pid' -or -name '*.tmp' \) -delete
  find "$WORK_DIR/" -type d -name '*.lock' -delete
}

cleanup() {
  [ -z "$LEECHER_CLIENTS" ] && rm -f "$LEECHER_LIST"
  if [ -z "$EXTERNAL_BL" ]; then
    rm -rf "$EXTERNAL_DIR"
  else
    acquire_file "$EXTERNAL_DIR" && {
      cleanup_extern_dir
      release_file "$EXTERNAL_DIR"
    }
  fi
}

reload() {
  error "reloading"
  : >"$WEB_DIR/blocklist.p2p"
  [ -n "$LEECHER_CLIENTS" ] && {
    acquire_file "$LEECHER_LIST" && {
      [ -f "$LEECHER_LIST" ] && cat "$LEECHER_LIST" >>"$WEB_DIR/blocklist.p2p"
      release_file "$LEECHER_LIST"
    }
  }
  [ -n "$EXTERNAL_BL" ] && {
    acquire_file "$EXTERNAL_DIR" && {
      ls "$EXTERNAL_DIR"/*.data >/dev/null 2>&1 && xcat "$EXTERNAL_DIR"/*.data >>"$WEB_DIR/blocklist.p2p"
      release_file "$EXTERNAL_DIR"
    }
  }
  gzip -f "$WEB_DIR/blocklist.p2p" || return 1
  error "blocklist URL: 'http://$BL_SERVER/blocklist.p2p.gz'"
  error "requesting Transmission to update the blocklist"
  tr_update_bl || return 1
  error "reloaded"
}

stop() {
  error "stopping"
  # exist pstree && pstree -p $$
  tty -s && {
    for pid in $LEECHER_PID $EXTERNAL_PID $WEBSERVER_PID; do
      kill -0 "-$pid" 2>/dev/null && kill -- "-$pid"
    done
  }
  cleanup
  error "stopped"
  exit 0
}

trap reload HUP
trap stop INT TERM

cleanup_pre
cleanup

[ -n "$LEECHER_CLIENTS" ] && {
  # Put all child processes in a separate group, so that we can kill them all in
  # the main process; we don't use kill -- -$$ because it may kill itself before
  # killing the whole tree
  tty -s && set -m
  update_leechers &
  tty -s && set +m
  # PID is also the GPID
  LEECHER_PID=$!
}
[ -n "$EXTERNAL_BL" ] && {
  tty -s && set -m
  update_external_lists &
  tty -s && set +m
  EXTERNAL_PID=$!
}
tty -s && set -m
run_web_server &
tty -s && set +m
WEBSERVER_PID=$!

reload

# wait can be interrupted by signals so we put it in while loop
while ! { [ -n "$LEECHER_CLIENTS" ] && ! proc_alive "$LEECHER_PID"; } &&
  ! { [ -n "$EXTERNAL_BL" ] && ! proc_alive "$EXTERNAL_PID"; } &&
  proc_alive "$WEBSERVER_PID"; do
  wait
done
stop

# ------------------------------------------------------------------------------
# MAIN PROCESS
# ------------------------------------------------------------------------------
