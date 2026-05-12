# mail_service

## 概要
- `mail_service` は LAN 内向けの POP3/SMTP サービスです。
- Postfix と Dovecot を同一サービス配下の別コンテナとして運用します。
- Postfix から Dovecot への配送は LMTP、SMTP 認証は Dovecot auth socket を使用します。
- 初期状態では SSL/TLS を使用しません。`ssl_update` が供給する wildcard 証明書の利用は今後の対応範囲です。

## 前提と依存関係
- サービスユーザーは `mail_service` です。
- LAN 内からの接続のみを想定します。
- サービス追加時は root `Makefile` の `SERVICES` に `mail_service` が含まれている必要があります。
- `SECRETS_DIR/mail_service/` にアカウント情報と Postfix map を配置します。
- SELinux 有効環境では、`security_package` が生成する `local-mochi-mail-security-selinux` RPM を事前に導入してください。

## 主要パラメータ一覧
- `SERVICE_PATH`: `/srv/project/mail_service`
- `MAIL_DOMAIN`: 受信対象ドメインです。既定値は `${CERT_DOMAIN}` です。
- `MAIL_HOSTNAME`: Postfix の `myhostname` です。既定値は `mail.${MAIL_DOMAIN}` です。
- `MAIL_MYNETWORKS`: SMTP relay を許可するネットワークです。
- `MAIL_SMTP_BACKEND_PORT`: rootless Postfix コンテナのホスト側待受ポートです。既定値は `2525` です。
- `MAIL_POP3_BACKEND_PORT`: rootless Dovecot コンテナのホスト側待受ポートです。既定値は `8110` です。
- `MAIL_SMTP_PUBLIC_PORT`: root proxy が公開する SMTP ポートです。既定値は `25` です。
- `MAIL_POP3_PUBLIC_PORT`: root proxy が公開する POP3 ポートです。既定値は `110` です。
- `MAIL_MAILDIR`: Dovecot maildir の永続化先です。既定値は `${INSTALL_ROOT}/mail_service_state/maildir` です。
- `MAIL_QUEUEDIR`: Postfix queue の永続化先です。既定値は `${INSTALL_ROOT}/mail_service_state/postfix-queue` です。
- `MAIL_SOCKET_VOLUME`: LMTP/auth socket 共有用の Podman named volume です。

## ディレクトリ・ボリューム構成
- `MAIL_MAILDIR` は `/var/mail/vhosts` に bind mount します。
- `MAIL_QUEUEDIR` は `/var/spool/postfix` に bind mount します。
- `MAIL_SOCKET_VOLUME` は Postfix と Dovecot の両方で `/run/mail-service` に mount します。
- ローカルディスクの bind mount であるため、quadlet では `:Z` を付与します。

## 環境変数・シークレット
`SECRETS_DIR/mail_service/users.passwd` は Dovecot の passwd-file 形式で配置します。

```text
alice@example.com:{SHA512-CRYPT}$6$rounds=5000$...
```

passwd-file 用の行は、デプロイ後に以下のコマンドで生成できます。出力された行を `SECRETS_DIR/mail_service/users.passwd` に追記し、再デプロイしてください。

```sh
sudo ${INSTALL_ROOT}/bin/mail-service-create-user-passwd alice@example.com
```

`SECRETS_DIR/mail_service/virtual_mailbox` は Postfix の `virtual_mailbox_maps` です。

```text
alice@example.com example.com/alice/Maildir/
```

このサービスでは Postfix が Dovecot LMTP へ配送するため、右辺のディレクトリ指定は実際の保存先としては使用されません。実際の保存先は Dovecot の `mail_location` に従い、`/var/mail/vhosts/<domain>/<local-part>/Maildir` になります。右辺には Postfix map として有効な任意の非空値を指定してください。

`SECRETS_DIR/mail_service/virtual_alias` は任意です。catch-all を使う場合は以下のように記述します。

```text
@example.com alice@example.com
```

`SECRETS_DIR/mail_service/transport` は任意です。宛先別に外部 SMTP relay へ送る場合は以下のように記述します。

```text
external@example.net smtp:[smtp.provider.example]:587
example.org smtp:[smtp.provider.example]:587
```

`SECRETS_DIR/mail_service/relay_sasl_passwd` は任意です。relay 先が認証を要求する場合に配置します。

```text
[smtp.provider.example]:587 relay-user:relay-password
```

## ユーザー追加手順
以下は `alice@example.com` を追加する例です。

1. passwd-file 用の行を生成します。コマンドは Dovecot コンテナの `doveadm pw` を使用し、パスワードを対話入力で受け取ります。

   ```sh
   sudo ${INSTALL_ROOT}/bin/mail-service-create-user-passwd alice@example.com
   ```

2. 出力された行を `SECRETS_DIR/mail_service/users.passwd` に追記します。

   ```text
   alice@example.com:{SHA512-CRYPT}$6$rounds=5000$...
   ```

3. `SECRETS_DIR/mail_service/virtual_mailbox` に受信者を追加します。右辺は実際の保存先としては使用されませんが、Postfix map の値として非空にします。

   ```text
   alice@example.com example.com/alice/Maildir/
   ```

4. 必要に応じて `SECRETS_DIR/mail_service/virtual_alias` に alias を追加します。

   ```text
   postmaster@example.com alice@example.com
   ```

5. 再デプロイして Postfix map と Dovecot 設定を反映します。

   ```sh
   make deploy
   ```

6. POP3 または SMTP AUTH で認証を確認します。初回配送時に Dovecot が Maildir を作成するので、メール送信する前に宛先メールアカウントの pop3 アクセスをしておいた方が良いかもしれません。

## systemd / quadlet / timer 構成
- `dovecot.container`: Dovecot POP3/LMTP/auth コンテナです。
- `postfix.container`: Postfix SMTP コンテナです。
- `proxy-smtp.socket` / `proxy-smtp.service`: `MAIL_SMTP_PUBLIC_PORT` から `MAIL_SMTP_BACKEND_PORT` へ転送します。
- `proxy-pop3.socket` / `proxy-pop3.service`: `MAIL_POP3_PUBLIC_PORT` から `MAIL_POP3_BACKEND_PORT` へ転送します。

## 運用コマンド
- デプロイ: `make deploy` / `make mail_service-deploy`
- 停止: `make stop` / `make mail_service-stop`
- ログ: `sudo journalctl -M "mail_service@.host" --user -u dovecot.service -u postfix.service`
- root proxy ログ: `sudo journalctl -u mochi-mail_service-proxy-smtp.service -u mochi-mail_service-proxy-pop3.service`

## 連携メモ
- Postfix は `virtual_transport = lmtp:unix:/run/mail-service/dovecot-lmtp` で Dovecot に配送します。
- SMTP 認証は `smtpd_sasl_type = dovecot` と `smtpd_sasl_path = /run/mail-service/dovecot-auth` を使用します。
- `transport` map により、特定の宛先またはドメインを外部 SMTP provider へ relay できます。
- TLS 対応時は `ssl_update` の証明書を read only で mount し、Postfix/Dovecot の TLS 設定を追加します。
- deploy 時に `MAIL_SMTP_BACKEND_PORT` / `MAIL_POP3_BACKEND_PORT` を `mochi_mail_high_port_t` に割り当てます。この type は `local-mochi-mail-security-selinux` RPM が提供します。

## トラブルシュート / 注意点
- `MAIL_MAILDIR` と `MAIL_QUEUEDIR` は NFS ではなくローカルディスク上に配置してください。
- `configure-selinux-ports` が `mochi_mail_high_port_t` の割り当てに失敗する場合は、`local-mochi-mail-security-selinux` RPM が導入済みか確認してください。
- `virtual_*` や `transport` を変更した場合は再デプロイしてください。deploy 時に postfix コンテナの `postmap` で `.db` を生成します。
- 初期状態は平文認証です。LAN 外へ公開しないでください。
