# trilium

## 概要
- TriliumNext を rootless Podman で動かすサービスです。
- 公式イメージ `ghcr.io/triliumnext/trilium:stable` をベースにローカルイメージをビルドします。

## 前提と依存関係
- サービスユーザーは `trilium` です。
- nginx_rp 経由で公開する前提です。
- SQLite DB は NFS に置かず、`DBFILE_DIR` に配置します。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/trilium`
- `TRILIUM_PORT`: ホスト側公開ポート（既定: 9002）
- `DBFILE_DIR`: SQLite DB を保持するローカルパス（既定: `/srv/project/trilium_db`）
- `NFS_ROOT/trilium`: バックアップ永続領域
- `CERT_DOMAIN`: vhost 名に使用
- `MAP_LOCAL_ADDRESS`: nginx upstream の接続先に使用

## ディレクトリ・ボリューム構成
- `container/Containerfile`: TriliumNext イメージのビルド定義
- `container/custom-build.sh.sample`: カスタムビルド用スクリプトのサンプル
- `https_trilium.conf`: nginx vhost 設定（`replace-files-user` で置換）
- `DBFILE_DIR`: `/home/node/trilium-data` に bind mount
- `NFS_ROOT/trilium`: /trilium_backup に bind mount（`pre-build-root` で書き込み権チェック）
- `home/.config/containers/systemd/trilium.container`: rootless quadlet 定義

## 環境変数・シークレット
- 環境変数ファイルは使用しません。

## systemd / quadlet / timer 構成
- `home/.config/containers/systemd/trilium.container`
  - `PublishPort=127.0.0.1:@@TRILIUM_PORT@@:8080`
  - `Volume=@@DBFILE_DIR@@:/home/node/trilium-data:Z`
  - `Volume=@@NFS_ROOT@@/trilium:/trilium_backup:Z`
  - `REPLACE_ADD_VAR=TRILIUM_PORT DBFILE_DIR` で置換します。
  - `NFS_ROOT` は共通必須変数として置換します。

## 運用コマンド
- デプロイ: `make deploy` / `make trilium-deploy`
- 停止: `make stop` / `make trilium-stop`
- ログ: `sudo journalctl -M "trilium@.host" --user -u trilium.service`
- `make trilium-deploy` は trilium 単体のみ更新します。`https_trilium.conf` の変更を nginx 公開設定へ反映する場合は `make deploy` または `make nginx_rp-deploy` も実行してください。

## 連携メモ
- nginx の upstream は `@@MAP_LOCAL_ADDRESS@@:@@TRILIUM_PORT@@` を参照します。
- `https_trilium.conf` は `nginx_rp` の `pre-build-root` で収集されます。

## トラブルシュート / 注意点
- `DBFILE_DIR` はローカルディスク上に作成されます。
- `NFS_ROOT/trilium` は `pre-build-root` で作成・チェックされます。初回構築時は `make -C trilium print-uid-gid` またはリポジトリルートで `make trilium-get-uid` / `make trilium-get-gid` を実行して UID/GID を確認し、必要に応じて NFS 側の所有権を調整してください。
- SELinux 有効環境では bind mount に `:Z` を付与しています。
- `custom-build.sh` が未配置の場合は `scripts/container-build.sh` による共通ビルドが実行されます。タイムゾーンなどのビルド引数を変更する場合は、`container/custom-build.sh.sample` を `container/custom-build.sh` にコピーして実行権限を付与してください。
