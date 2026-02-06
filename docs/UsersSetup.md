## コンテナユーザー作成ドキュメント

### mochi linux server ユーザー作成

uid/gid はシステムに合わせて適切な値を使用してください。この値は一つの例です。
NFS を使用しない場合は指定せずにシステムの割り当てた値で大丈夫です。
NFS を使用する場合は NFS サーバーと uid/gid を用いて権限の割り当てが行われますので適切な値を用いてください。

```
groupadd -g 20010 nginx_rp
useradd -u 20010 -g 20010 nginx_rp

groupadd -g 20011 ssl_update
useradd -u 20011 -g 20011 ssl_update

groupadd security_package -g 20012
useradd -u 20012 -g 20012 security_package 

groupadd nextcloud -g 20013
useradd -u 20013 -g 20013 nextcloud

groupadd redmine -g 20014
useradd -u 20014 -g 20014 redmine
```

nextcloud/www-data ユーザーID、redmine/redmine グループID取得（NFS使用時に必要です）

```
$ sudo make -C nextcloud print-uid-gid
make: Entering directory '/path/to/mochi-containers/nextcloud'
UID_NC: 431104
GID_NC: 431104
make: Leaving directory '/path/to/mochi-containers/nextcloud'

$ sudo make -C redmine print-uid-gid
make: Entering directory '/path/to/mochi-containers/redmine'
UID_NC: 497606
GID_NC: 497606
make: Leaving directory '/path/to/mochi-containers/redmine'

```

### freebsd NFSv4 server ユーザー作成（UID/GID は linux と合わせること）

```
pw groupadd nginx_rp -g 20010
pw useradd nginx_rp -u 20010 -g nginx_rp -m -s /usr/sbin/nologin
chown nginx_rp:nginx_rp /ztank/nfsv4root/containers/nginx_rp

pw groupadd ssl_update -g 20011
pw useradd ssl_update -u 20011 -g ssl_update -m -s /usr/sbin/nologin
chown ssl_update:ssl_update /ztank/nfsv4root/containers/ssl_update

pw groupadd security_package -g 20012
pw useradd security_package -u 20012 -g security_package -m -s /usr/sbin/nologin

pw groupadd nextcloud -g 20013
pw useradd nextcloud -u 20013 -g nextcloud -m -s /usr/sbin/nologin
chown nginx_rp:nginx_rp /ztank/nfsv4root/containers/nginx_rp

pw groupadd redmine -g 20014
pw useradd redmine -u 20014 -g redmine -m -s /usr/sbin/nologin

```

### freebsd NFSv4 server NFS 設定

/etc/exports に設定追加（例）

```
/etc/exports に追加
V4: /ztank/nfsv4root         -sec=sys -network 192.168.0.0/24
/ztank/nfsv4root/containers  -network 192.168.0.200/32
```

nfs 用ディレクトリ作成（431104, 497606 の数値は print-uid-gid で調べた数値に置き換える）
```
install -d -o nextcloud -g nextcloud -m 0711 /ztank/nfsv4root/containers/nextcloud
install -d -o 431104 -g nextcloud -m 770 /ztank/nfsv4root/containers/nextcloud/config /ztank/nfsv4root/containers/nextcloud/data /ztank/nfsv4root/containers/nextcloud/apps
install -d -g 497606 -o redmine -m 2770 /ztank/nfsv4root/containers/redmine
```

### mochi linux server NFS 設定

nfs client インストール

```
transactional-update pkg install nfs-client
```

/etc/idmapd.conf 編集（作成）
```
[General]
Domain = uhoria.local

[Mapping]
Nobody-User = nobody
Nobody-Group = nobody
```

再起動
```
reboot
```

nfs サービス開始

```
systemctl enable --now nfs-client.target
systemctl start nfs-idmapd
```

/etc/fstab に追加（NFS_ROOT 例: `/srv/nfs/containers`、サーバーのIPアドレス等は適切なものを設定）
以下、<NFS_ROOT> 部は適切に置き換えてください。

```
192.168.0.15:/containers  <NFS_ROOT>  nfs4  rw,vers=4.1,sec=sys,noatime,x-systemd.automount,_netdev  0 0
```

マウント（再起動後は自動でマウントされる）

```
mount <NFS_ROOT>
```
