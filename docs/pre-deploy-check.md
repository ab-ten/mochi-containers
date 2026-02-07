# `scripts/pre-deploy-check.sh` 実装メモ

`scripts/pre-deploy-check.sh` を編集した場合は、必ず本ドキュメントも更新してください。

## ゴール
- `make deploy` の前に、サービスユーザーと必須ディレクトリの存在・権限が正しいかを機械的にチェックし、`deploy-service.sh` が安全に動ける状態を保証する。
- 失敗時は即座に非 0 で終了し、後段を実行させない。

## 呼び出し前提
- 入口は各サービスの `Makefile` → `mk/services.mk` の `deploy` ターゲットから。`../scripts/pre-deploy-check.sh` として呼ばれる。
- ルートの `Makefile` からは `sudo INSTALL_ROOT=... SERVICE_PATH=... make -C <service> deploy` で実行される想定。ユーザー/ディレクトリ操作があるため root 前提で実装する。
- カレントディレクトリはサービスディレクトリ（例: `nginx_rp/`）。`SERVICE_NAME` と `SERVICE_USER` は一致している前提。

## 必須環境変数
- `SERVICE_NAME` … サービス名（ディレクトリ名と一致）
- `SERVICE_USER` … サービス実行ユーザー名
- `SERVICE_PATH` … `/srv/project/<service>` を指す絶対パス
- `INSTALL_ROOT` … `/srv/project/` のようなルート。末尾スラッシュは許容するが内部では削る
- `NFS_ROOT` … NFS 永続ディレクトリのルート。末尾スラッシュは許容するが内部では削る
- `CERT_DOMAIN` … 証明書ドメイン。`generate-index-html.sh` が生成するリンク先ドメインにも使用する
- `MAP_LOCAL_ADDRESS` … pasta の `--map-host-loopback` に割り当てるローカルアドレス
未定義または空の場合は即エラーとします。

## ルート Makefile から引き渡される環境変数
`pre-deploy-check.sh` では未使用でも、ルート `Makefile` から子 `make` に渡されるためドキュメント上の一覧に含めます。

- `INSTALL_ROOT`
- `NFS_ROOT`
- `SERVICE_PATH`
- `SERVICE_PREFIX`
- `SECRETS_DIR`
- `CERT_DOMAIN`
- `BASE_REPO_DIR`
- `SERVICES`
- `MAP_LOCAL_ADDRESS`

## 依存コマンド
- `getent`（ユーザー情報取得）
- `id` / `stat`（所有者確認に使用可）
- `sudo`（NFS ディレクトリ作成をサービスユーザー権限で行うため）
- `install`（ディレクトリ作成）

## 実装フロー（案）
1. `set -euo pipefail`。`err()`/`info()` の簡易ログ関数を用意し、`err` は即 exit 1。
2. `Makefile` に `pre-deploy-check-user` / `pre-deploy-check-root` があれば先に実行する（root で呼ばれている想定）。
3. 必須環境変数を走査し、未設定をまとめてエラーにする。
4. パス正規化:
   - `INSTALL_ROOT="${INSTALL_ROOT%/}"` で末尾スラッシュ除去。
   - `EXPECTED_SERVICE_PATH="${INSTALL_ROOT}/${SERVICE_NAME}"` を計算し、`SERVICE_PATH` が一致するか確認。ズレていればエラー。
   - `SERVICE_HOME="/home/${SERVICE_USER}"` を導出。
5. サービスユーザー検証:
   - `getent passwd "${SERVICE_USER}"` で HOME を取得。
   - HOME が `SERVICE_HOME` と一致しない場合はエラー（ホームは `/home/<service>` 固定）。
   - `id -u "${SERVICE_USER}"` / `id -g "${SERVICE_USER}"` で UID/GID を取得し、以後の NFS チェックに使用。
6. NFS 永続ディレクトリ検証・作成:
   - `NFS_GROUP_CHECK=No` の場合は NFS チェックをスキップする。
   - `svc_nfs_clients` のグループ所属チェックは現在無効化されている（将来再有効化の余地あり）。
   - `NFS_DIR="${NFS_ROOT}/${SERVICE_NAME}"` を決定。
   - 共有側で `NFS_ROOT` が `root:svc_nfs_clients` + `770` になっている前提。root では chown に失敗するため、`sudo -u "${SERVICE_USER}" install -d -m 0700 "${NFS_DIR}"` でサービスユーザー権限のまま作成する。
   - 既存なら `stat -c '%u %g'` で所有者をチェックし、サービスユーザーの UID/GID と一致しなければエラー終了（root では修正できない想定なので再作成を促すメッセージを出す）。
7. 最終確認ログを出して終了（例: `echo "pre-deploy-check: ok for ${SERVICE_NAME}"`）。

## エラー扱いと戻り値
- どこか一つでも不整合があれば標準エラーに理由を出し、exit 1。
- 期待以外のコマンドや権限不足で失敗した場合もそのまま非 0 を返す。

## 動作確認の目安
- 正常系: 既存ユーザー `nginx_rp` の HOME が一致し、`${NFS_ROOT}/nginx_rp` が無い状態で作成されること。
- 異常系: `SERVICE_USER` に存在しないユーザーを渡した際に「ユーザー無し」で落ちること、HOME がズレている場合に検知すること、NFS ディレクトリの所有権がサービスユーザーと一致しない場合に検知すること。
