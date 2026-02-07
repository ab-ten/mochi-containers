# QUICKSTART

本書は、最短でサービスを動作させるための手順を要点のみまとめたクイックスタートです。詳細仕様や前提の背景は省略していますので、必要に応じて各ドキュメントを参照してください。

## 1. このドキュメントの範囲
- 対象: OpenSUSE MicroOS + rootless Podman + systemd user unit を前提とした最小構成
- 目的: `make deploy` によりサービスが起動する状態まで到達すること
- 非対象: 汎用環境への移植、詳細な設計説明、トラブルシューティングの網羅

## 2. 前提・必要なもの
- OpenSUSE MicroOS（想定環境）
- rootless Podman
- systemd user unit / quadlet が利用できること（linger 前提）
- wildcard 証明書 + DNS-01（lego 想定）
- LAN 内の名前解決を split DNS または hosts で解決できること
- 必須コマンド: `sudo`, `rsync`, `make`, `podman`, `systemctl`

## 3. 事前準備（最小）
### 3.1 サービスユーザーの作成
サービスごとに専用ユーザーが必要です。作成例は `docs/UsersSetup.md` を参照してください。

### 3.2 NFS を使う場合
`NFS_ROOT` をマウントし、サービスユーザーが所有するディレクトリを作成してください。権限や所有者の不一致はデプロイ時にエラーになります。

### 3.3 `Makefile.local` とシークレット
環境依存の値は `Makefile.local` に定義します。最低限、以下の項目を確認してください。
- `INSTALL_ROOT`（例: `/srv/project`）
- `NFS_ROOT`（例: `/srv/nfs/containers`）
- `SECRETS_DIR`（例: `/srv/secrets`）
- `CERT_DOMAIN`（例: `example.com`）
- `SERVICES`（デプロイ対象のサービス一覧）
- `MAP_LOCAL_ADDRESS`（pasta の `--map-host-loopback` 用）

詳細は `docs/DEPLOYMENT.md` を参照してください。

### 3.4 `ssl_update` の環境変数ファイル
初回の証明書取得が必須です。`SECRETS_DIR/ssl_update.env-user` を作成し、内容は `ssl_update/README.md` の手順に従ってください。

### 3.5 SELinux 環境での `security_package`
SELinux が有効な環境では、`security_package` をデプロイして SELinux ポリシー RPM を作成し、ホストへ組み込む必要があります。手順は `security_package/README.md` を参照してください。

### 3.6 `nextcloud` を使う場合
`SECRETS_DIR/nextcloud.env-user` の作成が必要です。内容は `nextcloud/README.md` を参照してください。

### 3.7 `redmine` を使う場合
`SECRETS_DIR/redmine.env-user` の作成が必要です。内容は `redmine/README.md` を参照してください。

## 4. リポジトリ準備
1) リポジトリを取得し、`Makefile.local` を作成します。
2) `SERVICES` の並び順を決めます（例: `ssl_update → 各サービス → nginx_rp`）。

## 5. 最短デプロイ手順
初回は `SERVICES = ssl_update nginx_rp security_package` を `Makefile.local` に設定し、ルートで `make deploy` を実行します。
SELinux の場合は、INSTALL_ROOT/rpms に作成された rpm パッケージをインストールする必要があります。
特に OpenSUSE MicroOS の場合は transactional-update 内でインストールして再起動する必要があります。

```bash
sudo make deploy
```

`SERVICES` の一覧に従って順番にデプロイされます。サービス単体で実行したい場合は `make <service>-deploy` を使用してください（例: `make nginx_rp-deploy`）。

## 6. 動作確認（最小）
以下は最低限の確認例です。

```bash
sudo systemctl -M "<service_user>@.host" --user status <unit>
```

`curl https://CERT_DOMAIN/` を用いた疎通確認を行ってください。

## 7. つまずきポイント
- `systemctl --user` は `sudo systemctl -M "<user>@.host" --user ...` を使用してください。
- サービスユーザーのホームは `/home/<service>` 固定です。異なる場合はエラーになります。
- NFS の所有権がサービスユーザーと一致しない場合は失敗します。
- SELinux 環境では bind mount に `:Z` / `:ro,Z` が必要です。
- unit テンプレート内の `@@...@@` 置換漏れがあると起動に失敗します。

## 8. 次に読む
- 各サービスの `README.md`
- `docs/DEPLOYMENT.md`
- `docs/deploy-service.md`
- `docs/pre-deploy-check.md`
- `docs/collect-systemd-dropins.md`
- `docs/generate-index-html.md`
