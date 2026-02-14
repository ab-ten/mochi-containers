# `scripts/print_unshare_id.sh` 実装メモ

`scripts/print_unshare_id.sh` を編集した場合は、必ず本ドキュメントを同期してください。

## 目的
- rootless Podman の user namespace における ID マップを参照し、コンテナ内 UID/GID に対応するホスト側 ID を出力します。
- サービス Makefile 内の重複した `podman unshare awk` 呼び出しを共通化します。

## 呼び出し形式
以下の形式で呼び出します。

```bash
scripts/print_unshare_id.sh --type uid|gid --user <SERVICE_USER> --id <ID_IN_PODMAN>
```

### 引数
- `--type`  
  `uid` または `gid` を指定します。`uid` の場合は `/proc/self/uid_map`、`gid` の場合は `/proc/self/gid_map` を参照します。
- `--user`  
  対象のサービスユーザーを指定します。
- `--id`  
  コンテナ内の UID または GID を 10 進整数で指定します。

## 出力
- 成功時: 対応するホスト側 ID を標準出力へ 1 行で出力します。
- 失敗時: 標準エラーへ理由を出力し、非 0 で終了します。

## 実行ユーザー制約
- 実行ユーザーは `root` または `--user` で指定したユーザーである必要があります。
- 上記以外のユーザーで実行した場合はエラー終了します。
- `root` 実行時は内部で `sudo -u <SERVICE_USER> -H -- podman unshare ...` を実行します。

## エラー条件
- 必須引数不足、または不明引数が指定された場合
- `--type` が `uid`/`gid` 以外の場合
- `--id` が整数でない場合
- `--user` が存在しない場合
- 実行ユーザーが `root` でも `--user` でもない場合
- 指定 ID が user namespace のマップ範囲外で対応値を算出できない場合

## 利用例
```bash
scripts/print_unshare_id.sh --type uid --user nextcloud --id 33
scripts/print_unshare_id.sh --type gid --user redmine --id 999
```
