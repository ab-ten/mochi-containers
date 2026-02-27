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
- `NFS_ROOT/redmine/files`: 添付ファイル用永続領域
- `CERT_DOMAIN`: vhost 名に使用
- `MAP_LOCAL_ADDRESS`: nginx upstream の接続先に使用

## ディレクトリ・ボリューム構成
- `container/Containerfile`: Redmine イメージのビルド定義（プラグインを追加）
- `https_redmine.conf`: nginx vhost 設定（`replace-files-user` で置換）
- `NFS_ROOT/redmine/files`: `/usr/src/redmine/files` に bind mount
- `home/.config/containers/systemd/redmine.container`: rootless quadlet 定義

## 環境変数・シークレット
- `SECRETS_DIR/redmine.env-user` を `${SERVICE_PATH}/redmine.env-user` に 600 で配置します。
- Redmine 公式イメージの環境変数をこのファイルに記述します。

### `SECRETS_DIR/redmine.env-user` サンプル
```env
REDMINE_DB_POSTGRES=<postgres-host>
REDMINE_DB_DATABASE=redmine
REDMINE_DB_USERNAME=redmine
REDMINE_DB_PASSWORD=<postgres-passwd>
REDMINE_DB_ENCODING=utf8
```

## systemd / quadlet / timer 構成
- `home/.config/containers/systemd/redmine.container`
  - `PublishPort=127.0.0.1:@@REDMINE_PORT@@:3000`
  - `Volume=@@NFS_ROOT@@/redmine/files:/usr/src/redmine/files:Z`（NFS 運用では `docs/UsersSetup.md` の方針に従い `:z` / `:Z` を付けません）
  - `EnvironmentFile=@@SERVICE_PATH@@/redmine.env-user`
- `git_backend/dropins/systemd/user/containers/redmine/redmine.container.d/git-backend-repos-ro.conf`
  - `Volume=@@NFS_ROOT@@/git_backend:/var/git:ro`

## 運用コマンド
- デプロイ: `make deploy` / `make redmine-deploy`
- 停止: `make stop` / `make redmine-stop`
- ログ: `sudo journalctl -M "redmine@.host" --user -u redmine.service`
- `make redmine-deploy` は redmine 単体のみ更新します。`https_redmine.conf` の変更を nginx 公開設定へ反映する場合は `make deploy` または `make nginx_rp-deploy` も実行してください。

## 連携メモ
- nginx の upstream は `@@MAP_LOCAL_ADDRESS@@:@@REDMINE_PORT@@` を参照します。
- `https_redmine.conf` は `nginx_rp` の `pre-build-root` で収集されます。
- プラグイン更新は `container/Containerfile` の `WIKI_PAGE_TREE_SHA` を更新して再ビルドします。

## トラブルシュート / 注意点
- NFS の権限が不足する場合は `make -C redmine print-uid-gid` で UID/GID を確認し、`NFS_ROOT/redmine` の所有権と権限を調整してください。
- `SERVICES` に `git_backend` を含める場合、`pre-build-root` は `UID_IN_PODMAN:GID_IN_PODMAN` 相当権限で `NFS_ROOT/git_backend/repos` の読み取り可否を検証します。失敗時はエラーメッセージに従って group と権限を調整してください。
- `pre-build-root` で `setpriv` を使用します。`util-linux` をインストールしてください。
- SELinux 有効環境で NFS を bind mount する場合は `virt_use_nfs=on` を前提に `:z` / `:Z` を付けません。ローカルディスクの bind mount のみ `:z` / `:Z` を使用してください。
