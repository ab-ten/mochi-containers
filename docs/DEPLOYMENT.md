# DEPLOYMENT

デプロイスクリプト（`scripts/deploy-service.sh`）の仕様メモ。トップの `Makefile` から `make deploy` を実行すると、まず `earlystop` 依存で `SERVICES` を順に回し、`EARLY_STOP=Yes` のサービスだけ先行停止します。その後に `SERVICES` 順で各サービスの `make deploy` が実行されます。
この先行停止は、`trilium` の websocket セッションが残った状態で `nginx_rp` を停止すると graceful shutdown がタイムアウトしやすい問題を避けるためです。`trilium` origin を先に停止して websocket セッションを終了させてから `nginx_rp` を停止することで、停止待ち時間を短縮します。現行設定では `trilium` と `nginx_rp` を `EARLY_STOP=Yes` としています。

## 前提・ツール
- rootless Podman 前提。nginx_rp はコンテナを `-p 8443:443` で待受させ、443/tcp → 8443/tcp は systemd socket activation + systemd-socket-proxyd で転送。
- rootless で動かす systemd user unit と quadlet (`*.service` / `*.socket` / `*.container` / `*.timer` など) は、リポジトリ上では `<service>/home/.config/containers/systemd/`（Quadlet 系）と `<service>/home/.config/systemd/user/`（timer/service 系）に置き、デプロイ先では `/home/<service>/.config/containers/systemd/` と `/home/<service>/.config/systemd/user/` に配置する。root 権限が要る system unit は `/etc/systemd/system/` 直下に `<SERVICE_PREFIX>-<service>-<name>.service` 形式で置く（ディレクトリは掘らない）。
- 共通処理に使う `mk/` と `scripts/` は、各サービスの deploy/stop の直前に `prepare-common` で `${INSTALL_ROOT}/` へ `rsync` 同期する。`deploy-service.sh` 内の補助スクリプト参照は `${INSTALL_ROOT}/scripts` を基準にする。
- systemd drop-in は `<service>/dropins/systemd/` に定義する。配布元（origin）は `user/containers/<target>/...`（quadlet 用）、`user/systemd/<target>/...`（user unit 用）、`root/<target>/...`（root unit 用）に `*.d/*.conf` を置き、デプロイ時に target に収集される（自サービス向けも同様）。
- `user-*.conf` はユーザーカスタマイズ用として `.gitignore` に登録済み。drop-in は必ず全削除で上書きされるため、カスタマイズしたい場合は `<service>/dropins/systemd/` 配下に `user-*.conf` として置いてデプロイで反映する。
- 配置ルートは `INSTALL_ROOT`（例: `/srv/project/`）。各サービスはその直下に `<service>` ディレクトリを持ち、所有者は `<service>:<service>`。サービスユーザーのホームディレクトリは OS 既定の `/home/<service>` を使う（Podman ストレージが OS の変更に追従できるよう `/srv` 配下にホームを置かない）。
- 必須コマンド: `sudo`, `rsync`, `podman`, `systemctl`（system と --user の両方）。ユーザー情報確認用に `getent` / `id` なども使用可。
- --user の systemctl 呼び出しは `sudo systemctl -M "<user>@.host" --user ...` を使う。`deploy-service.sh` は deploy 時に常に linger を有効化する。
- サービス横断 root hook の `make` 呼び出しは `env -i` で実行し、`PATH`, `HOME`, `LANG`, `LC_ALL`, `USER`, `LOGNAME` と、`INSTALL_ROOT`, `NFS_ROOT`, `SERVICE_PREFIX`, `SECRETS_DIR`, `SERVICES`, `CERT_DOMAIN`, `MAP_LOCAL_ADDRESS`, `BASE_REPO_DIR`, `SCRIPT_DIR` のみを引き継ぐ。
- SELinux 有効環境で NFS を bind mount する場合は `docs/UsersSetup.md` の方針に従う。`virt_use_nfs=on` を前提に、サービスユーザー間で共有する NFS パスの `Volume=` では `:z` / `:Z` を付けない（ローカルディスクの bind mount のみ `:z` / `:Z` を使用）。
- 環境差異やオーバーライドは考慮不要。ロールバックは git でタグ/コミットを指定して再デプロイする。

## 環境変数
### サービス固有変数
- サービス固有の make 変数（例: `TRILIUM_PORT`, `DBFILE_DIR`, `UID_IN_PODMAN` など）は各サービスの `Makefile` で定義して `export` します。ルート `Makefile` では定義しません。
- 各サービスの `Makefile` では、`SERVICE_NAME` / `SERVICE_USER` / `SERVICE_PATH` などの変数定義とサービス固有ターゲット定義を行った後、ファイル末尾で `include ../mk/services.mk` を記述してください。
- root 実行時に `UID_IN_PODMAN` / `GID_IN_PODMAN` を定義した場合、`mk/services.mk` は `print_unshare_id.sh` で `UID_HOST_MAPPED` / `GID_HOST_MAPPED` を導出します。導出結果が空文字列になった場合は、`pre-build-root` などで不明瞭な失敗になる前に `make` を即時エラー終了します。
- 共通の環境変数名リストは `scripts/deploy-vars.subr` で一元管理します。
- `scripts/deploy-vars.subr` の仕様詳細は `docs/deploy-vars.subr.md` を参照します。

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
- `SERVICES`
- `CERT_DOMAIN`, `MAP_LOCAL_ADDRESS`
- 定義元: `scripts/deploy-vars.subr` の `DEPLOY_REQUIRED_VARS`
- 詳細仕様: `docs/deploy-vars.subr.md`

### `scripts/deploy-service.sh` で必須
- `SERVICE_NAME`, `SERVICE_USER`
- `SERVICE_PATH`, `INSTALL_ROOT`, `NFS_ROOT`
- `SERVICE_PREFIX`, `SECRETS_DIR`, `SERVICES`
- `CERT_DOMAIN`, `MAP_LOCAL_ADDRESS`（`replace-deploy-vars.sh` が常に参照するため必須）
- 定義元: `scripts/deploy-vars.subr` の `DEPLOY_REQUIRED_VARS`
- 詳細仕様: `docs/deploy-vars.subr.md`

## ハードコードされた文字列をmake変数・環境変数を用いてパラメータ化する場合
- 既定値はルート `Makefile` または各サービスの `Makefile` に定義し、`?=` で上書き可能にします。
- ルート `Makefile` から子 `make` に値を引き渡し、`scripts/deploy-service.sh` の `run_user_make` でも環境変数を伝播します。
- `scripts/pre-deploy-check.sh` / `scripts/deploy-service.sh` の必須チェックに変数を追加し、パスは末尾スラッシュ除去などの正規化を行います。
- unit/quadlet/drop-in で参照する場合は `@@VAR@@` 形式に置き換えます。`scripts/deploy-vars.subr` の `DEPLOY_REQUIRED_VARS` にないものはサービスごとの Makefile に変数を追加し、`REPLACE_ADD_VAR` に変数名を追加する事で置換可能になります。
- 追加した変数は `docs/DEPLOYMENT.md` / `docs/pre-deploy-check.md` / `docs/deploy-service.md` の一覧へ反映し、関連するサービス README を更新します。
- `scripts/deploy-vars.subr` を変更した場合は `docs/deploy-vars.subr.md` も必ず更新します。

## サービス追加時のドキュメント更新
- 新しいサービスを `SERVICES` に追加した場合は、ルート `README.md` の「Services and Customization」に `<service>/README.md` を追記してください。
- 同時に、追加したサービスの `README.md`（`<service>/README.md`）を作成または更新してください。

## デプロイ前チェック（サービスごと） `scripts/pre-deploy-check.sh`
1) サービス側 `Makefile` を経由して `mk/services.mk` から `scripts/pre-deploy-check.sh` が呼び出される。通常、各サービス側 `Makefile` は全 make 変数を export する指定が行われており、SERVICE_NAME や SERVICE_USER などが適切に定義され環境変数として設定されている。
2) `Makefile` に `pre-deploy-check-user` / `pre-deploy-check-root` があれば先に実行される。
3) 必須環境変数は「環境変数」節の通りで、欠けていた場合は即エラーとします。
4) `SERVICE_USER` が存在し、ホームが `/home/<service>` であることを確認します。不一致ならエラー終了です。UID/GID は `id` で取得し、NFS チェックに使用します。
5) `NFS_GROUP_CHECK=No` 以外の場合、`NFS_ROOT/<service>` をサービスユーザー権限で `install -d -m 0700` し、既存なら所有者が `SERVICE_USER` の UID/GID と一致するか確認します。ずれていたらエラー終了です。NFS チェック自体を無効化したいときは `NFS_GROUP_CHECK=No` を環境に渡します。`svc_nfs_clients` のグループ所属チェックは現在無効化されています。
6) deploy 本体では `SERVICE_NAME/SERVICE_USER/SERVICE_PATH/INSTALL_ROOT/SERVICE_PREFIX/SECRETS_DIR` の必須チェックを行い、`SERVICE_PATH` が `INSTALL_ROOT/<service>` と一致しない場合はエラー終了します。`replace-deploy-vars.sh` と drop-in 収集の都合で `CERT_DOMAIN`/`MAP_LOCAL_ADDRESS`/`SERVICES` も必須となります。
7) `scripts/check-systemd-trigger-services.sh` により `*.path` / `*.socket` / `*.timer` の参照先 service を検証します。参照先 unit には原則として `#NOSTART` が必要ですが、timer 運用を基本としつつ deploy 直後の起動も許可したい unit は `#FORCESTART` を付けることで例外的に許可されます。

## デプロイフロー（サービスごと）
- 基本は「停止 → 配置 → pre-build → ビルド → post-build → systemd 配置 → 再起動」。中間生成物の掃除は次回ビルド開始時に行う。
- root によるサービスは `/etc/systemd/system/<service>/` にインストールされ、rootless の --user サービスと quadlet は `/home/<service>/.config/containers/systemd/` にまとめてインストールする（home 配下必須）
- pre-buid-user などのターゲットの存在は Makefile を "^pre-build-user:" などのパターンで grep してチェックできる。
- drop-in 収集の詳細は `docs/collect-systemd-dropins.md` を参照。
- コンテナビルドの詳細仕様は `docs/container-build.md` を参照。

1) **既存サービス停止**:
   - `/home/<service>/.config/containers/systemd/` と `/home/<service>/.config/systemd/user/` にある `.service`/`.socket`/`.container`/`.timer`/`.path` を収集（配備済みファイル一覧をそのまま使う）。`/etc/systemd/system/` の `<SERVICE_PREFIX>-<service>-*` も同様に収集。停止順は `.timer` → `.socket` → `.path` → その他。
   - user unit は並べ替え済みのリスト順に `is-active` を見て stop、`is-enabled` を見て disable。root unit も同様。
   - root unit は stop/disable 後に `/etc/systemd/system/<SERVICE_PREFIX>-<service>-*` を一括削除してクリーンにする。
   - `deploy-service.sh stop` の場合は停止のみで終了する。
2) **配置ディレクトリ準備**: `install -d -o <service> -g <service> -m 0750` で `INSTALL_ROOT/<service>`、`/home/<service>`、`/home/<service>/.config/containers/systemd`、`/home/<service>/.config/systemd/user` を作成。
3) **ソース配置 + 置換**: リポジトリのサービスディレクトリを `rsync -a --delete --exclude '.git' --exclude '*.swp' --exclude '*~' ./ INSTALL_ROOT/<service>/` へ、ホーム配下 (`home/`) があれば `/home/<service>/` に `rsync -a --delete --exclude '.cache' --exclude '.local' --exclude '*~'` で同期。`chmod 750` した後、`${INSTALL_ROOT}/scripts/replace-deploy-vars.sh` で user unit の `@@ROOT_UNIT_PREFIX@@` / `@@SERVICE_PATH@@` / `@@INSTALL_ROOT@@` / `@@CERT_DOMAIN@@` などを実値に置換する（`CERT_DOMAIN` は置換処理が走る場合は実質必須、`REPLACE_ADD_VAR` で追加変数も置換対象にできる）。
   - `replace-deploy-vars.sh` は置換後に `@@[A-Z0-9_]+@@` が残っている行を `grep -nE` で出力し、1 件でもヒットした場合はエラー終了する。
   - rsync 後に `dropins/systemd/` 配下の `*.conf` に対して `${INSTALL_ROOT}/scripts/replace-deploy-vars.sh` を適用する（配布元の置換）。
   - `/home/<service>/.config/containers/systemd/` と `/home/<service>/.config/systemd/user/` の unit ファイルに `${INSTALL_ROOT}/scripts/replace-deploy-vars.sh` を適用する（`.d/*.conf` を含む）。
   - 続けて `${INSTALL_ROOT}/scripts/collect-systemd-dropins.sh` が `SERVICES` に含まれる origin から drop-in を収集し、target の user/root unit に配置する。自サービスも含めて収集するため、ユーザーカスタマイズ drop-in も反映される。drop-in は配布元で置換済みの前提で、収集側では置換しない。配置元の `dropins/systemd/` 構成や並び順の注意は `docs/collect-systemd-dropins.md` に整理。
4) **linger 有効化とマーカーファイル出力**:
   - rsync と drop-in 収集の後で、deploy 先 `/home/<service>/.config/containers/systemd/` と `/home/<service>/.config/systemd/user/` に実際に配置された user unit 一覧を収集する。
   - 続けて deploy 時は常に `loginctl enable-linger <service>` を実行する。
   - user unit が 1 件以上あれば `INSTALL_ROOT/<service>/.startup_linger` に `id -u <service>` の数値を 1 行だけ書き込む。
   - `.startup_linger` は起動時の linger 復旧対象サービスを示すマーカーファイルとして扱う。
   - user unit が 0 件ならマーカーファイルは作成しない。古いマーカーファイルは rsync `--delete` により消える前提とする。
5) **所有権統一**: `chown -R <service>:<service> INSTALL_ROOT/<service> /home/<service>`。
6) **pre-build-user / pre-build-root**: Makefile にターゲットがある場合のみ実行。user 側は `INSTALL_ROOT` / `SERVICE_PATH` を環境で渡してサービスユーザー権限、root 側はそのまま。
   - `pre-build-root` はリポジトリ上のサービスディレクトリを `cwd` にして実行するため、同階層や親ディレクトリへの相対参照を利用できる。
   - `nginx_rp` の `pre-build-root` は `scripts/collect-nginx-conf.sh` で `SERVICES` に含まれる各サービスの `${INSTALL_ROOT}/<service>/http_<service>.conf` / `https_<service>.conf` を `nginx_rp/container/conf/` に集約し、続けて `scripts/generate-index-html.sh` で `nginx_rp/container/html/index.html` を再生成する。`SERVICES` の並びは `ssl_update` → 各サービス → `nginx_rp` の順にしておく。
   - サービス横断 root hook（`pre-build-root-hook-%` / `post-build-root-hook-%`）は hook 定義側サービスの Makefile コンテキストで実行される。デプロイ対象サービスの情報が必要な場合は `HOOK_TARGET_SERVICE_*` を使用する。
   - hook 実行時は `env -i` により親サービス固有の環境変数を落とすため、`UID_IN_PODMAN` / `GID_IN_PODMAN` のような値は自動継承されない。hook 定義側サービスで必要な値は、そのサービスの `Makefile` または `Makefile.local` に定義する。
   - サービス横断 root hook は `make` の通常更新判定で実行されるため、毎回実行が必要な hook は `.PHONY`（または `FORCE` 依存）を定義する。増分実行を意図する hook は成果物と依存関係を明示して `.PHONY` 化しない。
7) **replace-files-user / replace-files-root**: `REPLACE_FILES_USER` / `REPLACE_FILES_ROOT` が空でなければ `make replace-files-user` / `make replace-files-root` を実行。
   - `make <service>-deploy` のような単体デプロイでは、`SERVICES` 全体を前提とした関連サービスへの反映は行われない。例えば `make redmine-deploy` のみを実行しても `redmine/https_redmine.conf` は `nginx_rp/container/conf/` に集約されないため、nginx 側への反映が必要な場合は `nginx_rp` を含めて再デプロイする。
8) **コンテナビルド**: `container/` と `container.*` ディレクトリを検出し、存在するディレクトリごとに `${INSTALL_ROOT}/scripts/container-build.sh` を実行する。`container-build.sh` は `custom-build.sh` があれば優先実行し、なければ共通処理として `podman build` を実行する。`custom-build.sh` が存在して実行不可な場合はエラー終了する。
9) **post-build-user / post-build-root**: あれば pre-build と同様に実行。
   - `ssl_update` の `post-build-root` は `${INSTALL_ROOT}/ssl_share` 配下の共有ディレクトリをローカルディスク上に作成し、証明書共有用の owner/group/mode を調整する。
   - `post-build-root` は deploy 先の `${SERVICE_PATH}` を `cwd` にして実行するため、リポジトリルート側の相対パスを前提にした処理は置かない。
   - `git_backend` の `pre-build-root` は `${INSTALL_ROOT}/git_triggers` 配下のディレクトリをローカルディスク上に常に作成する。`SERVICES` に `redmine` を含める場合は共有向け group / mode に調整し、含めない場合は特に何もしない。
     - 一度でも redmine 込みで deploy した場合は `pending/` にタイムスタンプファイルが touch される。
     - 過去を含めた deploy 全てにおいて redmine が有効ではなかった場合は pending/ が存在しないので何も行われない。
10) **systemd 配置**:
   - root unit: `INSTALL_ROOT/<service>/systemd/` のファイルを `/etc/systemd/system/<SERVICE_PREFIX>-<service>-<name>` にコピーし、`replace-deploy-vars.sh` でプレースホルダー置換する。旧 root unit が存在した場合、または新しい root unit を 1 件以上配置した場合に `systemctl daemon-reload` を実行する。
   - user unit / quadlet / timer: 旧 user unit が存在した場合、または新しい user unit が 1 件以上ある場合に、置換済みファイルを前提に `sudo systemctl -M "<user>@.host" --user daemon-reload` を実行する。
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

## トラブルシュート
### `/run/user/<uid>` が存在せず rootless Podman が失敗する場合
- `podman unshare` や rootless Podman 関連処理で `/run/user/<uid>` が存在しない旨のエラーが出る場合は、linger 状態の破損を疑ってください。
- 対象サービスユーザーに対して、以下のコマンドで状態を確認してください。

```bash
loginctl show-user <service_user> -p Linger -p State -p RuntimePath
```

- `Failed to get user: User ID <uid> is not logged in or lingering` が出る場合は、linger 状態が壊れている可能性があります。
- 以下を実行して復旧を試してください。

```bash
sudo systemctl restart systemd-logind
```

- 復旧後は再度 `loginctl show-user <service_user> -p Linger -p State -p RuntimePath` を実行し、`RuntimePath=/run/user/<uid>` が表示されることを確認してください。
