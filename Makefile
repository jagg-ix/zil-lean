SHELL := /bin/bash

SETUP_PROFILE ?= full
PROFILE ?= smoke
GROUP ?= all
REPORT ?=
PREFIX ?= $(HOME)/.local
INSTALL_MODE ?= copy
CLOJURE_TOOLS_VERSION ?= 1.12.5.1654

.PHONY: help self-check setup bootstrap doctor test test-smoke test-lean test-clojure \
        test-hybrid test-durable test-all examples examples-lean examples-native \
        examples-integration examples-legacy package package-dir install install-link \
        verify-install uninstall test-install container-build container-test clean-test

help:
	@printf '%s\n' \
	  'ZIL setup, testing, packaging, and installation' \
	  '' \
	  '  make self-check                     validate setup files without building' \
	  '  make setup SETUP_PROFILE=full       diagnose, resolve, and build' \
	  '  make bootstrap SETUP_PROFILE=full   install missing Elan/Clojure in user space' \
	  '  make doctor SETUP_PROFILE=full      inspect required tools' \
	  '  make test PROFILE=smoke             run one test profile' \
	  '  make test-all                       run all host profiles' \
	  '  make examples GROUP=all             run the documented example groups' \
	  '  make package                        build a versioned source tarball' \
	  '  make install PREFIX=~/.local        copy and activate the current checkout' \
	  '  make install-link PREFIX=~/.local   link the current development checkout' \
	  '  make verify-install PREFIX=~/.local verify installed state' \
	  '  make uninstall PREFIX=~/.local      remove installer-owned current version' \
	  '  make test-install                   exercise package/install/uninstall in temp' \
	  '  make container-test PROFILE=all     run in the pinned test container' \
	  '  make clean-test                     remove local reports and temporary outputs'

self-check:
	bash scripts/self-check.sh --report .zil/install-self-check.tsv

setup:
	bash scripts/setup.sh --profile "$(SETUP_PROFILE)"

bootstrap:
	bash scripts/setup.sh --profile "$(SETUP_PROFILE)" --install-tools

doctor:
	bash scripts/doctor.sh --profile "$(SETUP_PROFILE)" \
	  --report ".zil/doctor-$(SETUP_PROFILE).tsv"

test:
	bash scripts/test.sh --profile "$(PROFILE)" $(if $(REPORT),--report "$(REPORT)",)

test-smoke:
	$(MAKE) test PROFILE=smoke

test-lean:
	$(MAKE) test PROFILE=lean

test-clojure:
	$(MAKE) test PROFILE=clojure

test-hybrid:
	$(MAKE) test PROFILE=hybrid

test-durable:
	$(MAKE) test PROFILE=durable

test-all:
	$(MAKE) test PROFILE=all

examples:
	bash scripts/examples.sh --group "$(GROUP)" $(if $(REPORT),--report "$(REPORT)",)

examples-lean:
	$(MAKE) examples GROUP=lean

examples-native:
	$(MAKE) examples GROUP=native

examples-integration:
	$(MAKE) examples GROUP=integration

examples-legacy:
	$(MAKE) examples GROUP=legacy

package:
	bash scripts/package.sh --format tar.gz --output dist

package-dir:
	bash scripts/package.sh --format dir --output dist

install:
	bash scripts/install.sh --prefix "$(PREFIX)" --mode "$(INSTALL_MODE)" \
	  --profile "$(SETUP_PROFILE)"

install-link:
	bash scripts/install.sh --prefix "$(PREFIX)" --mode link \
	  --profile "$(SETUP_PROFILE)"

verify-install:
	bash scripts/verify-install.sh --prefix "$(PREFIX)" --structural

uninstall:
	bash scripts/uninstall.sh --prefix "$(PREFIX)"

test-install:
	bash scripts/install-lifecycle-test.sh \
	  --report .zil/install-lifecycle-test.tsv

container-build:
	docker build \
	  --build-arg CLOJURE_TOOLS_VERSION="$(CLOJURE_TOOLS_VERSION)" \
	  -f Dockerfile.test -t zil-lean-test:local .

container-test:
	mkdir -p .zil/container-reports
	ZIL_TEST_PROFILE="$(PROFILE)" \
	CLOJURE_TOOLS_VERSION="$(CLOJURE_TOOLS_VERSION)" \
	  docker compose -f compose.test.yml run --rm zil-test

clean-test:
	rm -rf .zil/test-reports .zil/examples-reports .zil/container-reports .zil/setup-report*.tsv \
	  .zil/doctor-*.tsv .zil/install-self-check.tsv \
	  .zil/install-lifecycle-test.tsv .zil/install-lifecycle-test.tsv.logs \
	  .zil/package-report.tsv .zil/setup.env .zil/setup.env.ps1
