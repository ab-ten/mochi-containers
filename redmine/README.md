# redmine

## 概要
- 公式イメージ `redmine:6.0-trixie` を rootless Podman で動かすサービスです。
- `redmine_wiki_page_tree` プラグイン（`https://github.com/ledsun/redmine_wiki_page_tree.git`）を固定リビジョンで組み込みます。
- 公開は `127.0.0.1:9001` で行い、外向き公開は nginx_rp 経由の HTTPS を前提とします。

## 前提と依存関係
- サービスユーザーは `redmine` です。
- nginx_rp 経由で公開する前提です。
- NFS の永続ディレクトリを使用します。
- `SERVICES` に `git_backend` を含める場合、`NFS_ROOT/git_backend` の read only mount を受け取り、`pre-build-root` で `NFS_ROOT/git_backend/repos` の読み取り可否を検証します。
- NFS の権限設計は `docs/UsersSetup.md` の 2 段階ディレクトリ構成（上位 + `repos`）を前提とします。
- HTTPS 証明書は `ssl_update` により `INSTALL_ROOT/ssl_share/certificates` に配置される前提です。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/redmine`
- `REDMINE_PORT`: ホスト側公開ポート（既定: 9001）
- `SLACK_NOTIFICATION`: Slack 通知用 `slack.env-user` の読み込み制御（既定: `Yes`）
- `NFS_ROOT/redmine/files`: 添付ファイル用永続領域
- `CERT_DOMAIN`: vhost 名に使用
- `MAP_LOCAL_ADDRESS`: nginx upstream の接続先に使用

## ディレクトリ・ボリューム構成
- `container/Containerfile`: Redmine イメージのビルド定義（プラグインを追加）
- `container/git_triggers/worker.rb`: `pending/` キューを取得し、`bin/rails runner` を一括起動する worker
- `container/git_triggers/run_batch.rb`: queue から取得した複数 repository の changeset 更新を一括実行する runner
- `container/git_triggers/redmine_repo_tools.rb`: repository path から Redmine の repository を特定し、changeset 更新を呼ぶ helper
- `container/git_triggers/failure_notifier.rb`: 失敗通知 hook の実行処理を共通化する notifier
- `container/git_triggers/notify-slack.sh`: changeset 更新失敗時に Slack API へ通知する hook
- `container/git_triggers/notify-systemd-failure-slack.sh`: systemd `OnFailure=` から Slack API へ通知する hook
- `https_redmine.conf`: nginx vhost 設定（`replace-files-user` で置換）
- `NFS_ROOT/redmine/files`: `/usr/src/redmine/files` に bind mount
- `home/.config/containers/systemd/redmine.container`: rootless quadlet 定義

## 環境変数・シークレット
- `SECRETS_DIR/redmine.env-user` を `${SERVICE_PATH}/redmine.env-user` に 600 で配置します。
- Redmine 公式イメージの環境変数をこのファイルに記述します。
- Redmine では `SLACK_NOTIFICATION=Yes` を既定とします。`SECRETS_DIR/slack.env-user` が存在する場合のみ、通知用 environment file が unit に追加されます。
- `SECRETS_DIR/slack.env-user` が存在しても Slack 通知を使用しない場合は、`Makefile.local` などで `SLACK_NOTIFICATION=No` を指定します。
- `SLACK_NOTIFICATION` と `@@SLACK_NOTIFICATION_ENV@@` の共通仕様は `docs/DEPLOYMENT.md` を参照してください。

### `SECRETS_DIR/redmine.env-user` サンプル
```env
REDMINE_DB_POSTGRES=<postgres-host>
REDMINE_DB_DATABASE=redmine
REDMINE_DB_USERNAME=redmine
REDMINE_DB_PASSWORD=<postgres-passwd>
REDMINE_DB_ENCODING=utf8
RAILS_ENV=production
```

Slack の token/channel は `SECRETS_DIR/redmine.env-user` ではなく、`SECRETS_DIR/slack.env-user` に記述します。

### `SECRETS_DIR/slack.env-user` サンプル
```env
SLACK_TOKEN=<slack-bot-token>
SLACK_CHANNEL=<channel-id>
```

changeset 更新失敗通知と systemd `OnFailure=` 通知は同じ `SECRETS_DIR/slack.env-user` を使用します。`SLACK_NOTIFICATION=Yes` かつ `SECRETS_DIR/slack.env-user` が存在する場合のみ、`${SERVICE_PATH}/slack.env-user` に 600 で配置され、container unit と通知 service unit の両方から読み込まれます。

## systemd / quadlet / timer 構成
- `home/.config/containers/systemd/redmine.container`
  - `PublishPort=127.0.0.1:@@REDMINE_PORT@@:3000`
  - `Volume=@@NFS_ROOT@@/redmine/files:/usr/src/redmine/files:Z`（NFS 運用では `docs/UsersSetup.md` の方針に従い `:z` / `:Z` を付けません）
  - `Volume=@@SERVICE_PATH@@/container/git_triggers:/usr/local/lib/git_triggers:ro,Z`
  - `EnvironmentFile=@@SERVICE_PATH@@/redmine.env-user`
  - `@@SLACK_NOTIFICATION_ENV@@`
- `home/.config/systemd/user/redmine-git-triggers-worker.service`
  - `Type=oneshot`
  - `ExecStart=/usr/bin/podman exec redmine /usr/local/lib/git_triggers/worker.rb -v`
- `home/.config/systemd/user/redmine-git-triggers-worker.path`
  - `DirectoryNotEmpty=@@INSTALL_ROOT@@/git_triggers/pending`
  - `Unit=redmine-git-triggers-worker.service`
- `home/.config/systemd/user/redmine-git-triggers-worker-failure-notify.service`
  - `Type=oneshot`
  - `EnvironmentFile=@@SERVICE_PATH@@/redmine.env-user`
  - `@@SLACK_NOTIFICATION_ENV@@`
  - `ExecStart=@@SERVICE_PATH@@/container/git_triggers/notify-systemd-failure-slack.sh redmine-git-triggers-worker.service`
  - `#NOSTART` により deploy 時の自動起動を抑止
- `dropins/systemd/user/systemd/redmine/redmine-git-triggers-worker.service.d/user-onfailure-slack.conf.sample`
  - `OnFailure=redmine-git-triggers-worker-failure-notify.service`
  - 利用時は sample を `user-*.conf` にコピーして有効化
- `git_backend/dropins/systemd/user/containers/redmine/redmine.container.d/git-backend-repos-ro.conf`
  - `Volume=@@NFS_ROOT@@/git_backend:/var/git:ro`
- `git_backend/dropins/systemd/user/containers/redmine/redmine.container.d/git-triggers-rw.conf`
  - `Volume=@@INSTALL_ROOT@@/git_triggers:/var/git_triggers:rw`

## 運用コマンド
- デプロイ: `make deploy` / `make redmine-deploy`
- 停止: `make stop` / `make redmine-stop`
- ログ: `sudo journalctl -M "redmine@.host" --user -u redmine.service`
- worker service ログ: `sudo journalctl -M "redmine@.host" --user -u redmine-git-triggers-worker.service`
- path unit 状態: `sudo systemctl -M "redmine@.host" --user status redmine-git-triggers-worker.path`
- OnFailure 通知 service ログ: `sudo journalctl -M "redmine@.host" --user -u redmine-git-triggers-worker-failure-notify.service`
- OnFailure 通知テスト: `redmine-git-triggers-worker.service` の `ExecStart` を一時的に `/usr/bin/false` へ変更して `make redmine-deploy` を実行し、`sudo systemctl -M "redmine@.host" --user start redmine-git-triggers-worker.service` で失敗通知を確認します。確認後は `ExecStart` を元に戻して再デプロイしてください。
- worker 手動実行: `podman exec redmine /usr/local/lib/git_triggers/worker.rb -v`
- worker 詳細ログ: `podman exec redmine /usr/local/lib/git_triggers/worker.rb -vv`
- worker 排他確認: `podman exec redmine /usr/local/lib/git_triggers/worker.rb -p`
- worker 通知テスト: `podman exec redmine /usr/local/lib/git_triggers/worker.rb -f`
- `make redmine-deploy` は redmine 単体のみ更新します。`https_redmine.conf` の変更を nginx 公開設定へ反映する場合は `make deploy` または `make nginx_rp-deploy` も実行してください。

## 連携メモ
- nginx の upstream は `@@MAP_LOCAL_ADDRESS@@:@@REDMINE_PORT@@` を参照します。
- `https_redmine.conf` は `nginx_rp` の `pre-build-root` で収集されます。
- プラグイン更新は `container/Containerfile` の `WIKI_PAGE_TREE_SHA` を更新して再ビルドします。
- `git_backend` の post-receive hook は `/var/git_triggers/pending/<repo_name>` を作成します。
- worker は `pending/` から queue を `processing/` へ移動して取得し、今回取得した repository のみを 1 回の `bin/rails runner` で一括更新します。
- `redmine-git-triggers-worker.path` は host 側 `@@INSTALL_ROOT@@/git_triggers/pending` が非空になると oneshot worker service を起動します。
- `redmine-git-triggers-worker.service` の `OnFailure=` は sample drop-in で任意に有効化できます。通知 service 自体は `#NOSTART` 付きなので、`OnFailure=` から参照された時だけ起動されます。
- `processing/` に残った queue は自動回復しません。必要に応じて内容を確認し、手動で `pending/` へ戻して再投入してください。
- changeset 更新失敗時は、既定で `/usr/local/lib/git_triggers/notify-slack.sh` を `repo_name` と `error_message` を引数にして実行します。追加で `GIT_TRIGGERS_REPO_NAME`、`GIT_TRIGGERS_REPO_PATH`、`GIT_TRIGGERS_ERROR_MESSAGE`、`GIT_TRIGGERS_ERROR_CLASS` を環境変数として渡します。`GIT_TRIGGERS_FAILURE_HOOK` を指定した場合は、その hook で既定 hook を上書きします。
- `worker.rb -f` は queue 処理を行わず、実運用と同じ notifier 経路でテスト用失敗通知を 1 回送信します。
- `notify-slack.sh` は `SLACK_TOKEN` と `SLACK_CHANNEL` の両方が設定されている場合のみ Slack API へ通知します。どちらかが未設定の場合は通知をスキップして 0 で終了します。
- `notify-systemd-failure-slack.sh` は host 側 user systemd service から実行され、`slack.env-user` の `SLACK_TOKEN` / `SLACK_CHANNEL` を使用して通知します。未設定時は通知をスキップして 0 で終了します。

## トラブルシュート / 注意点
- NFS の権限が不足する場合は `make -C redmine print-uid-gid` またはリポジトリルートで `make redmine-get-uid` / `make redmine-get-gid` を実行して UID/GID を確認し、`NFS_ROOT/redmine` の所有権と権限を調整してください。
- `SERVICES` に `git_backend` を含める場合、`pre-build-root` は `UID_IN_PODMAN:GID_IN_PODMAN` 相当権限で `NFS_ROOT/git_backend/repos` の読み取り可否を検証します。失敗時はエラーメッセージに従って group と権限を調整してください。
- `pre-build-root` で `setpriv` を使用します。`util-linux` をインストールしてください。
- worker の排他 lock は `/tmp/redmine-git-triggers-worker.lock` に作成されます。二重起動時は即時失敗します。
- SELinux 有効環境で NFS を bind mount する場合は `virt_use_nfs=on` を前提に `:z` / `:Z` を付けません。`redmine` と `git_backend` のようにサービスユーザー間で共有する NFS mount を扱うためです。ローカルディスクの bind mount のみ `:z` / `:Z` を使用してください。
