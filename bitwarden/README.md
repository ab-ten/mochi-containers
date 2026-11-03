# bitwarden

## 概要
- Bitwarden Lite を rootless Podman で動かすサービスです。
- 公式イメージ `ghcr.io/bitwarden/lite:2026.10.1` をベースにローカルイメージ `localhost/bitwarden:dev` をビルドします。
- HTTPS 終端は nginx_rp で行い、Bitwarden コンテナは HTTP のみを公開します。
- DB は LAN 内の既存 PostgreSQL サーバーを使用します。

## 前提と依存関係
- サービスユーザーは `bitwarden` です。ユーザーは作成済みである前提です。
- nginx_rp 経由で公開する前提です。
- PostgreSQL DB とユーザーは外部 PostgreSQL サーバー側で事前に用意します。
- HTTPS 証明書は `ssl_update` により nginx_rp へ配布され、nginx_rp コンテナ内の `/run/nginx-certs` で参照される前提です。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/bitwarden`
- `BITWARDEN_PORT`: ホスト側公開ポート（既定: 9003）
- `BITWARDEN_DATA_DIR`: `/etc/bitwarden` 用永続領域（既定: `${INSTALL_ROOT}/bitwarden_data`）
- `BITWARDEN_BACKUP_DIR`: `/backups` 用永続領域（既定: `${INSTALL_ROOT}/bitwarden_backup`）
- `UID_IN_PODMAN` / `GID_IN_PODMAN`: ホスト側 UID/GID マッピングの計算対象（既定: 911 / 911）。コンテナの実行 UID/GID を指定する変数ではありません。
- `BW_PORT_HTTP`: コンテナ内 HTTP ポート（既定: 8080）
- `BW_ENABLE_SSL`: コンテナ内 TLS の有効化（既定: `false`）
- `BW_DB_PROVIDER`: DB 種別（既定: `postgresql`）
- `BW_DOMAIN`: Bitwarden の外部公開 FQDN（既定: `bitwarden.${CERT_DOMAIN}`）
- `BW_DB_SERVER`: 外部 PostgreSQL ホスト（`Makefile.local` で指定します）
- `BW_DB_PORT`: 外部 PostgreSQL ポート（既定: 5432）
- `BW_DB_DATABASE`: PostgreSQL DB 名（既定: `bitwarden`）
- `BW_DB_USERNAME`: PostgreSQL ユーザー名（既定: `bitwarden`）
- `BW_ENABLE_ADMIN` / `BW_ENABLE_API` / `BW_ENABLE_EVENTS` / `BW_ENABLE_ICONS` / `BW_ENABLE_IDENTITY` / `BW_ENABLE_NOTIFICATIONS`: 各機能の有効化（いずれも既定: `true`）
- `BW_ENABLE_SCIM` / `BW_ENABLE_SSO`: SCIM / SSO の有効化（いずれも既定: `false`）
- `globalSettings__disableUserRegistration`: 新規登録の有効化制御（既定: `true`）
- `CERT_DOMAIN`: vhost 名と証明書名に使用
- `MAP_LOCAL_ADDRESS`: nginx upstream の接続先に使用

## ディレクトリ・ボリューム構成
- `container/Containerfile`: Bitwarden Lite 派生イメージのビルド定義
- `https_bitwarden.conf`: nginx vhost 設定（`replace-files-user` で置換）
- `BITWARDEN_DATA_DIR`: `/etc/bitwarden` に bind mount
- `BITWARDEN_BACKUP_DIR`: `/backups` に bind mount
- `home/.config/containers/systemd/bitwarden.container`: rootless quadlet 定義

既定の保存先はローカルの `/srv/project/bitwarden_data` と `/srv/project/bitwarden_backup` です。保存先は `bitwarden/Makefile.local` で変更できます。`BITWARDEN_DATA_DIR` のバックアップファイル内にデータベースもdumpされています。

## 環境変数・シークレット
- `SECRETS_DIR/bitwarden.env-user` を `${SERVICE_PATH}/bitwarden.env-user` に 600 で配置します。
- `bitwarden.env-user` には秘密情報を記述します。Quadlet に定義されていない追加の環境変数もこのファイルで渡せます。
- ドメイン、DB ホスト、DB 名、DB ユーザー名、新規登録制御などの非秘密情報は `Makefile.local` に記述し、Quadlet の `Environment=` で渡します。
- `SECRETS_DIR/bitwarden.env-user` はリポジトリには含めません。別途安全に保管してください。

### `Makefile.local` サンプル
```make
BW_DB_SERVER = postgres.example.lan
BW_DB_PORT = 5432
BW_DB_DATABASE = bitwarden
BW_DB_USERNAME = bitwarden
BW_DOMAIN = bitwarden.example.com
globalSettings__disableUserRegistration = true
```

初回ユーザー作成時だけ `globalSettings__disableUserRegistration = false` に変更してデプロイし、ユーザー作成後は `true` に戻して再デプロイしてください。

### `SECRETS_DIR/bitwarden.env-user` サンプル
```env
BW_DB_PASSWORD=<secret>
BW_INSTALLATION_ID=<secret>
BW_INSTALLATION_KEY=<secret>
globalSettings__identityServer__certificatePassword=<secret>
```

SMTP は必須ではありません。メール送信を使用する場合は、SMTP 関連設定を `bitwarden.env-user` に追加してください。`Makefile.local` に変数を追加するだけではコンテナへ渡されません。Makefile 側で管理する場合は `REPLACE_ADD_VAR` と Quadlet の `Environment=` にも対応する設定が必要です。

mail_service を SMTP サーバーとして使用する場合、Bitwarden コンテナから host 側の mail_service へ接続するため、`globalSettings__mail__smtp__host` には `host.containers.internal` を指定してください。SMTP 認証のパスワードなどは `SECRETS_DIR/bitwarden.env-user` に記述してください。

```env
globalSettings__mail__smtp__host=host.containers.internal
globalSettings__mail__smtp__port=25
```

## systemd / quadlet / timer 構成
- `home/.config/containers/systemd/bitwarden.container`
  - `Image=localhost/bitwarden:dev`
  - `Pull=never`
  - `PublishPort=127.0.0.1:@@BITWARDEN_PORT@@:@@BW_PORT_HTTP@@`
  - `Volume=@@BITWARDEN_DATA_DIR@@:/etc/bitwarden:Z`
  - `Volume=@@BITWARDEN_BACKUP_DIR@@:/backups:Z`
  - `EnvironmentFile=@@SERVICE_PATH@@/bitwarden.env-user`
  - 非秘密の Bitwarden 設定は `Environment=` で渡します。
- デプロイ時に `/home/bitwarden/.config/containers/systemd/` へ配置します。
- `Restart=on-failure`、`RestartSec=5`、`TimeoutStopSec=40` を設定しています。専用の timer はありません。

## 運用コマンド
- デプロイ: `make deploy` / `make bitwarden-deploy`
- 停止: `make stop` / `make bitwarden-stop`
- ログ: `sudo journalctl -M "bitwarden@.host" --user -u bitwarden.service`
- `make bitwarden-deploy` は bitwarden 単体のみ更新します。`https_bitwarden.conf` の変更を nginx 公開設定へ反映する場合は `make deploy` または `make nginx_rp-deploy` も実行してください。

## 初回デプロイ
1. 外部 PostgreSQL サーバー側で DB とユーザーを作成します。SQL は環境に合わせて調整してください。
   ```sql
   CREATE USER bitwarden WITH PASSWORD '<secret>';
   CREATE DATABASE bitwarden OWNER bitwarden;
   ALTER ROLE bitwarden IN DATABASE bitwarden SET TimeZone TO 'UTC';
   ```
2. `SECRETS_DIR/bitwarden.env-user` に秘密情報を作成します。
3. `bitwarden/Makefile.local` に `BW_DB_SERVER` などの非秘密設定を作成します。
4. 初回ユーザー登録のため、`globalSettings__disableUserRegistration = false` を設定します。
5. `make -C bitwarden print-uid-gid` またはリポジトリルートで `make bitwarden-get-uid` / `make bitwarden-get-gid` を実行し、NFS 側の UID/GID を確認します。
6. `make bitwarden-deploy` を実行します。
7. `https_bitwarden.conf` を nginx_rp に反映するため、必要に応じて `make nginx_rp-deploy` を実行します。
8. 初回ユーザーを登録します。
9. ユーザー登録が不要なら `globalSettings__disableUserRegistration = true` に戻し、`make bitwarden-deploy` を再実行します。

## 連携メモ
- nginx の upstream は `@@MAP_LOCAL_ADDRESS@@:@@BITWARDEN_PORT@@` を参照します。
- `https_bitwarden.conf` は `nginx_rp` の `pre-build-root` で収集されます。
- `BW_ENABLE_SSL=false` とし、HTTPS 終端は nginx_rp に集約します。
- `container/Containerfile` は公式イメージの `FROM` のみで、entrypoint へのパッチはありません。

## 最小の復旧試験
1. PostgreSQL DB のバックアップを検証用 DB へ復元します。
2. `BITWARDEN_DATA_DIR` のバックアップを検証用の保存先へ復元します。
3. `Makefile.local` の `BW_DB_SERVER`、`BW_DB_DATABASE`、`BITWARDEN_DATA_DIR`、`BITWARDEN_BACKUP_DIR` を検証用に変更します。
4. `SECRETS_DIR/bitwarden.env-user` を検証環境へ配置します。
5. `make bitwarden-deploy` を実行し、ログインと vault 表示を確認します。

## トラブルシュート / 注意点
- `pre-deploy-check-root` は `BW_DB_SERVER` が未設定の場合に失敗します。`Makefile.local` で外部 PostgreSQL ホストを指定してください。
- `pre-build-root` は `BITWARDEN_DATA_DIR` を owner/group=`bitwarden:bitwarden`、mode=`0750` で作成・調整します。
- `BITWARDEN_BACKUP_DIR` は owner=`bitwarden`、group=`GID_HOST_MAPPED`、mode=`0770` で作成・調整します。
- マッピングは `make bitwarden-get-uid` / `make bitwarden-get-gid` で確認できます。`GID_HOST_MAPPED` を取得できない場合はデプロイできません。
- `NFS_GROUP_CHECK=No` により共通の NFS ディレクトリ所有権チェックを無効化しています。`setpriv` による書き込み検査も行いません。
- 保存先を NFS に変更する場合、公式 entrypoint による `chown` が失敗する可能性があります。NFS 側の権限と rootless Podman の UID/GID マッピングを確認してください。
- SELinux 有効環境では bind mount に `:Z` を付与しています。
