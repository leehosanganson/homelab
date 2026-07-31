---
name: github-ops
description: >-
  Manage GitHub issues, PRs, comments, and reviews. Load this skill when the user asks to create, update, review, comment on, or merge GitHub issues and pull requests. It verifies repository context first and follows safe defaults: no force-push, no merges without passing checks unless the user explicitly overrides, and no closing issues without confirmation.
---

## Overview

Carry out GitHub repository operations on behalf of the user. Start by confirming the repository and current branch context, then perform the requested action with the least privilege necessary. Use `gh` CLI or `github_*` MCP tools depending on what is available and authenticated.

## Permissions

Before acting, verify:

1. **Repository context** — which repo (`owner/repo`) and which branch/PR this applies to.
2. **Authentication** — `gh auth status` or the availability of `github_*` tools.
3. **User intent** — whether the user wants you to act directly or just draft the change.

If repo context is unclear, run `gh repo view` or read the local `.git/config`. If no tool is authenticated, ask the user before proceeding.

## Workflows

### Create an issue

1. Gather title, body, labels, and assignees.
2. Use `gh issue create` or the equivalent MCP tool.
3. Report the issue number and URL.

### Update a PR description

1. Identify the PR via URL, number, or current branch (`gh pr view`).
2. Draft the updated description.
3. Confirm with the user before editing.
4. Apply with `gh pr edit <pr> --body-file ...` or equivalent.

### Review a PR

1. Check out the PR branch if needed (`gh pr checkout <pr>`).
2. Read the diff (`gh pr diff <pr>`).
3. Leave review comments or a summary review.
4. If approving, ensure the user explicitly asked for approval; otherwise leave a comment review.

### Comment on an issue or PR

1. Identify the issue/PR.
2. Draft the comment.
3. Post with `gh issue comment <number>` or `gh pr comment <number>`.
4. Report the comment URL.

### Merge a PR

1. Verify checks are passing: `gh pr checks <pr>`.
2. Confirm merge strategy (merge, squash, rebase) with the user.
3. Merge only after the user confirms.
4. Report the merge commit and post-merge state.

## Safety

- Never force-push.
- Never merge without checks passing unless the user explicitly says to override.
- Never close an issue or PR without confirmation.
- Never delete branches or tags without confirmation.
- Prefer drafting edits and showing them to the user before applying.
- When using `gh`, keep commands single-purpose and avoid chaining.