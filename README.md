[English](#English)

Transmission 辅助脚本，屏蔽迅雷等吸血客户端的 IP 地址。

## 使用

在 Transmission [配置文件](https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md) 里设置 `"blocklist-enabled": true`。

编辑脚本，按需修改以下参数：

```sh
# 主机:端口
# 通常无需修改
HOST="localhost:9091"

# 用户名:密码
AUTH="username:password"

# 需要屏蔽的客户端，以空格分隔，不区分大小写
# 只要包含关键字即可，如 "xun" 也会屏蔽 "xunlei"
CLIENTS="xunlei thunder gt0002 xl0012 xfplay dandanplay dl3760 qq"

# 屏蔽列表文件，在配置目录的 blocklists 文件夹下
# https://github.com/transmission/transmission/blob/main/docs/Blocklists.md
LIST="$HOME/.config/transmission-daemon/blocklists/leechers.txt"

# 每过一段时间清空列表，单位：秒
# 0 表示永久屏蔽，由于 IP 动态分配，不建议永久屏蔽
# TIMEOUT_SECONDS=$((60 * 60 * 24)) # 24 小时
TIMEOUT_SECONDS=0
```

然后运行即可。

在 Web 管理页面，点击 🔧 -> Peers，查看屏蔽规则是否生效。

注：规则生效并不意味着立即停止上传，这可能是 Transmission 的问题，如需立即停止上传，建议手动重启。

### Systemd

```sh
$ curl https://raw.githubusercontent.com/qianbinbin/transmission-blocker/master/transmission-block-clients.service -o /etc/systemd/system/transmission-block-clients.service
```

修改 `/etc/systemd/system/transmission-block-clients.service` 中以下参数：

```sh
# 用户
User=debian-transmission
# 脚本路径
ExecStart=/path/to/trans-block.sh
```

执行：

```sh
$ systemctl daemon-reload
$ systemctl enable transmission-block-clients.service # 开机启动
$ systemctl start  transmission-block-clients.service # 立即启动
$ systemctl status transmission-block-clients.service # 查看状态
```

# English

A shell script for Transmission to block IPs of leecher clients, such as Xunlei.

## Usage

Set `"blocklist-enabled": true` in Transmission [configuration file](https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md).

Change these values in the script:

```sh
# host:port
# Usually no need to change
HOST="localhost:9091"

AUTH="username:password"

# Clients to block, split by whitespaces, case insensitive
# Only keywords needed, which means "xun" would also block "xunlei"
CLIENTS="xunlei thunder gt0002 xl0012 xfplay dandanplay dl3760 qq"

# Blocklist file in its configuration folder
# https://github.com/transmission/transmission/blob/main/docs/Blocklists.md
LIST="$HOME/.config/transmission-daemon/blocklists/leechers.txt"

# Clear blocklist every specified time period (in seconds)
# 0=disable, not recommended due to dynamic IPs
# TIMEOUT_SECONDS=$((60 * 60 * 24)) # 24 hours
TIMEOUT_SECONDS=0
```

Then run the script.

Open the web interface, go to 🔧 -> Peers to check if the rules take effects.

Note that enabling the rules doesn't mean stopping seeding at once, which I believe is a problem of Transmission. Manually restarting Transmission should do the trick.

### Systemd

```sh
$ curl https://raw.githubusercontent.com/qianbinbin/transmission-blocker/master/transmission-block-clients.service -o /etc/systemd/system/transmission-block-clients.service
```

Edit `/etc/systemd/system/transmission-block-clients.service`:

```sh
User=debian-transmission
ExecStart=/path/to/trans-block.sh
```

Then:

```sh
$ systemctl daemon-reload
$ systemctl enable transmission-block-clients.service
$ systemctl start  transmission-block-clients.service
$ systemctl status transmission-block-clients.service
```

