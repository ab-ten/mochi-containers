# project-root/Makefile
# sudo で root になれる一般ユーザーで make deploy する想定

export
SERVICES = ssl_update nextcloud redmine trilium nginx_rp security_package
INSTALL_ROOT = /srv/project
NFS_ROOT = /srv/nfs/containers
SERVICE_PREFIX = mochi
SECRETS_DIR = $(realpath ../secrets)
CERT_DOMAIN = example.com
MAP_LOCAL_ADDRESS = 172.22.22.22

-include Makefile.local

BASE_REPO_DIR = ${CURDIR}


.PHONY: all deploy stop $(SERVICES) prepare-common intall-pre-commit-hook

all:
	@echo "Available services: $(SERVICES)"

deploy: $(SERVICES:%=%-deploy)

stop: $(SERVICES:%=%-stop)

prepare-common:
	@sudo rsync -rtp --chmod=D775 --delete --exclude '*~' ./mk ./scripts ${INSTALL_ROOT}/

# 下位呼び出し: nginx-deploy, lego-deploy, ...
%-deploy: prepare-common
	@sudo   INSTALL_ROOT="${INSTALL_ROOT}" \
		NFS_ROOT="${NFS_ROOT}" \
		SERVICE_PATH="${INSTALL_ROOT}/$*" \
		SERVICE_PREFIX="${SERVICE_PREFIX}" \
		SECRETS_DIR="${SECRETS_DIR}" \
		CERT_DOMAIN="${CERT_DOMAIN}" \
		BASE_REPO_DIR="${BASE_REPO_DIR}" \
		SERVICES="${SERVICES}" \
		MAP_LOCAL_ADDRESS="${MAP_LOCAL_ADDRESS}" \
		$(MAKE) -C "$*" deploy

%-stop: prepare-common
	@sudo   INSTALL_ROOT="${INSTALL_ROOT}" \
		NFS_ROOT="${NFS_ROOT}" \
		SERVICE_PATH="${INSTALL_ROOT}/$*" \
		SERVICE_PREFIX="${SERVICE_PREFIX}" \
		SECRETS_DIR="${SECRETS_DIR}" \
		CERT_DOMAIN="${CERT_DOMAIN}" \
		BASE_REPO_DIR="${BASE_REPO_DIR}" \
		SERVICES="${SERVICES}" \
		MAP_LOCAL_ADDRESS="${MAP_LOCAL_ADDRESS}" \
		$(MAKE) -C "$*" stop

intall-pre-commit-hook: .git/hooks/pre-commit
.git/hooks/pre-commit: pre-commit.sh
	ln -sf ../../pre-commit.sh .git/hooks/pre-commit
