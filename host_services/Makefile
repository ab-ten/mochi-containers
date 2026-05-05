# host_services/Makefile
export
SERVICE_NAME = host_services
SERVICE_USER = host_services
NFS_GROUP_CHECK = No
STARTUP_SENTINEL_RECHECK_DELAY ?= 7
REPLACE_ADD_VAR = STARTUP_SENTINEL_RECHECK_DELAY

-include Makefile.local


# user service, quadlet は持たない
pre-build-user:
	test ! -d home

post-build-root:
	tmp_file="$$(mktemp)"; \
	trap 'rm -f "$$tmp_file"' EXIT; \
	: > "$$tmp_file"; \
	for service in ${SERVICES}; do \
	  linger_file="${INSTALL_ROOT}/$$service/.startup_linger"; \
	  if [ -f "$$linger_file" ]; then \
	    sed -e '/^[[:space:]]*$$/d' "$$linger_file" >> "$$tmp_file"; \
	  fi; \
	done; \
	LC_ALL=C sort -u "$$tmp_file" > "${SERVICE_PATH}/startup_uid_list"; \
	chown root:root "${SERVICE_PATH}/startup_uid_list"; \
	chmod 0644 "${SERVICE_PATH}/startup_uid_list"; \
	echo -n "startup_uid_list entries: "; \
	wc -l < "${SERVICE_PATH}/startup_uid_list"; \
	chown root:root "${SERVICE_PATH}/startup_sentinel.sh"; \
	chmod 0755 "${SERVICE_PATH}/startup_sentinel.sh"


include ../mk/services.mk
