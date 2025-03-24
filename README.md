# transmission-block

Transmission 辅助脚本，屏蔽迅雷等吸血客户端以及在线屏蔽列表（黑名单）中的 IP 地址。

特性：

* 支持屏蔽指定客户端（已预设，详见配置文件中的 `LEECHER_CLIENTS`）。
* 支持抓取多个指定在线黑名单，支持文本、gzip、zip 格式（详见配置文件中的 `EXTERNAL_BL`）。
* 完全端到端访问，理论支持容器中的 Transmission，甚至可以运行在另一主机。
* 支持受限用户运行。
* 理论兼容 POSIX Shell 环境。
* 同步转换 [PBH-BTN/BTN-Collected-Rules](https://github.com/PBH-BTN/BTN-Collected-Rules)
  为 Transmission 兼容的黑名单（详见 [blocklist](https://github.com/qianbinbin/transmission-block/tree/blocklist) 分支）。

依赖：

* transmission-remote 命令，通常已经与 Transmission 一起安装。隔离安装（如某些
  NAS 系统）的 transmission-remote 可能需要设置 `PATH`，详见配置文件。
* curl、file 命令（如果使用在线黑名单）。
* HTTP 服务程序，nginx、busybox httpd、python3 任意一种（排序分先后）。前两者资源占用极低，后两者普遍预装。
* systemd 235 或以上版本（如果使用 systemd 管理）。要在更低版本上使用，参考[问题排查](#问题排查)。

## 使用

### 删除旧版 trans-block.sh 脚本（可选）

以 root 权限运行：

```sh
rm /path/to/trans-block.sh # 旧脚本保存路径
systemctl disable transmission-block.service
systemctl stop transmission-block.service
rm /etc/systemd/system/transmission-block.service
systemctl daemon-reload
```

删除[配置目录](https://github.com/transmission/transmission/blob/main/docs/Configuration-Files.md)下的旧黑名单：

```sh
rm -i /path/to/config/blocklists/leechers.txt*
```

> \[!TIP]
> 如果不知道配置目录，可以使用以下命令获取（替换自己的用户名和密码）：
>
> ```sh
> transmission-remote --auth username:password --session-info | sed -n -E 's/.*Configuration directory: (.*)/\1/p'
> ```

### 设置 Transmission

* 启用远程访问；设置用户名和密码（可选）。
* 启用黑名单，并设置为 `http://127.0.0.1:9098/blocklist.p2p.gz`。

以 transmission-daemon 为例，在[配置文件](https://github.com/transmission/transmission/blob/main/docs/Configuration-Files.md)中：

```json
{
  "rpc-enabled": true,                                      <--- 启用远程访问
  "rpc-authentication-required": true,                      <--- 启用用户验证
  "rpc-username": "username",                               <--- 用户名
  "rpc-password": "password",                               <--- 密码
  "blocklist-enabled": true,                                <--- 启用黑名单
  "blocklist-url": "http://127.0.0.1:9098/blocklist.p2p.gz" <--- 黑名单地址
}
```

> \[!TIP]
> 修改密码建议在 daemon 关闭状态下，因为密码会在启动后加盐哈希。
>
> 如不使用默认 HTTP 监听地址（见配置文件中的 `BL_SERVER`），则 `"blocklist-url"` 要相应修改。
>
> 如果 daemon 正在运行，使用 `systemctl reload transmission-daemon.service`
> [重新加载配置](https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md#reload-settings)，直接重启不会生效。

### 自动运行（systemd）

下载脚本及配置文件，以 root 权限运行：

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

如果启用了用户验证，在 `/usr/local/etc/transmission-block/transmission-block.conf` 中设置 `TR_AUTH` 用户名和密码。其余均为可选参数，用法由注释给出。

> \[!TIP]
> 推荐启用 [BTN-Collected-Rules](https://github.com/qianbinbin/transmission-block/tree/blocklist) 黑名单：
>
> ```
> EXTERNAL_BL=https://raw.githubusercontent.com/qianbinbin/transmission-block/blocklist/btn-all.p2p
> # 更新较为频繁
> RENEW_INTERVAL=1h
> ```
>
> | 列表 | 备注 |
> | ---- | ---- |
> | [完整列表](https://raw.githubusercontent.com/qianbinbin/transmission-block/blocklist/btn-all.p2p) | 包括 IPv4 和 IPv6 地址，适用于 Transmission v4.0.0 及以上版本 |
> | [完整列表](https://cdn.jsdelivr.net/gh/qianbinbin/transmission-block@blocklist/btn-all.p2p) | 同上，jsDelivr CDN 有一定延迟 |
> | [仅 IPv4](https://raw.githubusercontent.com/qianbinbin/transmission-block/blocklist/btn-all-ipv4.p2p) | 仅 IPv4 地址，适用于 Transmission v4.0.0 以下版本 |
> | [仅 IPv4](https://cdn.jsdelivr.net/gh/qianbinbin/transmission-block@blocklist/btn-all-ipv4.p2p) | 同上，jsDelivr CDN 有一定延迟 |

运行：

```sh
systemctl enable transmission-block.service # 开机启动
systemctl start transmission-block.service # 立即启动
systemctl status transmission-block.service # 查看状态
journalctl -f -u transmission-block.service # 查看 log
```

在 Transmission Web 管理页面，点击 🔧 > Peers，查看屏蔽规则是否生效。

### 临时使用

```sh
curl https://raw.githubusercontent.com/qianbinbin/transmission-block/master/transmission-block.sh \
  -o ./transmission-block.sh
chmod +x ./transmission-block.sh
export TR_AUTH=username:password # 用户名和密码，可以加入到环境变量
./transmission-block.sh # ./transmission-block.sh -h 查看更多参数
```

## 原理

脚本主要做以下几件事：

1. 匹配指定客户端，并将其 IP 加入客户端黑名单（可选）。
2. 下载在线黑名单（可选）。
3. 将两种黑名单合并，在本地建立 HTTP 服务，提供给 Transmission 访问。

其中客户端黑名单和在线黑名单，两者至少需要选择一种。

要屏蔽的客户端是由 `LEECHER_CLIENTS` 指定的，使用区分大小写的 BRE（POSIX 基本正则表达式）匹配，即
`grep` 不加  `-i` 和 `-E` 的匹配方式。

> \[!TIP]
> 也欢迎在 [issue](https://github.com/qianbinbin/transmission-block/issues/9) 补充其他可疑客户端，通过
> `transmission-remote --auth username:password --torrent all --peer-info` 查看所有连接。

考虑到普通用户的 IP 动态分配，客户端黑名单默认每 7 天清空一次；在线黑名单默认每 1 天检查更新一次。这些都是可定制项。

systemd 方式默认工作目录为 `/var/lib/transmission-block/`（请勿手动创建），结构示例如下：

```
/var/lib/transmission-block/
├── extern                                      <--- 在线黑名单目录
│   ├── 2caf2f77158e146478b2eb68c9c0c2a4.data   <--- 在线黑名单原始文件
│   └── 2caf2f77158e146478b2eb68c9c0c2a4.etag   <--- 在线黑名单 Etag 信息
├── leechers.p2p                                <--- 客户端黑名单
└── web                                         <--- HTTP 服务根目录
    └── blocklist.p2p.gz                        <--- 最终黑名单文件
```

Transmission 会更新黑名单到[配置目录](https://github.com/transmission/transmission/blob/main/docs/Configuration-Files.md)下的
`blocklists/blocklist.bin`。

> \[!TIP]
> 如果遇到可疑 IP，你可以在同目录下新建一个[文本文件](https://en.wikipedia.org/wiki/PeerGuardian#P2P_plaintext_format)，格式为
> `描述:起始IP-结束IP`，例如 `suspect:106.8.130.0-106.8.130.255`，然后重新加载或重启 Transmission。
>
> 如何确定可疑 IP？在 <https://iknowwhatyoudownload.com/en/peer/> 上查询该 IP 的下载记录，如果下载量远超普通用户，说明可能是离线下载服务器或刷流量的。

## 问题排查

* [加入黑名单后不会立即生效](https://github.com/transmission/transmission/issues/732)，系
  Transmission bug，预计 v4.1.0 版本将修复这个问题。对于小于此版本，脚本尝试通过重启任务解决（见配置文件中的 `RESTART_TORRENT`），但偶尔会重启失败。
* Transmission v4.0.0 以下不支持屏蔽 IPv6 地址。
* 一些客户端被离线下载服务器使用，但不排除有正常用户使用。例如
  `libtorrent (Rasterbar) 2.0.7`、`libTorrent (Rakshasa) 0.13.8` 可能是迅雷或 PikPak 服务器，脚本默认屏蔽。
* 一些数据中心 IP 会被激进的在线黑名单拉黑，如 Vultr。
* systemd 235 以下版本（通过 `systemctl --version` 查看）不支持 DynamicUser 和
  StateDirectory，有条件建议升级。如果无法升级，需自行创建工作目录并修改 systemd 单元文件：
  ```sh
  mkdir /var/lib/transmission-block
  chown nobody:nogroup /var/lib/transmission-block # nobody:nogroup 可改为自己想要的用户和用户组
  sed -i -e 's/DynamicUser=yes/User=nobody/' \ # User= 要与上面的用户相同
    -e '/StateDirectory=%p/d' \
    -e 's,"$STATE_DIRECTORY",/var/lib/transmission-block,' \
    /usr/local/lib/systemd/system/transmission-block.service
  systemctl daemon-reload
  ```
  如果你不在乎安全问题，可以删除文件中 `DynamicUser=` 和 `User=` 的行，这将直接以 root 用户运行。

## 鸣谢

[blocklist](https://github.com/qianbinbin/transmission-block/tree/blocklist)
分支同步并转换以下数据为 Transmission 兼容的格式：

* [PBH-BTN/BTN-Collected-Rules](https://github.com/PBH-BTN/BTN-Collected-Rules)，[CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.zh-hans) 许可。
