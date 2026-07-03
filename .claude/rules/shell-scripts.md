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

## OCI CLI Output Capture

- Never `output=$("${cmd[@]}" 2>&1)` when output is parsed data (JSON, OCID, name)
- `2>&1` only in error-message analysis blocks (human-readable text, pattern matching)
- New OCI wrappers always route through `_oci_run_capture` in `lib/oci_helpers.sh`
- verify: `grep '2>&1' lib/oci_helpers.sh` — only allowed in `check_oci_cli_auth` and error-display functions

## validate_inputs() Ordering

- Required CLI param checks (`[[ -n "$VAR" ]] || die`) ALWAYS before `require_oci_cli`
- `require_oci_cli` aborts with "Missing required commands: oci" in CI without OCI installed;
  BATS tests for specific param errors never see their expected message if it fires first
- verify: in every `validate_inputs()` the first `require_oci_cli` call must appear AFTER all required-param `die` lines

## Makefile Workflow

- Never run `shfmt -w` directly — always use `make format` (applies `-i 4 -bn -ci -sr`)
- Pre-release checklist: `make lint && make format-check && make test` — all three green before `git tag`

## Style

- Functions: snake_case
- Constants: UPPER_CASE
- Local variables in functions: `local` keyword
- One function per logical task
- `main "$@"` call at end of script
