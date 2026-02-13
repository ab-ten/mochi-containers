# `scripts/deploy-vars.subr` 実装メモ

`scripts/deploy-vars.subr` を編集した場合は、必ず本ドキュメントと `docs/DEPLOYMENT.md` / `docs/pre-deploy-check.md` / `docs/deploy-service.md` を同期してください。

## ゴール
- デプロイ関連スクリプトで共通利用する環境変数の定義・正規化・検証を一元管理します。
- `pre-deploy-check.sh` / `deploy-service.sh` / `replace-deploy-vars.sh` 間の定義ずれを防ぎます。

## 提供する定義
### `DEPLOY_REQUIRED_VARS`
デプロイ時に必須とする環境変数の一次定義です。現状は以下を定義します。

- `SERVICE_NAME`
- `SERVICE_USER`
- `SERVICE_PATH`
- `INSTALL_ROOT`
- `NFS_ROOT`
- `SERVICES`
- `CERT_DOMAIN`
- `MAP_LOCAL_ADDRESS`
- `SERVICE_HOME`
- `SERVICE_PREFIX`
- `SECRETS_DIR`
- `ROOT_UNIT_PREFIX`
- `ROOT_UNIT_DEST`
- `BASE_REPO_DIR`
- `NFS_GROUP_CHECK`
- `SCRIPT_DIR`

## 提供する関数
### `deploy_vars_collect_missing <vars_ref> <missing_ref>`
- 目的: 指定された変数名配列を走査し、未設定または空文字の変数名を `missing_ref` へ収集します。
- 主な利用箇所: `pre-deploy-check.sh` / `deploy-service.sh` / `replace-deploy-vars.sh` の必須チェック。

### `deploy_vars_get_replacement_vars <vars_ref>`
- 目的: 置換対象変数一覧を生成します。
- 挙動:
  - 基本は `DEPLOY_REQUIRED_VARS` を展開します。
  - `REPLACE_ADD_VAR` が定義されている場合は、その変数名を追加します。
- 主な利用箇所: `replace-deploy-vars.sh` のテンプレート置換対象の決定。

### `deploy_vars_build_env_pairs <vars_ref> <pairs_ref>`
- 目的: `env KEY=VALUE ...` 形式で子プロセスに渡す引数配列を生成します。
- 挙動:
  - 入力配列中で値が設定済みの変数のみを `KEY=VALUE` 形式で出力します。
  - 未設定変数はここでは除外します（事前の必須チェックで検知する前提）。
- 主な利用箇所: `deploy-service.sh` の `run_user_make`。

## 読み込み時の処理
本ファイルは読み込み時に以下を実行します。

1. 主要パスの正規化（末尾 `/` を除去）
   - `INSTALL_ROOT`
   - `NFS_ROOT`
   - `SERVICE_PATH`
2. 派生変数の算出
   - `EXPECTED_SERVICE_PATH`
   - `SERVICE_HOME`
   - `USER_UNIT_DIR`
   - `USER_CONTAINER_UNIT_DIR`
   - `USER_SYSTEMD_USER_DIR`
   - `ROOT_UNIT_PREFIX`
   - `ROOT_UNIT_DEST`
   - `NFS_GROUP_CHECK`（未設定時は `Yes`）
3. `DEPLOY_REQUIRED_VARS` に対する必須チェック
   - 未設定がある場合は標準エラーへ一覧を出力し、exit 1 で終了します。

## 運用ルール
- デプロイ関連の必須変数を追加・削除する場合は、まず `DEPLOY_REQUIRED_VARS` を更新してください。
- 追加した変数の用途に応じて、以下のドキュメントも同時に更新してください。
  - `docs/DEPLOYMENT.md`
  - `docs/pre-deploy-check.md`
  - `docs/deploy-service.md`
- unit/quadlet/drop-in の `@@VAR@@` 置換に使用する変数を増やす場合:
  - 共通必須なら `DEPLOY_REQUIRED_VARS` に追加します。
  - サービス固有ならサービス Makefile 側で定義し、`REPLACE_ADD_VAR` で追加します。

## 動作確認の目安
- 必須変数欠落時に、読み込み時点で即座にエラー終了すること。
- `INSTALL_ROOT=/srv/project/` のように末尾 `/` が付与されていても、`/srv/project` に正規化されること。
- `REPLACE_ADD_VAR="DEPLOY_ENV APP_PORT"` を指定した場合に、`replace-deploy-vars.sh` で `@@DEPLOY_ENV@@` / `@@APP_PORT@@` が置換対象に含まれること。
