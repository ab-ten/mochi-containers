# mk/services.mk

# SERVICE_NAME, SERVICE_USER, SERVICE_PATH などを
# 各サービス側 Makefile で定義してから include する前提。

# 共通ターゲット: deploy / stop / restart / status など
EARLY_STOP ?= No

ifeq ($(shell id -u),0)
ifneq ($(strip $(UID_IN_PODMAN)),)
UID_HOST_MAPPED ?= $(shell ../scripts/print_unshare_id.sh --type uid --user "${SERVICE_USER}" --id "${UID_IN_PODMAN}")
ifeq ($(strip $(UID_HOST_MAPPED)),)
$(error UID_HOST_MAPPED is empty. print_unshare_id.sh failed? SERVICE_USER="$(SERVICE_USER)" UID_IN_PODMAN="$(UID_IN_PODMAN)")
endif
endif
ifneq ($(strip $(GID_IN_PODMAN)),)
GID_HOST_MAPPED ?= $(shell ../scripts/print_unshare_id.sh --type gid --user "${SERVICE_USER}" --id "${GID_IN_PODMAN}")
ifeq ($(strip $(GID_HOST_MAPPED)),)
$(error GID_HOST_MAPPED is empty. print_unshare_id.sh failed? SERVICE_USER="$(SERVICE_USER)" GID_IN_PODMAN="$(GID_IN_PODMAN)")
endif
endif
endif

print-uid-gid:
ifeq ($(shell id -u),0)
	@echo -n "UID_HOST_MAPPED: "
	@make --no-print-directory get-uid
	@echo -n "GID_HOST_MAPPED: "
	@make --no-print-directory get-gid

get-uid:
ifneq ($(strip $(UID_IN_PODMAN)),)
	@echo "${UID_HOST_MAPPED}"
else
	@echo "(UID_IN_PODMAN is not defined)"
endif

get-gid:
ifneq ($(strip $(GID_IN_PODMAN)),)
	@echo "${GID_HOST_MAPPED}"
else
	@echo "(GID_IN_PODMAN is not defined)"
endif

else
	@echo "print-uid-gid is available only when running as root."
endif


deploy:
	@echo
	@echo "Checking $(SERVICE_NAME)..."
	@../scripts/pre-deploy-check.sh
	@echo "Deploying $(SERVICE_NAME)..."
	@../scripts/deploy-service.sh

earlystop:
	@if [ "$(EARLY_STOP)" = "Yes" ]; then \
	  echo "Early stopping $(SERVICE_NAME)..."; \
	  ../scripts/deploy-service.sh stop; \
	else \
	  echo "Skipping early stop for $(SERVICE_NAME) (EARLY_STOP=$(EARLY_STOP))"; \
	fi

stop:
	@echo "Stopping $(SERVICE_NAME)..."
	@../scripts/deploy-service.sh stop

restart:
	@echo "Restarting $(SERVICE_NAME)..."
	@sudo -u $(SERVICE_USER) systemctl --user restart $(SERVICE_NAME).service

status:
	@sudo -u $(SERVICE_USER) systemctl --user status $(SERVICE_NAME).service

replace-files-user:
	@if [ -n "$(REPLACE_FILES_USER)" ]; then \
	  for file in $(REPLACE_FILES_USER); do \
	    case "$$file" in /*) ;; *) echo "REPLACE_FILES_USER must be absolute: $$file" >&2; exit 1 ;; esac; \
	      echo "$$file"; \
	      ../scripts/replace-deploy-vars.sh "$$file"; \
	  done; \
	fi

replace-files-root:
	@if [ -n "$(REPLACE_FILES_ROOT)" ]; then \
	  for file in $(REPLACE_FILES_ROOT); do \
	    case "$$file" in /*) ;; *) echo "REPLACE_FILES_ROOT must be absolute: $$file" >&2; exit 1 ;; esac; \
	      echo "$$file"; \
	      ../scripts/replace-deploy-vars.sh "$$file"; \
	  done; \
	fi

pre-build-root-hook-%:
	@:

post-build-root-hook-%:
	@:

$(SERVICE_PATH)/%.env-user: $(SECRETS_DIR)/%.env-user
	install -o "$(SERVICE_USER)" -g "$(SERVICE_USER)" -m 600 "$<" "$@"
	../scripts/replace-deploy-vars.sh "$@"
	chown "$(SERVICE_USER):$(SERVICE_USER)" $@
	chmod 600 $@

$(SERVICE_PATH)/%.env-root: $(SECRETS_DIR)/%.env-root
	install -o root -g root -m 600 "$<" "$@"
	../scripts/replace-deploy-vars.sh "$@"
	chown "root:root" $@
	chmod 600 $@
