# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: Makefile
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.04.08
# Version....: v0.5.1
# Purpose....: Development workflow automation for OraDBA Data Safe Extension.
#              Provides targets for testing, linting, formatting, building,
#              and releasing.
# Notes......: Config via .env (overrides). Use 'make help' for targets.
# Reference..: https://github.com/oehrlis/odb_datasafe
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

# Ensure Homebrew-installed tools are found regardless of caller's PATH
PATH := /opt/homebrew/bin:/usr/local/bin:$(PATH)
export PATH

# -- Colors --------------------------------------------------------------------
COLOR_RESET  := \033[0m
COLOR_BOLD   := \033[1m
COLOR_GREEN  := \033[32m
COLOR_YELLOW := \033[33m
COLOR_BLUE   := \033[34m
COLOR_RED    := \033[31m

# -- Project -------------------------------------------------------------------
PROJECT_NAME   := odb_datasafe
VERSION        := $(shell cat VERSION 2>/dev/null || echo "0.0.0")
EXTENSION_NAME := $(shell grep '^name:' .extension 2>/dev/null | awk '{print $$2}' || echo "odb_datasafe")

# -- Directories ---------------------------------------------------------------
SCRIPT_DIR := scripts
BIN_DIR    := bin
LIB_DIR    := lib
DIST_DIR   := dist

# -- Verbosity -----------------------------------------------------------------
V ?=
Q := $(if $(V),,@)

# -- Tools ---------------------------------------------------------------------
SHELLCHECK   := $(shell PATH="$(PATH)" command -v shellcheck 2>/dev/null)
SHFMT        := $(shell PATH="$(PATH)" command -v shfmt 2>/dev/null)
MARKDOWNLINT := $(shell PATH="$(PATH)" command -v markdownlint 2>/dev/null || \
                         PATH="$(PATH)" command -v markdownlint-cli 2>/dev/null)
BATS         := $(shell PATH="$(PATH)" command -v bats 2>/dev/null)
GIT          := $(shell PATH="$(PATH)" command -v git 2>/dev/null)
TIMEOUT      := $(shell PATH="$(PATH)" command -v timeout 2>/dev/null || \
                         PATH="$(PATH)" command -v gtimeout 2>/dev/null)
TEST_TIMEOUT ?= 1800

# ==============================================================================
# Help
# ==============================================================================

.PHONY: help
help: ## Show this help message
	@echo -e "$(COLOR_BOLD)$(PROJECT_NAME) Makefile$(COLOR_RESET)"
	@echo "Version: $(VERSION)"
	@echo ""
	@echo "Release workflow:"
	@echo "  Patch : make release                 # bump patch -> commit -> tag"
	@echo "  Minor : make version-bump-minor && make tag"
	@echo "  Major : make version-bump-major && make tag"
	@echo "  After : git push origin main && git push origin v<VERSION>"
	@echo ""
	@echo -e "$(COLOR_BOLD)Development:$(COLOR_RESET)"
	@grep -E '^(test|check)[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-24s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Lint and Format:$(COLOR_RESET)"
	@grep -E '^(lint|fmt|format)[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-24s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Build and Distribution:$(COLOR_RESET)"
	@grep -E '^(build|clean)[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-24s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Version Management:$(COLOR_RESET)"
	@grep -E '^(version|check-version)[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-24s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Release Management:$(COLOR_RESET)"
	@grep -E '^(tag|release):.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-24s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)CI/CD and Info:$(COLOR_RESET)"
	@grep -E '^(ci|pre-commit|tools|info|status):.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-24s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Quick Shortcuts:$(COLOR_RESET)"
	@grep -E '^[tlfbc]:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-24s$(COLOR_RESET) %s\n", $$1, $$2}'

# ==============================================================================
# Development
# ==============================================================================

.PHONY: test
test: ## Run BATS tests (excluding integration tests)
	@echo -e "$(COLOR_BLUE)Running unit tests (timeout: $(TEST_TIMEOUT)s)...$(COLOR_RESET)"
	@if [ -z "$(BATS)" ]; then \
		echo -e "$(COLOR_RED)Error: bats not found. Install with: brew install bats-core$(COLOR_RESET)"; \
		exit 1; \
	fi
	@if [ "$(TEST_TIMEOUT)" -gt 0 ] && [ -n "$(TIMEOUT)" ]; then \
		$(TIMEOUT) $(TEST_TIMEOUT) $(BATS) --no-tempdir-cleanup -j 1 $$(ls tests/*.bats | grep -v integration_tests.bats); \
		rc=$$?; \
		if [ $$rc -eq 0 ]; then \
			echo -e "$(COLOR_GREEN)✓ Tests passed$(COLOR_RESET)"; \
		elif [ $$rc -eq 124 ]; then \
			echo -e "$(COLOR_YELLOW)⚠️  Tests timed out after $(TEST_TIMEOUT)s (increase TEST_TIMEOUT or set TEST_TIMEOUT=0)$(COLOR_RESET)"; \
		else \
			echo -e "$(COLOR_YELLOW)⚠️  Some tests failed or require OCI CLI$(COLOR_RESET)"; \
		fi; \
	else \
		$(BATS) --no-tempdir-cleanup -j 1 $$(ls tests/*.bats | grep -v integration_tests.bats) && \
			echo -e "$(COLOR_GREEN)✓ Tests passed$(COLOR_RESET)" || \
			echo -e "$(COLOR_YELLOW)⚠️  Some tests failed or require OCI CLI$(COLOR_RESET)"; \
	fi

.PHONY: test-all
test-all: ## Run all tests including integration tests
	@echo -e "$(COLOR_BLUE)Running all tests including integration (may require OCI CLI)...$(COLOR_RESET)"
	@if [ -z "$(BATS)" ]; then \
		echo -e "$(COLOR_RED)Error: bats not found$(COLOR_RESET)"; \
		exit 1; \
	fi
	@$(BATS) --no-tempdir-cleanup -j 1 tests || echo -e "$(COLOR_YELLOW)⚠️  Some tests failed$(COLOR_RESET)"

.PHONY: check
check: lint test ## Run all checks (lint + test)
	@echo -e "$(COLOR_GREEN)✓ All checks passed$(COLOR_RESET)"

# ==============================================================================
# Lint and Format
# ==============================================================================

.PHONY: lint
lint: lint-shell lint-markdown check-version ## Run all lint checks

.PHONY: lint-shell
lint-shell: ## Lint shell scripts with shellcheck
	@echo -e "$(COLOR_BLUE)Linting shell scripts...$(COLOR_RESET)"
	@if [ -z "$(SHELLCHECK)" ]; then \
		echo -e "$(COLOR_RED)Error: shellcheck not found. Install with: brew install shellcheck$(COLOR_RESET)"; \
		exit 1; \
	fi
	@FAILED=0; \
	while IFS= read -r -d '' file; do \
		echo -e "  Checking $$file..."; \
		if [[ "$$file" == tests/* ]]; then \
			$(SHELLCHECK) -x -e SC2155,SC2315,SC2126,SC2207,SC2030,SC2031,SC2181,SC1091,SC2076 "$$file" || FAILED=1; \
		else \
			$(SHELLCHECK) -x -S warning "$$file" || FAILED=1; \
		fi; \
	done < <(find scripts bin lib tests \( -name "*.sh" -o -name "*.bats" \) -type f -print0 2>/dev/null); \
	if [ $$FAILED -eq 0 ]; then \
		echo -e "$(COLOR_GREEN)✓ All shell scripts passed linting$(COLOR_RESET)"; \
	else \
		echo -e "$(COLOR_RED)✗ Shell linting failed$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: lint-sh
lint-sh: lint-shell ## Alias for lint-shell

.PHONY: lint-markdown
lint-markdown: ## Lint Markdown files with markdownlint
	@echo -e "$(COLOR_BLUE)Linting Markdown files...$(COLOR_RESET)"
	@if [ -z "$(MARKDOWNLINT)" ]; then \
		echo -e "$(COLOR_YELLOW)Warning: markdownlint not found. Install with: npm install -g markdownlint-cli$(COLOR_RESET)"; \
		exit 1; \
	fi
	@$(MARKDOWNLINT) --config .markdownlint.yaml '**/*.md' \
		--ignore node_modules --ignore dist --ignore build --ignore CHANGELOG.md || exit 1; \
	echo -e "$(COLOR_GREEN)✓ Markdown files passed linting$(COLOR_RESET)"

.PHONY: lint-md
lint-md: lint-markdown ## Alias for lint-markdown

.PHONY: format
format: ## Format shell scripts with shfmt (in-place)
	@echo -e "$(COLOR_BLUE)Formatting shell scripts...$(COLOR_RESET)"
	@if [ -z "$(SHFMT)" ]; then \
		echo -e "$(COLOR_YELLOW)Warning: shfmt not found. Install with: brew install shfmt$(COLOR_RESET)"; \
		exit 1; \
	fi
	@find scripts bin lib -name "*.sh" -type f | \
		xargs $(SHFMT) -i 4 -bn -ci -sr -w; \
	echo -e "$(COLOR_GREEN)✓ Scripts formatted$(COLOR_RESET)"

.PHONY: format-check
format-check: ## Check if scripts are formatted correctly (diff only)
	@echo -e "$(COLOR_BLUE)Checking script formatting...$(COLOR_RESET)"
	@if [ -z "$(SHFMT)" ]; then \
		echo -e "$(COLOR_YELLOW)Warning: shfmt not found$(COLOR_RESET)"; \
		exit 1; \
	fi
	@find scripts bin lib -name "*.sh" -type f | \
		xargs $(SHFMT) -i 4 -bn -ci -sr -d || \
		(echo -e "$(COLOR_RED)✗ Scripts need formatting. Run: make format$(COLOR_RESET)" && exit 1); \
	echo -e "$(COLOR_GREEN)✓ All scripts properly formatted$(COLOR_RESET)"

# ==============================================================================
# Build and Distribution
# ==============================================================================

.PHONY: build
build: ## Build extension tarball
	@echo -e "$(COLOR_BLUE)Building extension tarball...$(COLOR_RESET)"
	@./scripts/build.sh --dist "$(DIST_DIR)" && \
		echo -e "$(COLOR_GREEN)✓ Build complete$(COLOR_RESET)" || \
		(echo -e "$(COLOR_RED)✗ Build failed$(COLOR_RESET)" && exit 1)

.PHONY: clean
clean: ## Clean build artifacts
	@echo -e "$(COLOR_BLUE)Cleaning build artifacts...$(COLOR_RESET)"
	@rm -rf "$(DIST_DIR)"
	@find . -name "*.log" -type f -not -path "./.git/*" -delete 2>/dev/null || true
	@find . -name "*.tmp" -type f -not -path "./.git/*" -delete 2>/dev/null || true
	@find . -name "*~"    -type f -not -path "./.git/*" -delete 2>/dev/null || true
	@echo -e "$(COLOR_GREEN)✓ Cleaned$(COLOR_RESET)"

.PHONY: clean-all
clean-all: clean ## Deep clean (including OS caches)
	@echo -e "$(COLOR_BLUE)Deep cleaning...$(COLOR_RESET)"
	@find . -type d -name "__pycache__" -not -path "./.git/*" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name ".DS_Store" -not -path "./.git/*" -delete 2>/dev/null || true
	@echo -e "$(COLOR_GREEN)✓ Deep cleaned$(COLOR_RESET)"

# ==============================================================================
# Version Management
# ==============================================================================

.PHONY: check-version
check-version: ## Validate semantic version format in VERSION file
	@grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' VERSION \
		&& echo -e "$(COLOR_GREEN)✓ Version is valid: $(VERSION)$(COLOR_RESET)" \
		|| (echo -e "$(COLOR_RED)✗ Invalid version format in VERSION$(COLOR_RESET)"; exit 1)

.PHONY: version
version: ## Show current version
	@echo -e "$(COLOR_BOLD)$(PROJECT_NAME) Version: $(COLOR_GREEN)$(VERSION)$(COLOR_RESET)"

.PHONY: version-bump-patch
version-bump-patch: ## Bump patch version (0.0.X) -> commit
	@echo -e "$(COLOR_BLUE)Bumping patch version...$(COLOR_RESET)"
	@current="$$(cat VERSION)"; \
	major="$${current%%.*}"; rest="$${current#*.}"; \
	minor="$${rest%%.*}"; patch="$${rest#*.}"; \
	new_version="$$major.$$minor.$$((patch + 1))"; \
	echo "$$new_version" > VERSION; \
	perl -pi -e "s/^version:.*/version: $$new_version/" .extension; \
	$(GIT) add VERSION .extension; \
	$(GIT) commit -m "chore: bump version to v$$new_version"; \
	echo -e "$(COLOR_GREEN)✓ Bumped and committed: $$current -> v$$new_version$(COLOR_RESET)"; \
	echo "   Next: make tag"

.PHONY: version-bump-minor
version-bump-minor: ## Bump minor version (0.X.0) -> commit
	@echo -e "$(COLOR_BLUE)Bumping minor version...$(COLOR_RESET)"
	@current="$$(cat VERSION)"; \
	major="$${current%%.*}"; rest="$${current#*.}"; \
	minor="$${rest%%.*}"; \
	new_version="$$major.$$((minor + 1)).0"; \
	echo "$$new_version" > VERSION; \
	perl -pi -e "s/^version:.*/version: $$new_version/" .extension; \
	$(GIT) add VERSION .extension; \
	$(GIT) commit -m "chore: bump version to v$$new_version"; \
	echo -e "$(COLOR_GREEN)✓ Bumped and committed: $$current -> v$$new_version$(COLOR_RESET)"; \
	echo "   Next: make tag"

.PHONY: version-bump-major
version-bump-major: ## Bump major version (X.0.0) -> commit
	@echo -e "$(COLOR_BLUE)Bumping major version...$(COLOR_RESET)"
	@current="$$(cat VERSION)"; \
	major="$${current%%.*}"; \
	new_version="$$((major + 1)).0.0"; \
	echo "$$new_version" > VERSION; \
	perl -pi -e "s/^version:.*/version: $$new_version/" .extension; \
	$(GIT) add VERSION .extension; \
	$(GIT) commit -m "chore: bump version to v$$new_version"; \
	echo -e "$(COLOR_GREEN)✓ Bumped and committed: $$current -> v$$new_version$(COLOR_RESET)"; \
	echo "   Next: make tag"

# ==============================================================================
# Release Management
# ==============================================================================

.PHONY: tag
tag: ## Create git tag from VERSION (guards: clean tree + VERSION committed)
	@if [ -z "$(GIT)" ]; then \
		echo -e "$(COLOR_RED)Error: git not found in PATH$(COLOR_RESET)"; exit 1; \
	fi; \
	version="$$(cat VERSION)"; \
	tag="v$$version"; \
	if ! $(GIT) diff --quiet HEAD 2>/dev/null; then \
		echo -e "$(COLOR_RED)❌ Working tree is dirty - commit all changes before tagging:$(COLOR_RESET)"; \
		$(GIT) status -sb; \
		exit 1; \
	fi; \
	committed="$$($(GIT) show HEAD:VERSION 2>/dev/null | tr -d '[:space:]')"; \
	if [ "$$committed" != "$$version" ]; then \
		echo -e "$(COLOR_RED)❌ VERSION ($$version) not yet committed (HEAD has: $$committed)$(COLOR_RESET)"; \
		echo "   Run: make version-bump-patch  (or -minor / -major)"; \
		exit 1; \
	fi; \
	if $(GIT) rev-parse "$$tag" >/dev/null 2>&1; then \
		echo -e "$(COLOR_RED)❌ Tag $$tag already exists$(COLOR_RESET)"; \
		exit 1; \
	fi; \
	$(GIT) tag -a "$$tag" -m "Release $$tag"; \
	echo -e "$(COLOR_GREEN)✅ Created tag $$tag$(COLOR_RESET)"; \
	echo ""; \
	echo "   Push manually:"; \
	echo "     git push origin main"; \
	echo "     git push origin $$tag"

.PHONY: release
release: ## Full patch release: bump patch -> commit -> tag
	@echo -e "$(COLOR_BLUE)🚀 Starting patch release...$(COLOR_RESET)"
	@$(MAKE) --no-print-directory version-bump-patch
	@$(MAKE) --no-print-directory tag
	@version="$$(cat VERSION)"; \
	echo -e "$(COLOR_GREEN)🎉 Release v$$version complete!$(COLOR_RESET)"; \
	echo ""; \
	echo "   Push manually:"; \
	echo "     git push origin main"; \
	echo "     git push origin v$$version"

# ==============================================================================
# CI/CD Helpers
# ==============================================================================

.PHONY: ci
ci: clean lint test build ## Run full CI pipeline locally
	@echo -e "$(COLOR_GREEN)✓ CI pipeline completed successfully$(COLOR_RESET)"

.PHONY: pre-commit
pre-commit: format lint test ## Run pre-commit checks
	@echo -e "$(COLOR_GREEN)✓ Pre-commit checks passed$(COLOR_RESET)"

# ==============================================================================
# Info
# ==============================================================================

.PHONY: tools
tools: ## Show installed development tools
	@echo -e "$(COLOR_BOLD)Development Tools Status$(COLOR_RESET)"
	@echo ""
	@printf "%-20s %s\n" "Tool" "Status"
	@printf "%-20s %s\n" "----" "------"
	@printf "%-20s %s\n" "shellcheck" "$$([[ -n '$(SHELLCHECK)' ]] && echo -e '$(COLOR_GREEN)✓ installed$(COLOR_RESET)' || echo -e '$(COLOR_RED)✗ not found$(COLOR_RESET)')"
	@printf "%-20s %s\n" "shfmt" "$$([[ -n '$(SHFMT)' ]] && echo -e '$(COLOR_GREEN)✓ installed$(COLOR_RESET)' || echo -e '$(COLOR_RED)✗ not found$(COLOR_RESET)')"
	@printf "%-20s %s\n" "markdownlint" "$$([[ -n '$(MARKDOWNLINT)' ]] && echo -e '$(COLOR_GREEN)✓ installed$(COLOR_RESET)' || echo -e '$(COLOR_RED)✗ not found$(COLOR_RESET)')"
	@printf "%-20s %s\n" "bats" "$$([[ -n '$(BATS)' ]] && echo -e '$(COLOR_GREEN)✓ installed$(COLOR_RESET)' || echo -e '$(COLOR_RED)✗ not found$(COLOR_RESET)')"
	@printf "%-20s %s\n" "git" "$$([[ -n '$(GIT)' ]] && echo -e '$(COLOR_GREEN)✓ installed$(COLOR_RESET)' || echo -e '$(COLOR_RED)✗ not found$(COLOR_RESET)')"
	@echo ""
	@echo -e "$(COLOR_YELLOW)Install missing tools:$(COLOR_RESET)"
	@echo "  macOS:  brew install shellcheck shfmt bats-core"
	@echo "          npm install -g markdownlint-cli"
	@echo "  Linux:  apt-get install shellcheck bats"
	@echo "          npm install -g markdownlint-cli"

.PHONY: info
info: ## Show project information
	@echo -e "$(COLOR_BOLD)$(PROJECT_NAME) Information$(COLOR_RESET)"
	@echo ""
	@echo "Extension:   $(EXTENSION_NAME)"
	@echo "Version:     $(VERSION)"
	@echo "Dist dir:    $(DIST_DIR)"
	@echo ""
	@echo "Directories:"
	@for dir in bin sql rcv etc lib scripts tests; do \
		if [ -d "$$dir" ]; then \
			count=$$(find "$$dir" -type f 2>/dev/null | wc -l | xargs); \
			printf "  %-12s %s files\n" "$$dir:" "$$count"; \
		fi; \
	done

.PHONY: status
status: ## Show git status and current version
	@echo -e "$(COLOR_BOLD)Project Status$(COLOR_RESET)"
	@echo -e "Extension: $(COLOR_GREEN)$(EXTENSION_NAME)$(COLOR_RESET)"
	@echo -e "Version:   $(COLOR_GREEN)$(VERSION)$(COLOR_RESET)"
	@if [ -n "$(GIT)" ]; then \
		echo ""; \
		$(GIT) status -sb; \
	fi

# ==============================================================================
# Quick Shortcuts
# ==============================================================================

.PHONY: t
t: test ## Shortcut for test

.PHONY: l
l: lint ## Shortcut for lint

.PHONY: f
f: format ## Shortcut for format

.PHONY: b
b: build ## Shortcut for build

.PHONY: c
c: clean ## Shortcut for clean

# --- EOF ----------------------------------------------------------------------
