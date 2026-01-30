# ssl_update

## 概要
- goacme/lego を rootless Podman でワンショット実行し、DNS-01 で証明書を取得・更新するサービスです。
- 取得した証明書は nginx_rp と共有する前提です。

## 前提と依存関係
- サービスユーザーは `ssl_update` です。
- DNS プロバイダの API トークンが必要です。
- `INSTALL_ROOT/ssl_share` を介して証明書を共有します（nginx_rp 側で参照）。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/ssl_update`
- `INSTALL_ROOT/ssl_share`: `/var/ssl_share` に bind mount
- `SECRETS_DIR/ssl_update.env-user`: lego の環境変数ファイル

## ディレクトリ・ボリューム構成
- `container/scripts/`: コンテナ内 `/scripts` に read-only で bind mount
- `/var/ssl_share/accounts`: `ssl_update:ssl_update` 700
- `/var/ssl_share/certificates`: `ssl_update:nginx_rp` 750
- 親ディレクトリは 770（`ssl_update/Makefile` の post-build-root で調整）

## 環境変数・シークレット
- `SECRETS_DIR/ssl_update.env-user` を `${SERVICE_PATH}/ssl_update.env-user` に 600 で配置します。
- `EMAIL`, `DNSPROVIDER`, `DOMAIN`, `ADDITIONAL_OPTIONS`, `RENEW_OPTION`, `RUN_OPTIONS` を使用します。
- DNS プロバイダの API トークン類も lego の仕様に従って記述します。

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
- 更新が発生した場合、`/var/ssl_share/certificates/.cert-updated` を touch します。
- nginx_rp の `cert-reload.path` が上記ファイルを監視します。
- `/var/ssl_share/certificates/.executed` は毎回 touch されます。

## トラブルシュート / 注意点
- DNS プロバイダのトークン不足や権限不足で失敗する場合があります。
- レート制限を回避するため、`RENEW_OPTION` の強制実行は慎重に使用してください。
