# host_services

## 概要
- ホスト側で直接動作する root systemd unit を配置するためのサービスです。
- rootless Podman や user systemd unit は使用しません。

## 前提と依存関係
- サービスユーザーは `host_services` です。
- 実行対象は root systemd unit です。
- user unit / quadlet は配置しません。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/host_services`
- 配置先 systemd ディレクトリ: `/etc/systemd/system`
- unit プレフィックス: `@@ROOT_UNIT_PREFIX@@`
- `STARTUP_SENTINEL_RECHECK_DELAY`: `systemd-logind` 再起動後に `/run/user/<uid>` を再確認するまでの待機秒数。既定値は `7` 秒で、`host_services/Makefile.local` から上書きできます。

## ディレクトリ・ボリューム構成
- `systemd/`: root systemd unit の配布元です。
- `dropins/systemd/root/`: root systemd unit 向け drop-in の配布元です。

## systemd / quadlet / timer 構成
- `systemd/` 配下の `*.service` / `*.socket` / `*.timer` / `*.path` を root systemd unit として配置します。
- 配置時にはファイル名の先頭に `${SERVICE_PREFIX}-${SERVICE_NAME}-` が付与されます。
- user systemd unit / quadlet / user timer は使用しません。

## startup_sentinel
- `startup_sentinel.sh` は引数で受け取った `${SERVICE_PATH}/startup_uid_list` を読み取り、rootless Podman や user systemd の起動に必要な `/run/user/<uid>` が揃っているか確認します。
- `startup_sentinel.sh` は第 2 引数で受け取った待機秒数ぶん `systemd-logind` 再起動後に `sleep` してから `/run/user/<uid>` を再確認します。
- `startup_uid_list` は deploy 時に `SERVICES` を走査し、各サービスの `${INSTALL_ROOT}/<service>/.startup_linger` から収集した UID を `sort -u` 相当で正規化して生成します。
- `post-build-root` は `startup_uid_list` 生成直後に有効な UID 件数を標準出力へ表示します。
- `startup_sentinel.service` は root 権限で上記スクリプトを実行します。欠損した `/run/user/<uid>` が 1 件以上ある場合のみ `systemctl restart systemd-logind` を実行し、不要な再起動を避けます。
- `startup_sentinel.service` は script を直接 exec せず、`/usr/bin/bash` 経由で `${SERVICE_PATH}/startup_sentinel.sh ${SERVICE_PATH}/startup_uid_list` を実行します。
- `startup_sentinel.service` 自体は static unit であり、deploy 時に自動起動されません。起動契機は `startup_sentinel.timer` に限定します。
- `startup_sentinel.timer` は `timers.target` にぶら下げ、timer 自身が有効化されてから 5 分後に一度だけ `startup_sentinel.service` を起動します。
- この構造にする理由は、対象 UID の収集と復旧判定を `host_services` に集約し、各アプリケーションサービスへ個別の root unit や復旧ロジックを分散させないためです。
- また、起動契機を root timer に統一することで、通常再起動と userspace の再起動の両方で同じ unit 構成を再利用しやすくします。
- UID 一覧を deploy 時生成にすることで、runtime では静的ファイルを読むだけで判定でき、サービス追加・削除時の追従も `SERVICES` と `.startup_linger` の実体に委ねられます。

## 運用コマンド
- デプロイ: `make deploy` / `make host_services-deploy`
- 停止: `make stop` / `make host_services-stop`
- ログ: `sudo journalctl -u <配置後の unit 名>`

## 連携メモ
- `@@SERVICE_PATH@@` や `@@ROOT_UNIT_PREFIX@@` などのプレースホルダーは deploy 時に置換されます。
- unit の実体が未配置でも、サービス雛形としてデプロイ可能です。
- user unit を持たないため、deploy 時に `.startup_linger` は作成されません。

## トラブルシュート / 注意点
- root systemd unit 以外のファイルを `systemd/` に置いても deploy 対象にはなりません。
- このサービスでも共通 deploy 処理により `/home/host_services` は作成されますが、運用上の user unit は使用しません。
