.PHONY: setup check lint test credential-test restart-test extend-test all help

PROVIDER ?= aws

_ACG_URL := https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
_PROVIDER := $(if $(filter az,$(PROVIDER)),azure,$(PROVIDER))

help:
	@printf 'Targets:\n'
	@printf '  setup             — npm install + download Playwright Chromium browser\n'
	@printf '  check             — node --check all playwright/*.js files\n'
	@printf '  lint              — shellcheck all bin/ scripts\n'
	@printf '  test              — run fixture-based Playwright tests (no live session needed)\n'
	@printf '  credential-test   — run bin/acg-credential-test against the ACG portal (happy path)\n'
	@printf '                      optional: PROVIDER=aws|gcp|az  (default: aws)\n'
	@printf '  restart-test      — force sandbox restart then re-extract credentials (restart path)\n'
	@printf '                      optional: PROVIDER=aws|gcp|az  (default: aws)\n'
	@printf '  extend-test       — run bin/acg-extend-test against the ACG portal\n'
	@printf '                      optional: PROVIDER=aws|gcp|az  (default: aws)\n'
	@printf '  all               — run check + lint + test + credential-test + restart-test + extend-test\n'
	@printf '                      optional: PROVIDER=aws|gcp|az  (default: aws)\n'

setup:
	npm install
	npx playwright install chromium
	git config core.hooksPath .githooks

check:
	node --check playwright/*.js

test:
	npx playwright test --config playwright.config.js

lint:
	shellcheck -S warning bin/acg-credential-test bin/acg-extend-test

credential-test:
	bin/acg-credential-test "$(_ACG_URL)" --provider "$(_PROVIDER)"

restart-test:
	bin/acg-credential-test "$(_ACG_URL)" --provider "$(_PROVIDER)" --force-restart

extend-test:
	bin/acg-extend-test "$(_ACG_URL)" --provider "$(_PROVIDER)"

all: check lint test credential-test restart-test extend-test
