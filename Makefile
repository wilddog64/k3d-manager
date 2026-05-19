.PHONY: setup check lint credential-test extend-test help

SANDBOX_URL ?= https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
PROVIDER ?=

help:
	@printf 'Targets:\n'
	@printf '  setup             — npm install + download Playwright Chromium browser\n'
	@printf '  check             — node --check all playwright/*.js files\n'
	@printf '  lint              — shellcheck all bin/ scripts\n'
	@printf '  credential-test   — run bin/acg-credential-test (default: ACG portal URL)\n'
	@printf '                      optional: PROVIDER=aws|gcp SANDBOX_URL=<url>\n'
	@printf '  extend-test       — run bin/acg-extend-test (default: ACG portal URL)\n'
	@printf '                      optional: SANDBOX_URL=<url>\n'

setup:
	npm install
	npx playwright install chromium
	git config core.hooksPath .githooks

check:
	node --check playwright/*.js

lint:
	shellcheck -S warning bin/acg-credential-test bin/acg-extend-test

credential-test:
	bin/acg-credential-test "$(SANDBOX_URL)" $(if $(PROVIDER),--provider "$(PROVIDER)",)

extend-test:
	bin/acg-extend-test "$(SANDBOX_URL)"
