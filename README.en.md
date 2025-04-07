# transmission-block

Transmission auxiliary script for blocking leecher clients like Xunlei,
as well as IP addresses in the online blocklists.

Features:

* Supports blocking specified clients
  (preset with `LEECHER_CLIENTS` in the configuration file).
* Supports multiple online blocklists with the file format of text/gzip/zip
  (see `EXTERNAL_BL` in the configuration file for details).
* End-to-end access, theoretically supports Transmission in containers,
  and can even run on another host.
* Supports running as restricted users.
* Theoretically compatible with POSIX Shell.
* Converts some rules, e.g. [BTN-Collected-Rules](https://github.com/PBH-BTN/BTN-Collected-Rules)
  to a Transmission-compatible format (see the
  [blocklist](https://github.com/qianbinbin/transmission-block/tree/blocklist)
  branch for details).

Dependencies:

* transmission-remote command, which is usually installed with Transmission.
  For isolated installations (such as some NAS systems),
  transmission-remote may require setting `PATH`,
  see the configuration file for details.
* curl and file commands (if using online blocklists).
* HTTP server program, any of nginx, busybox httpd, or python3 (sorted by priority).
  The former two have extremely low resource usage,
  and the latter two are commonly pre-installed.
* systemd version 235 or above (if managing with systemd).
  For lower versions, refer to [Troubleshooting](#troubleshooting).

## Usage

### Set up Transmission

* Enable remote access; set your username and password (optional).
* Enable the blocklist and set the URL to `http://127.0.0.1:9098/blocklist.p2p.gz`.

Take transmission-daemon for example, in the
[configuration file](https://github.com/transmission/transmission/blob/main/docs/Configuration-Files.md):

```json
{
  "rpc-enabled": true,
  "rpc-authentication-required": true,
  "rpc-username": "username",
  "rpc-password": "password",
  "blocklist-enabled": true,
  "blocklist-url": "http://127.0.0.1:9098/blocklist.p2p.gz"
}
```

> \[!NOTE]
> It is recommended to change the password when the daemon is stopped,
> as the password will be salted and hashed after startup.
>
> If the default HTTP listening address (see `BL_SERVER` in the configuration
> file) is not used, `"blocklist-url"` should be modified accordingly.
>
> If the daemon is running, run `systemctl reload transmission-daemon.service`
> to [reload the configuration](https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md#reload-settings);
> simply restarting will not take effect.

### Manage with systemd

Run as root to install the script and configuration file:

```sh
mkdir -p /usr/local/bin /usr/local/lib/systemd/system /usr/local/etc/transmission-block
chmod 700 /usr/local/etc/transmission-block
curl https://raw.githubusercontent.com/qianbinbin/transmission-block/master/transmission-block.sh \
  -o /usr/local/bin/transmission-block \
  https://raw.githubusercontent.com/qianbinbin/transmission-block/master/transmission-block.service \
  -o /usr/local/lib/systemd/system/transmission-block.service \
  https://raw.githubusercontent.com/qianbinbin/transmission-block/master/transmission-block.conf \
  -o /usr/local/etc/transmission-block/transmission-block.conf
chmod +x /usr/local/bin/transmission-block
systemctl daemon-reload
```

If user authentication is enabled,
set `TR_AUTH` with your username and password in
`/usr/local/etc/transmission-block/transmission-block.conf`.
The usage of other options is described in the comments.

> \[!TIP]
> The BTN-Collected-Rules blocklist is recommended:
>
> ```
> EXTERNAL_BL=https://raw.githubusercontent.com/qianbinbin/transmission-block/blocklist/btn-all.p2p
> # Updates frequently
> RENEW_INTERVAL=1h
> ```
>
> | List | CDN | Note |
> | ---- | --- | ---- |
> | [Complete list](https://raw.githubusercontent.com/qianbinbin/transmission-block/blocklist/btn-all.p2p) | [Cloudflare](https://blocklist.binac.org/btn-all.p2p) [jsDelivr](https://cdn.jsdelivr.net/gh/qianbinbin/transmission-block@blocklist/btn-all.p2p) | Including IPv4 and IPv6 addresses, compatible with Transmission v4.0.0 and above |
> | [IPv4 only](https://raw.githubusercontent.com/qianbinbin/transmission-block/blocklist/btn-all-ipv4.p2p) | [Cloudflare](https://blocklist.binac.org/btn-all-ipv4.p2p) [jsDelivr](https://cdn.jsdelivr.net/gh/qianbinbin/transmission-block@blocklist/btn-all-ipv4.p2p) | IPv4 addresses only, applicable to Transmission versions lower than v4.0.0 |
>
> Note: jsDelivr has some latency, and DNS pollution may exist in some areas.
>
> Also check [blocklist branch](https://github.com/qianbinbin/transmission-block/tree/blocklist)
> and [other blocklists](#other-blocklists).

Run:

```sh
systemctl enable transmission-block.service # start at boot
systemctl start transmission-block.service
systemctl status transmission-block.service
journalctl -f -u transmission-block.service # view the logs
```

In the Transmission Web page, click 🔧 > Peers to check if the blocklists are effective.

<details>

<summary>Run Manually</summary>

### Run Manually

```sh
curl https://raw.githubusercontent.com/qianbinbin/transmission-block/master/transmission-block.sh \
  -o ./transmission-block.sh
chmod +x ./transmission-block.sh
export TR_AUTH=username:password
./transmission-block.sh # for more options run ./transmission-block.sh -h
```

</details>

## Supplement Leecher Clients and Suspicious IPs

Feel free to supplement leecher clients and suspicious IPs at <https://github.com/qianbinbin/transmission-block/issues/9>.

Run `transmission-remote --auth username:password --torrent all --peer-info`
to view all connections.

> \[!TIP]
> How to detect a suspicious IP? Check the download history of the IP at <https://iknowwhatyoudownload.com/en/peer/>.
> If the download volume is significantly higher than that of an ordinary user,
> it may be an offline download server or a malicious peer.

## Troubleshooting

* [blocklist doesn't take effect immediately](https://github.com/transmission/transmission/issues/732),
  which is a Transmission bug expected to be fixed in version v4.1.0.
  For versions lower than this,
  the script attempts to work it around by restarting the torrent
  (see `RESTART_TORRENT` in the configuration file),
  but occasionally the restart may fail.
* Transmission versions lower than v4.0.0 don't support blocking IPv6 addresses.
* Some clients are used by offline download servers,
  but it is not excluded that normal users may use them. For example, peers using
  `libtorrent (Rasterbar) 2.0.7` and `libTorrent (Rakshasa) 0.13.8`
  may be Xunlei or PikPak servers, and the script will block them by default.
* Some data center, such as Vultr, may be listed by aggressive online blocklists.
* systemd versions lower than 235 (check with `systemctl --version`)
  don't support DynamicUser and StateDirectory, and it is recommended to upgrade.
  If an upgrade is not possible,
  you need to create a working directory and modify the systemd unit file manually:
  ```sh
  mkdir /var/lib/transmission-block
  chown nobody:nogroup /var/lib/transmission-block # replace nobody:nogroup with desired user and group
  sed -i -e 's/DynamicUser=yes/User=nobody/' \ # value of User= should be the same as the user above
    -e '/StateDirectory=%p/d' \
    -e 's,"$STATE_DIRECTORY",/var/lib/transmission-block,' \
    /usr/local/lib/systemd/system/transmission-block.service
  systemctl daemon-reload
  ```
  If you don't care about security issues,
  you can delete the lines `DynamicUser=` and `User=` from the file,
  which will run the script as root.

## Credits

[blocklist](https://github.com/qianbinbin/transmission-block/tree/blocklist)
branch converts the following data to a Transmission-compatible format:

* [PBH-BTN/BTN-Collected-Rules](https://github.com/PBH-BTN/BTN-Collected-Rules)
  under [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) License.
* <https://github.com/qianbinbin/transmission-block/issues/9>

## Other Blocklists

The following blocklists are collected from the Internet for reference.

* [waelisa/Best-blocklist](https://github.com/waelisa/Best-blocklist):
  The author states that only bad peers and copyright IPs are blocked,
  not good peers. Data source unknown.
* [mirror.codebucket.de - transmission](https://mirror.codebucket.de/transmission/):
  Mainly includes malicious IPs,
  but it seems this should be blocked by the firewall rather than P2P.
* [I-BlockList - level1](https://www.iblocklist.com/list?list=ydxerpxkpcfqjaybcssw):
  Includes anti-P2P addresses. The source Bluetack has been closed for many years,
  but the blocklist is still being updated strangely. I-BlockList is commercial,
  and their website also includes some paid blocklists.
* [eMule Security](https://www.emule-security.org/):
  Includes a large number of data center IPs, not recommended.
