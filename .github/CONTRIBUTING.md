# Contributing to homelab

This guide outlines the conventions and workflows we use to keep the repository organized, searchable, and maintainable.

---

## 1. Branch Protection

No direct commits into `main`. Every item must go through a Pull Request with squash-merge. This keeps the `main` branch history clean and forces every change through review.

---

## 2. Branch Names

### Standard format

```
<TYPE>/<PROJECT>/<SHORT-DESCRIPTION>
```

| Part                | Description                                                                    |
| ------------------- | ------------------------------------------------------------------------------ |
| `TYPE`              | One of: `feat`, `fix`, `chore`, `test`                                         |
| `PROJECT`           | The main project the branch impacts (e.g., `immich`, `opencode`, `monitoring`) |
| `SHORT-DESCRIPTION` | A brief, lowercase-kebab-case description                                      |

### Examples

```
feat/immich/add-backups
fix/opencode/timeout-bug
chore/monitoring/update-alerts
```

### Bot-triggered workflows

When a bot (GitHub Copilot, OpenCode, Renovate, etc.) triggers the workflow or creates changes on your behalf, include the bot name as a separate segment:

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

| Artifact    | Convention                           |
| ----------- | ------------------------------------ |
| Branch name | `<TYPE>/<PROJECT>/<kebab-case-desc>` |
| PR title    | `(TYPE)PROJECT: Description` |

Keep changes small, titles descriptive, and templates filled out — this makes reviews faster and history cleaner.
