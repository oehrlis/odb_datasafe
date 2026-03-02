# CLAUDE.md — odb_datasafe

## Project Overview

`odb_datasafe` is a Bash extension for managing Oracle OCI Data Safe, built on top of OCI CLI. Key capabilities:

- **Target Management** — register, refresh, and manage Data Safe database targets
- **Service Installer** — install Data Safe On-Premises Connectors as systemd services
- **Connector Management** — list, configure, and manage connectors
- **OCI Integration** — helper functions layered over OCI CLI
- **Test Suite** — BATS tests with full coverage

---

## Workflow

### Planning

- Use plan mode for any task involving 3+ steps or architectural decisions
- Write a plan to `tasks/todo.md` with checkable items before starting implementation
- Check in with the user before beginning implementation
- If something goes sideways, stop and re-plan — don't push forward blindly

### Execution

- Mark `tasks/todo.md` items complete as you go
- Provide a high-level summary of changes at each step
- Fix bugs autonomously when given a report — use logs, errors, and failing tests to resolve without hand-holding

### Verification

- Never mark a task complete without proving it works
- Run tests, check logs, demonstrate correctness
- Ask: *"Would a staff engineer approve this?"*

### Code Quality

- For non-trivial changes, pause and ask: *"Is there a more elegant solution?"*
- If a fix feels hacky, implement the elegant solution instead
- Skip this for simple, obvious fixes — don't over-engineer

---

## Core Principles

- **Simplicity first** — make every change as small and focused as possible
- **Minimal impact** — only touch what's necessary; avoid unintended side effects
- **No shortcuts** — find root causes, not temporary fixes; apply senior developer standards

---

## Task & Lesson Tracking

- Plans and progress → `tasks/todo.md`
- After any user correction → update `tasks/lessons.md` with the pattern and a rule to prevent recurrence
- Review `tasks/lessons.md` at the start of each session for relevant context
- Add a results/review section to `tasks/todo.md` when a task is complete

---

## Related Repositories (ecosystem context)

| Repo                | Role                                          | Edit policy                              |
|---------------------|-----------------------------------------------|------------------------------------------|
| **oradba**          | Base environment; odb_datasafe extends this   | Read-only unless explicitly requested    |
| **exatoolbox**      | Exadata wrapper orchestrating odb_datasafe    | Only `bin/exa_ds.sh` + `doc/exa_ds.md`   |
| **datasafe**        | Customer config + docs for odb_datasafe       | Full edit                                |
| **datasafe_legacy** | Legacy reference scripts                      | READ ONLY — do not modify                |

### Path reference

- **oradba**: `/Users/stefan.oehrli/Development/github/oehrlis/oradba`
- **exatoolbox**: `/Users/stefan.oehrli/Library/CloudStorage/OneDrive-Accenture/Customers/VW/10_Arbeitsresultate/exatoolbox`
  (symlink: `/opt/oracle/local/exatoolbox`)
- **datasafe**: `/Users/stefan.oehrli/Library/CloudStorage/OneDrive-Accenture/Customers/VW/10_Arbeitsresultate/datasafe`
- **datasafe_legacy**: `/Users/stefan.oehrli/Library/CloudStorage/OneDrive-Accenture/Customers/VW/10_Arbeitsresultate/datasafe_legacy`

### OneDrive path note

`/Users/stefan.oehrli/OneDrive - Accenture` is a **symlink** to
`/Users/stefan.oehrli/Library/CloudStorage/OneDrive-Accenture`.
Prefer the **CloudStorage path** in tool calls — no spaces, canonical macOS path.
