# Contributing to homelab

This guide outlines the conventions and workflows we use to keep the repository organized, searchable, and maintainable.

---

## 1. Commit Messages

### Format

```
(TYPE)(scope): Description
```

- **TYPE** — One of:

| Type    | Meaning                                  |
| ------- | ---------------------------------------- |
| `feat`  | A new feature                            |
| `fix`   | A bug fix                                |
| `chore` | Maintenance, tooling, dependency updates |

- **scope** — Optional but recommended. Name the affected project or module (e.g., `immich`, `opencode`, `monitoring`). Omit it only when a change touches many projects or is purely global.

- Each commit should represent a **single, focused change**.

### Examples

```
(feat)immich: add backup cron job
(fix)opencode: correct timeout config
(chore): bump dependency versions
```

---

## 2. Branch Names

### Standard format

```
<TYPE>/<PROJECT>/<SHORT-DESCRIPTION>
```

| Part                | Description                                                                    |
| ------------------- | ------------------------------------------------------------------------------ |
| `TYPE`              | Same types as commit messages: `feat`, `fix`, `chore`, `test`                  |
| `PROJECT`           | The main project the branch impacts (e.g., `immich`, `opencode`, `monitoring`) |
| `SHORT-DESCRIPTION` | A brief, lowercase-kebab-case description                                      |

### Examples

```
feat/immich/add-backups
fix/opencode/timeout-bug
chore/monitoring/update-alerts
```

### Bot-triggered workflows

When a bot (GitHub Copilot, OpenCode, Renovate, etc.) triggers the workflow or creates changes on your behalf, prepend `bot` to the path:

```
<TYPE>/<BOT>/<PROJECT>/<SHORT-DESCRIPTION>
```

### Examples

```
feat/copilot/immich/auto-updates
chore/opencode/monitoring/renovate-pin
```

---

## 3. Pull Requests

### Title format

```
(TYPE)PROJECT: DESCRIPTION
```

GitHub will append the PR number automatically after creation, so the final title looks like:

```
(feat)immich: add backup cron job #123
```

### Examples

```
(feat)immich: add backup cron job
(fix)opencode: correct timeout config
```

### PR Description template

Use the template at `.github/PULL_REQUEST_TEMPLATE.md` which includes:

- **What** — What changed and why (the problem solved or feature added)
- **How to test** — Steps, commands, or UI actions to verify the change works
- **Impact** — Notes for reviewers (risk areas, things to double-check, things that needs to be done outside of the codebase, trade-offs)

---

## 4. Issues

### Bug Report

Use the template at `.github/ISSUE_TEMPLATE/bug_report.md`

Required sections:

- **Problem description** — What went wrong
- **Expected behavior** — What you thought would happen
- **Actual behavior** — What actually happened
- **Steps to reproduce** — Numbered steps someone else can follow
- **Environment / Context** — OS, version, browser, etc.

### Suggestion

Use the template at `.github/ISSUE_TEMPLATE/suggestion.md`

Required sections:

- **Problem being solved** — What pain point or gap exists today
- **Evaluation** — Feasibility, impact, complexity, trade-offs to consider
- **Research** — Prior art, alternatives researched, docs reviewed, comparisons made
- **Proposed implementation** — How you envision this being built
- **Alternatives considered** — Other approaches you've weighed

### Feature Request

Use the template at `.github/ISSUE_TEMPLATE/feature_request.md`

Required sections:

- **Problem being solved** — What pain point or limitation exists today
- **Proposed solution** — Research findings, proposed approach
- **Alternatives considered** — Other approaches you've weighed

---

## Quick reference

| Artifact     | Convention                             |
| ------------ | -------------------------------------- |
| Commit type  | `feat`, `fix`, `chore`                 |
| Commit scope | Optional project name, e.g. `(immich)` |
| Branch name  | `<TYPE>/<PROJECT>/<kebab-case-desc>`   |
| PR title     | `(TYPE)PROJECT: Description`           |

Keep changes small, titles descriptive, and templates filled out — this makes reviews faster and history cleaner.
