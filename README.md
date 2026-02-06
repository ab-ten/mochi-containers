# mochi-containers

OpenSUSE MicroOS 上で **rootless Podman + systemd user unit** を使用し、**サービス単位のユーザー分離**で運用するセキュリティモデルを検証する実験プロジェクトです。
`Makefile.local` と systemd drop-in によるカスタマイズを前提としています。

> 本リポジトリは **環境特化の実験プロジェクト** です。汎用のプロダクトではなく、同一の前提条件を持つ方が構成を参考にするために参照する用途を想定しています。

---

## What This Is / What This Isn’t

- 目的: rootless + ユーザー分離 + systemd で安全に運用するための構成を検証すること
- 想定: 自宅 LAN・特定 OS・DNS 運用前提の環境
- 非想定: そのまま導入できる手順書や汎用プロダクト

---

## Security Model

本リポジトリの主な方針は以下のとおりです。

- **サービスごとに専用ユーザー**を用意して隔離する
- **rootless Podman** により権限境界を明確化する
- **systemd user unit / quadlet** で運用を統一する
- **SELinux** を前提にした運用も想定する（環境によっては必須）

---

## Architecture at a Glance

- ルート `Makefile` でサービス一覧を管理する
- サービスは `<service>/{container,config,systemd,home/.config/containers/systemd}` の構成とする
- 実稼働の user unit / quadlet は `/home/<service>/.config/containers/systemd/` に配置する
- drop-in は `dropins/systemd/` に集約し、デプロイ時に収集する

---

## Quick Start

最短で動作させる手順は `docs/deploy-service.md` を参照してください。
（クイックスタート用の短縮版は `QUICKSTART.md` に分離予定です）

---

## Prerequisites (Key Assumptions)

- **wildcard 証明書 + DNS-01** が必須です（lego で取得）
- LAN 内の名前解決は **split DNS** または **hosts** で吸収します
- OpenSUSE MicroOS + rootless Podman を前提とします

---

## Configuration Surface

- `Makefile.local` に環境依存の差分を集約します
- `SERVICES` を絞って段階導入します（例: `ssl_update` + `nginx_rp` + `security_package` →  `redmine`, `nextcloud`）
- `SECRETS_DIR` で DNS API キーなどを管理します

---

## Services and Customization

- 各サービスの設定はそれぞれの README に分離しています
  - `nginx_rp/README.md`
  - `ssl_update/README.md`
  - `nextcloud/README.md`
  - `redmine/README.md`
  - `security_package/README.md`

---

## Storage & NFS Notes

- `NFS_ROOT`（デフォルト: `/srv/nfs/containers/`）を NFSv4 等でマウントして永続化できます
- NFS サーバー側の権限や設定が必要で、環境依存度は高めです

---

## Limitations / Known Constraints

- 前提が多く、初期設定のコストは高いです
- 直接導入より「構成の参考」に向きます

---

## License / No Warranty

本リポジトリは実験プロジェクトであり、いかなる保証もありません。
利用・改変・運用は自己責任でお願いします。

ライセンスは `LICENSE` を参照してください。
