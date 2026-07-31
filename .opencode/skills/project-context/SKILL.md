---
name: project-context
description: >-
  Manages branch context, sync policy, and PR state before any work begins. Loads whenever you need to determine which branch to work on, ensure changes are based on latest main, or handle existing PR references. Use whenever the user's request involves branching decisions, continuation of work, or references to existing PRs. Ensures no stale state causes lost work.
---

## Overview

Before any task decomposition or dispatching, resolve the project context: ensure you're synced with latest `main`, determine whether this is new work or continuation, and handle any PR references. This prevents working on stale branches and ensures no changes are lost. The skill runs silently — the Architect then proceeds with clarification and dispatch.

## Sync Policy

- Always run `git fetch` first to refresh remote tracking.
- Never force-push, hard-reset, or rebase. On sync failure, pause and report.

## Branch Resolution

Determine the correct base branch based on the user's intent:

1. **Continuing existing work** ("review", "fix", "continue", "add to it") → stay on current branch + `git pull`. The previous work is ongoing.
2. **New/different scope** (explicitly new, unrelated task) → switch to `main` + `git pull origin main`. Ground changes in latest state.
3. **Unknown** → ask the user before proceeding.

Check what's actually on each branch (`git log`, `git status`) rather than assuming. If previous work has been merged into `main`, treat it as new scope and switch to `main`.

## PR Context

- **Explicit PR mention** (URL, number like "#123", "that PR"): never create a new PR. Resolve via `gh pr view <PR>` → checkout its branch + pull. All changes go to this same branch. Update title/description with `gh pr edit` only when meaningful; suggest to user first.
- **Implicit continuation** (no PR mentioned but request implies continuing): run `gh pr list --state open --state draft`, auto-continue the most recent by last-updated date. Checkout its branch + pull.

## Outcome

After resolving context, report back: which branch you're on, whether it's synced with remote, and any active PRs found. The Architect then proceeds to clarify requirements and dispatch.