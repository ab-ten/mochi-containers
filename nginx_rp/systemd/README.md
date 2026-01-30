# nginx_rp systemd units (root)

このディレクトリには root 権限で動作する systemd units を配置します。

## 現在の構成

### proxy-80.socket / proxy-80.service

- **目的**: ホストの特権ポート 80/tcp で受け付けたリクエストを、rootless で動作する nginx_rp サービス (localhost:8080) に転送する
- **仕組み**: 
  - `proxy-80.socket` が port 80 で listen
  - `proxy-80.service` が `systemd-socket-proxyd` を使って 127.0.0.1:8080 に転送
  - rootless quadlet (`nginx_rp.container`) が 8080 でコンテナ内の nginx (port 80) を公開

## テンプレート変数

これらの unit ファイルは `@@ROOT_UNIT_PREFIX@@` などのプレースホルダーを含んでおり、
`deploy-service.sh` によるデプロイ時に `sed` で実際の値に置換されます。

### 利用可能なプレースホルダー

- `@@ROOT_UNIT_PREFIX@@` → 例: `http-nginx_rp-` (SERVICE_PREFIX と SERVICE_NAME から生成)
  - ファイル名のプレフィックスと unit 内の依存関係記述の両方で使用
  - 例: unit 内で `Requires=@@ROOT_UNIT_PREFIX@@proxy-80.socket` と記述すると、デプロイ後は `Requires=http-nginx_rp-proxy-80.socket` に展開される

### デプロイ後のファイル配置

元ファイル (`nginx_rp/systemd/`) → 配置先 (`/etc/systemd/system/`):
- `proxy-80.socket` → `http-nginx_rp-proxy-80.socket`
- `proxy-80.service` → `http-nginx_rp-proxy-80.service`

### テンプレート変数の追加方法

新しいプレースホルダーを追加したい場合は、`scripts/deploy-service.sh` の該当箇所に置換ルールを追加:

```bash
sed -e "s|@@ROOT_UNIT_PREFIX@@|${ROOT_UNIT_PREFIX}|g" \
    -e "s|@@NEW_VARIABLE@@|${NEW_VALUE}|g" \
    "${SERVICE_PATH}/systemd/${unit}" > "${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}${unit}"
```

推奨する変数名形式: `@@UPPERCASE_WITH_UNDERSCORES@@`

## デプロイ方法

`deploy-service.sh` を使用して自動デプロイします:

```bash
cd /path/to/mochi-containers
sudo SERVICE_NAME=nginx_rp SERVICE_USER=nginx_rp \
  SERVICE_PATH=/srv/project/nginx_rp INSTALL_ROOT=/srv/project \
  SERVICE_PREFIX=http \
  ./scripts/deploy-service.sh
```

または nginx_rp の Makefile から:

```bash
cd nginx_rp
sudo make deploy
```

## 確認方法

```bash
# socket が listen しているか確認
sudo systemctl status nginx_rp-proxy.socket
sudo ss -tlnp | grep :80

# rootless nginx_rp が 8080 で動いているか確認 (nginx_rp ユーザーで)
systemctl --user status nginx_rp.service
ss -tlnp | grep :8080

# 実際にアクセスしてみる
curl http://localhost/
```

## 注意点

- root systemd units なので、`/etc/systemd/system/` に手動でコピーする必要があります
- rootless の nginx_rp サービスが先に起動している必要があります
- nginx_rp ユーザーの quadlet は従来通り 8080 でバインドします (PublishPort=8080:80)
