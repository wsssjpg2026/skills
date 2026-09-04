# Code Review (Generic)

Automated code review for GitHub pull requests using multiple specialized agents with confidence-based scoring to filter false positives. Works in any coding agent that supports skills (SKILL.md format) and can spawn subagents — not tied to Claude Code or any specific vendor.

## Overview

This skill automates pull request review by launching multiple agents in parallel to independently audit changes from different perspectives. It uses confidence scoring to filter out false positives, ensuring only high-quality, actionable feedback is posted.

By default it reads the repo's guideline files — **CLAUDE.md and AGENTS.md** — treating both as equivalent sources of repo-specific coding guidance (a repo may have either or both).

## What it does

1. Checks if review is needed (skips closed, draft, trivial, or already-reviewed PRs)
2. Gathers relevant guideline files (CLAUDE.md / AGENTS.md) from the repository
3. Summarizes the pull request changes
4. Launches 5 parallel agents to independently review:
   - **Agent #1**: Audit for CLAUDE.md / AGENTS.md compliance
   - **Agent #2**: Scan for obvious bugs in the changes
   - **Agent #3**: Analyze git blame/history for context-based issues
   - **Agent #4**: Check previous PRs and their comments for applicable feedback
   - **Agent #5**: Verify compliance with guidance in code comments
5. Scores each issue 0-100 for confidence level
6. Filters out issues below the 80 confidence threshold
7. Posts a review comment with high-confidence issues only

## Usage

Invoke the skill in your agent (or via `/code-review-from-claude` where slash-commands are supported) on a PR branch:

- Launches 5 review agents in parallel
- Scores each issue for confidence
- Posts a comment with issues ≥80 confidence
- Skips posting if no high-confidence issues are found

**Review comment format:**

```markdown
### Code review

Found 3 issues:

1. Missing error handling for OAuth callback (CLAUDE.md says "Always handle OAuth errors")

https://github.com/owner/repo/blob/abc123.../src/auth.ts#L67-L72

2. Memory leak: OAuth state not cleaned up (bug due to missing cleanup in finally block)

https://github.com/owner/repo/blob/abc123.../src/auth.ts#L88-L95

3. Inconsistent naming pattern (src/conventions/AGENTS.md says "Use camelCase for functions")

https://github.com/owner/repo/blob/abc123.../src/utils.ts#L23-L28
```

**Confidence scoring:**

- **0**: Not confident, false positive
- **25**: Somewhat confident, might be real
- **50**: Moderately confident, real but minor
- **75**: Highly confident, real and important
- **100**: Absolutely certain, definitely real

**False positives filtered:**

- Pre-existing issues not introduced in the PR
- Code that looks like a bug but isn't
- Pedantic nitpicks
- Issues linters will catch
- General quality issues (unless in a guideline file)
- Issues with lint ignore comments

## Best practices

- Maintain clear CLAUDE.md / AGENTS.md files for better compliance checking
- Trust the 80+ confidence threshold — false positives are filtered
- Run on all non-trivial pull requests
- Review agent findings as a starting point for human review
- Update guideline files based on recurring review patterns

## Configuration

### Adjusting confidence threshold

The default threshold is 80. To adjust, edit SKILL.md:

```markdown
Filter out any issues with a score less than 80.
```

Change `80` to your preferred threshold (0-100).

### Customizing review focus

Edit SKILL.md to add or modify agent tasks, e.g.:

- Security-focused agents
- Performance analysis agents
- Accessibility checking agents
- Documentation quality checks

## Requirements

- Git repository with GitHub integration
- GitHub CLI (`gh`) installed and authenticated (for other forges, adapt to that platform's CLI/API)
- CLAUDE.md / AGENTS.md files (optional but recommended for guideline checking)

## Troubleshooting

- **Review takes too long**: normal for large PRs — agents run in parallel; consider splitting large PRs.
- **Too many false positives**: make guideline files more specific about what matters.
- **No review comment posted**: check whether the PR is closed/draft/trivial/already reviewed, or no issues scored ≥80.
- **Link formatting broken**: links must use the exact form `https://github.com/owner/repo/blob/[full-sha]/path/file.ext#L[start]-L[end]` with at least 1 line of context.
- **`gh` not working**: install and authenticate it (`gh auth login`), and verify the repository has a GitHub remote.

## Provenance

Originally derived from Anthropic's Claude Code code-review plugin (author: Boris Cherny), since generalized: standard SKILL.md format, no vendor-specific agent types or tool permissions, neutral footer, and reads both CLAUDE.md and AGENTS.md by default.

## Version

2.0.0
