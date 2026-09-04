# Global Rules

These rules apply to ALL projects and ALL sessions.

## Git Commits — MANDATORY Delegation

**Any request to commit, save changes to git, or push MUST be delegated to the `git-commit` agent via the Task tool (subagent_type: "git-commit").**

- NEVER run `git commit` or `git push` directly in a primary session
- The agent loads the `git-commit` skill (gated: secrets, sensitive files, conflict markers) and follows Conventional Commits style
- Push ONLY when the user explicitly requests it — pass the instruction through to the agent
- Works in every project; if the `task` tool is unavailable, tell the user instead of committing manually

## Image Generation — MANDATORY Delegation

**Any request to draw, generate, create, render, or edit an image MUST be delegated:**

- Default → `generate-image` agent (Task tool, subagent_type: "generate-image") — Gemini image model
- ONLY if the user explicitly requests GPT/DALL-E (e.g. "use gpt image", "dall-e", "gpt-image") → `generate-image-gpt` agent
- NEVER call generation skills, scripts, or image APIs directly from a primary session

## MCP-First Rules

### Web Search
- Use `webSearchPrime` MCP tool for all search tasks
- Translate Russian queries to English before searching

### Reading URLs
- Use `webReader` MCP tool for reading webpage content

### GitHub Repositories
- Use `zread` MCP tools: `search_doc`, `get_repo_structure`, `read_file`

### Fallback
- If MCP tools fail, use `webfetch` as a last resort
