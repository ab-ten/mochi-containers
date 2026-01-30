# security_package

## 概要
- systemd-socket-proxyd の bind/connect を許可するローカル SELinux ポリシーを RPM 化するサービスです。
- 生成した RPM は `INSTALL_ROOT/rpms/` に配置し、ホストへ導入します。

## 前提と依存関係
- サービスユーザーは `security_package` です。
- SELinux が有効な環境を前提とします。
- nginx_rp の root systemd socket activation を使用する環境で必要になります。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/security_package`
- `INSTALL_ROOT/rpms`: RPM の配置先
- `rpmbuild/VERSION.mk`: `PKGVER` / `PKGREL` の管理元

## ディレクトリ・ボリューム構成
- `container/Containerfile`: rpmbuild 用コンテナ
- `rpmbuild/SOURCES/local_mochi_security.te`: ポリシー本体
- `rpmbuild/SPECS/local-mochi-security-selinux.spec`: spec ファイル
- `rpmbuild/VERSION.mk`: EVR 管理
- `out/`: ビルド成果物
- `.package-evr`: デプロイ時の EVR キャッシュ
- `check-version-consistency.sh`: VERSION/changelog 整合性チェック

## 環境変数・シークレット
- `SPEC_USER_NAME` / `SPEC_EMAIL_ADDRESS` は `Makefile.local` で上書きできます。

## systemd / quadlet / timer 構成
- 該当なし（systemd unit は使用しません）。

## 運用コマンド
- デプロイ: `make deploy` / `make security_package-deploy`
- 停止: `make stop` / `make security_package-stop`
- ログ: systemd unit がないため、デプロイ時の標準出力を確認します。

## 連携メモ
- 生成された RPM は `transactional-update pkg install` で導入し、再起動が必要です。
- SELinux の許可が不足している場合は nginx_rp の起動に失敗します。

## トラブルシュート / 注意点
- ポリシー更新時は `PKGREL` の更新と `%changelog` の追記が必要です。
- `check-version-consistency.sh` で更新漏れを検知できます。
