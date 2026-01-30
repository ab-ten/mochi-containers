# DEPLOYMENT

デプロイスクリプト（`scripts/deploy-service.sh`）の仕様メモ。トップの `Makefile` から `make deploy` を叩くと `SERVICES` に列挙された各サービス（`nginx_rp`, `ssl_update`, `security_package` など）で順に、各サービスのディレクトリをカレントとして `make deploy` が実行される。

## 前提・ツール
- rootless Podman 前提。nginx_rp はコンテナを `-p 8443:443` で待受させ、443/tcp → 8443/tcp は systemd socket activation + systemd-socket-proxyd で転送。
- rootless で動かす systemd user unit と quadlet (`*.service` / `*.socket` / `*.container` / `*.timer` など) は、リポジトリ上では `<service>/home/.config/containers/systemd/`（Quadlet 系）と `<service>/home/.config/systemd/user/`（timer/service 系）に置き、デプロイ先では `/home/<service>/.config/containers/systemd/` と `/home/<service>/.config/systemd/user/` に配置する。root 権限が要る system unit は `/etc/systemd/system/` 直下に `<SERVICE_PREFIX>-<service>-<name>.service` 形式で置く（ディレクトリは掘らない）。
- systemd drop-in は `<service>/dropins/systemd/` に定義する。配布元（origin）は `user/containers/<target>/...`（quadlet 用）、`user/systemd/<target>/...`（user unit 用）、`root/<target>/...`（root unit 用）に `*.d/*.conf` を置き、デプロイ時に target に収集される（自サービス向けも同様）。
- `user-*.conf` はユーザーカスタマイズ用として `.gitignore` に登録済み。drop-in は必ず全削除で上書きされるため、カスタマイズしたい場合は `<service>/dropins/systemd/` 配下に `user-*.conf` として置いてデプロイで反映する。
- 配置ルートは `INSTALL_ROOT`（例: `/srv/project/`）。各サービスはその直下に `<service>` ディレクトリを持ち、所有者は `<service>:<service>`。サービスユーザーのホームディレクトリは OS 既定の `/home/<service>` を使う（Podman ストレージが OS の変更に追従できるよう `/srv` 配下にホームを置かない）。
- 必須コマンド: `sudo`, `rsync`, `podman`, `systemctl`（system と --user の両方）。ユーザー情報確認用に `getent` / `id` なども使用可。
- --user の systemctl 呼び出しは `sudo systemctl -M "<user>@.host" --user ...` を使う（linger 前提）。
- 環境差異やオーバーライドは考慮不要。ロールバックは git でタグ/コミットを指定して再デプロイする。

## 環境変数
### ルート `Makefile` から子 `make` に引き渡す環境変数
- `INSTALL_ROOT`
- `NFS_ROOT`
- `SERVICE_PATH`
- `SERVICE_PREFIX`
- `SECRETS_DIR`
- `CERT_DOMAIN`
- `BASE_REPO_DIR`
- `SERVICES`
- `MAP_LOCAL_ADDRESS`

### `scripts/pre-deploy-check.sh` で必須
- `SERVICE_NAME`, `SERVICE_USER`
- `SERVICE_PATH`, `INSTALL_ROOT`, `NFS_ROOT`
- `MAP_LOCAL_ADDRESS`

### `scripts/deploy-service.sh` で必須
- `SERVICE_NAME`, `SERVICE_USER`
- `SERVICE_PATH`, `INSTALL_ROOT`, `NFS_ROOT`
- `SERVICE_PREFIX`, `SECRETS_DIR`, `SERVICES`
- `CERT_DOMAIN`, `MAP_LOCAL_ADDRESS`（`replace-deploy-vars.sh` が常に参照するため必須）

## ハードコードされた文字列をmake変数・環境変数を用いてパラメータ化する場合
- 既定値はルート `Makefile` または に定義し、`?=` で上書き可能にします。
- ルート `Makefile` から子 `make` に値を引き渡し、`scripts/deploy-service.sh` の `run_user_make` でも環境変数を伝播します。
- `scripts/pre-deploy-check.sh` / `scripts/deploy-service.sh` の必須チェックに変数を追加し、パスは末尾スラッシュ除去などの正規化を行います。
- unit/quadlet/drop-in で参照する場合は `@@VAR@@` 形式へ置換し、`scripts/replace-deploy-vars.sh` の `REPLACEMENT_VARS` に追加します。
- 追加した変数は `docs/DEPLOYMENT.md` / `docs/pre-deploy-check.md` / `docs/deploy-service.md` の一覧へ反映し、関連するサービス README を更新します。

## デプロイ前チェック（サービスごと） `scripts/pre-deploy-check.sh`
1) サービス側 `Makefile` を経由して `mk/services.mk` から `scripts/pre-deploy-check.sh` が呼び出される。通常、各サービス側 `Makefile` は全 make 変数を export する指定が行われており、SERVICE_NAME や SERVICE_USER などが適切に定義され環境変数として設定されている。
2) `Makefile` に `pre-deploy-check-user` / `pre-deploy-check-root` があれば先に実行される。
3) 必須環境変数は「環境変数」節の通りで、欠けていた場合は即エラーとします。
4) `SERVICE_USER` が存在し、ホームが `/home/<service>` であることを確認します。不一致ならエラー終了です。UID/GID は `id` で取得し、NFS チェックに使用します。
5) `NFS_GROUP_CHECK=No` 以外の場合、`NFS_ROOT/<service>` をサービスユーザー権限で `install -d -m 0700` し、既存なら所有者が `SERVICE_USER` の UID/GID と一致するか確認します。ずれていたらエラー終了です。NFS チェック自体を無効化したいときは `NFS_GROUP_CHECK=No` を環境に渡します。`svc_nfs_clients` のグループ所属チェックは現在無効化されています。
6) deploy 本体では `SERVICE_NAME/SERVICE_USER/SERVICE_PATH/INSTALL_ROOT/SERVICE_PREFIX/SECRETS_DIR` の必須チェックを行い、`SERVICE_PATH` が `INSTALL_ROOT/<service>` と一致しない場合はエラー終了します。`replace-deploy-vars.sh` と drop-in 収集の都合で `CERT_DOMAIN`/`MAP_LOCAL_ADDRESS`/`SERVICES` も必須となります。

## デプロイフロー（サービスごと）
- 基本は「停止 → 配置 → pre-build → ビルド → post-build → systemd 配置 → 再起動」。中間生成物の掃除は次回ビルド開始時に行う。
- root によるサービスは `/etc/systemd/system/<service>/` にインストールされ、rootless の --user サービスと quadlet は `/home/<service>/.config/containers/systemd/` にまとめてインストールする（home 配下必須）
- pre-buid-user などのターゲットの存在は Makefile を "^pre-build-user:" などのパターンで grep してチェックできる。
- drop-in 収集の詳細は `docs/collect-systemd-dropins.md` を参照。

1) **既存サービス停止**:
   - `/home/<service>/.config/containers/systemd/` と `/home/<service>/.config/systemd/user/` にある `.service`/`.socket`/`.container`/`.timer`/`.path` を収集（配備済みファイル一覧をそのまま使う）。`/etc/systemd/system/` の `<SERVICE_PREFIX>-<service>-*` も同様に収集。停止順は `.timer` → `.socket` → `.path` → その他。
   - user unit は並べ替え済みのリスト順に `is-active` を見て stop、`is-enabled` を見て disable。root unit も同様。
   - root unit は stop/disable 後に `/etc/systemd/system/<SERVICE_PREFIX>-<service>-*` を一括削除してクリーンにする。
   - `deploy-service.sh stop` の場合は停止のみで終了する。
2) **配置ディレクトリ準備**: `install -d -o <service> -g <service> -m 0750` で `INSTALL_ROOT/<service>`、`/home/<service>`、`/home/<service>/.config/containers/systemd`、`/home/<service>/.config/systemd/user` を作成。
3) **ソース配置 + 置換**: リポジトリのサービスディレクトリを `rsync -a --delete --exclude '.git' --exclude '*.swp' --exclude '*~' ./ INSTALL_ROOT/<service>/` へ、ホーム配下 (`home/`) があれば `/home/<service>/` に `rsync -a --delete --exclude '.cache' --exclude '.local' --exclude '*~'` で同期。`chmod 750` した後、`scripts/replace-deploy-vars.sh` で user unit の `@@ROOT_UNIT_PREFIX@@` / `@@SERVICE_PATH@@` / `@@INSTALL_ROOT@@` / `@@CERT_DOMAIN@@` などを実値に置換する（`CERT_DOMAIN` は置換処理が走る場合は実質必須、`REPLACE_ADD_VAR` で追加変数も置換対象にできる）。
   - rsync 後に `dropins/systemd/` 配下の `*.conf` に対して `replace-deploy-vars.sh` を適用する（配布元の置換）。
   - `/home/<service>/.config/containers/systemd/` と `/home/<service>/.config/systemd/user/` の unit ファイルに `replace-deploy-vars.sh` を適用する（`.d/*.conf` を含む）。
   - 続けて `scripts/collect-systemd-dropins.sh` が `SERVICES` に含まれる origin から drop-in を収集し、target の user/root unit に配置する。自サービスも含めて収集するため、ユーザーカスタマイズ drop-in も反映される。drop-in は配布元で置換済みの前提で、収集側では置換しない。配置元の `dropins/systemd/` 構成や並び順の注意は `docs/collect-systemd-dropins.md` に整理。
4) **所有権統一**: `chown -R <service>:<service> INSTALL_ROOT/<service> /home/<service>`。
5) **linger 有効化**: `loginctl enable-linger <service>`。
6) **pre-build-user / pre-build-root**: Makefile にターゲットがある場合のみ実行。user 側は `INSTALL_ROOT` / `SERVICE_PATH` を環境で渡してサービスユーザー権限、root 側はそのまま。
   - `nginx_rp` の `pre-build-root` は `SERVICES` に含まれる各サービスの `${INSTALL_ROOT}/<service>/http_<service>.conf` / `https_<service>.conf` を集約して `nginx_rp/container/conf/` にコピーするため、`SERVICES` の並びは `ssl_update` → 各サービス → `nginx_rp` の順にしておく。
7) **replace-files-user / replace-files-root**: `REPLACE_FILES_USER` / `REPLACE_FILES_ROOT` が空でなければ `make replace-files-user` / `make replace-files-root` を実行。
8) **コンテナビルド**: `container/` と `container.*` ディレクトリを検出し、存在するディレクトリごとに `podman build` を実行する。
9) **post-build-user / post-build-root**: あれば pre-build と同様に実行。
10) **systemd 配置**:
   - root unit: `INSTALL_ROOT/<service>/systemd/` のファイルを `/etc/systemd/system/<SERVICE_PREFIX>-<service>-<name>` にコピーし、`replace-deploy-vars.sh` でプレースホルダー置換。0644/root:root にして `systemctl daemon-reload`。
   - user unit / quadlet / timer: 置換済みファイルを前提に `sudo systemctl -M "<user>@.host" --user daemon-reload`。
11) **起動/再起動**:
    - user unit:
      - `.container` は start のみ（enable 不可）。
      - その他は `[Install]` セクションがあれば `enable --now`、無ければ `start` のみ。`#NOSTART` 付きはスキップ。
    - root unit:
      - `.container` は start のみ。
      - その他は `[Install]` セクションがあれば `enable --now`、無ければ `start` のみ。`#NOSTART` 付きはスキップ。
    - `[Install]` のない unit を `enable` すると systemd がエラーになるため、事前に判定して分岐する。

## エラー時の扱い
- ユーザー/ホームパス確認や NFS ディレクトリの所有権確認、ディレクトリ準備に失敗したら即時エラー終了。
- 中途のコピーやビルド生成物はそのまま残して構わない（デバッグ用途）。次回ビルド開始時に掃除する。
