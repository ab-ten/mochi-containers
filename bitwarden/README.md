# bitwarden

## 概要
- Bitwarden Lite を rootless Podman で動かすサービスです。
- 公式イメージ `ghcr.io/bitwarden/lite:2026.4.1` をベースにローカルイメージ `localhost/bitwarden:dev` をビルドします。
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
- `BITWARDEN_DATA_DIR`: `/etc/bitwarden` 用永続領域（既定: `${NFS_ROOT}/bitwarden/data`）
- `BW_DOMAIN`: Bitwarden の外部公開 FQDN（既定: `bitwarden.${CERT_DOMAIN}`）
- `BW_DB_SERVER`: 外部 PostgreSQL ホスト（`Makefile.local` で指定します）
- `BW_DB_PORT`: 外部 PostgreSQL ポート（既定: 5432）
- `BW_DB_DATABASE`: PostgreSQL DB 名（既定: `bitwarden`）
- `BW_DB_USERNAME`: PostgreSQL ユーザー名（既定: `bitwarden`）
- `globalSettings__disableUserRegistration`: 新規登録の有効化制御（既定: `true`）
- `CERT_DOMAIN`: vhost 名と証明書名に使用
- `MAP_LOCAL_ADDRESS`: nginx upstream の接続先に使用

## ディレクトリ・ボリューム構成
- `container/Containerfile`: Bitwarden Lite 派生イメージのビルド定義
- `bitwarden-entrypoint.sample.sh`: upstream entrypoint の参考サンプル
- `https_bitwarden.conf`: nginx vhost 設定（`replace-files-user` で置換）
- `BITWARDEN_DATA_DIR`: `/etc/bitwarden` に bind mount
- `home/.config/containers/systemd/bitwarden.container`: rootless quadlet 定義

`/etc/bitwarden` は `${NFS_ROOT}/bitwarden/data` に bind mount されます。このディレクトリは ZFS または zfs-autobackup の対象に含める想定です。復旧には PostgreSQL DB と `${NFS_ROOT}/bitwarden/data` の両方が必要です。

## 環境変数・シークレット
- `SECRETS_DIR/bitwarden.env-user` を `${SERVICE_PATH}/bitwarden.env-user` に 600 で配置します。
- `bitwarden.env-user` には秘密情報のみを記述します。
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

SMTP は必須ではありません。メール送信を使用する場合は、Bitwarden Lite の環境変数に合わせて SMTP 関連設定を `Makefile.local` または `bitwarden.env-user` に追加してください。パスワードやトークンなどの秘密情報は `bitwarden.env-user` に記述してください。

mail_service を SMTP サーバーとして使用する場合、Bitwarden コンテナから host 側の mail_service へ接続するため、`globalSettings__mail__smtp__host` には `host.containers.internal` を指定してください。SMTP 認証のパスワードなどは `SECRETS_DIR/bitwarden.env-user` に記述してください。

```env
globalSettings__mail__smtp__host=host.containers.internal
globalSettings__mail__smtp__port=25
```

## systemd / quadlet / timer 構成
- `home/.config/containers/systemd/bitwarden.container`
  - `Image=localhost/bitwarden:dev`
  - `Pull=never`
  - `PublishPort=127.0.0.1:@@BITWARDEN_PORT@@:8080`
  - `Volume=@@BITWARDEN_DATA_DIR@@:/etc/bitwarden:Z`
  - `EnvironmentFile=@@SERVICE_PATH@@/bitwarden.env-user`
  - 非秘密の Bitwarden 設定は `Environment=` で渡します。

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
   ```
2. `SECRETS_DIR/bitwarden.env-user` に秘密情報を作成します。
3. `bitwarden/Makefile.local` に `BW_DB_SERVER` などの非秘密設定を作成します。
4. 初回ユーザー登録のため、`globalSettings__disableUserRegistration = false` を設定します。
5. `make -C bitwarden print-uid-gid` またはリポジトリルートで `make bitwarden-get-uid` / `make bitwarden-get-gid` を実行し、NFS 側の UID/GID を確認します。
6. `make bitwarden-deploy` を実行します。
7. `https_bitwarden.conf` を nginx_rp に反映するため、必要に応じて `make nginx_rp-deploy` を実行します。
8. 初回ユーザーを登録します。
9. `globalSettings__disableUserRegistration = true` に戻し、`make bitwarden-deploy` を再実行します。

## 連携メモ
- nginx の upstream は `@@MAP_LOCAL_ADDRESS@@:@@BITWARDEN_PORT@@` を参照します。
- `https_bitwarden.conf` は `nginx_rp` の `pre-build-root` で収集されます。
- `BW_ENABLE_SSL=false` とし、HTTPS 終端は nginx_rp に集約します。
- `container/Containerfile` は upstream `/entrypoint.sh` を `/entrypoint.sh.orig` に保存してからパッチします。
- rootless Podman + NFS bind mount では container root namespace からの `chown` が失敗する場合があります。そのため、`/etc/bitwarden` だけを entrypoint の `chown -R` 対象から除外し、NFS 側のディレクトリ作成と書き込み可否検査は `pre-build-root` で管理します。
- `/app`、`/etc/nginx/http.d`、`/etc/supervisor`、`/var/log`、`/run` など、`/etc/bitwarden` 以外の container 内部ディレクトリに対する upstream の `chown` は維持します。

## 最小の復旧試験
1. PostgreSQL DB のバックアップを検証用 DB へ復元します。
2. `${NFS_ROOT}/bitwarden/data` のバックアップを検証用 NFS 領域へ復元します。
3. `Makefile.local` の `BW_DB_SERVER`、`BW_DB_DATABASE`、`BITWARDEN_DATA_DIR` を検証用に変更します。
4. `SECRETS_DIR/bitwarden.env-user` を検証環境へ配置します。
5. `make bitwarden-deploy` を実行し、ログインと vault 表示を確認します。

## トラブルシュート / 注意点
- `pre-deploy-check-root` は `BW_DB_SERVER` が未設定の場合に失敗します。`Makefile.local` で外部 PostgreSQL ホストを指定してください。
- `pre-build-root` は `${NFS_ROOT}/bitwarden` と `${BITWARDEN_DATA_DIR}` を作成し、UID/GID mapping 相当権限で `${BITWARDEN_DATA_DIR}` へ書き込みできることを検証します。
- NFS の権限が不足する場合は `make -C bitwarden print-uid-gid` またはリポジトリルートで `make bitwarden-get-uid` / `make bitwarden-get-gid` を実行して UID/GID を確認し、`${NFS_ROOT}/bitwarden` の所有権と権限を調整してください。
- `${NFS_ROOT}/bitwarden` と `${BITWARDEN_DATA_DIR}` は owner=`bitwarden`、group=`GID_HOST_MAPPED`、mode=`2770` を基本とします。ただし、NFS と subuid/subgid の組み合わせでは `stat` の表示が期待値と一致しない場合があるため、`pre-build-root` は owner/group の表示値ではなく `setpriv` による書き込み可否で判定します。
- `pre-build-root` で `setpriv` を使用します。`util-linux` をインストールしてください。
- SELinux 有効環境では bind mount に `:Z` を付与しています。
