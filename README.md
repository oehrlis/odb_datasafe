# OraDBA Extension Template

This repository is a ready-to-use OraDBA extension template. Copy/clone it,
rename the extension, and start adding your own scripts, SQL, and RMAN content.
CI and release workflows are included; the build script only packages the
extension payload (bin/sql/rcv/etc/lib + metadata/docs), not the dev helpers.

## Quick Start

- Clone/copy this repo.
- Rename the extension metadata: `./scripts/rename-extension.sh --name myext --description "My OraDBA add-ons"`
- Customize `bin/`, `sql/`, `rcv/`, `etc/`, and `lib/` with your logic.
- Build tarball + checksum: `./scripts/build.sh`
- Tag and push to GitHub to publish via the included release workflow.

## Structure (repo = extension)

```text
.extension                  # Extension metadata (name/version/priority/description)
README.md                   # Template overview (this file)
CHANGELOG.md, VERSION, LICENSE
bin/                        # Scripts added to PATH
sql/                        # SQL scripts added to SQLPATH
rcv/                        # RMAN scripts
etc/                        # Config examples (not auto-loaded)
lib/                        # Shared helpers
scripts/                    # Dev tooling (build/rename)
tests/                      # BATS tests for dev tooling
.github/workflows/          # CI (lint/tests) and release
dist/                       # Build outputs (ignored)
```

## Packaging

- `scripts/build.sh` reads `VERSION` and `.extension` to create `dist/<name>-<version>.tar.gz` plus `<tarball>.sha256`.
- Only extension payload is included by default (`.extension`, `.checksumignore`,
  README/CHANGELOG/LICENSE/VERSION, bin/sql/rcv/etc/lib). Dev assets
  (`scripts/`, `tests/`, `.github/`, `dist/`, `.git*`) are excluded.
- Override output dir with `--dist`. Override version with `--version`.
- Build also generates `.extension.checksum` file for integrity verification.

## Integrity Checking

The `.checksumignore` file specifies patterns for files excluded from integrity checks:

- **Default exclusions**: `.extension`, `.checksumignore`, and `log/` directory
- **Glob patterns supported**: `*.log`, `keystore/`, `secrets/*.key`, etc.
- **One pattern per line**: Lines starting with `#` are comments
- **Common use cases**: credentials, caches, temporary files, user-specific configs

Example `.checksumignore`:

```text
# Exclude log directory (already default)
log/

# Credentials and secrets
keystore/
*.key
*.pem

# Cache and temporary files
cache/
*.tmp
```

When OraDBA verifies extension integrity, files matching these patterns are skipped.

## Rename Helper

- `scripts/rename-extension.sh --name <newname> [--description "..."] [--workdir <path>]`
- Updates `.extension`, README, the sample config filename in `etc/`, and
  references to the old name (including release notes).
- Run immediately after cloning to avoid manual edits.

## CI and Releases

- CI: shellcheck for scripts, markdownlint for docs, BATS tests for helper scripts.
- Release: on tags `v*.*.*` (or manual dispatch), runs lint/tests, builds
  tarball + checksum, and publishes them as GitHub release assets.

## Using the Template

1. Add your logic to `bin/`, `sql/`, `rcv/`, `etc/`, and `lib/`.
2. Keep `.extension` metadata current (name, version, priority).
3. Users copy any needed settings from `etc/<name>.conf.example` into `${ORADBA_PREFIX}/etc/oradba_customer.conf`.
4. Extract the tarball into `${ORADBA_LOCAL_BASE}`; auto-discovery will load the extension.
