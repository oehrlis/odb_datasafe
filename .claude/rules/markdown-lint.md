# Markdown Standards

- Follow markdownlint MD001-MD053; config in `.markdownlint.json` (line_length: 120, MD033: off)
- Long tables: wrap with `<!-- markdownlint-disable MD013 MD060 -->` / `<!-- markdownlint-enable -->`
- Code blocks: always specify language - `bash`, `sql`, `hcl`, `yaml`, not bare backticks
- Typography: hyphen-minus ` - ` only, never em-dash (--) or en-dash (-)
- MD041: first line must be a top-level heading
