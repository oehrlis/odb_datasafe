# CLAUDE.md - odb_datasafe

## Project

`odb_datasafe` is a Bash extension for managing Oracle OCI Data Safe targets and connectors,
built on top of OCI CLI. Scripts live in `bin/`, shared libraries in `lib/`.

## Quick Reference

- Test: `make test` or `bats tests/`
- Lint: `make lint` (shellcheck + markdownlint)
- Help: `make help` or `./bin/odb_datasafe_help.sh`
- Secrets: 1Password via `op read "op://vault/item/field"`

## Rules (always active)

@.claude/rules/shell-scripts.md
@.claude/rules/markdown-lint.md
@.claude/rules/oci-naming.md

## Skills (load on demand)

- Shell scripts & headers  →  /bash-header
- OCI / Terraform          →  /oci-terraform

## Project Details

@.claude/CLAUDE.md
