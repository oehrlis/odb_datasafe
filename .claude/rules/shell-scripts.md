# Shell Script Standards (OraDBA)

- `set -euo pipefail` mandatory (first line after shebang)
- New scripts: use `/bash-header` skill (OraDBA header required)
- Required flags: `--dry-run`, `--delete`, `--yes`, `--help`
- Error output always to stderr: `echo "ERROR: ..." >&2`
- All scripts must pass `shellcheck` without warnings
- Secrets: `op read "op://vault/item/field"` - never hardcode

## Platform Compatibility (macOS/BSD)

- Default target: macOS (BSD tools) - never assume GNU unless target is explicitly Linux-only
- `sed`: use `-e` for expressions; no `\+`, `\|`, `\n` in basic regex - use `-E` for ERE
- `sed -i`: requires explicit backup suffix on BSD - use `sed -i ''` or `perl -pi -e`
- `grep`: avoid `grep -P` (PCRE not available on BSD grep) - use `-E` instead
- `date`: BSD `date` has different flags than GNU `date` - test on macOS first
- verify: run `shellcheck` with `--shell=bash` before committing

## Style

- Functions: snake_case
- Constants: UPPER_CASE
- Local variables in functions: `local` keyword
- One function per logical task
- `main "$@"` call at end of script
