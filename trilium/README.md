# trilium

## 概要
- TriliumNext を rootless Podman で動かすサービスです。
- 公式イメージ `ghcr.io/triliumnext/notes:latest` をベースにローカルイメージをビルドします。

## 前提と依存関係
- サービスユーザーは `trilium` です。
- nginx_rp 経由で公開する前提です。
- SQLite DB は NFS に置かず、`DBFILE_DIR` に配置します。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/trilium`
- `TRILIUM_PORT`: ホスト側公開ポート（既定: 9002）
- `DBFILE_DIR`: SQLite DB を保持するローカルパス（既定: `/srv/project/trilium_db`）
- `CERT_DOMAIN`: vhost 名に使用
- `MAP_LOCAL_ADDRESS`: nginx upstream の接続先に使用

## ディレクトリ・ボリューム構成
- `container/Containerfile`: TriliumNext イメージのビルド定義
- `https_trilium.conf`: nginx vhost 設定（`replace-files-user` で置換）
- `DBFILE_DIR`: `/home/node/trilium-data` に bind mount
- `home/.config/containers/systemd/trilium.container`: rootless quadlet 定義

## 環境変数・シークレット
- 環境変数ファイルは使用しません。

## systemd / quadlet / timer 構成
- `home/.config/containers/systemd/trilium.container`
  - `PublishPort=127.0.0.1:@@TRILIUM_PORT@@:8080`
  - `Volume=@@DBFILE_DIR@@:/home/node/trilium-data:Z`
  - `REPLACE_ADD_VAR=TRILIUM_PORT DBFILE_DIR` で置換します。

## 運用コマンド
- デプロイ: `make deploy` / `make trilium-deploy`
- 停止: `make stop` / `make trilium-stop`
- ログ: `sudo journalctl -M "trilium@.host" --user -u trilium.service`

## 連携メモ
- nginx の upstream は `@@MAP_LOCAL_ADDRESS@@:@@TRILIUM_PORT@@` を参照します。
- `https_trilium.conf` は `nginx_rp` の `pre-build-root` で収集されます。

## トラブルシュート / 注意点
- `DBFILE_DIR` はローカルディスク上に作成されます。バックアップ転送は別途計画・運用してください。
- SELinux 有効環境では bind mount に `:Z` を付与しています。
