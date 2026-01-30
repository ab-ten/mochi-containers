# nextcloud

## 概要
- 公式イメージ `nextcloud:stable-apache` を rootless Podman で動かすサービスです。
- コンテナ内ユーザーは `www-data`（uid/gid 33）前提です。

## 前提と依存関係
- サービスユーザーは `nextcloud` です。
- nginx_rp 経由で公開する前提です。
- NFS 永続ディレクトリを使用します。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/nextcloud`
- `HTML_DIR`: `/srv/project/nextcloud_html`
- `NEXTCLOUD_PORT`: ホスト側公開ポート（既定: 9000）
- `NFS_ROOT/nextcloud/{app,data,config}`: 永続領域

## ディレクトリ・ボリューム構成
- `HTML_DIR` に `app/` `data/` `config/` を作成します（`pre-build-root`）。
- `NFS_ROOT/nextcloud/app` / `data` / `config` を作成します（`post-build-user`）。
- `https_nextcloud.conf` を `SERVICE_PATH` に配置し、`replace-files-user` で `@@CERT_DOMAIN@@` を置換します。
- unit 側で `HTML_DIR` や NFS ボリュームを bind mount します。

## 環境変数・シークレット
- `SECRETS_DIR/nextcloud.env-user` を `${SERVICE_PATH}/nextcloud.env-user` に 600 で配置します。
- Nextcloud の公式環境変数をこのファイルに記述します。

### `SECRETS_DIR/nextcloud.env-user` サンプル
```env
POSTGRES_DB=nextcloud
POSTGRES_USER=nextcloud
POSTGRES_PASSWORD=<postgres-passwd>
POSTGRES_HOST=<postgres-host>
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=<nextcloud-passwd>
NEXTCLOUD_TRUSTED_DOMAINS=@@SERVICE_NAME@@.@@CERT_DOMAIN@@
PHP_UPLOAD_LIMIT=64M
APACHE_DISABLE_REWRITE_IP=1
TRUSTED_PROXIES=127.0.0.1
OVERWRITEHOST=@@SERVICE_NAME@@.@@CERT_DOMAIN@@
OVERWRITEPROTOCOL=https
OVERWRITECLIURL=https://@@SERVICE_NAME@@.@@CERT_DOMAIN@@
```

## systemd / quadlet / timer 構成
- quadlet で `127.0.0.1:@@NEXTCLOUD_PORT@@:80` を公開します。
- `REPLACE_ADD_VAR=HTML_DIR NEXTCLOUD_PORT` を使用して `@@HTML_DIR@@` / `@@NEXTCLOUD_PORT@@` を置換します。

## 運用コマンド
- デプロイ: `make deploy` / `make nextcloud-deploy`
- 停止: `make stop` / `make nextcloud-stop`
- ログ: `sudo journalctl -M "nextcloud@.host" --user -u nextcloud.service`

## 連携メモ
- nginx の upstream は `@@MAP_LOCAL_ADDRESS@@:@@NEXTCLOUD_PORT@@` を参照します。
- `TRUSTED_PROXIES` と `OVERWRITE*` 系の環境変数を適切に設定してください。

## トラブルシュート / 注意点
- userns に合わせた UID/GID で `HTML_DIR` の所有権を調整する必要があります。
- UID/GID の確認には `make -C nextcloud print-uid-gid` を使用してください。
