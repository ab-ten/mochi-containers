# Nextcloud stable-apache を rootless Podman + NFS で復旧・アップグレードする手順

## 1. 対象環境

mochi-containers 627009cbb77bc1533ffd18981ae506badb1f85cd 以前のリポジトリで構築したシステム

### 前提

* コンテナ: `docker.io/nextcloud:stable-apache` 派生イメージ
* 実行方式: rootless Podman
* 永続領域: NFSv4 上の bind mount
* NFS security: `sec=sys`
* Nextcloud: 31→32のメジャーアップグレード（例：`31.0.12.3` から `32.0.8.2`）

### 今回発生した主な症状

```text
rsync: [generator] chown "/var/www/html/custom_apps" failed: Invalid argument (22)
rsync: [generator] chown "/var/www/html/config" failed: Invalid argument (22)
Console has to be executed with the user that owns the file config/config.php
Current user id: 33
Owner id of config.php: 65534
```

## 2. 原因概要

### 2.1 `app` と `apps/custom_apps` の整理

当初、以下のような bind mount があった。

```text
/var/www/html/app
/var/www/html/data
/var/www/html/config
```

しかし `/var/www/html/app` は typo であり、Nextcloud 標準の永続化対象ではない。
Nextcloud の追加アプリ用に永続化するなら、`apps` ではなく `custom_apps` を使う。

修正方針:

```text
/var/www/html/app         使用しない。空なら削除（アップグレード時に自動で削除される）
/var/www/html/apps        永続化しない。イメージ側の標準アプリ領域。
/var/www/html/custom_apps 追加アプリ用に必要なら永続化。
/var/www/html/config      設定。
/var/www/html/data        アップロードデータ。
```

### 2.2 rootless Podman + NFS の UID/GID 問題

rootless Podman では、コンテナ内 UID/GID がホスト側の subuid/subgid 範囲に写像される。
例:

```sh
$ grep nextcloud /etc/sub*id
/etc/subgid:nextcloud:431072:65536
/etc/subuid:nextcloud:431072:65536
$ id nextcloud
uid=20013(nextcloud) gid=20013(nextcloud) groups=20013(nextcloud)
```

この場合、概念上は次のように対応する。

```text
container 0:0   -> host/NFS 20013:20013
container 33:33 -> host/NFS 431104:431104
container 33:0  -> host/NFS 431104:20013
```

ただし NFS は user namespace を理解しないため、実際には「読み書きはできるが、stat/fileowner() では UID 65534/nobody に見える」という状態が起き得る。
今回も `www-data` で `config/` に `touch` はできたが、`config.php` の owner が `65534` と見え、Nextcloud の `occ` が拒否した。

Nextcloud の `occ` は HTTP user、Debian 系では通常 `www-data` で実行する必要がある。([Nextcloud][3])
しかし今回の環境では、`www-data` で実行していても `fileowner(config.php)` が `65534` を返すため、Nextcloud 側の安全チェックが誤爆した。

## 3. 復旧方針

### 採用した方針

1. コンテナは root 起動のまま維持する（`USER www-data` 化はしない）
2. 公式 entrypoint の Apache 設定処理は通す。
3. entrypoint の `rsync --chown` だけ無効化する。
4. `occ` の `config.php` owner check だけ局所的に回避する。
5. `occ` 自体は引き続き `www-data` で実行する。
6. NFS 側のディレクトリは、コンテナ内 root と `www-data` の両方が読める権限に寄せる。

### 採用しなかった方針

#### `USER www-data` 化

`USER www-data` にすると entrypoint の `rsync --chown` は避けられるが、Apache 設定変更など root 前提処理で失敗した。

実際に以下のようなエラーになった。

```text
Could not remove /etc/apache2/conf-enabled/remoteip.conf: Permission denied
```

したがって、`stable-apache` イメージ全体を非 root 実行するのではなく、root 起動は維持し、問題箇所だけパッチする。

## 4. NFS サーバー側の作業

ここは環境依存が強いため、以下は **作者の今回の手順** として扱う。

### 4.1 subuid/subgid の確認

Podman ホスト側で確認する。

```sh
id nextcloud; sudo make nextcloud-get-uid nextcloud-get-gid
```

例:

```text
uid=20013(nextcloud) gid=20013(nextcloud) groups=20013(nextcloud)
431104
431104
```

この場合:

```text
container UID 33 -> NFS UID 431104
container GID 0  -> NFS GID 20013
container GID 33 -> NFS GID 431104
```

### 4.2 NFS 上の Nextcloud ディレクトリを確認

NFS サーバー側で確認する。

```sh
ls -lan /ztssd/nfsv4root/containers/nextcloud
ls -lan /ztssd/nfsv4root/containers/nextcloud/config
ls -lan /ztssd/nfsv4root/containers/nextcloud/data
ls -lan /ztssd/nfsv4root/containers/nextcloud/custom_apps
```

### 4.3 typo の `app` ディレクトリを削除

`/var/www/html/app` 用に作った NFS 側ディレクトリが空なら削除する。

```sh
rmdir /ztssd/nfsv4root/containers/nextcloud/app
```

空でなければ中身を確認してから退避する。

```sh
find /ztssd/nfsv4root/containers/nextcloud/app -maxdepth 2 -ls
```

### 4.4 `custom_apps` を作成

```sh
mkdir -p /ztssd/nfsv4root/containers/nextcloud/custom_apps
```

### 4.5 ディレクトリ owner/mode を調整

`rsync --chown` を無効化するため、entrypoint による所有者修正は期待しない。
コンテナ内では以下のように見えることを目標にする。

```text
config       www-data:root 2770
custom_apps  www-data:root 2770
data         www-data:root 2770
```

subuid/subgid base が `431072` で、`www-data` が `33` の場合、NFS 側では概念上こうなる。

```text
www-data:root -> 431104:20013
```

NFS サーバー側で実行する。

```sh
chown 431104:20013 /ztssd/nfsv4root/containers/nextcloud/config
chown 431104:20013 /ztssd/nfsv4root/containers/nextcloud/custom_apps
chown 431104:20013 /ztssd/nfsv4root/containers/nextcloud/data

chmod 2770 /ztssd/nfsv4root/containers/nextcloud/config
chmod 2770 /ztssd/nfsv4root/containers/nextcloud/custom_apps
chmod 2770 /ztssd/nfsv4root/containers/nextcloud/data
```

### 4.6 config 配下の調整

`config.php` は機密情報を含むため、基本は `0640`。

```sh
chown -R 431104:20013 /ztssd/nfsv4root/containers/nextcloud/config
find /ztssd/nfsv4root/containers/nextcloud/config -type d -exec chmod 2770 {} +
find /ztssd/nfsv4root/containers/nextcloud/config -type f -exec chmod 0640 {} +
```

ただし、テンプレート類を `0644` にしたい運用なら、`config.php` のみ `0640` にしてもよい。

```sh
chmod 0640 /ztssd/nfsv4root/containers/nextcloud/config/config.php
```

### 4.7 data 配下について

`data` は巨大なため、最初から `chown -R` しない。
まずトップディレクトリだけ整えて、Nextcloud 起動後に実アクセスで問題が出るか確認する。

```sh
chown 431104:20013 /ztssd/nfsv4root/containers/nextcloud/data
chmod 2770 /ztssd/nfsv4root/containers/nextcloud/data
```

必要になった場合のみ、段階的に修正する。

```sh
find /ztssd/nfsv4root/containers/nextcloud/data -maxdepth 2 -ls | head
```

全体修正が必要と判断した場合:

```sh
chown -R 431104:20013 /ztssd/nfsv4root/containers/nextcloud/data
find /ztssd/nfsv4root/containers/nextcloud/data -type d -exec chmod 2770 {} +
find /ztssd/nfsv4root/containers/nextcloud/data -type f -exec chmod 0660 {} +
```

## 5. カスタムイメージの作成

### 5.1 Containerfile

（Containerfile を以下のようにしてパッチを二箇所行った）

```Containerfile
FROM docker.io/nextcloud:32-apache

# Rootless Podman + NFS:
# Disable rsync chown because NFS may reject chown from the container's user namespace.
RUN set -eu; \
  cp -a /entrypoint.sh /entrypoint.sh.orig; \
  grep -F 'rsync_options="-rlDog --chown $user:$group"' /entrypoint.sh; \
  sed -i \
    's/rsync_options="-rlDog --chown $user:$group"/rsync_options="-rlD"/' \
    /entrypoint.sh; \
  ! grep -F 'rsync_options="-rlDog --chown $user:$group"' /entrypoint.sh; \
  grep -F 'rsync_options="-rlD"' /entrypoint.sh

# Rootless Podman + NFS:
# fileowner(config/config.php) may appear as uid 65534/nobody even when www-data can read/write it.
# Keep occ running as www-data, but bypass this single owner-id equality check.
RUN set -eu; \
  for f in /usr/src/nextcloud/console.php /var/www/html/console.php /usr/src/nextcloud/cron.php /var/www/html/cron.php; do \
    if [ -f "$f" ]; then \
      cp -a "$f" "$f.orig"; \
      grep -F "\$configUser = fileowner(OC::\$configDir . 'config.php');" "$f"; \
      perl -0pi -e "s/\\\$configUser = fileowner\\(OC::\\\$configDir \\. 'config\\.php'\\);/\\\$configUser = \\\$user; \\/\\/ patched for rootless Podman + NFS owner-id reporting/" "$f"; \
      grep -F "\$configUser = \$user;" "$f"; \
    fi; \
  done
```

### 5.2 ビルド / デプロイ（自動起動）

```sh
sudo make nextcloud-deploy
```

正常起動ログ例:

```text
$ sudo machinectl -q shell nextcloud@.host /bin/bash
$ podman logs nextcloud
Conf remoteip disabled.
To activate the new configuration, you need to run:
  service apache2 reload
=> Configuring PHP session handler...
==> Using default PHP session handler
=> Searching for hook scripts (*.sh) to run, located in the folder "/docker-entrypoint-hooks.d/before-starting"
==> Skipped: the "before-starting" folder is empty (or does not exist)
Apache/2.4.66 (Debian) PHP/8.3.30 configured -- resuming normal operations
```

## 7. アップグレード状態の確認

```sh
podman exec -u www-data nextcloud php ./occ status
```

`needsDbUpgrade: true` の場合:

```text
Nextcloud or one of the apps require upgrade - only a limited number of commands are available
  - installed: true
  - version: 32.0.8.2
  - maintenance: false
  - needsDbUpgrade: true
```

Nextcloud の `occ` は HTTP user で実行する必要があるため、ここでは必ず `-u www-data` を使う。([Nextcloud][3])

## 8. 手動アップグレード

```sh
$ sudo machinectl -q shell nextcloud@.host /bin/bash
podman exec -u www-data nextcloud php ./occ upgrade
```

成功例:

```text
Setting log level to debug
Turned on maintenance mode
Updating database schema
Updated database
Updating <federation> ...
...
Starting code integrity check...
Finished code integrity check
Update successful
Turned off maintenance mode
Resetting log level
```

maintenance mode を確認・解除する。

```sh
podman exec -u www-data nextcloud php ./occ maintenance:mode --off
```

最終確認:

```sh
podman exec -u www-data nextcloud php /var/www/html/occ status
```

期待値:

```text
  - installed: true
  - version: 32.0.8.2
  - versionstring: 32.0.8
  - maintenance: false
  - needsDbUpgrade: false
```

## 9. 追加メンテナンス

アップグレード後に必要に応じて実行する。

```sh
podman exec -u www-data nextcloud php /var/www/html/occ maintenance:repair
podman exec -u www-data nextcloud php /var/www/html/occ db:add-missing-indices
podman exec -u www-data nextcloud php /var/www/html/occ db:add-missing-columns
podman exec -u www-data nextcloud php /var/www/html/occ db:add-missing-primary-keys
```

## 10. トラブルシュート

### 10.1 `rsync: chown ... failed`

原因候補:

* entrypoint の `rsync_options` パッチが効いていない
* 古いイメージで起動している
* `/entrypoint.sh` の該当文字列が公式側で変更された

確認:

```sh
podman exec -u www-data nextcloud grep -n 'rsync_options=' /entrypoint.sh
```

### 10.2 `Console has to be executed with the user that owns the file config/config.php`

原因候補:

* `console.php` パッチが `/var/www/html/console.php` に反映されていない
* `occ` を `www-data` 以外で実行している
* イメージ再作成でパッチ前のファイルに戻った

確認:

```sh
podman exec -u www-data nextcloud grep -n 'configUser' /var/www/html/console.php
```

期待:

```php
$configUser = $user; // patched for rootless Podman + NFS owner-id reporting
```

### 10.3 `Could not remove /etc/apache2/conf-enabled/remoteip.conf`

原因:

* コンテナを `USER www-data` / `User=33:33` で起動している

対処:

* `User=33:33` を削除
* root 起動に戻す

### 10.4 `Permission denied` で config/data/custom_apps が読めない

確認:

```sh
podman exec nextcloud ls -ldn /var/www/html/config /var/www/html/data /var/www/html/custom_apps
podman exec -u www-data nextcloud sh -c 'touch /var/www/html/config/.write-test && rm /var/www/html/config/.write-test'
```

NFS サーバー側で owner/mode を再確認する。

```sh
ls -lan /ztssd/nfsv4root/containers/nextcloud/config
ls -lan /ztssd/nfsv4root/containers/nextcloud/data
ls -lan /ztssd/nfsv4root/containers/nextcloud/custom_apps
```

## 11. 既知の限界

### 11.1 Nextcloud 本体へのパッチを含む

今回の `console.php` パッチは、`config.php` の owner UID 一致チェックを回避する。
これは rootless Podman + NFS で `fileowner()` が 65534/nobody を返す問題への局所回避であり、一般環境では推奨される変更ではない。

### 11.2 公式イメージ更新時に追従が必要

Nextcloud のバージョン更新で `/entrypoint.sh` や `console.php`, `cron.php` の該当行が変わる可能性がある。
Containerfile では `grep` で該当行が存在することを確認し、変わっていた場合はビルド失敗させる。

### 11.3 NFS 上の `data` でも類似問題が出る可能性

`config.php` は `console.php` の owner check に引っかかった。
今後、Nextcloud 側が `data` ディレクトリの owner を厳密に見る処理で同様の問題が出る可能性はある。

必要になったら、以下を検討する。

* `config` と `custom_apps` だけローカル FS に移す
* `data` もローカル FS に移し、NFS はバックアップ/同期先にする
* NFS export / idmap / ACL 設計を見直す
* rootful Podman/Docker へ移行する

## 12. 最終確認チェックリスト

* [ ] `/var/www/html/app` mount を削除した
* [ ] `/var/www/html/apps` は永続化していない
* [ ] `/var/www/html/custom_apps` を使っている
* [ ] カスタムイメージで `rsync_options="-rlD"` になっている
* [ ] `console.php` の `$configUser = fileowner(...)` が `$configUser = $user;` に置換されている
* [ ] `podman exec -u www-data nextcloud php /var/www/html/occ status` が通る
* [ ] `needsDbUpgrade: false`
* [ ] `maintenance: false`
* [ ] Web UI にアクセスできる
* [ ] 管理画面の「概要」に重大な警告がない

## 13. 今回の復旧結果

最終状態:

```text
Nextcloud 32.0.8.2
maintenance: false
needsDbUpgrade: false
occ upgrade: successful
```

今回の本質は、**NFS 上で実際には読み書きできるにもかかわらず、rootless Podman の user namespace と NFS の UID/GID 表示が噛み合わず、Nextcloud の stat/fileowner ベースの安全チェックが誤爆した**ことです。
そのため、実アクセス権の調整だけでは足りず、Nextcloud 公式イメージの root 前提同期処理と `occ` の owner check を、今回の運用環境に合わせて局所的にパッチしました。

[1]: https://github.com/nextcloud/docker/issues/1028 "Problems with image docker and volumes on NFS #1028"
[2]: https://www.redhat.com/ja/blog/rootless-podman-nfs "Rootless Podman and NFS"
[3]: https://docs.nextcloud.com/server/stable/admin_manual/occ_command.html "Using the occ command"
