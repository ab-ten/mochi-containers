# nginx/Makefile
export
SERVICE_NAME = nginx_rp
SERVICE_USER = nginx_rp
REPLACE_FILES_USER = \
	${SERVICE_PATH}/container/conf/https_default.conf \
	${SERVICE_PATH}/container/conf/http_default.conf \
	${SERVICE_PATH}/container/10-sites-symlink.sh

-include Makefile.local


pre-build-root:
	@sh ../scripts/collect-nginx-conf.sh
	@sh ../scripts/generate-index-html.sh

post-build-root:
	chmod 755 ${SERVICE_PATH}/container/*.sh ${SERVICE_PATH}/container/html
	chmod 644 ${SERVICE_PATH}/container/html/*.html


include ../mk/services.mk
