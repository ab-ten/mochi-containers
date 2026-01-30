# nginx_rp

## 概要
- rootless Podman で nginx を動かし、リバースプロキシと静的配信を行うサービスです。
- 公開は 127.0.0.1:8080(http) / 127.0.0.1:8443(https) で行い、外向き 80/443 は root systemd の socket activation で転送します。

## 前提と依存関係
- サービスユーザーは `nginx_rp` です。
- 証明書は `ssl_update` により `INSTALL_ROOT/ssl_share/certificates` に配置される前提です。
- 特権ポート 80/443 の待ち受けは root systemd unit を使用します。
- `MAP_LOCAL_ADDRESS` を使って pasta の host loopback をコンテナに渡します。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/nginx_rp`
- 公開ポート: `127.0.0.1:8080` / `127.0.0.1:8443`
- 外向きポート: `80` / `443`（root systemd で中継）
- `CERT_DOMAIN`: 証明書ファイル名の識別に使用
- `MAP_LOCAL_ADDRESS`: pasta の `--map-host-loopback` に使用

## ディレクトリ・ボリューム構成
- `container/Containerfile`: nginx:alpine ベースのイメージ定義
- `container/conf/`: サイト設定（bind mount）
- `container/html/`: 静的コンテンツ（bind mount）
- `${SERVICE_PATH}/http_<service>.conf` / `https_<service>.conf`: サービス別 vhost 設定
- `${INSTALL_ROOT}/ssl_share/certificates`: `/var/ssl_share/certificates` に bind mount

## systemd / quadlet / timer 構成
- `home/.config/containers/systemd/nginx_rp.container`
  - `PublishPort=127.0.0.1:8080:80` / `127.0.0.1:8443:443`
  - `@@SERVICE_PATH@@/container/*` と `@@INSTALL_ROOT@@/ssl_share/certificates` を bind mount
  - `Network=pasta:--map-host-loopback=@@MAP_LOCAL_ADDRESS@@`
- `home/.config/systemd/user/cert-reload.path` / `cert-reload.service`
  - `@@INSTALL_ROOT@@/ssl_share/certificates/.cert-updated` の更新を監視し、`/root/reload.sh` を実行
- `systemd/proxy-80.*` / `systemd/proxy-443.*`
  - root systemd の socket activation で 80/443 を 127.0.0.1:8080/8443 に転送
  - `@@ROOT_UNIT_PREFIX@@` を `${SERVICE_PREFIX}-${SERVICE_NAME}-` に置換

## 運用コマンド
- デプロイ: `make deploy` / `make nginx_rp-deploy`
- 停止: `make stop` / `make nginx_rp-stop`
- ログ: `sudo journalctl -M "nginx_rp@.host" --user -u nginx_rp.service`

## 連携メモ
- `container/10-sites-symlink.sh` が `/etc/nginx/sites-available` から `conf.d` へ symlink を作成します。
- `http_*.conf` は常時有効、`https_*.conf` は証明書ファイルが揃った場合のみ有効化します。
- `pre-build-root` が `SERVICES` に含まれる各サービスの `http_*.conf` / `https_*.conf` を集約し、`container/conf/` に配置します。
- `container/reload.sh` は symlink 更新 → `nginx -t` → `nginx -s reload` を実行します。

## トラブルシュート / 注意点
- SELinux 有効環境では systemd-socket-proxyd の bind/connect を許可する必要があります。

### ポリシーモジュールの導入例
```shell
checkmodule -M -m -o mochi_nginx_rp.mod mochi_nginx_rp.te
semodule_package -o mochi_nginx_rp.pp -m mochi_nginx_rp.mod
sudo semodule -i mochi_nginx_rp.pp
```

### 代替手段（権限を広げる方法）
```shell
setsebool -P systemd_socket_proxyd_bind_any 1
setsebool -P systemd_socket_proxyd_connect_any 1
```
