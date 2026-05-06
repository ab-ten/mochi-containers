# Local Customization

本書は、公開リポジトリへプライベートなカスタマイズを混入させずに、`Makefile.local`、user drop-in、`custom-build.sh` などをデプロイへ反映する方法を説明します。

## 概要

`deploy-view-build.sh` は、`mochi-containers` とカスタマイズディレクトリを合成した `mochi-deploy-view` を作成し、その view 上で `sudo make "$@"` を実行します。

基本的な流れは以下のとおりです。

1. `mochi-containers` を `mochi-deploy-view` へ `rsync --delete` でミラーします。
2. カスタマイズディレクトリのファイルを `mochi-deploy-view` へ追加コピーします。
3. `mochi-deploy-view` をカレントディレクトリとして `sudo make "$@"` を実行します。

`mochi-deploy-view` は生成物です。view 上で直接編集した内容は次回再生成で失われ、カスタマイズディレクトリにも反映されません。

## 方式の選択

### `_local/` を使う場合

`mochi-containers` 直下に `_local/` を作成し、カスタマイズファイルを配置します。`MOCHI_CUSTOMIZE` が未設定で、カレントディレクトリが `mochi-containers` ルート、かつ `_local/` が存在する場合、`deploy-view-build.sh` は `./_local/` をカスタマイズディレクトリとして使用します。

```text
mochi-containers/
  deploy-view-build.sh
  _local/
    Makefile.local
    nginx_rp/dropins/systemd/...
mochi-deploy-view/
```

`_local/` は `.gitignore` に登録済みです。`_local/` を使う場合は、`mochi-containers` ルートから以下を実行します。

```bash
./deploy-view-build.sh deploy
```

`_local/` が存在する状態で直接 `sudo make deploy` または `sudo make <service>-deploy` を実行すると、ルート `Makefile` がエラー終了します。カスタマイズを無視したデプロイを防ぐためです。

### 外部 `mochi-customize` を使う場合

カスタマイズを別リポジトリで管理する場合は、`mochi-customize` などの外部ディレクトリを作成します。

```text
mochi-containers/
  deploy-view-build.sh
mochi-customize/
  Makefile.local
  redmine/dropins/systemd/...
mochi-deploy-view/
```

`mochi-customize` 側にラッパースクリプトを置く場合は、以下のように `deploy-view-build.sh` へ処理を委譲します。

```bash
#!/usr/bin/env bash
set -euo pipefail

export SECRETS_DIR=/srv/secrets
exec ../mochi-containers/deploy-view-build.sh "$@"
```

## 初期セットアップ

`mochi-deploy-view` は利用者が事前に作成します。`deploy-view-build.sh` は存在しない場合に自動作成せず、エラー終了します。

```bash
mkdir ../mochi-deploy-view
```

`MOCHI_DEPLOY_VIEW` を指定すると、既定の `../mochi-deploy-view` 以外のディレクトリを使用できます。

```bash
MOCHI_DEPLOY_VIEW=/path/to/mochi-deploy-view ./deploy-view-build.sh deploy
```

## 配置できるカスタマイズ例

カスタマイズディレクトリは add-only です。`mochi-containers` に存在しない相対パスのファイルだけを追加できます。

主な配置例は以下のとおりです。

- `Makefile.local`
- `<service>/dropins/systemd/.../user-*.conf`
- `<service>/container/custom-build.sh`
- `<service>/container.<suffix>/custom-build.sh`
- `<service>/home/.config/systemd/user/*.d/*.conf`

既存ファイルの上書きや削除は扱いません。`mochi-containers` と同じ相対パスのファイルを置いた場合は、衝突としてエラー終了します。

## 除外と衝突のルール

`deploy-view-build.sh` は、カスタマイズディレクトリを追加コピーする前に衝突を検出します。

- `mochi-containers` と同じ相対パスのファイルは衝突として扱います。
- 親パスの型が異なる場合も衝突として扱います。
- カスタマイズディレクトリ側の `.git/`、`.gitignore`、`*.swp`、`*~` は衝突判定と転送から除外します。
- カスタマイズディレクトリ側の `/README.md` は衝突判定と転送から除外します。
- `mochi-containers` 側の `/_local/` は view 生成時に除外します。
- `mochi-containers` 側の `.git/` は view に含めます。

`security_package` のバージョン判定では `mochi-containers` 側の Git メタデータを参照します。そのため、view 生成時に `mochi-containers` 側の `.git/` は除外しません。

## 環境変数

`deploy-view-build.sh` は以下の環境変数を参照します。

- `MOCHI_CUSTOMIZE`: カスタマイズディレクトリを明示します。設定されている場合は最優先で使用します。
- `MOCHI_DEPLOY_VIEW`: deploy view ディレクトリを明示します。未設定時は `mochi-containers` から見た `../mochi-deploy-view` を使用します。
- `SECRETS_DIR`: 設定されている場合は絶対パスへ正規化し、`sudo make` 側へ引き渡します。未設定時はルート `Makefile` の既定値を使用します。

## トラブルシュート

### `_local/` がある状態で `sudo make deploy` が失敗する

`_local/` がある場合は、直接 `sudo make deploy` を実行せず、以下のように deploy view を経由してください。

```bash
./deploy-view-build.sh deploy
```

### 衝突エラーが出る

カスタマイズディレクトリに `mochi-containers` と同じ相対パスのファイルがあります。既存ファイルの上書きはできないため、drop-in や `Makefile.local` など、追加ファイルとして扱える配置へ移してください。

### view 上の変更が消える

`mochi-deploy-view` は毎回再生成される生成物です。変更は `_local/` または外部 `mochi-customize` に配置してください。
