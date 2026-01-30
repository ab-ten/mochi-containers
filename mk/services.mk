# mk/services.mk

# SERVICE_NAME, SERVICE_USER, SERVICE_PATH などを
# 各サービス側 Makefile で定義してから include する前提。

# 共通ターゲット: deploy / stop / restart / status など


deploy:
	@echo
	@echo "Checking $(SERVICE_NAME)..."
	@../scripts/pre-deploy-check.sh
	@echo "Deploying $(SERVICE_NAME)..."
	@../scripts/deploy-service.sh

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
