---
name: commit
description: Analyze changes in the current branch and create a commit
disable-model-invocation: true
allowed-tools:
  - Bash(git *)
---

# commit

Create a commit based on all changes in the current branch.

## Instructions

1. **Verify prerequisites**:
   - Check that we're not on the main branch
   - Ensure there are changes

2. **Analyze the changes**:
   - Run `git status` to check working tree status
   - Check the diff since last commit to understand the changes

3. **Write commit message**:
   - Review recent commit history: `git log --oneline -10` to match existing style
   - Structure the commit message:
     - **Subject line** (required): Concise summary in imperative mood (50-72 chars)
       - Examples: "Add user profile component", "Fix authentication redirect", "Refactor database queries"
       - Use present tense imperative: "Add" not "Added" or "Adds"
     - **Body** (optional but recommended for complex changes):
       - Explain the "why" and context, not just the "what"
       - Use bullet points for multiple changes:
         ```
         - Add JWT-based session management
         - Remove Redis dependency for sessions
         - Update authentication flow to use HTTP-only cookies
         ```
       - Reference specific files or components when helpful
       - Keep each line under 72 characters
   - Format using heredoc for proper multi-line handling:
     ```bash
     git commit -m "$(cat <<'EOF'
     Subject line here

     - First change detail
     - Second change detail
     - Third change detail
     EOF
     )"
     ```

4. **Push**:
   - Check if branch is pushed to remote: `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`
   - If not pushed, push with: `git push -u origin <branch-name>`

## Important Notes

- **DO NOT** include any line like "Generated with Claude Code" or similar attribution
- **DO NOT** add emojis to the commit message
- **DO** make the commit message concise and clear
- **DO** reference specific files or features that changed


## Error Handling

- If not in a git repository, inform the user
- If on main branch, warn and exit
- If no changes exist, inform the user
