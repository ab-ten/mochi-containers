# host_services systemd units (root)

このディレクトリには root 権限で動作する systemd unit を配置します。

## 配置対象

- `*.service`
- `*.socket`
- `*.timer`
- `*.path`

上記のファイルは deploy 時に `/etc/systemd/system/` へコピーされ、ファイル名の先頭に `@@ROOT_UNIT_PREFIX@@` が付与されます。

## テンプレート変数

- `@@ROOT_UNIT_PREFIX@@`
- `@@SERVICE_PATH@@`
- `@@INSTALL_ROOT@@`
- `@@SERVICE_NAME@@`
- `@@SERVICE_USER@@`
- `@@STARTUP_SENTINEL_RECHECK_DELAY@@`

deploy 時に未置換の `@@...@@` が残っている場合はエラーになります。

## 注意点

- user systemd unit や quadlet はこのサービスでは使用しません。
- 将来 root unit を追加する場合は、必要に応じて `dropins/systemd/root/` も併用してください。
- `startup_sentinel.service` は static unit として配置し、`startup_sentinel.timer` からのみ起動します。
- `startup_sentinel.timer` は `WantedBy=timers.target` と `OnActiveSec=5min` を使用し、timer 有効化から 5 分後に一度だけ service を起動します。
