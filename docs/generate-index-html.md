# `scripts/generate-index-html.sh` 実装メモ

`scripts/generate-index-html.sh` を編集した場合は、必ず本ドキュメントも更新してください。

## ゴール
- `nginx_rp` が reverse proxy するサービス一覧ページ（`index.html`）を、`SERVICES` と `container/conf/` の実在ファイルから自動生成します。
- 手動で HTML をメンテナンスせず、`SERVICES` の増減に追従できる状態を維持します。

## 呼び出し前提
- 呼び出し元は `nginx_rp/Makefile` の `pre-build-root` ターゲットです。
- 実行順は `scripts/collect-nginx-conf.sh` の後です。先に `http_<service>.conf` / `https_<service>.conf` を収集してから本スクリプトで HTML を生成します。
- deploy 時は `deploy-service.sh` の `rsync -a --delete` が先に実行され、`${SERVICE_PATH}/container/conf/` はリポジトリ状態に初期化された後で `collect-nginx-conf.sh` が再収集します。

## 必須環境変数
- `SERVICE_PATH`（必須）: 対象サービスの配置先パスです。未設定の場合は即エラーで終了します。
- `SERVICES`（必須）: 公開対象サービス一覧（スペース区切り）です。この一覧順でインデックス項目を生成します。
- `CERT_DOMAIN`（実質必須）: 生成するリンク先ドメインのサフィックスに使用します。未設定でもスクリプトは動作しますが、`https://<service>./` のような不正な URL になるため、デプロイ時は必ず設定してください。

## 入出力
- 入力ディレクトリ: `${SERVICE_PATH}/container/conf`
- 出力ファイル: `${SERVICE_PATH}/container/html/index.html`

## 生成仕様
1. 走査対象サービスは `SERVICES` の各要素です。
2. `SERVICE_NAME`（通常は `nginx_rp`）と同名のサービスは除外します。
3. `container/conf/https_<service>.conf` または `container/conf/http_<service>.conf` が存在するサービスのみを一覧に含めます。
4. `SERVICES` に重複がある場合は最初の 1 件のみ採用します。
5. 各サービスのリンクは以下の規則で URL スキームを決定します。
   - `https_<service>.conf` が存在する場合は `https`
   - 存在しない場合は `http`
6. `SERVICES` に含まれないサービスの残存 conf（過去デプロイ残骸）は無視します。
7. 出力先 HTML は都度上書きします。

## ログ出力
- 進捗は標準エラーに出力します。
- 例: `generating mochi-index: https:nextcloud..http:redmine.. Done.`

## 制約・注意点
- サービス名に空白が含まれることは想定していません。
- `CERT_DOMAIN` が未設定の場合、リンク先 URL が壊れます。
- `SERVICES` に該当する `http_*.conf` / `https_*.conf` が 1 件もない場合は「現在公開中のサービスはありません」を表示します。

## 動作確認の目安
- `SERVICE_PATH=/srv/project/nginx_rp SERVICES=\"nextcloud redmine nginx_rp\" CERT_DOMAIN=example.com sh scripts/generate-index-html.sh` を実行し、`${SERVICE_PATH}/container/html/index.html` が更新されることを確認してください。
- 生成後に `podman run --rm localhost/nginx_rp:dev nginx -t` でコンテナ設定に問題がないことを確認してください。
