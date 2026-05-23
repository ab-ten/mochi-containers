# ssl_update

## 概要
- goacme/lego を rootless Podman でワンショット実行し、DNS-01 で証明書を取得・更新するサービスです。
- 取得した証明書を `certs.tar` として配布します。既定の配布先は nginx_rp と mail_service ですが、`SERVICES` に含まれるサービスのみを対象にします。

## 前提と依存関係
- サービスユーザーは `ssl_update` です。
- DNS プロバイダの API トークンが必要です。
- `INSTALL_ROOT/ssl_share` を介して証明書アーカイブを配布します。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/ssl_update`
- `INSTALL_ROOT/ssl_share`: `/var/ssl_share` に bind mount
- `SECRETS_DIR/ssl_update.env-user`: lego の環境変数ファイル
- `USE_STAGING`: `Yes` の場合は Let's Encrypt staging と `ssl_share/staging/` を使用します。`No` の場合は `ssl_share/production/` を使用します（既定: `No`）
- `SSL_UPDATE_CLIENTS`: 証明書アーカイブの配布先候補一覧です。`SERVICES` に含まれるサービスのみ配布先ディレクトリを作成し、コンテナ内の配布対象にします（既定: `nginx_rp mail_service`）
- `SLACK_NOTIFICATION`: Slack 通知用 `slack.env-user` の読み込み制御（既定: `Yes`）

## ディレクトリ・ボリューム構成
- `container/scripts/`: コンテナ内 `/scripts` に read-only で bind mount
- `/var/ssl_share`: `ssl_update:ssl_update` 755
- `/var/ssl_share/production`: `ssl_update:ssl_update` 750
- `/var/ssl_share/production/accounts`: `ssl_update:ssl_update` 750
- `/var/ssl_share/production/certificates`: `ssl_update:ssl_update` 750
- `/var/ssl_share/staging`: `ssl_update:ssl_update` 750
- `/var/ssl_share/staging/accounts`: `ssl_update:ssl_update` 750
- `/var/ssl_share/staging/certificates`: `ssl_update:ssl_update` 750
- `/var/ssl_share/nginx_rp`: `ssl_update:<nginx_rp の SERVICE_GROUP>` 2750（`SERVICES` に `nginx_rp` が含まれる場合）
- `/var/ssl_share/mail_service`: `ssl_update:<mail_service の SERVICE_GROUP>` 2750（`SERVICES` に `mail_service` が含まれる場合）
- 旧配置の `/var/ssl_share/accounts` と `/var/ssl_share/certificates` が存在する場合、`post-build-root` で `production/` 配下へ移行します。移行先が既に存在する場合は自動移行を停止します。

## 環境変数・シークレット
- `SECRETS_DIR/ssl_update.env-user` を `${SERVICE_PATH}/ssl_update.env-user` に 600 で配置します。
- `EMAIL`, `DNSPROVIDER`, `DOMAIN`, `ADDITIONAL_OPTIONS`, `RENEW_OPTION`, `RUN_OPTIONS` を使用します。
- DNS プロバイダの API トークン類も lego の仕様に従って記述します。
- Slack 通知の token/channel は `SECRETS_DIR/slack.env-user` に記述します。`SLACK_NOTIFICATION=Yes` かつ `SECRETS_DIR/slack.env-user` が存在する場合のみ読み込まれます。

### `SECRETS_DIR/ssl_update.env-user` サンプル（さくらのクラウドDNS用）
```env
EMAIL=<your-email-address>
DNSPROVIDER=sakuracloud
DOMAIN=*.@@CERT_DOMAIN@@
RUN_OPTIONS=
SAKURACLOUD_ACCESS_TOKEN=<your-access-token>
SAKURACLOUD_ACCESS_TOKEN_SECRET=<your-access-secret>
```

## systemd / quadlet / timer 構成
- `home/.config/containers/systemd/lego.container` から `lego.service` が生成されます。
- `lego.timer` は日次実行（`OnCalendar=*-*-* 03:30:00`）で、`RandomizedDelaySec=1h` を使用します。
- DNS 設定やタイマーの変更は drop-in で上書きします。
  - `ssl_update/dropins/systemd/user/systemd/ssl_update/lego.service.d/`
  - `ssl_update/dropins/systemd/user/systemd/ssl_update/lego.timer.d/`

## 運用コマンド
- デプロイ: `make deploy` / `make ssl_update-deploy`
- 停止: `make stop` / `make ssl_update-stop`
- ログ: `sudo journalctl -M "ssl_update@.host" --user -u lego.service`

## 連携メモ
- lego hook が実行された場合、`/var/ssl_share/marker.updated` を touch します。このファイルは最終状態確認用であり、配布処理の分岐には使用しません。
- lego 実行中は `/var/ssl_share/.lego-error` を作成し、lego が正常終了した場合に削除します。このファイルは最終状態確認用です。
- 証明書ファイルを検証した後、`/var/ssl_share/certs.tar` を作成し、`SSL_UPDATE_CLIENTS` のうち `SERVICES` に含まれる各配布先へ `certs.tar` として配布します。
- nginx_rp への配布が完了した場合、`/var/ssl_share/nginx_rp/marker.updated` を touch します。nginx_rp の `cert-reload.path` はこのファイルを監視します。
- `USE_STAGING=No` の場合は `/var/ssl_share/production/certificates` と `/var/ssl_share/production/accounts` を使用します。`USE_STAGING=Yes` の場合は `/var/ssl_share/staging/certificates` と `/var/ssl_share/staging/accounts` を使用し、配布先の tar ファイル名は通常時と同じです。

## トラブルシュート / 注意点
- DNS プロバイダのトークン不足や権限不足で失敗する場合があります。
- レート制限を回避するため、`RENEW_OPTION` の強制実行は慎重に使用してください。
- lego エラー、ロック獲得失敗、証明書配布失敗は exit 1 とし、Slack 環境変数が設定されている場合は通知します。
