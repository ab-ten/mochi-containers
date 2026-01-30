# Repository Guidelines

## Project Structure & Module Organization
- ルートの `Makefile` でサービス一覧を管理し、`nginx_rp/` が現在のサンプルサービス。今後も `<service>/container`, `<service>/config`, `<service>/systemd`, `<service>/home/.config/containers/systemd/`  を並べる構成を徹底（リポジトリ上の配置）。デプロイ時は user unit / quadlet を `/home/<service>/.config/containers/systemd/` に展開する。
- 共通ターゲットは `mk/services.mk` に集約。サービス個別の `Makefile` では `SERVICE_NAME`, `SERVICE_USER`, `SERVICE_PATH` を定義して include する。
- `nginx_rp/container/` 配下はコンテナビルド素材（`Containerfile`, `default.conf`, `html/index.html`）。`config/` や `systemd/` は将来の本番用設定・systemd 連携を置く想定だが、稼働させる user unit / quadlet は `<service>/home/.config/containers/systemd/` に必ず配置する（実際の稼働先は `/home/<service>/.config/containers/systemd/`）。
- rootless 前提のため、systemd user unit と quadlet（`.service` / `.socket` / `.container` など）は `<service>/home/.config/containers/systemd/` に必ずまとめて配置し、デプロイ時に `/home/<service>/.config/containers/systemd/` へ同期する。user timer / service (`*.timer` など) は systemd 標準の `<service>/home/.config/systemd/user/` に置き、デプロイ時に `/home/<service>/.config/systemd/user/` へ同期する。
- root での systemd unit が必要な場合は <service>/systemd/ に配置をする（特権ポートへの systemd socket activation を使用したい場合など）

## Build, Test, and Development Commands
- `make` または `make all` … 管理対象サービスの一覧を表示。
- `make deploy|restart|status` … ルートから呼ぶと各サービスの同名ターゲットを実行（systemd user サービス向け）。
- rootless Podman の systemd user unit を操作するときは `sudo systemctl -M "${SERVICE_USER}@.host" --user <cmd>` を使うこと（`sudo <user> systemctl` だと dbus に繋がらず失敗する）。

## Coding Style & Naming Conventions
- Makefile はタブインデント必須。ターゲット名・変数名は小文字スネーク or 大文字スネークで統一（例: `SERVICE_NAME`）。
- nginx 設定と HTML は 2 スペースインデント。ファイル名は役割を明示（`default.conf`, `index.html`）。
- サービスディレクトリ名は小文字スネークでサービスユーザーと合わせる（例: `nginx_rp` → `nginx_rp` ユーザー）。

## Docs
- デプロイ仕様は `docs/DEPLOYMENT.md` に集約。更新があればここも最新に反映すること。
- 作業メモや現在の進行状況は `CURRENT.md` を必要に応じて更新・参照すること。
- `scripts/pre-deploy-check.sh` と `docs/pre-deploy-check.md`、`scripts/deploy-service.sh` と `docs/deploy-service.md` の内容は常に同期してください（詳細は `scripts/AGENTS.md` を参照）。
- デプロイ関連の必須環境変数は `docs/DEPLOYMENT.md` / `docs/pre-deploy-check.md` / `docs/deploy-service.md` で同一の一覧になるよう維持してください。
- 各サービスの `README.md` は、以下の章構成を基準に作成・更新してください。運用手順は `make deploy` / `make <service>-deploy` と `make stop` / `make <service>-stop` を前提とし、詳細なデプロイ手順は不要です。
  - 概要（目的 / 非目的 / 対象範囲）
  - 前提と依存関係（サービスユーザー、他サービスとの連携、順序）
  - 主要パラメータ一覧（`SERVICE_PATH`、公開ポート、必須変数など）
  - ディレクトリ・ボリューム構成（bind mount / NFS を含む）
  - 環境変数・シークレット（配置先、必須項目、サンプル）
  - systemd / quadlet / timer 構成（unit 一覧、drop-in 運用）
  - 運用コマンド（デプロイ / 停止 / ログの入口のみ）
  - 連携メモ（nginx、証明書、外部依存）
  - トラブルシュート / 注意点（SELinux など）
- 環境変数ファイル（`.env` / `*.env-user` / `*.env-root`）は、サービスの `Makefile` に `env-files-user` / `env-files-root` が定義され、かつ container quadlet に `EnvironmentFile=` がある場合のみ README に記載してください。両方の条件を満たさないサービスでは、環境変数ファイルに関する記述を行わないでください。

## ハードコードされた文字列をmake変数・環境変数を用いてパラメータ化する場合
- 既定値はルート `Makefile` に定義します。ユーザーは必要に応じて git 管理外の Makefile.local を用いてカスタマイズします。
- ルート `Makefile` から子 `make` に値を必ず引き渡し、`scripts/deploy-service.sh` の `run_user_make` でも環境変数を伝播してください。
- `scripts/pre-deploy-check.sh` / `scripts/deploy-service.sh` の必須チェックに追加し、パスは末尾スラッシュ除去などの正規化を行ってください。
- unit/quadlet/drop-in で参照する場合は `@@VAR@@` 形式に置き換え、`scripts/replace-deploy-vars.sh` の `REPLACEMENT_VARS` に追加してください。
- 変更した変数は `docs/DEPLOYMENT.md` / `docs/pre-deploy-check.md` / `docs/deploy-service.md` の一覧へ追記し、サービスの README も更新してください。

## Testing Guidelines
- 自動テスト基盤は未整備。変更時は `podman build` → `podman run` → `curl` で実際にレスポンスを確認。
- nginx 設定を編集したらコンテナ内で `nginx -t` を走らせて構文エラーを防ぐ（`podman run --rm localhost/nginx_rp:dev nginx -t` など）。
- デプロイ前にローカルポートでの挙動を最小限チェックすること。

## Commit & Pull Request Guidelines
- コミットメッセージは英語の命令形 50 文字以内を基本（例: “Add nginx reverse proxy container”）。セットアップ・設定・ドキュメントはプレフィックスで簡潔に区別しても良い（`build:`, `config:`, `docs:`）。
- PR では目的、主要変更点、テスト結果（`podman build/run` と確認方法）を箇条書きで記載。設定変更時は対象ファイルパスと影響範囲を明記。
- 新サービス追加時は README 的なミニガイドを `<service>/AGENTS.md` に置き、実行ユーザーや公開ポートを説明するとスムーズ。

## Security & Configuration Tips
- ルートレス Podman 前提。サービスごとに専用ユーザーを分け、`/srv/project/<service>` へ rsync でデプロイする設計を守る。サービスユーザーのホームディレクトリは OS 既定の `/home/<service>` を使う（Podman のストレージ前提に合わせてホームを外出ししない）。
- 永続データは `NFS_ROOT/<user>` など外部ボリュームを bind mount する方針。権限はサービスユーザーに合わせて調整。
- SELinux が有効な Podman 環境では bind mount に `:Z`（read only の場合は `:ro,Z`）を必ず付けること。context が付かずに起動失敗するのを防ぐ。
- 本番公開時は systemd socket activation（443 → 8443）や lego ベースの DNS-01 証明書運用を見据え、関連ファイルは `quadlet/` や `config/` に整理する。

## コミットメッセージルール
- 必ず日本語で回答し、コミットメッセージは Conventional Commits のルールに則って記述してください。
- 変更内容を簡潔かつ分かりやすく説明してください。
- 変更内容を詳細に説明し、複数行のメッセージを生成してください。
- 変更の理由や影響についても言及してください。
- ドキュメントのみの変更、もしくは最重要の変更がドキュメントの場合は、`docs:` プレフィックスを使用してください。
- テストのみの追加・変更、もしくは最重要の変更がテストの場合は、`test:` プレフィックスを使用してください。

## 各サービスのドキュメント
- 各サービスのドキュメントはそのサービスのディレクトリ内の README.md に記述する（例： nginx_rp/README.md）
