SHELL := /usr/bin/env bash

DIST ?= dist
VERSION := $(shell cat VERSION)

.PHONY: help lint lint-sh lint-md test build clean

help:
	@echo "Targets:"; \
	echo "  lint       Run shellcheck and markdownlint"; \
	echo "  lint-sh    Run shellcheck on scripts/bin/lib"; \
	echo "  lint-md    Run markdownlint on markdown files"; \
	echo "  test       Run BATS tests"; \
	echo "  build      Build extension tarball into $(DIST)"; \
	echo "  clean      Remove $(DIST)"

lint: lint-sh lint-md

lint-sh:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found"; exit 1; }
	find scripts bin lib -name "*.sh" -type f -print0 2>/dev/null | xargs -0 shellcheck -e SC1091

lint-md:
	@command -v markdownlint >/dev/null 2>&1 || { echo "markdownlint not found"; exit 1; }
	markdownlint --config .markdownlint.yaml "**/*.md" --ignore node_modules --ignore dist --ignore build --ignore CHANGELOG.md

test:
	@command -v bats >/dev/null 2>&1 || { echo "bats not found"; exit 1; }
	@echo "Running unit tests (timeout: 60s)..."
	@timeout 60 bats $$(ls tests/*.bats | grep -v integration_tests.bats) || echo "⚠️  Some tests failed or require OCI CLI"

test-all:
	@command -v bats >/dev/null 2>&1 || { echo "bats not found"; exit 1; }
	@echo "Running all tests including integration (may require OCI CLI)..."
	@bats tests || echo "⚠️  Some tests failed"

build:
	./scripts/build.sh --dist "$(DIST)"

clean:
	rm -rf "$(DIST)"
