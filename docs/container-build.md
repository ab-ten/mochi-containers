# `scripts/container-build.sh` 実装メモ

コンテナビルドの共通エントリーポイントです。`deploy-service.sh` から呼び出され、サービスごとのカスタムビルド有無を判定します。

## 呼び出し関係
- `scripts/deploy-service.sh` が `container/` および `container.*` を列挙し、各ディレクトリごとに `CONTAINER_IMAGE` と `CONTAINER_DIR` を設定して `scripts/container-build.sh` を実行します。
- `scripts/container-build.sh` は `${CONTAINER_DIR}/custom-build.sh` を検出します。
- `custom-build.sh` が存在し実行可能な場合は、そのスクリプトを実行します。
- `custom-build.sh` が存在するが実行不可の場合はエラー終了します。
- `custom-build.sh` が存在しない場合は共通処理として `podman build -t "${CONTAINER_IMAGE}" "${CONTAINER_DIR}"` を実行します。

## 必須環境変数
- `CONTAINER_IMAGE`: ビルド後イメージタグです。
- `CONTAINER_DIR`: ビルドコンテキストとなるコンテナディレクトリです。

## エラーハンドリング
- `CONTAINER_IMAGE` または `CONTAINER_DIR` が未設定の場合はエラー終了します。
- `custom-build.sh` が実行不可の場合は、権限修正を促すエラーメッセージを出力して終了します。
- カスタムビルド失敗時は、その終了コードをそのまま上位へ伝播します。

## サービス側の運用ルール
- サービス固有のカスタムビルドが必要な場合は、`<service>/container/custom-build.sh` を配置してください。
- サンプルを配布する場合は `custom-build.sh.sample` とし、利用時に `custom-build.sh` へコピーして実行権限を付与してください。
