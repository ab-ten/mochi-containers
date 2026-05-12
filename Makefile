# project-root/Makefile

export
SERVICES = ssl_update nextcloud git_backend redmine trilium mail_service nginx_rp security_package host_services
INSTALL_ROOT = /srv/project
NFS_ROOT = /srv/nfs/containers
SERVICE_PREFIX = mochi
SECRETS_DIR ?= $(realpath ../secrets)
SCRIPT_DIR=${INSTALL_ROOT}/scripts
CERT_DOMAIN = example.com
MAP_LOCAL_ADDRESS = 172.22.22.22

-include Makefile.local

BASE_REPO_DIR = ${CURDIR}

ifeq ($(shell id -u),0)
else
$(error この Makefile は root で実行してください。例: sudo make deploy)
endif


.PHONY: all deploy earlystop stop $(SERVICES) prepare-common guard-no-local-customize install-pre-commit-hook

all:
	@echo "Available services: $(SERVICES)"

deploy: guard-no-local-customize
	@$(MAKE) earlystop
	@$(MAKE) $(SERVICES:%=%-deploy)

earlystop: $(SERVICES:%=%-earlystop)

stop: $(SERVICES:%=%-stop)

prepare-common:
	@rsync -rtp --chmod=D775 --delete --exclude '*~' ./mk ./scripts ${INSTALL_ROOT}/

guard-no-local-customize:
	@if [ -d "_local" ]; then \
	  echo "ERROR: _local/ が存在するため、直接 sudo make deploy は実行できません。" >&2; \
	  echo "ERROR: ./deploy-view-build.sh deploy を実行してください。" >&2; \
	  exit 1; \
	fi

# 下位呼び出し: nginx-deploy, lego-deploy, ...
%-deploy: guard-no-local-customize
	@$(MAKE) prepare-common
	@SERVICE_PATH="${INSTALL_ROOT}/$*" $(MAKE) -C "$*" deploy

%-stop: prepare-common
	@SERVICE_PATH="${INSTALL_ROOT}/$*" $(MAKE) -C "$*" stop

%-earlystop: prepare-common
	@SERVICE_PATH="${INSTALL_ROOT}/$*" $(MAKE) --no-print-directory -C "$*" earlystop

%-get-uid:
	@SERVICE_PATH="${INSTALL_ROOT}/$*" $(MAKE) --no-print-directory -C "$*" get-uid

%-get-gid:
	@SERVICE_PATH="${INSTALL_ROOT}/$*" $(MAKE) --no-print-directory -C "$*" get-gid

%-get-service-user:
	@SERVICE_PATH="${INSTALL_ROOT}/$*" $(MAKE) --no-print-directory -C "$*" get-service-user


#
install-pre-commit-hook: .git/hooks/pre-commit
.git/hooks/pre-commit: pre-commit.sh
	ln -sf ../../pre-commit.sh .git/hooks/pre-commit
