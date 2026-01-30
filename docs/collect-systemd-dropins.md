# `scripts/collect-systemd-dropins.sh` 実装メモ

`deploy-service.sh` の rsync 後に呼ばれる drop-in 収集スクリプトの仕様メモ。`dropins/systemd/` に置いた drop-in を対象サービスの user/root unit に集約する。

## 役割
- 他サービス/自サービス向けの systemd drop-in を収集し、対象サービスの unit 配下へ配置する。
- 古い drop-in を削除してから再配置する（再デプロイ時の残骸防止）。
- drop-in の置換は `deploy-service.sh` が配布元の `dropins/systemd/` に対して事前に行う。収集側では置換を行わない。

## 対象ディレクトリ構造（配布元サービス側）
- user quadlet 用: `<service>/dropins/systemd/user/containers/<target>/`
- user unit 用: `<service>/dropins/systemd/user/systemd/<target>/`
- root unit 用: `<service>/dropins/systemd/root/<target>/`
- いずれも `*.d/*.conf` を配置する。

## 必須環境変数
- `SERVICE_PREFIX` … root unit に付与するプレフィックス。
- `SERVICE_NAME` … 収集対象サービス名（デプロイ中のサービス）。
- `SERVICE_USER` … 収集対象サービスのユーザー。
- `INSTALL_ROOT` … `/srv/project/` などの配置ルート。
- `SERVICES` … サービス一覧（スペース区切り）。
- `USER_CONTAINER_UNIT_DIR` … 収集先の user quadlet 配下（例: `/home/<user>/.config/containers/systemd`）。
- `USER_SYSTEMD_USER_DIR` … 収集先の user systemd 配下（例: `/home/<user>/.config/systemd/user`）。
- `ROOT_UNIT_DEST` … root unit 配下（例: `/etc/systemd/system`）。
- `ROOT_UNIT_PREFIX` … root unit の接頭辞（例: `<SERVICE_PREFIX>-<SERVICE_NAME>-`）。

## 処理フロー
1. 必須環境変数の未設定を検知したら即エラー終了。
2. 収集先の drop-in を全削除する。
   - user unit / quadlet: `*.conf` を全削除。
   - root unit: `${ROOT_UNIT_PREFIX}*.d/` の配下にある `${SERVICE_PREFIX}-dropin-*.conf` を削除。
3. `SERVICES` に含まれる各サービスの `dropins/systemd/` を探索し、対象サービス向けの drop-in をコピーする（自サービスも対象）。
   - `user/containers/<target>/` → `${USER_CONTAINER_UNIT_DIR}`
   - `user/systemd/<target>/` → `${USER_SYSTEMD_USER_DIR}`
   - `root/<target>/` → `${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}...`
4. `SERVICES` 内で対象サービスより後に並んだサービスから drop-in が見つかった場合は警告を出す（初回 deploy で未反映になりうるため）。

## 注意点
- drop-in は配布元で `replace-deploy-vars.sh` によって置換済みが前提。収集側での再置換は行わない。
- user unit と quadlet は `SERVICE_USER` の所有権で配置される。root unit の drop-in は `root:root` で配置される。
- 削除対象は `*.conf` なので、収集先に手動で置いた drop-in も消える。`dropins/systemd/` に置いたファイルは rsync 後に再収集される前提で管理する。
- `user-*.conf` はユーザーカスタマイズ用として `.gitignore` に登録済み。drop-in は必ず全削除で上書きされるため、カスタマイズしたい場合は配布元の `<service>/dropins/systemd/` 配下に `user-*.conf` として置き、デプロイ時に再配置されるようにする。

## 動作確認の目安
- `SERVICES` に含まれるサービスが `dropins/systemd/` を持つ場合に、収集先へ `mochi-dropin-*.conf` が配置されること。
- `SERVICES` の並び順が `drop-in 作成サービス → 対象サービス` の順になっていること。
