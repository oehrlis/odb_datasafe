# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: Makefile
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.01.12
# Revision...: 0.5.0
# Purpose....: Development workflow automation for OraDBA Data Safe Extension.
#              Provides targets for testing, linting, formatting, building,
#              and releasing.
# Notes......: Use 'make help' to show all available targets
# Reference..: https://github.com/oehrlis/odb_datasafe
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------

# Project configuration
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# Directories and Configuration
DIST ?= dist
VERSION := $(shell cat VERSION 2>/dev/null || echo "0.0.0")
EXTENSION_NAME := $(shell grep '^name:' .extension 2>/dev/null | awk '{print $$2}' || echo "odb_datasafe")

# Tools
SHELLCHECK		:= $(shell command -v shellcheck 2>/dev/null)
SHFMT 			:= $(shell command -v shfmt 2>/dev/null)
MARKDOWNLINT	:= $(shell command -v markdownlint 2>/dev/null || command -v markdownlint-cli 2>/dev/null)
BATS 			:= $(shell command -v bats 2>/dev/null)
GIT 			:= $(shell command -v git 2>/dev/null)

# Color output
COLOR_RESET 	:= \033[0m
COLOR_BOLD		:= \033[1m
COLOR_GREEN 	:= \033[32m
COLOR_YELLOW	:= \033[33m
COLOR_BLUE 		:= \033[34m
COLOR_RED 		:= \033[31m

# ==============================================================================
# Help
# ==============================================================================

.PHONY: help
help: ## Show this help message
	@echo -e "$(COLOR_BOLD)OraDBA Extension Development Makefile$(COLOR_RESET)"
	@echo "Version: $(VERSION)"
	@echo ""
	@echo -e "$(COLOR_BOLD)Usage:$(COLOR_RESET)"
	@echo -e "  make $(COLOR_GREEN)<target>$(COLOR_RESET)"
	@echo ""
	@echo -e "$(COLOR_BOLD)Development:$(COLOR_RESET)"
	@grep -E '^(test|lint|format|check).*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[32m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Build & Distribution:$(COLOR_RESET)"
	@grep -E '^(build|clean).*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[32m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Version & Git:$(COLOR_RESET)"
	@grep -E '^(version|tag|status).*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[32m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)CI/CD & Tools:$(COLOR_RESET)"
	@grep -E '^(ci|pre-commit|tools|info).*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[32m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Quick Shortcuts:$(COLOR_RESET)"
	@grep -E '^[tlfbc]:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[32m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Examples:$(COLOR_RESET)"
	@echo "  make test              # Run tests"
	@echo "  make lint              # Run all linters"
	@echo "  make format            # Format code"
	@echo "  make build             # Build extension"
	@echo "  make ci                # Run full CI pipeline"

# ==============================================================================
# Development
# ==============================================================================

.PHONY: test
test: ## Run BATS tests (excluding integration tests)
	@echo -e "$(COLOR_BLUE)Running unit tests (timeout: 300s)...$(COLOR_RESET)"
	@if [ -z "$(BATS)" ]; then \
		echo -e "$(COLOR_RED)Error: bats not found. Install with: brew install bats-core$(COLOR_RESET)"; \
		exit 1; \
	fi
	@timeout 300 $(BATS) --no-tempdir-cleanup -j 1 $$(ls tests/*.bats | grep -v integration_tests.bats) && \
		echo -e "$(COLOR_GREEN)✓ Tests passed$(COLOR_RESET)" || \
		echo -e "$(COLOR_YELLOW)⚠️  Some tests failed or require OCI CLI$(COLOR_RESET)"

.PHONY: test-all
test-all: ## Run all tests including integration tests
	@echo -e "$(COLOR_BLUE)Running all tests including integration (may require OCI CLI)...$(COLOR_RESET)"
	@if [ -z "$(BATS)" ]; then \
		echo -e "$(COLOR_RED)Error: bats not found$(COLOR_RESET)"; \
		exit 1; \
	fi
	@$(BATS) --no-tempdir-cleanup -j 1 tests || echo -e "$(COLOR_YELLOW)⚠️  Some tests failed$(COLOR_RESET)"

# ==============================================================================
# Linting & Formatting
# ==============================================================================

.PHONY: lint
lint: lint-shell lint-markdown ## Run all linters

.PHONY: lint-shell
lint-shell: ## Lint shell scripts with shellcheck
	@echo -e "$(COLOR_BLUE)Linting shell scripts...$(COLOR_RESET)"
	@if [ -n "$(SHELLCHECK)" ]; then \
		FAILED=0; \
		while IFS= read -r -d '' file; do \
			echo -e "  Checking $$file..."; \
			if [[ "$$file" == tests/* ]]; then \
				$(SHELLCHECK) -x -e SC2155,SC2315,SC2126,SC2207,SC2030,SC2031,SC2181,SC1091 "$$file" || FAILED=1; \
			else \
				$(SHELLCHECK) -x -S warning "$$file" || FAILED=1; \
			fi; \
		done < <(find scripts bin lib tests \( -name "*.sh" -o -name "*.bats" \) -type f -print0 2>/dev/null); \
		if [ $$FAILED -eq 0 ]; then \
			echo -e "$(COLOR_GREEN)✓ All shell scripts passed linting$(COLOR_RESET)"; \
		else \
			echo -e "$(COLOR_RED)✗ Shell linting failed$(COLOR_RESET)"; \
			exit 1; \
		fi; \
	else \
		echo -e "$(COLOR_RED)Error: shellcheck not found. Install with: brew install shellcheck$(COLOR_RESET)"; \
		exit 1; \
	fi

.PHONY: lint-sh
lint-sh: lint-shell ## Alias for lint-shell

.PHONY: lint-markdown
lint-markdown: ## Lint Markdown files with markdownlint
	@echo -e "$(COLOR_BLUE)Linting Markdown files...$(COLOR_RESET)"
	@if [ -n "$(MARKDOWNLINT)" ]; then \
		$(MARKDOWNLINT) --config .markdownlint.yaml '**/*.md' --ignore node_modules --ignore dist --ignore build --ignore CHANGELOG.md || exit 1; \
		echo -e "$(COLOR_GREEN)✓ Markdown files passed linting$(COLOR_RESET)"; \
	else \
		echo -e "$(COLOR_YELLOW)Warning: markdownlint not found. Install with: npm install -g markdownlint-cli$(COLOR_RESET)"; \
	fi

.PHONY: lint-md
lint-md: lint-markdown ## Alias for lint-markdown

.PHONY: format
format: ## Format shell scripts with shfmt
	@echo -e "$(COLOR_BLUE)Formatting shell scripts...$(COLOR_RESET)"
	@if [ -n "$(SHFMT)" ]; then \
		find scripts bin lib -name "*.sh" -type f | \
			xargs $(SHFMT) -i 4 -bn -ci -sr -w; \
		echo -e "$(COLOR_GREEN)✓ Scripts formatted$(COLOR_RESET)"; \
	else \
		echo -e "$(COLOR_YELLOW)Warning: shfmt not found. Install with: brew install shfmt$(COLOR_RESET)"; \
	fi

.PHONY: format-check
format-check: ## Check if scripts are formatted correctly
	@echo -e "$(COLOR_BLUE)Checking script formatting...$(COLOR_RESET)"
	@if [ -n "$(SHFMT)" ]; then \
		find scripts bin lib -name "*.sh" -type f | \
			xargs $(SHFMT) -i 4 -bn -ci -sr -d || \
			(echo -e "$(COLOR_RED)✗ Scripts need formatting. Run: make format$(COLOR_RESET)" && exit 1); \
		echo -e "$(COLOR_GREEN)✓ All scripts properly formatted$(COLOR_RESET)"; \
	else \
		echo -e "$(COLOR_YELLOW)Warning: shfmt not found$(COLOR_RESET)"; \
	fi

.PHONY: check
check: lint test ## Run all checks (lint + test)
	@echo -e "$(COLOR_GREEN)✓ All checks passed$(COLOR_RESET)"

# ==============================================================================
# Build and Distribution
# ==============================================================================

.PHONY: build
build: ## Build extension tarball
	@echo -e "$(COLOR_BLUE)Building extension tarball...$(COLOR_RESET)"
	@./scripts/build.sh --dist "$(DIST)" && echo -e "$(COLOR_GREEN)✓ Build complete$(COLOR_RESET)" || (echo -e "$(COLOR_RED)✗ Build failed$(COLOR_RESET)" && exit 1)

.PHONY: clean
clean: ## Clean build artifacts
	@echo -e "$(COLOR_BLUE)Cleaning build artifacts...$(COLOR_RESET)"
	@rm -rf "$(DIST)"
	@find . -name "*.log" -type f -delete 2>/dev/null || true
	@find . -name "*.tmp" -type f -delete 2>/dev/null || true
	@find . -name "*~" -type f -delete 2>/dev/null || true
	@echo -e "$(COLOR_GREEN)✓ Cleaned$(COLOR_RESET)"

.PHONY: clean-all
clean-all: clean ## Deep clean (including caches)
	@echo -e "$(COLOR_BLUE)Deep cleaning...$(COLOR_RESET)"
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name ".DS_Store" -delete 2>/dev/null || true
	@echo -e "$(COLOR_GREEN)✓ Deep cleaned$(COLOR_RESET)"

# ==============================================================================
# Git and Version Management
# ==============================================================================

.PHONY: version
version: ## Show current version
	@echo -e "$(COLOR_BOLD)OraDBA Extension Version: $(COLOR_GREEN)$(VERSION)$(COLOR_RESET)"

.PHONY: version-bump-patch
version-bump-patch: ## Bump patch version (0.0.X)
	@echo -e "$(COLOR_BLUE)Bumping patch version...$(COLOR_RESET)"
	@current=$$(cat VERSION); \
	major=$${current%%.*}; \
	rest=$${current#*.}; \
	minor=$${rest%%.*}; \
	patch=$${rest#*.}; \
	new_patch=$$((patch + 1)); \
	new_version="$$major.$$minor.$$new_patch"; \
	echo "$$new_version" > VERSION; \
	sed -i.bak "s/^version:.*/version: $$new_version/" .extension && rm -f .extension.bak || \
	sed -i '' "s/^version:.*/version: $$new_version/" .extension; \
	echo -e "$(COLOR_GREEN)✓ Version bumped: $$current → $$new_version$(COLOR_RESET)"; \
	echo -e "$(COLOR_GREEN)✓ Updated VERSION file and .extension metadata$(COLOR_RESET)"

.PHONY: version-bump-minor
version-bump-minor: ## Bump minor version (0.X.0)
	@echo -e "$(COLOR_BLUE)Bumping minor version...$(COLOR_RESET)"
	@current=$$(cat VERSION); \
	major=$${current%%.*}; \
	rest=$${current#*.}; \
	minor=$${rest%%.*}; \
	new_minor=$$((minor + 1)); \
	new_version="$$major.$$new_minor.0"; \
	echo "$$new_version" > VERSION; \
	sed -i.bak "s/^version:.*/version: $$new_version/" .extension && rm -f .extension.bak || \
	sed -i '' "s/^version:.*/version: $$new_version/" .extension; \
	echo -e "$(COLOR_GREEN)✓ Version bumped: $$current → $$new_version$(COLOR_RESET)"; \
	echo -e "$(COLOR_GREEN)✓ Updated VERSION file and .extension metadata$(COLOR_RESET)"

.PHONY: version-bump-major
version-bump-major: ## Bump major version (X.0.0)
	@echo -e "$(COLOR_BLUE)Bumping major version...$(COLOR_RESET)"
	@current=$$(cat VERSION); \
	major=$${current%%.*}; \
	new_major=$$((major + 1)); \
	new_version="$$new_major.0.0"; \
	echo "$$new_version" > VERSION; \
	sed -i.bak "s/^version:.*/version: $$new_version/" .extension && rm -f .extension.bak || \
	sed -i '' "s/^version:.*/version: $$new_version/" .extension; \
	echo -e "$(COLOR_GREEN)✓ Version bumped: $$current → $$new_version$(COLOR_RESET)"; \
	echo -e "$(COLOR_GREEN)✓ Updated VERSION file and .extension metadata$(COLOR_RESET)"

.PHONY: tag
tag: ## Create git tag from VERSION file
	@if [ -n "$(GIT)" ]; then \
		$(GIT) tag -a "v$(VERSION)" -m "Release v$(VERSION)"; \
		echo -e "$(COLOR_GREEN)✓ Created tag v$(VERSION)$(COLOR_RESET)"; \
	fi

.PHONY: status
status: ## Show git status and current version
	@echo -e "$(COLOR_BOLD)Project Status$(COLOR_RESET)"
	@echo -e "Extension: $(COLOR_GREEN)$(EXTENSION_NAME)$(COLOR_RESET)"
	@echo -e "Version: $(COLOR_GREEN)$(VERSION)$(COLOR_RESET)"
	@if [ -n "$(GIT)" ]; then \
		echo "";\
		$(GIT) status -sb; \
	fi

# ==============================================================================
# CI/CD Helpers
# ==============================================================================

.PHONY: ci
ci: clean lint test build ## Run CI pipeline locally
	@echo -e "$(COLOR_GREEN)✓ CI pipeline completed successfully$(COLOR_RESET)"

.PHONY: pre-commit
pre-commit: format lint test ## Run pre-commit checks
	@echo -e "$(COLOR_GREEN)✓ Pre-commit checks passed$(COLOR_RESET)"

# ==============================================================================
# Development Tools
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
	@echo "  macOS:  brew install shellcheck shfmt bats-core markdownlint-cli"
	@echo "  Linux:  apt-get install shellcheck shfmt bats"
	@echo "          npm install -g markdownlint-cli"

# ==============================================================================
# Info
# ==============================================================================

.PHONY: info
info: ## Show project information
	@echo -e "$(COLOR_BOLD)OraDBA Extension Information$(COLOR_RESET)"
	@echo ""
	@echo "Extension:   $(EXTENSION_NAME)"
	@echo "Version:     $(VERSION)"
	@echo "Dist dir:    $(DIST)"
	@echo ""
	@echo "Directories:"
	@for dir in bin sql rcv etc lib scripts tests; do \
		if [ -d "$$dir" ]; then \
			count=$$(find "$$dir" -type f 2>/dev/null | wc -l | xargs); \
			printf "  %-12s %s files\n" "$$dir:" "$$count"; \
		fi; \
	done

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
