# mail_service

## 概要
- `mail_service` は LAN 内向けの POP3/SMTP サービスです。
- Postfix と Dovecot を同一サービス配下の別コンテナとして運用します。
- Postfix から Dovecot への配送は LMTP、SMTP 認証は Dovecot auth socket を使用します。
- `ssl_update` が供給する wildcard 証明書を使用し、POP3 は STARTTLS を必須、SMTP は STARTTLS を任意として提供します。

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
- `MAIL_MYNETWORKS`: SMTP の信頼ネットワークです。外部宛て relay は `relay_allowed_recipients` で別途制御します。
- `MAIL_SMTP_BACKEND_ADDRESS`: rootless Postfix コンテナのホスト側待受アドレスです。既定値は `127.0.0.1` です。
- `MAIL_POP3_LISTEN_ADDRESS`: rootless Dovecot コンテナのホスト側待受アドレスです。既定値は `0.0.0.0` です。
- `MAIL_SMTP_BACKEND_PORT`: rootless Postfix コンテナのホスト側待受ポートです。既定値は `2525` です。
- `MAIL_POP3_BACKEND_PORT`: Dovecot POP3 の LAN 向け公開ポートです。既定値は `8110` です。
- `MAIL_SMTP_PUBLIC_PORT`: root proxy が公開する SMTP ポートです。既定値は `25` です。
- `MAIL_MAILDIR`: Dovecot maildir の永続化先です。既定値は `${INSTALL_ROOT}/mail_service_state/maildir` です。
- `MAIL_QUEUEDIR`: Postfix queue の永続化先です。既定値は `${INSTALL_ROOT}/mail_service_state/postfix-queue` です。
- `MAIL_SOCKET_VOLUME`: LMTP/auth socket 共有用の Podman named volume です。
- `MAIL_CERT_SHARE_DIR`: `ssl_update` が `certs.tar` と `marker.updated` を配布するディレクトリです。既定値は `${INSTALL_ROOT}/ssl_share/mail_service` です。
- `MAIL_CERT_DOMAIN`: `certs.tar` 内の証明書ファイル名を決定するドメインです。既定値は `${CERT_DOMAIN}` です。

## ディレクトリ・ボリューム構成
- `MAIL_MAILDIR` は `/var/mail/vhosts` に bind mount します。
- `MAIL_QUEUEDIR` は `/var/spool/postfix` に bind mount します。
- `MAIL_SOCKET_VOLUME` は Postfix と Dovecot の両方で `/run/mail-service` に mount します。
- `MAIL_CERT_SHARE_DIR` は Postfix と Dovecot の両方で `/var/ssl_share/mail_service` に read-only bind mount します。
- ローカルディスクの bind mount であるため、quadlet では `:Z` を付与します。
- `MAIL_CERT_SHARE_DIR` は `ssl_update` と共有するため、quadlet では `:ro,z` を付与します。

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

`SECRETS_DIR/mail_service/relay_allowed_recipients` は任意です。外部宛てに送信できる宛先を Postfix access map 形式で記述します。このファイルが空または未配置の場合、`MAIL_DOMAIN` 以外への送信は拒否されます。

```text
external@example.net OK
@example.org OK
```

`SECRETS_DIR/mail_service/transport` は任意です。宛先別に外部 SMTP relay へ送る場合は以下のように記述します。

```text
external@example.net smtp:[smtp.provider.example]:587
example.org smtp:[smtp.provider.example]:587
```

外部宛てに送信する場合は、`relay_allowed_recipients` で受け付ける宛先を許可し、`transport` で配送先 SMTP relay を指定してください。

`SECRETS_DIR/mail_service/generic` は任意です。外部 SMTP relay へ送る際の送信元アドレスを書き換える Postfix generic map です。relay 先の provider が envelope sender を検証する場合は、provider 側で有効な送信元へ書き換えてください。generic map はヘッダー上の送信者にも影響する場合があります。

```text
alice@example.com provider-user@provider.example
@example.com provider-user@provider.example
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
- `cert-reload.path` / `cert-reload.service`: `MAIL_CERT_SHARE_DIR/marker.updated` を監視し、Dovecot と Postfix の証明書を再展開して reload します。
- `proxy-smtp.socket` / `proxy-smtp.service`: `MAIL_SMTP_PUBLIC_PORT` から `MAIL_SMTP_BACKEND_PORT` へ転送します。
- POP3 は root proxy を使用せず、`dovecot.container` が `MAIL_POP3_LISTEN_ADDRESS:MAIL_POP3_BACKEND_PORT` で直接待ち受けます。

## 運用コマンド
- デプロイ: `make deploy` / `make mail_service-deploy`
- 停止: `make stop` / `make mail_service-stop`
- ログ: `sudo journalctl -M "mail_service@.host" --user -u dovecot.service -u postfix.service -u cert-reload.service`
- root proxy ログ: `sudo journalctl -u mochi-mail_service-proxy-smtp.service`

## 連携メモ
- Postfix は `virtual_transport = lmtp:unix:/run/mail-service/dovecot-lmtp` で Dovecot に配送します。
- SMTP 認証は `smtpd_sasl_type = dovecot` と `smtpd_sasl_path = /run/mail-service/dovecot-auth` を使用します。
- `relay_allowed_recipients` により、外部宛て送信を許可する宛先を制限します。既定では外部宛て送信を許可しません。
- `transport` map により、許可済みの特定宛先またはドメインを外部 SMTP provider へ relay できます。
- `generic` map により、外部 SMTP relay へ送る送信元アドレスを provider 側で有効なアドレスへ書き換えられます。
- SMTP AUTH は Dovecot auth socket で有効ですが、外部宛て relay の許可条件には使用していません。外部宛ては `relay_allowed_recipients` に一致する宛先のみ受け付けます。
- `ssl_update` が配布する `certs.tar` は各コンテナの起動時と reload 時に `/run/mail-service-certs` へ展開します。Dovecot と Postfix は `/run/mail-service-certs/fullchain.crt` と `/run/mail-service-certs/privkey.key` を参照します。
- Dovecot は `ssl = required` と `disable_plaintext_auth = yes` により POP3 の STARTTLS を必須化します。LMTP と auth socket には TLS を適用しません。
- Postfix は inbound smtpd で `smtpd_tls_security_level = may` を使用します。STARTTLS は advertise しますが、LAN 内運用との互換性を優先して必須化しません。
- outbound relay 側の `smtp_tls_security_level` は既定どおり `none` です。外部 SMTP relay への TLS 方針は別途検討してください。
- POP3 は標準の 110/tcp を使用せず、既定では 8110/tcp を直接公開します。110/tcp を root proxy で中継すると Dovecot が接続を localhost の安全な接続として扱い、TLS なし認証を許可する場合があるためです。POP3 の STARTTLS 必須化を優先し、root proxy を使用しない高ポート公開にしています。
- POP3s 995/tcp、Submission 587/tcp、SMTPS 465/tcp は現在の構成には含めていません。追加する場合は Dovecot/Postfix 設定、root proxy unit または直接公開ポート、SELinux port 定義を拡張してください。
- deploy 時に `MAIL_SMTP_BACKEND_PORT` / `MAIL_POP3_BACKEND_PORT` を `mochi_mail_high_port_t` に割り当てます。この type は `local-mochi-mail-security-selinux` RPM が提供します。

## トラブルシュート / 注意点
- `MAIL_MAILDIR` と `MAIL_QUEUEDIR` は NFS ではなくローカルディスク上に配置してください。
- `MAIL_CERT_SHARE_DIR/certs.tar` が存在しない場合、Dovecot と Postfix は TLS 証明書を展開できないため起動に失敗します。先に `ssl_update` を実行し、`mail_service` への証明書配布が完了していることを確認してください。
- `MAIL_CERT_DOMAIN` は `certs.tar` 内の `_.<domain>.crt` と `_.<domain>.key` に一致させてください。
- `MAIL_POP3_LISTEN_ADDRESS=0.0.0.0` の場合、`MAIL_POP3_BACKEND_PORT` は LAN から直接到達可能になります。ホスト側 firewall で公開範囲を LAN に限定してください。
- `configure-selinux-ports` が `mochi_mail_high_port_t` の割り当てに失敗する場合は、`local-mochi-mail-security-selinux` RPM が導入済みか確認してください。
- `virtual_*`、`relay_allowed_recipients`、`transport`、`generic` を変更した場合は再デプロイしてください。deploy 時に postfix コンテナの `postmap` で `.db` を生成します。
- POP3 の TLS なし認証が拒否されることを確認してください。クライアントは既定で `MAIL_POP3_BACKEND_PORT` の `8110/tcp` へ接続します。

### TLS 確認例

POP3 STARTTLS を確認します。

```sh
openssl s_client -starttls pop3 -connect 127.0.0.1:8110 -servername mail.example.com
```

SMTP STARTTLS を確認します。

```sh
openssl s_client -starttls smtp -connect 127.0.0.1:25 -servername mail.example.com
```

証明書更新時の reload を確認します。

```sh
sudo -u ssl_update touch /srv/project/ssl_share/mail_service/marker.updated
sudo journalctl -M "mail_service@.host" --user -u cert-reload.service -u dovecot.service -u postfix.service
```
