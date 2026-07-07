---
name: raise-pr
description: Analyze changes in the current branch and raise a pull request to main
disable-model-invocation: true
allowed-tools:
  - Bash(git *)
  - Bash(gh *)
---

# raise-pr

Create a pull request to main based on all changes in the current branch.

## Instructions

1. **Verify prerequisites**:
   - Check that we're not on the main branch
   - Verify gh CLI is available
   - Ensure there are changes to PR
   - Ensure the latest changes are added and committed

2. **Analyze the changes**:
   - Run `git status` to check working tree status
   - Run `git diff main...HEAD` to see all commits that will be included
   - Read the actual diff to understand the nature of changes
   - Check recent commits with `git log main..HEAD --oneline`

3. **Draft PR content**:
   - Create a concise, descriptive title (under 70 characters) that summarizes the changes
   - Write a clear PR body that includes:
     - **Summary**: Brief overview of what changed and why (2-4 bullet points)
     - **Changes**: List of specific changes made
     - **Testing**: How these changes were verified (if applicable)
   - Analyze ALL commits included in the PR, not just the latest one
   - Focus on the "why" not just the "what"

4. **Push and create PR**:
   - Check if branch is pushed to remote: `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`
   - If not pushed, push with: `git push -u origin <branch-name>`
   - Create PR using: `gh pr create --title "..." --body "..."`
   - Use a HEREDOC for the body to ensure proper formatting

5. **Return the PR URL**:
   - Display the PR URL so the user can view it

## Important Notes

- **DO NOT** include any line like "Generated with Claude Code" or similar attribution
- **DO NOT** add emojis to the PR title or body
- **DO** ensure the title accurately reflects the changes (use "add", "update", "fix", "refactor", etc. appropriately)
- **DO** make the PR description clear and professional
- **DO** reference specific files or features that changed

## Example PR Body Format

```markdown
## Summary
- Brief point about what changed
- Why this change was needed

## Changes
- Specific file or component modified
- Another specific change

## Testing
- How the changes were verified
```

## Error Handling

- If not in a git repository, inform the user
- If on main branch, warn and exit
- If no changes exist, inform the user
- If latest changes not committed, use the commit skill to commit them
- If gh CLI not available, instruct user to install it
