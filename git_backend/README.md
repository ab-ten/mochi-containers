# git_backend

## 概要
- `git-http-backend` を rootless Podman で提供するサービスです。
- `git_backend`（`fcgiwrap`）と `git_backend-nginx`（Basic 認証付き HTTP reverse proxy）の 2 コンテナで構成します。
- 外向き公開は `nginx_rp` 経由の HTTPS を前提とし、`nginx_rp` からは `git_backend-nginx` へ HTTP で接続します。

## 前提と依存関係
- サービスユーザーは `git_backend` です。
- `nginx_rp` と `ssl_update` が先にデプロイ設定済みであることを前提とします。
- `nginx_rp` は TLS 終端と reverse proxy のみを担当し、Basic 認証と FastCGI は `git_backend` 側で処理します。
- bare リポジトリの永続領域として `NFS_ROOT/git_backend/repos` を使用します。
- `SERVICES` に `redmine` を含める場合、`pre-build-root` は `${INSTALL_ROOT}/git_triggers` をローカルディスク上に作成し、将来の更新トリガ連携に備えます。
- HTTPS 証明書は `ssl_update` により `INSTALL_ROOT/ssl_share/certificates` に配置される前提です。

## クイックスタート
- サービスをデプロイする場合は `make deploy` または `make git_backend-deploy` を実行してください。
- bare リポジトリを追加する場合は `sudo ${INSTALL_ROOT}/bin/git-backend-create-repo <name>.git` を実行してください。
- リポジトリ名の命名規則だけ確認する場合は `sudo ${INSTALL_ROOT}/bin/git-backend-create-repo -n <name>.git` を実行してください。
- リポジトリ作成成功時は、作成先パスに加えて利用するリポジトリ URL が表示されます。

### 実行例
```text
$ sudo /srv/project/bin/git-backend-create-repo sample.git
created: /srv/nfs/containers/git_backend/repos/sample.git
repository url: https://git.example.com/sample.git
```

## リポジトリ追加
- リポジトリ名は `^[A-Za-z0-9][A-Za-z0-9._-]*\.git$` に一致させてください。
- 先頭文字は英数字とし、使用可能な文字は英数字、`.`、`_`、`-`、末尾の `.git` のみです。
- `-n` オプションを付けると、bare リポジトリは作成せず命名規則の検証のみを行います。
- コマンドは `git_backend` サービスユーザー権限で bare リポジトリを作成します。
- 表示された URL を clone / remote URL に使用してください。
- Basic 認証は `git_backend-nginx` 側で実施します。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/git_backend`
- `GIT_BACKEND_PORT`: ホスト側公開ポート（既定: 9010、`git_backend-nginx` が待ち受け）
- `FCGIWRAP_CHILDREN`: `fcgiwrap` の子プロセス数（既定: 4）
- `GIT_BACKEND_SOCK_VOLUME`: `fcgiwrap` と `git_backend-nginx` が共有する Podman volume 名（既定: `git_backend_fcgi_sock`）
- `NFS_ROOT/git_backend/repos`: bare リポジトリ永続領域
- `INSTALL_ROOT/git_triggers`: `redmine` 連携用のローカル共有ディレクトリ
- `CERT_DOMAIN`: vhost 名に使用します。
- `MAP_LOCAL_ADDRESS`: `nginx_rp` の `proxy_pass` 接続先に使用します。

## ディレクトリ・ボリューム構成
- `container/Containerfile`: `fcgiwrap + git-http-backend` イメージのビルド定義（UNIX domain socket 待受）
- `container.nginx/Containerfile`: Basic 認証付き reverse proxy 用 nginx イメージのビルド定義
- `container.nginx/default.conf`: `git_backend-nginx` 内の FastCGI 設定
- `http_git_backend.conf`: HTTP から HTTPS へのリダイレクト設定
- `https_git_backend.conf`: `nginx_rp` 側の reverse proxy vhost 設定（`replace-files-user` で置換）
- `NFS_ROOT/git_backend`: `/var/git` への bind mount（NFS サーバー準備完了までは quadlet で無効化可能）
- `INSTALL_ROOT/git_triggers`: `redmine` と共有するローカルディレクトリ（`pending/`, `processing/` を含む）
- `home/.config/containers/systemd/git_backend.container`: `fcgiwrap` 用 rootless quadlet 定義
- `home/.config/containers/systemd/git_backend-nginx.container`: 認証プロキシ用 rootless quadlet 定義
- `dropins/systemd/user/containers/redmine/redmine.container.d/git-backend-repos-ro.conf`: `redmine` コンテナへ `NFS_ROOT/git_backend` を read only で配布する drop-in
- `GIT_BACKEND_SOCK_VOLUME`: 両コンテナで共有する UNIX domain socket 用 Podman volume（`post-build-user` で作成）
- `${SERVICE_PATH}/git_backend.htpasswd`: `pre-build-root` で配置する Basic 認証ファイル
- `scripts/create-repo.sh`: bare リポジトリ作成スクリプト
- `bin/git-backend-create-repo`: deploy 時に `${INSTALL_ROOT}/bin/git-backend-create-repo` として配置するラッパースクリプト

## 環境変数・シークレット
- `SECRETS_DIR/git_backend.htpasswd` を `pre-build-root` で `${SERVICE_PATH}/git_backend.htpasswd` に配置します。
- Basic 認証は `git_backend-nginx` 側で実施します。

### `SECRETS_DIR/git_backend.htpasswd` サンプル
```text
git:$2y$10$exampleexampleexampleexampleexampleexampleexampleexample
```

## systemd / quadlet / timer 構成
- `home/.config/containers/systemd/git_backend.container`
  - `Volume=@@GIT_BACKEND_SOCK_VOLUME@@:/run/git-backend-fcgi`
  - `Volume=@@NFS_ROOT@@/git_backend:/var/git:rw`（NFS 用。`docs/UsersSetup.md` の方針に従い `:z` / `:Z` は付けません）
  - `Environment=FCGIWRAP_CHILDREN=@@FCGIWRAP_CHILDREN@@`
- `home/.config/containers/systemd/git_backend-nginx.container`
  - `Requires=git_backend.service`, `After=git_backend.service`
  - `PublishPort=127.0.0.1:@@GIT_BACKEND_PORT@@:80`
  - `Volume=@@GIT_BACKEND_SOCK_VOLUME@@:/run/git-backend-fcgi`
  - `Volume=@@SERVICE_PATH@@/git_backend.htpasswd:/etc/nginx/git_backend.htpasswd:ro,Z`
- 置換変数には `REPLACE_ADD_VAR=GIT_BACKEND_PORT FCGIWRAP_CHILDREN GIT_BACKEND_SOCK_VOLUME` を使用します。

## 運用コマンド
- デプロイ: `make deploy` / `make git_backend-deploy`
- 停止: `make stop` / `make git_backend-stop`
- ログ: `sudo journalctl -M "git_backend@.host" --user -u git_backend.service -u git_backend-nginx.service`
- リポジトリ作成: `sudo ${INSTALL_ROOT}/bin/git-backend-create-repo <name>.git`
- リポジトリ名検証: `sudo ${INSTALL_ROOT}/bin/git-backend-create-repo -n <name>.git`
- `make git_backend-deploy` は git_backend 単体のみ更新します。`https_git_backend.conf` / `http_git_backend.conf` の変更を nginx 公開設定へ反映する場合は `make deploy` または `make nginx_rp-deploy` も実行してください。

## 連携メモ
- `nginx_rp` の `proxy_pass` は `@@MAP_LOCAL_ADDRESS@@:@@GIT_BACKEND_PORT@@` を参照します。
- `https_git_backend.conf` / `http_git_backend.conf` は `nginx_rp` の `pre-build-root` で収集されます。
- `git_backend-nginx` は Basic 認証の後に `fastcgi_pass unix:/run/git-backend-fcgi/git-http-backend.sock` で `fcgiwrap` に転送します。
- `container/Containerfile` は `git_backend_sock`（既定 GID: 4096）を解決し、`/run/git-backend-fcgi` を `root:<socket-group>` + `2770` で準備したうえで `umask 007` で `fcgiwrap` を起動します。
- `container.nginx/Containerfile` は nginx ユーザーを `git_backend_sock`（既定 GID: 4096）へ追加し、UNIX socket への group write 接続を許可します。
- `post-build-user` は `GIT_BACKEND_SOCK_VOLUME` が存在しない場合に自動作成します。
- `pre-build-root` は `SERVICES` に `redmine` を含める場合、`make redmine-get-gid` で取得した host 側 GID を group に使用し、`${INSTALL_ROOT}/git_triggers` を 0751、`pending/` を 2770、`processing/` を 0070 で作成・調整します。
- `post-build-root` は `${INSTALL_ROOT}/bin/git-backend-create-repo` を配置し、`@@NFS_ROOT@@` などのテンプレートを実値へ置換します。
- `dropins/systemd/user/containers/redmine/redmine.container.d/git-backend-repos-ro.conf` を配置すると、`redmine` デプロイ時に `NFS_ROOT/git_backend` が `/var/git` へ `read only` で mount されます（リポジトリ実体は `/var/git/repos`）。
- 補助: 直接実行する場合は `sudo -u git_backend env NFS_ROOT=/srv/nfs/containers /srv/project/git_backend/scripts/create-repo.sh sample.git`

## トラブルシュート / 注意点
- `SECRETS_DIR/git_backend.htpasswd` は `htpasswd` 形式で作成してください。
  - 例: `htpasswd -nB -C 10 git 'YOUR_PASSWORD'`
- UNIX domain socket 連携で問題が出た場合は、`git_backend` と `git_backend-nginx` の両サービスログを確認してください。
- `NFS_ROOT` の bind mount を無効化している場合、リポジトリはコンテナ内の一時領域でのみ参照可能です。永続運用時は bind mount を有効化してください。
- SELinux 有効環境で NFS を bind mount する場合は `virt_use_nfs=on` を前提に `:z` / `:Z` を付けません。`git_backend` と `redmine` などサービスユーザー間で共有する NFS mount を扱うためです。ローカルディスクの bind mount のみ `:z` / `:Z` を使用してください。
