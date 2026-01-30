# openSUSE MicroOS / rootless Podman コンテナ基盤メモ

## 0. 最近の更新（作業メモ）

- `scripts/deploy-service.sh` / `scripts/pre-deploy-check.sh` / `scripts/replace-deploy-vars.sh` の実装差分に合わせて `docs/deploy-service.md` / `docs/pre-deploy-check.md` / `docs/DEPLOYMENT.md` を同期更新（stop-only、container.* ビルド、置換変数、NFS チェックの挙動など）。
- nginx_rp の pre-build で `SERVICES` に含まれる各サービスの http/https 設定を自動収集し、`container/conf/http_default.conf` / `https_default.conf` に整理。起動時は symlink と証明書有無で https を有効化。
- nextcloud の nginx 設定を `nextcloud/https_nextcloud.conf` に移動し、deploy 時に `@@CERT_DOMAIN@@` を置換して `SERVICE_PATH` 配下へ配置する流れに変更。
- 各サービスの `Makefile` は `mk/services.mk` を `include` 必須に統一し、読み込み失敗をビルドで検知できるようにした。

## 1. 全体方針・前提

- ホストOS: openSUSE MicroOS（immutable 前提）
- コンテナランタイム: Podman（rootless 基本）
- 役割分担:
  - 「開発ユーザー」= 通常ログインして Git 操作 / 編集を行う一般ユーザー（例: `you`）
  - 「サービスユーザー」= コンテナを実行する専用ユーザー（例: `nginx_rp`, 将来 `svc-nextcloud` 等）
  - 「コンテナ内部ユーザー」= nginx などアプリケーションユーザー（`nginx`, `www-data` 等）
- リポジトリ構成方針: **サービス優先構成**
  - トップディレクトリ直下に `nginx_rp/`, `ssl_update/`, `nextcloud/`, `munin/`, `git-backend/` など「サービス名」を置く。
  - 各サービス配下で `container/`, `config/`, `systemd/` などを分ける。
- 基本思想:
  - 設定ファイルは「可能なものは bind mount 派」
  - 本番永続データは `NFS_ROOT/<username>` の ZFS/NFSv4 ボリュームに保存し、`zfs-autobackup` で snapshot & バックアップ。

---

## 2. リポジトリ構成（現状の想定）

ルート構成（概念レベル、まだ全部は実体化していない）:

```text
project-root/
  AGENTS.md              # codex-cli / エージェント向けのプロジェクト説明
  mk/
    services.mk          # 各サービス共通の make ターゲット定義
  scripts/
    deploy-service.sh    # rsync デプロイ用の共通スクリプト
  nginx_rp/
    AGENTS.md            # nginx サービス専用ガイド（任意）
    home/.config/containers/systemd/  # rootless systemd user unit / quadlet 用ディレクトリ
    container/
      Containerfile
      default.conf
    html/
        index.html
    config/
      # nginx.conf / 各種 vhost 設定 (bind mount 前提)
    systemd/
      # root での service が必要なときに使用（特権ポートの socket acitivation など）
  security_package/
    container/           # SELinux ポリシー RPM をビルドするコンテナ
    rpmbuild/            # te/spec/VERSION.mk など rpm ソース一式
    out/                 # build-rpm 後の生成物置き場（deploy 時に INSTALL_ROOT/rpms へコピー）
  ssl_update/
    README.md            # lego 実行フローや .env サンプル
    Makefile
    container/
      Containerfile
      scripts/
        run.sh
        hook.sh
    config/
      # ssl_update 用設定等（現状空）
    home/.config/containers/systemd/
      lego.container
    systemd/              # root 管理が必要ならここに置く（現状空）
  nextcloud/
    container/
    config/
    systemd/
  munin/
    ...
  git-backend/
    ...
````

### `AGENTS.md` の役割（概要）

* ルート `AGENTS.md`:

  * 「トップにはサービス名ディレクトリを置く」
  * 「新サービス追加時は `<service>/container`, `<service>/config`, `<service>/systemd`, `<service>/home/.config/containers/systemd/` を作り、user systemd/quadlet は home 配下に置く」
  * 「nginx_rp ディレクトリがテンプレートになる」などを明文化。
* 各サービス配下の `AGENTS.md`:

  * そのサービス固有のルール（例: nginx はまだ SSL 不要、ポート 443 固定など）を記述。

---

## 3. ステージ設計（フェーズ分け）

### ステージ1（完了済み）

**目的:** nginx Hello World コンテナを rootless Podman で動かし、基本構造を確認。

* nginx hello コンテナ:

  * `nginx_rp/container/Containerfile`

    * ベース: `nginx:alpine`（将来 openSUSE ベースに変更も可）
    * `default.conf` を `/etc/nginx/conf.d/default.conf` に COPY
    * `html/` 配下を `/usr/share/nginx/html/` に COPY
    * コンテナ内部で `EXPOSE 80`
  * `default.conf`:

    * SSL なし、`listen 80;` で `index.html` を返すだけのシンプル構成。
  * `html/index.html`:

    * 「Hello from MicroOS + Podman + nginx」的なテストページ。

* 動作確認:

  * 開発ユーザー (`you`) で:

    * `podman build -t localhost/nginx-hello:latest ./nginx/container`
    * `podman run --rm -d -p 8080:80 localhost/nginx-hello:latest`
    * `curl http://localhost:8080` でページが返ることを確認。

### ステージ2（スキップ or 軽く触る程度）

* 「開発ユーザー ＝ Podman 実行ユーザー」のまま、簡易運用を続けるフェーズ。
* 今回の構想では「すぐステージ3へ移行」のため、深掘りはしない方向。

### ステージ3（完了）

* サービスユーザー分離 (`nginx_rp` 等)
* 本番用 `/srv` デプロイツリー
* 設定ファイル、ダミーコンテンツの bind mount によるコンテナイメージのビルドと容量の最適化
* systemd socket activation で 80→8080 をプロキシ

### ステージ4（https化 / ssl_update / lego 証明書運用）

* nginx_rp の自己署名証明書での 8443 https サービス
  * ステージ4で起動時に真正の証明書があればそちらを使用するようにする（ssl_update との連携）
* lego (go-acme) による DNS-01 で証明書取得・更新を自動化
* `ssl_update` サービスユーザーを前提に、nginx への証明書供給と reload 連携を整備

---

## 4. ステージ3 詳細（完了済み）

### 4.1 ユーザーとディレクトリ設計

* 開発ユーザー:

  * 例: `you`
  * Git リポジトリ所有者。`/srv/develop/mochi-containers/` で作業。

* サービスユーザー:

  * 例: `nginx_rp`（nginx 処理の実行ユーザー）
  * 将来的には `nextcloud` なども追加予定。
  * `loginctl enable-linger nginx_rp` で user systemd を常駐可能にする。
  * ホームディレクトリは OS 既定の `/home/<service>` を使用（以前の `/srv/project/<service>/home` だと Podman ストレージアクセスが OS 更新で壊れたため、ホームを分離）。

* デプロイツリー:

  * `/srv/project/nginx_rp` … nginx_rp 用「現在版」設定の配置場所

    * リリースごとのディレクトリは **作らない** 方針。
    * 必要なら `git checkout <tag/commit>` → `/srv` へ rsync で「再デプロイ」。
  * 他サービスも `/srv/project/<service>` で展開。

* 永続データ:

  * `NFS_ROOT/<username>` を ZFS/NFSv4 ボリュームとしてマウント。

    * 例: `NFS_ROOT/nextcloud/nextcloud-data` など。
  * NFS サーバー側は ZFS dataset 単位で `zfs-autobackup` による snapshot & send/recv を実行。
  * Podman 側からは「既にマウント済みのディレクトリを bind mount」するだけ。

### 4.2 デプロイ方法（rsync 一発＋権限調整）

* 方針:

  * 「リリースディレクトリ」は使わず、`/srv/project/nginx_rp` を常に「現在版」とする。
  * 実装に関しては docs/DEPLOYMENT.md, docs/deploy-service.md に記載

### 4.3 systemd socket activation（443 → 8443）

#### 目的

* rootless Podman の nginx コンテナは 8443 を host に公開 (`-p 8443:443`)。
* 外部からの 443/tcp は systemd の socket + `systemd-socket-proxyd` で 127.0.0.1:8443 に転送。

#### 想定構成

* `/etc/systemd/system/nginx-https.socket`:

  * `ListenStream=443` で root 権限による待ち受け。

* `/etc/systemd/system/nginx-https-proxy.service`:

  * `ExecStart=/usr/lib/systemd/systemd-socket-proxyd 127.0.0.1:8443`
  * 常駐プロキシ or socket activation 連携。

* nginx_rp コンテナ (rootless, `nginx_rp` ユーザー):

  * `podman run --name nginx_rp -p 8443:443 ...`
  * user systemd の `nginx_rp-container.service` で管理。

#### user systemd サービスの配置・操作（`docs/DEPLOYMENT.md` 補足）

* --user の unit や quadlet は **サービスユーザーのホーム配下** に置く。リポジトリの `<service>/home/.config/containers/systemd/` から `/home/<service>/.config/containers/systemd/` へ rsync して daemon-reload（`sudo -u <service> systemctl --user daemon-reload`）。
* 起動/停止/再起動もサービスユーザー権限で `systemctl --user start/stop ...` を使う。root 管理の unit は `/etc/systemd/system/<service>/` に配置して通常の `sudo systemctl ...`。

## 5. ステージ4 詳細（ssl_update / lego）

### 5.1 証明書取得・配置の基本方針

* `go-acme/lego` コンテナ（rootless）
* DNS-01 challenge（例: Cloudflare や Route53 など DNS プロバイダに合わせた driver）
* lego 用ディレクトリ `/srv/project/ssl_share/` を `ssl_update` 所有で作成し、nginx 側は bind mount で参照
* `--path /lego` などで保存先指定し、初回取得は `podman run` を手動実行

### 5.2 更新フローと reload 連携

* 更新は日次程度で systemd timer 管理
* `renew` 成否だけでは更新有無が分からないため、`--renew-hook` を使い **更新された時だけ** nginx reload を発火
* hook コマンド例: `systemctl --user reload nginx_rp-container.service`

### 5.3 実装スケッチ

* `/srv/lego/lego-renew.sh`（`ssl_update` 所有）

  * lego コンテナ実行（DNS トークンは環境変数 or .env ファイルから読み込む）
  * `renew --days 30 --renew-hook "systemctl --user reload nginx_rp-container.service"`

* systemd (user) による定期実行:

* `~ssl_update/.config/containers/systemd/lego-renew.service` (Type=oneshot)
* `~ssl_update/.config/containers/systemd/lego-renew.timer` (OnCalendar=daily)

---

## 6. Make ベースの「ports 風」ビルド/デプロイ（初版導入済み）

* トップレベル `Makefile`:

  * `SERVICES = ssl_update nextcloud nginx_rp security_package` を管理中（将来拡張予定）。`SERVICE_PREFIX=mochi`、`INSTALL_ROOT=/srv/project`、`SECRETS_DIR=../secrets` がデフォルト。
  * `make deploy|stop` で全サービスに順回し、`make <service>-deploy` で個別実行。
  * `SECRETS_DIR` は `../secrets` をデフォルトとし、`.env-user` / `.env-root` を対象とする。

* `mk/services.mk`:

  * `deploy`, `stop` は `scripts/pre-deploy-check.sh` → `scripts/deploy-service.sh` を呼び出す。

* `scripts/deploy-service.sh` 周り:

  * 必須変数 (`SERVICE_NAME`/`SERVICE_USER`/`SERVICE_PATH`/`INSTALL_ROOT`/`SERVICE_PREFIX` など) をチェックし、`SERVICE_PATH=INSTALL_ROOT/<service>` でないとエラー。
  * 停止対象の unit は `/home/<service>/.config/containers/systemd/` と `/home/<service>/.config/systemd/user/` の **デプロイ済みファイル名**、および `/etc/systemd/system/${SERVICE_PREFIX}-${SERVICE_NAME}-*` を find して timer → socket → path → その他の順で stop/disable。root unit は停止後に一括削除。
  * `install -d` で `/home/<service>` / `.config/containers/systemd` / `.config/systemd/user` / `${SERVICE_PATH}` を 0750 で掘り、`rsync` でワークツリーと `home/` を同期。`scripts/replace-deploy-vars.sh` で user/root unit の `@@ROOT_UNIT_PREFIX@@` / `@@SERVICE_PATH@@` / `@@INSTALL_ROOT@@` を置換してから `chown -R`。
  * `loginctl enable-linger <service>` を必ず実行。`pre-build-user` は呼び出し元 cwd（サービスディレクトリ）で `sudo -u <service> INSTALL_ROOT=... SERVICE_PATH=... make`、`post-build-user` は `${SERVICE_PATH}` で実行する。root フックも Makefile 定義があれば叩く。
  * `container/` があれば `podman build -t localhost/<service>:dev` を実行。root unit は `/etc/systemd/system/${SERVICE_PREFIX}-${SERVICE_NAME}-<name>` へコピーして置換・0644/root:root に設定し、daemon-reload。user unit は置換済みを前提に --user daemon-reload して `[Install]` 有無で enable/start を分岐、`.container` は start のみ、`#NOSTART` はスキップ。root unit も同様に enable/start を分岐。

* 各サービス `Makefile`:

  * `nginx_rp` / `ssl_update` ともに `mk/services.mk` を include 済みで、`make <service>-deploy` が動く状態。
  * `nginx_rp` の `pre-build-root` は `SERVICES` に含まれる各サービスの `${INSTALL_ROOT}/<service>/http_<service>.conf` / `https_<service>.conf` を集約して `nginx_rp/container/conf/` にコピーするため、`SERVICES` の並びは `ssl_update` → 各サービス → `nginx_rp` の順にしておく。
  * `security_package` は `NFS_GROUP_CHECK=No` で rpmbuild 用。pre-build-root で LICENSE コピー、`check-version-consistency.sh` 実行、`.package-evr` を生成し、post-build-user で RPM をコンテナ内ビルドして `INSTALL_ROOT/rpms/local-mochi-security-selinux-<evr>.noarch.rpm` を配置する。

---

## 7. 現状の達成状況と今後のマイルストーン

### 達成済み

* [x] nginx_rp Hello World コンテナ (rootless Podman, 開発ユーザー) の起動確認。
* [x] リポジトリ構成の基本方針:

  * トップにサービス名ディレクトリ
  * 各サービス配下に `container/`, `config/`, (`systemd/`) など。
* [x] 「設定は基本 bind mount 派」、永続データは `NFS_ROOT/<username>` に集約する方針の確立。
* [x] デプロイ側はリリースディレクトリを持たず、Git でタグ/ハッシュを指定して再デプロイする思想に決定。
* [x] ステージ3: `nginx_rp` の rootless 仮構成（80→8080 socket/proxy、/srv 配置）を完了。
* [x] Make ベースの deploy / stop フロー初版（トップ Makefile + mk/services.mk + scripts/*）を導入。
* [x] `ssl_update` のコンテナ/quadlet スケルトンと README（`.env` サンプル付き）を作成。
* [x] `security_package` サービス追加（socket-proxyd 用 SELinux ポリシーを RPM 化するコンテナ + Makefile/README）。`SERVICES` に組み込み済み。
* [x] `docs/DEPLOYMENT.md` / `docs/deploy-service.md` を `scripts/deploy-service.sh` の現実装（ユニット探索順・置換スクリプト・pre/post-build の cwd/環境変数渡しなど）に同期。

* ssl_update / lego 証明書運用
* [x] lego コンテナで初回証明書取得 (`run`) を実施し、nginx 用に bind mount。
* [x] nginx の SSL 設定を証明書参照に切り替え、`https://` でのアクセス確認。
* [x] nginx の 443→8443 socket/proxy を設定。
* [x] nginx_rp 側の bind mount 設定と reload 連携の整備（`.cert-updated` トリガー活用）。
* [x] ssl_update の lego renew 用 .timer unit を実装し、更新時のみ nginx reload が走ることを確認。

* security_package (SELinux policy RPM) の実運用
* [x] `make deploy` を回して `local-mochi-security-selinux-<evr>.noarch.rpm` を生成し、`INSTALL_ROOT/rpms/` へ配置。
* [x] transactional-update でホストにインストールし、443/80 socket-proxy 運用時の AVC を確認。
* [x] te/spec 更新時は `rpmbuild/VERSION.mk` と `%changelog` の整合を維持（`check-version-consistency.sh` で検出）。

### これからの主要マイルストーン

1. nextcloud 対応

- [x] nextcloud サービス追加: nextcloud:stable-apache ベースの構成案を整理し、nginx_rp の SNI 連携前提で実装方針を確定
- [x] nginx_rp ↔  nextcloud の通信方式を 9000/TCP で行う
- [x] nextcloud サービス定義内に nginx_rp 用の conf を持たせ、deploy 時に `SERVICE_PATH` 配下へ配置する（nextcloud 固定ではなく汎用の仕組みにする）

2. **Make ベース「ports 風」システムの導入**

* [x] `mk/services.mk` の初版作成（deploy/stop）。
* [x] `nginx_rp/Makefile` / `ssl_update/Makefile` を整備し、`make <service>-deploy` で stop → rsync →  start まで完結。
* [x] トップレベル `Makefile` から `SERVICES = ssl_update nextcloud nginx_rp security_package` を管理。
* [ ] munin / git-backend などを SERVICES に追加していく。

---

## 8. 引き継ぎ時のポイント

* 設計のキモは **「rootless Podman + systemd (socket/proxy) + NFS/ZFS バックアップ」** の三位一体。
* 443 の扱い:

  * rootless コンテナは 8443 で待ち受け。
  * 443 は systemd-socket-proxyd が 8443 に転送。
* 証明書更新:

  * lego コンテナ（rootless）で DNS-01。
  * `--renew-hook` で「更新された時だけ nginx reload」させる。
* デプロイ:

  * `/srv/project/<service>` は常に「現在版」。
  * Git の commit/tag ベースで再デプロイする方針。
* 永続データ:

  * `NFS_ROOT/<username>` 配下に集約。
  * ZFS snapshot + zfs-autobackup により日次バックアップ & HDD/mirror へ転送。
