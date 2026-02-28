# `scripts/deploy-service.sh` 実装メモ

`docs/DEPLOYMENT.md` のフローを実体化する共通デプロイスクリプト用ノート。`scripts/deploy-service.sh` を編集したら、ここも必ず同期してください。

## ゴールと前提
- 役割: `mk/services.mk` の `deploy` ターゲット経由でサービスごとに rsync デプロイとビルドを行い、systemd (--user / root) を最新化する。
- 呼び出し元: ルート `Makefile` の `make deploy` は `earlystop` 依存を持ち、`EARLY_STOP=Yes` が設定されたサービスのみを先に停止した後で `make -C <service> deploy` を順次呼び出す（ルート Makefile 自体が root 実行を必須化）。`cwd` はサービスディレクトリ（例: `nginx_rp/`）。この直前に `scripts/pre-deploy-check.sh` が走って、ユーザーやディレクトリの前提を担保済み。
- 共通スクリプト参照: `deploy-service.sh` は `SCRIPT_DIR=${INSTALL_ROOT}/scripts` を参照し、`replace-deploy-vars.sh` / `collect-systemd-dropins.sh` / `container-build.sh` を同ディレクトリから実行する。`prepare-common` が事前に `mk/` と `scripts/` を `${INSTALL_ROOT}/` へ同期している前提。
- コンテナビルドの詳細仕様は `docs/container-build.md` を参照してください。
- rootless Podman 前提。systemd user unit / quadlet はリポジトリ上では `<service>/home/.config/containers/systemd/` に集約し、デプロイ先では `/home/<service>/.config/containers/systemd/` に配置する（nginx_rp もこの構成）。

## 参照するディレクトリ構造（例: `nginx_rp/`）
- `container/` … `Containerfile`, `default.conf`, `html/` などコンテナビルド素材。
- `config/` … 将来の本番設定置き場（現状は空想定）。
- `systemd/` … root で実行する systemd unit の置き場（443 → 8443 の socket-proxyd など）。
- `dropins/systemd/` … systemd drop-in 配布元。`user/containers/<target>/...`（quadlet 向け）、`user/systemd/<target>/...`（user systemd unit 向け）、`root/<target>/...`（root unit 向け）に `*.d/*.conf` を置く。
- `user-*.conf` はユーザーカスタマイズ用として `.gitignore` に登録済み。drop-in は必ず全削除で上書きされるため、カスタマイズしたい場合は `<service>/dropins/systemd/` 配下に `user-*.conf` として置いてデプロイで反映する。
- `home/.config/containers/systemd/` … rootless systemd user unit / quadlet をまとめる置き場（リポジトリ上）。デプロイ後の稼働場所は `/home/<service>/.config/containers/systemd/`。
- `home/.config/systemd/user/` … user systemd timer / service を置く標準ディレクトリ（リポジトリ上）。デプロイ後の稼働場所は `/home/<service>/.config/systemd/user/`。

## サービス固有変数の定義場所
- サービス固有の make 変数（例: `TRILIUM_PORT`, `DBFILE_DIR` など）は各サービスの `Makefile` で定義して `export` し、ルート `Makefile` では定義しません。
- 各サービスの `Makefile` では、サービス固有の変数・ターゲットを定義した後、ファイル末尾で `include ../mk/services.mk` を記述してください。
- root 実行時に `UID_IN_PODMAN` / `GID_IN_PODMAN` を定義するサービスでは、`mk/services.mk` が `print_unshare_id.sh` で導出した `UID_HOST_MAPPED` / `GID_HOST_MAPPED` が空文字列の場合に即時エラー終了します。

## 必須環境変数
- 変数名リストは `scripts/deploy-vars.subr` の `DEPLOY_REQUIRED_VARS` で一元管理する。
- 一元管理の詳細仕様は `docs/deploy-vars.subr.md` を参照する。
- `SERVICE_NAME`, `SERVICE_USER` … サービス名と実行ユーザー（同一前提）です。
- `SERVICE_PATH` … 配置先 `/srv/project/<service>` の絶対パスです。`INSTALL_ROOT` と合わせて正規化チェックします。
- `INSTALL_ROOT` … `/srv/project/` のようなルートです（末尾 `/` は削って扱います）。
- `NFS_ROOT` … NFS 永続ディレクトリのルートです（末尾 `/` は削って扱います）。
- `SERVICE_PREFIX` … root unit に付与するプレフィックスです（空白禁止）。`<SERVICE_PREFIX>-<SERVICE_NAME>-<unit>` の形で使います。
- `SECRETS_DIR` … 追加シークレット配置のためのパスです（存在チェック用途を想定し、未設定ならエラーにします）。
- `SERVICES` … サービス一覧（スペース区切り）です。drop-in 収集や nginx 設定集約で参照します。
- `CERT_DOMAIN` … `replace-deploy-vars.sh` が参照するため必須です（テンプレート置換の有無に関わらず必要です）。
- `MAP_LOCAL_ADDRESS` … `replace-deploy-vars.sh` が参照するため必須です。pasta の `--map-host-loopback` の割り当て先としても使用します。

## 任意で使う環境変数
- `BASE_REPO_DIR` … `pre-build` / `post-build` の Makefile 呼び出しに渡す値。
- `HOOK_TARGET_SERVICE_NAME` / `HOOK_TARGET_SERVICE_USER` / `HOOK_TARGET_SERVICE_PATH` … サービス横断 root フック（`pre-build-root-hook-%` / `post-build-root-hook-%`）の呼び出し時に渡されるデプロイ対象サービス情報。
  - フック本体は「hook を定義しているサービス」の Makefile コンテキストで実行されます。
  - そのため、フック内で `SERVICE_NAME` / `SERVICE_USER` / `SERVICE_PATH` / `ROOT_UNIT_PREFIX` / `SERVICE_HOME` / `USER_UNIT_DIR` などを参照した場合は、原則として hook 定義側サービスの値を参照します。
  - デプロイ対象サービス（`deploy-service.sh` を現在実行している対象）の情報が必要な場合は、必ず `HOOK_TARGET_SERVICE_*` を参照してください。
  - hook 定義側サービスの root unit 接頭辞が必要な場合は、`$(SERVICE_PREFIX)-$(SERVICE_NAME)-` で計算できます。
- `REPLACE_FILES_USER` / `REPLACE_FILES_ROOT` … 値が空でなければ `replace-files-user` / `replace-files-root` ターゲットを実行するトリガ。
- `REPLACE_ADD_VAR` … `replace-deploy-vars.sh` の置換対象変数を追加する（例: `REPLACE_ADD_VAR=DEPLOY_ENV` で `@@DEPLOY_ENV@@` を置換）。
- `run_user_make` に渡す環境変数リストは `scripts/deploy-vars.subr` の `DEPLOY_REQUIRED_VARS` で一元管理する。
- 必須変数・派生変数の更新手順は `docs/deploy-vars.subr.md` に従う。

## 期待する依存コマンド
`rsync`, `sudo`, `systemctl`（system / --user 両方）, `podman`, `install`, `grep`, `make`。
--user の systemctl 呼び出しは `sudo systemctl -M "<user>@.host" --user ...` を使う（linger 前提）。

## 処理フロー案
1. `set -euo pipefail`。`info()/err()` ロガーを用意。
2. 環境変数の必須チェックとパス正規化。`SERVICE_PATH` と `INSTALL_ROOT/SERVICE_NAME` の一致を確認し、`SERVICE_PREFIX` も必須（ハイフンを含む文字列を許容、空は禁止）。
3. 既存サービス停止:
   - `/home/<service>/.config/containers/systemd/`（quadlet 等）と `/home/<service>/.config/systemd/user/`（timer/service 等）に **デプロイ済みのファイル名** を find して停止対象にする。root unit は `/etc/systemd/system/` 直下の `${ROOT_UNIT_PREFIX}*` を拾う。ユニット名の決め打ちはせず、現地にあるファイルをそのまま対象とする。このリストは `.timer` を最優先、次に `.socket`、`.path` の順に並べ、timer や socket activation での再起動を防ぐ。
   - user unit: 並べ替え後のリスト順に、`sudo systemctl -M "${SERVICE_USER}@.host" --user is-active ...` で動作中のみ stop、その後 is-enabled を見て disable。
   - root unit: 同様に `/etc/systemd/system/${SERVICE_PREFIX}-${SERVICE_NAME}-<name>` で is-active/is-enabled を確認しながら stop/disable（`.timer` と `.socket` を先に止める）。その後 `/etc/systemd/system/${SERVICE_PREFIX}-${SERVICE_NAME}-*` をまとめて削除してクリーンな状態にしてから配備する（旧バージョン残留を防ぐ）。
4. `deploy-service.sh stop` の場合は停止処理のみで終了。
5. 配置ディレクトリ準備: ホームは OS 既定の `/home/<service>` を使用。`install -d -o ${SERVICE_USER} -g ${SERVICE_USER} -m 0750` で `${SERVICE_PATH}`、`/home/${SERVICE_USER}`、`/home/${SERVICE_USER}/.config/containers/systemd`、`/home/${SERVICE_USER}/.config/systemd/user` を掘る。
6. ソース配置（rsync）:
   - ワークツリー → `${SERVICE_PATH}/` へ `rsync -a --delete --exclude '.git' --exclude '*.swp' --exclude '*~' ./ "${SERVICE_PATH}/"`。
   - `nginx_rp` の `${SERVICE_PATH}/container/conf/` はこの `rsync --delete` で毎回リポジトリ状態へリセットされるため、前回デプロイ時の収集結果は引き継がれません。
   - user unit / quadlet / timer → `/home/${SERVICE_USER}/` へ `rsync -a --delete --exclude '.cache' --exclude '.local' --exclude '*~' "./home/" "/home/${SERVICE_USER}/"`（`.config/containers/systemd/` と `.config/systemd/user/` をまとめて同期。ホームはデプロイ先で直接管理する）。
   - `${INSTALL_ROOT}/scripts/replace-deploy-vars.sh` を `dropins/systemd/` 配下の `*.conf` に適用し、配布元の drop-in を先に置換する。
   - `${INSTALL_ROOT}/scripts/replace-deploy-vars.sh` を `/home/${SERVICE_USER}/.config/containers/systemd/` と `/home/${SERVICE_USER}/.config/systemd/user/` 配下の unit ファイル全て（`.d/*.conf` も含む）に実行し、`@@ROOT_UNIT_PREFIX@@` / `@@SERVICE_PATH@@` / `@@INSTALL_ROOT@@` / `@@CERT_DOMAIN@@` などを置換する（置換後に `chown` で権限を整える）。
   - `${INSTALL_ROOT}/scripts/collect-systemd-dropins.sh` で `SERVICES` に含まれる origin サービスの `dropins/systemd/` を収集し、target の user/root unit に drop-in を追加する（drop-in ファイルは `mochi-dropin-*.conf` に統一して、デプロイ時に古い drop-in を掃除する）。自サービスも対象に含める。収集済み drop-in は配布元で置換済みの前提で、収集側では置換しない。
   - 配置後に `chown -R ${SERVICE_USER}:${SERVICE_USER} "${SERVICE_PATH}" "/home/${SERVICE_USER}"` で所有者を揃える。
   - ディレクトリパーミッションは `${SERVICE_PATH}` / `/home/${SERVICE_USER}` 共に `chmod 750` で締める。
7. enable-linger 処理
   - 先に `loginctl enable-linger ${SERVICE_USER}` を実行（ユーザーセッションが無くても podman build / systemd --user が動くようにする）。
8. pre-build フック:
   - `grep -q '^pre-build-user:' Makefile` で存在したら `sudo -u ${SERVICE_USER} INSTALL_ROOT=... NFS_ROOT=... SERVICE_PATH=... make -C "${SERVICE_PATH}" pre-build-user`（`cwd` は INSTALL_ROOT 下の `${SERVICE_PATH}`）。
   - `grep -q '^pre-build-root:' Makefile` で存在したら root のまま `make pre-build-root`。
   - `pre-build-root` 実行後、`SERVICES` を巡回して各サービスの `pre-build-root-hook-<デプロイ対象サービス名>` を root で実行する。
   - フック呼び出しは `BASE_REPO_DIR/<service>/Makefile` を対象に実行する。これにより、`Makefile.local` で定義したフックも利用できる。
   - `mk/services.mk` には no-op の `pre-build-root-hook-%` が定義されているため、フック未定義サービスがあってもエラーにはならない。サービス固有の明示ターゲットが定義されている場合は、明示ターゲットが優先される。
   - フック実行時には `HOOK_TARGET_SERVICE_NAME` / `HOOK_TARGET_SERVICE_USER` / `HOOK_TARGET_SERVICE_PATH` を環境変数として渡す。
   - フック呼び出しは `make --no-print-directory` で実行され、`--always-make`（`-B`）は付与しない。したがって hook ターゲットは make の通常更新判定（タイムスタンプ）に従って実行・スキップされる。
   - 次のいずれかに該当する hook は `.PHONY`（または `FORCE` 依存）を定義し、毎回実行されるようにする。
     - hook がファイル更新よりも副作用（外部状態の収集、設定の再生成、通知など）を主目的としている。
     - hook ターゲット名と同名のファイル/ディレクトリが存在し得る。
     - 依存ファイルのタイムスタンプが変わらなくても、デプロイのたびに実行する必要がある。
   - 逆に、成果物と依存関係で増分実行を正しく制御したい hook は `.PHONY` 化せず、入力と出力を明示したターゲットとして定義する。
   - フック内で `SERVICE_*` 系変数を参照すると hook 定義側サービスの値を参照します。デプロイ対象サービスを参照する場合は `HOOK_TARGET_SERVICE_*` を使用してください。
   - フック内で `INSTALL_ROOT/<service>` 配下のファイル（例: `replace-deploy-vars.sh` 適用済みファイル）を参照する場合は、`SERVICES` の順序に依存する。対象サービスの deploy が未実行であれば、前回 deploy 時点の古い内容を参照するか、初回 deploy ではファイルが存在しない可能性がある。
   - `nginx_rp` では `pre-build-root` 内で `scripts/collect-nginx-conf.sh` と `scripts/generate-index-html.sh` を実行し、`container/conf/` の vhost 設定収集と `container/html/index.html` の再生成を行う。実行順は「`rsync --delete` で初期化 → `collect-nginx-conf.sh` で `SERVICES` 分を収集 → `generate-index-html.sh` で一覧生成」です。
   - そのため `make <service>-deploy` の単体実行では、他サービス側で変更した `https_<service>.conf` / `http_<service>.conf` は `nginx_rp` に反映されません。vhost 変更を公開設定へ反映する場合は `make deploy` または `make nginx_rp-deploy` を追加で実行してください。
9. `replace-files-user` / `replace-files-root`:
   - `REPLACE_FILES_USER` / `REPLACE_FILES_ROOT` が空でなければ `make replace-files-user` / `make replace-files-root` を実行する。
10. コンテナビルド:
   - `container/` と `container.*` を検出する。
   - `container/` は `localhost/${SERVICE_NAME}:dev`、`container.<suffix>` は `localhost/${SERVICE_NAME}-<suffix>:dev` のタグでビルドする。
   - `deploy-service.sh` は `${INSTALL_ROOT}/scripts/container-build.sh` を実行する。実行時には `CONTAINER_IMAGE` と `CONTAINER_DIR` を環境変数で渡す。
   - `container-build.sh` は当該ディレクトリの `custom-build.sh` を優先実行する。
   - `custom-build.sh` が存在するが実行不可の場合はエラー終了する。共通ビルドへのフォールバックは行わない。
   - `custom-build.sh` がない場合は共通処理として `podman build -t "${CONTAINER_IMAGE}" "${CONTAINER_DIR}"` を行う。
11. post-build フック:
   - `post-build-user` / `post-build-root` があれば pre-build 同様に実行。`post-build-user` は `sudo -u ${SERVICE_USER} INSTALL_ROOT=... NFS_ROOT=... SERVICE_PATH=... make -C ${SERVICE_PATH} post-build-user` で呼ばれる。
   - `post-build-root` 実行後、`SERVICES` を巡回して各サービスの `post-build-root-hook-<デプロイ対象サービス名>` を root で実行する。
   - `mk/services.mk` には no-op の `post-build-root-hook-%` が定義されているため、フック未定義サービスがあってもエラーにはならない。
   - post-build 側も pre-build 側と同様に、`SERVICE_*` 系は hook 定義側サービスの値になります。デプロイ対象サービスを参照する場合は `HOOK_TARGET_SERVICE_*` を使用してください。
   - フック内で `INSTALL_ROOT/<service>` 配下を参照する場合の順序依存・ファイル不在の可能性は、pre-build フックと同様に考慮する。
   - nginx 系なら `post-build-user` で `podman run --rm localhost/${SERVICE_NAME}:dev nginx -t` で構文チェックを行うことが期待される。
12. 環境変数ファイルの配置:
    - `Makefile` に `env-files-user` / `env-files-root` が定義されている場合、`make -C ${SERVICE_PATH} --always-make env-files-user` / `env-files-root` を root で実行する。
    - `$(SERVICE_PATH)/%.env-user` と `$(SERVICE_PATH)/%.env-root` は `SECRETS_DIR` の同名ファイルからコピーし、`scripts/replace-deploy-vars.sh` でテンプレートを置換する。
13. systemd 配置:
- user unit / quadlet / timer: 上記置換済みファイルを前提に `sudo systemctl -M "${SERVICE_USER}@.host" --user daemon-reload` を実行。Podman + SELinux 環境ではローカルディスクの bind mount に `Volume=...:Z` / `Volume=...:ro,Z` を付与する。NFS パスは `docs/UsersSetup.md` の方針に従い、`virt_use_nfs=on` を前提に `:z` / `:Z` を付けない（サービスユーザー間で共有する NFS bind mount のため）。
    - root unit（例: 80 → 8080 の socket-proxyd）を持つ場合は `${SERVICE_PATH}/systemd/` にあるファイルを `/etc/systemd/system/${SERVICE_PREFIX}-${SERVICE_NAME}-<name>` というファイル名で配置する。`scripts/replace-deploy-vars.sh` で `@@ROOT_UNIT_PREFIX@@` / `@@SERVICE_PATH@@` / `@@INSTALL_ROOT@@` / `@@CERT_DOMAIN@@` を置換したうえで `chmod 0644 && chown root:root`。`sudo systemctl daemon-reload` を忘れずに。
14. 再起動・有効化:
    - user unit:
      - `.container` は Quadlet 生成ユニットなので `start` のみ（enable 不可）。
      - それ以外の unit は、unit ファイル内に `[Install]` セクションがあるかを `grep -q '^\[Install\]'` でチェック:
        - `[Install]` セクションあり → `sudo systemctl -M "${SERVICE_USER}@.host" --user enable --now ${unit}`
        - `[Install]` セクションなし → `sudo systemctl -M "${SERVICE_USER}@.host" --user start ${unit}`（enable せずに start のみ）
        - unit ファイルが `#NOSTART` を含む場合は起動・有効化をスキップする（暫定配置や依存専用 unit を想定）
    - root unit:
      - `.container` は `sudo systemctl start ${unit%.container}`（enable 不可）。
      - それ以外は配置後のファイル `/etc/systemd/system/${SERVICE_PREFIX}-${SERVICE_NAME}-<name>` に `[Install]` セクションがあるかチェック:
        - `[Install]` セクションあり → `sudo systemctl enable --now ...`
        - `[Install]` セクションなし → `sudo systemctl start ...`（enable せずに start のみ）
        - unit ファイルが `#NOSTART` を含む場合は起動・有効化をスキップする
15. 正常終了ログを出して終了。途中で失敗したら即 `exit 1`。

## [Install] セクションのチェック処理
unit ファイルを起動する際、`[Install]` セクションの有無によって `enable` するか `start` のみにするかを自動判定する。

### チェック方法
- `grep -q '^\[Install\]' <unit_file>` で unit ファイル内に `[Install]` セクションが存在するかを確認
- 存在する場合: `systemctl enable --now` で有効化と起動を同時実行
- 存在しない場合: `systemctl start` で起動のみ実行（enable は不可のため）

### 対象となる unit
- **Quadlet 生成 unit (`.container` ファイル)**: Quadlet が自動生成する service unit には `[Install]` セクションが含まれないため、常に `start` のみ実行
- **通常の `.service` / `.socket` / `.timer` ファイル**: unit ファイルの記述次第
  - socket activation を使う socket unit は通常 `[Install]` セクションを持つ
  - timer unit は `WantedBy=timers.target` を持つ場合が多い（`enable --now` で即スケジュールされる点に注意）
  - 他の unit から依存されるだけの service unit は `[Install]` セクションを持たない場合がある
- **`#NOSTART` を含む unit**: 配置のみ行い、起動や enable をスキップするためのマーカーとして使う

### 理由
- `[Install]` セクションのない unit を `enable` しようとすると systemd がエラーを返すため、事前チェックで回避
- Quadlet の `.container` ファイルは systemd-generator が `.service` unit を生成するが、この生成 unit には `[Install]` セクションが含まれない仕様

## テンプレート処理の詳細
user unit / quadlet / root unit のテンプレート置換は `scripts/replace-deploy-vars.sh` に集約して行う。`@@...@@` 形式の変数をデプロイ時の実値に差し替え、bind mount のパスや依存先 unit 名を動的に合わせる。
`replace-deploy-vars.sh` は置換後に `grep -nE '@@[A-Z0-9_]+@@'` で未置換トークンを検出し、該当行が 1 件でも存在する場合はエラー終了する。

### サポートするプレースホルダー
- `@@ROOT_UNIT_PREFIX@@` … `${SERVICE_PREFIX}-${SERVICE_NAME}-` に置換（例: `http-nginx_rp-`）。root unit のファイル名や `Requires` などで使用。
  - unit ファイルの依存関係や `WantedBy` などで他の unit を参照する際に使用
  - 例: `Requires=@@ROOT_UNIT_PREFIX@@proxy-80.socket` → `Requires=http-nginx_rp-proxy-80.socket`
- `@@SERVICE_PATH@@` / `@@INSTALL_ROOT@@` … user unit / root unit 両方で `${SERVICE_PATH}` / `${INSTALL_ROOT}` に置換（bind mount のパス指定などで使用）
- `@@CERT_DOMAIN@@` … `${CERT_DOMAIN}` に置換（証明書ドメインなどに使用）
- `@@MAP_LOCAL_ADDRESS@@` … `${MAP_LOCAL_ADDRESS}` に置換（pasta の `--map-host-loopback` や proxy の upstream 指定で使用）
- `@@<任意の追加変数>@@` … `REPLACE_ADD_VAR` によって追加された変数名が置換対象になる（例: `REPLACE_ADD_VAR=DEPLOY_ENV` なら `@@DEPLOY_ENV@@` が置換される）

### 拡張方法
将来的にプレースホルダーを追加する場合は、`scripts/deploy-vars.subr` の `DEPLOY_REQUIRED_VARS` に変数名を足す。`@@NEW_VAR@@` を unit ファイルに書き、NEW_VAR 環境変数が設定されていれば自動で置換される。
追加時の同期対象と確認観点は `docs/deploy-vars.subr.md` を参照する。

### 注意点
- プレースホルダーは `@@VARIABLE@@` 形式を推奨（識別しやすく、誤置換を防ぐため）
- user unit / quadlet (`/home/<service>/.config/containers/systemd/`) も `@@SERVICE_PATH@@` / `@@INSTALL_ROOT@@` を実際のパスに置換したうえで配置する（bind mount のソース指定を想定）
- テンプレート処理が不要な root unit は従来通り記述すれば良い（プレースホルダーを含まなければそのままコピーされる）
  - drop-in も同様に `@@...@@` を置換する。origin 配布の drop-in は `deploy-service.sh` が `dropins/systemd/` に対して `replace-deploy-vars.sh` を実行した後に `collect-systemd-dropins.sh` で配置する（収集側では置換しない）。

## 動作確認の目安
- 正常系: sudo make deploy が完走する事。
- 異常系: 必須変数欠け、rsync 失敗、podman build 失敗、systemd reload/restart 失敗で即座に非 0 で落ちること。
- テンプレート置換: 配置後の `/etc/systemd/system/` 内の unit ファイルに `@@` が残っていないことを確認（`grep -r '@@' /etc/systemd/system/<SERVICE_PREFIX>-<SERVICE_NAME>-*`）。
