#!/usr/bin/make -f

cc_green="\033[0;32m" #Change text to green.
cc_end="\033[0m" #Change text back to normal.

PHP?=$(shell which php)
PHP_VERSION?=5.6.17

APP_DIR?=${PWD}/drupal
APP_URI?=http://127.0.0.1:8888
APP_PASSWORD?=password
LOGS_DIR?=~
DRUSH_BIN=~/.composer/vendor/bin/drush
DRUSH_CMD=~/.composer/vendor/bin/drush -r ${APP_DIR}
DRUSH_VERSION=~8.1
DRUPAL_REPO=git://drupalcode.org/project/drupal.git
DRUPAL_VERSION=8.3.x
MODULE_NAME=dynamic_entity_reference
SIMPLETEST_DB?=mysql://drupal:drupal@localhost/local
PHANTOMJS_DIR=~/.phantomjs
PHANTOMJS_BIN=~/.phantomjs/phantomjs-2.1.1-linux-x86_64/bin/phantomjs
CODER_VERSION=~8.2
PHPCS=~/.composer/vendor/bin/phpcs
PHPCS_STANDARD=~/.composer/vendor/drupal/coder/coder_sniffer/Drupal
PHPCS_DIRS=${APP_DIR}/modules/${MODULE_NAME}
TYPES?="Simpletest,PHPUnit-Unit,PHPUnit-Kernel,PHPUnit-Functional"


.PHONY: list build make install test

# Display a list of the commands
list:
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1n}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$'

# Build steps for local dev
build: init mkdirs lint-php make

# Builds steps for CI
ci-build: init mkdirs ci-vhost make

clean:
	chmod u+w ${APP_DIR}/sites/default || true
	rm -rf ${APP_DIR} ${PWD}/vendor

init:
	@echo ${cc_green}">>> Installing dependencies..."${cc_end}
	composer global require drush/drush:${DRUSH_VERSION}
	composer global require drupal/coder:${CODER_VERSION}
	cp -r ${PWD} ~/tmp
	cd ${PWD} && git clone --depth 1 --branch ${DRUPAL_VERSION} ${DRUPAL_REPO} drupal
	cd ${APP_DIR} && composer install --prefer-dist --no-progress

mkdirs:
	@echo ${cc_green}">>> Creating dirs..."${cc_end}
	sudo chown -R $(whoami):www-data ${APP_DIR}
	mkdir -p ${APP_DIR}/sites/default/files/tmp ${APP_DIR}/sites/default/private ${APP_DIR}/sites/default/files/simpletest ${APP_DIR}/sites/simpletest
	chmod -R 777 ${APP_DIR}/sites/default/files ${APP_DIR}/sites/simpletest
	chmod -R 2775 ${APP_DIR}/sites/default/private
	cp ${APP_DIR}/sites/default/default.settings.php ${APP_DIR}/sites/default/settings.php
	chmod 777 ${APP_DIR}/sites/default/settings.php
	mv ~/tmp ${APP_DIR}/modules/${MODULE_NAME}

make:
	${DRUSH_BIN} sql-create --verbose --debug --yes --db-su=${DB_USER} --db-url=${SIMPLETEST_DB}

install:
	cd ${APP_DIR} && ${DRUSH_BIN} --yes site-install --site-name=drupal --account-pass='${APP_PASSWORD}' --db-url=${SIMPLETEST_DB} testing
	${DRUSH_CMD} --yes pm-enable simpletest ${MODULE_NAME}

run-server:
	cd ${APP_DIR} && nohup ${PHP} -S 127.0.0.1:8888 > ${LOGS_DIR}/localhost.txt &
	# Wait until the web server is responding.
	until curl -s 127.0.0.1:8888; do true; done > /dev/null

phantomjs-install:
	[ ! -d ${PHANTOMJS_DIR} ] && mkdir -p ${PHANTOMJS_DIR}; wget https://assets.membergetmember.co/software/phantomjs-2.1.1-linux-x86_64.tar.bz2 -O ${PHANTOMJS_DIR}/phantomjs-2.1.1-linux-x86_64.tar.bz2; tar -xvf ${PHANTOMJS_DIR}/phantomjs-2.1.1-linux-x86_64.tar.bz2 -C ${PHANTOMJS_DIR};

phantomjs-start:
  # Start phanomjs for javascript testing.
	${PHANTOMJS_BIN} --ssl-protocol=any --ignore-ssl-errors=true ${APP_DIR}/vendor/jcalderonzumba/gastonjs/src/Client/main.js 8510 1024 768 2>&1 >> ${LOGS_DIR}/phantomjs.txt &
	sleep 2

phantomjs-stop:
  # Terminate all the phantomjs and php instances so that we can start fresh.
	ps axo pid,command | grep phantomjs | grep -v grep | grep -v make | awk '{print $$1}' | xargs -I {} kill {}
	ps axo pid,command | grep php | grep -v grep | grep -v phpstorm | grep -v make | awk '{print $$1}' | xargs -I {} kill {}

lint-php:
	@echo ${cc_green}">>> Linting PHP..."${cc_end}
	${PHPCS} --report=full --standard=${PHPCS_STANDARD} ${PHPCS_DIRS}


ci-lint: ci-lint-php

ci-lint-php:
	@echo ${cc_green}">>> Linting PHP..."${cc_end}
	${PHPCS} --report=full --standard=${PHPCS_STANDARD} ${PHPCS_DIRS}

ci-vhost:
	@echo ${cc_green}"PHP version: "${PHP_VERSION}${cc_end}
	sudo cp ${PWD}/vhost /etc/apache2/sites-available/drupal
	sudo sed -i -e 's@##app.uri##@${APP_URI}@g' -e 's@##app.dir##@${APP_DIR}@g' -e 's@##php.version##@${PHP_VERSION}@g' /etc/apache2/sites-available/drupal
	a2ensite drupalc
	a2enmod rewrite
	sudo service apache2 restart

devify:
	chmod u+w ${APP_DIR}/sites/default
	cp ${APP_DIR}/sites/example.settings.local.php ${APP_DIR}/sites/default/settings.local.php
	${DRUSH_CMD} en -y simpletest

test:
	cd ${APP_DIR} && sudo -u www-data ${PHP} ./core/scripts/run-tests.sh \
	--concurrency 8 \
	--verbose \
	--color \
	--types ${TYPES} \
	--dburl ${SIMPLETEST_DB}  \
	--php ${PHP} \
	--url ${APP_URI}/ \
	--module ${MODULE_NAME}

ci-test:
	cd ${APP_DIR} && sudo -u www-data ${PHP} ./core/scripts/run-tests.sh \
	--concurrency 8 \
	--verbose \
	--color \
	--types ${TYPES} \
	--sqlite /tmp/test-db.sqlite \
	--dburl sqlite://localhost//tmp/test-db.sqlite  \
	--php ${PHP} \
	--url ${APP_URI} \
	--module ${MODULE_NAME}
