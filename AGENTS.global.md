# Global Rules

These rules apply to ALL projects, ALL sessions, and ALL agents. They override anything suggested by earlier session history or project habits.

## Git Commits — HARD RULE

**NEVER run `git commit`, `git push`, or `git tag` yourself. ALWAYS delegate to the `git-commit` agent via the Task tool (subagent_type: "git-commit"). No exceptions, in any project, even if this session's history contains past direct commits.**

- Applies to every phrasing: "commit", "push", "save changes", "закоммить", "запушь", "сохрани в git"
- Direct `git commit` / `git push` are blocked by permissions for everyone except the `git-commit` agent. **If such a call is denied — that is your signal to delegate via `task` to the `git-commit` agent, not to work around it**
- Pass through the push instruction only if the user explicitly asked to push
- If the `task` tool is unavailable, tell the user instead of committing manually

## Image Generation — HARD RULE

**Any request to draw, generate, create, render, or edit an image MUST be delegated:**

- Default → `generate-image` agent (Task tool, subagent_type: "generate-image") — Gemini image model
- ONLY if the user explicitly requests GPT/DALL-E (e.g. "use gpt image", "dall-e", "gpt-image") → `generate-image-gpt` agent
- NEVER call generation skills, scripts, or image APIs directly

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
