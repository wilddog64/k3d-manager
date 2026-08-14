.PHONY: setup check lint test credential-test restart-test extend-test all help

PROVIDER ?= aws

_ACG_URL := https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
_PROVIDER := $(if $(filter az,$(PROVIDER)),azure,$(PROVIDER))
_ACG_DIR := scripts/lib/acg

help:
	@printf 'ACG module targets (module lives in $(_ACG_DIR)):\n'
	@printf '  setup             — npm ci + download Playwright Chromium browser\n'
	@printf '  check             — node --check all module JS files\n'
	@printf '  lint              — shellcheck bin/ entry-point scripts\n'
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
	cd $(_ACG_DIR) && npm ci && npx playwright install chromium

check:
	cd $(_ACG_DIR) && npm run check

test:
	cd $(_ACG_DIR) && npx playwright test --config playwright.config.js

lint:
	shellcheck -S warning $(_ACG_DIR)/bin/acg-credential-test $(_ACG_DIR)/bin/acg-extend-test

credential-test:
	cd $(_ACG_DIR) && bin/acg-credential-test "$(_ACG_URL)" --provider "$(_PROVIDER)"

restart-test:
	cd $(_ACG_DIR) && bin/acg-credential-test "$(_ACG_URL)" --provider "$(_PROVIDER)" --force-restart

extend-test:
	cd $(_ACG_DIR) && bin/acg-extend-test "$(_ACG_URL)" --provider "$(_PROVIDER)"

all: check lint test credential-test restart-test extend-test
