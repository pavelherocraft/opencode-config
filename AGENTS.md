# Project Rules

## MCP Tools Rules

### Search

Always use the webSearchPrime MCP tool for web search. Do NOT use webfetch for searching.

- Use webSearchPrime for all web searches, finding information, documentation, and resources
- When the user asks you to find, search, or look up something — use webSearchPrime first
- Search queries work best in English; translate Russian queries to English before searching

### Read URLs

Always use the webReader MCP tool for reading webpage content. Do NOT use webfetch.

- Use webReader when you need to read or analyze content from a specific URL
- webReader returns structured content including title, main body, metadata, and links
- webfetch should NOT be used — prefer webReader for all URL reading tasks

### GitHub Repositories and Open Source Documentation

Always use the zread MCP tools for working with GitHub repositories. Do NOT use webfetch or manual browsing.

- Use search_doc to search documentation, issues, PRs, and code in any GitHub repository
- Use get_repo_structure to get the directory structure and file list of a repository
- Use read_file to read the complete content of a specific file in a repository
- When you ask about a library, framework, or open source project — use zread tools first

## Architecture Requirements

All architecture requirements are defined in ARCHITECTURE.md in the project root.

- Routing tables (agent whitelists)
- Pipeline definitions
- JSON validation fields
- MCP server configurations
- Identity probe whitelists
- Outdated terms to check

The consistency-checker agent reads ARCHITECTURE.md to validate all configuration files.

## Dual Primary Agents Architecture

OpenCode uses two primary agents that handle different task types. Agents do NOT call each other — the user must manually switch between them.

### orchestrator


Handles operational and execution tasks:

- BUGFIX - Bug fixing workflows
- DEVOPS - DevOps operations
- DEV - Development tasks
- DOCS - Documentation writing

### plankestrator

Handles planning and research tasks:

- PLAN - Planning workflows
- RESEARCH - Research workflows
- RESEARCH+PLAN - Combined research and planning

## Routing Tables

### orchestrator Whitelist (20 agents)

| Agent Name | Role |
|------------|------|
| orchestrator-identity-probe | Identity verification |
| dev-reviewer | Code review |
| dev-professor | Development guidance |
| mcp-github | GitHub operations |
| worker | Simple development tasks |
| bugfix | Bug fixing |
| rework | Rework on feedback |
| mcp-read | File reading |
| utility | Syntax checking, formatting |
| devops | DevOps tasks |
| bugfix-triage | Initial bug analysis |
| plan-bug | Bug fix planning |
| devops-agent | DevOps operations |
| devops-reviewer | DevOps review |
| dev-planner | Development planning |
| mcp-search | Web search |
| docs-writer | Documentation writing |
| summarizer | Content summarization |
| execute-bug | Bug fix implementation |
| consistency-checker | Architecture consistency validation |

### plankestrator Whitelist (9 agents)

| Agent Name | Role |
|------------|------|
| plankestrator-identity-probe | Identity verification |
| plan-writer-simple | Simple planning |
| plan-writer-complex | Complex planning |
| plan-reviewer-simple | Simple plan review |
| plan-reviewer-complex | Complex plan review |
| research-writer-simple | Simple research |
| research-writer-complex | Complex research |
| research-reviewer | Research review |
| devops-readonly | DevOps read-only |

## Pipelines

### BUGFIX (SIMPLE)

bugfix-triage -> worker -> consistency-checker -> utility

Simple bug fixes use the straightforward pipeline with triage, implementation, consistency check, and validation.

### BUGFIX DEEP

bugfix-triage -> plan-bug -> execute-bug -> dev-reviewer -> rework -> utility

Complex bug fixes include planning, execution, review, and rework cycles.

### DEV SIMPLE


worker -> consistency-checker -> utility

Simple development tasks go from implementation to consistency check to validation.


### DEV COMPLEX


dev-planner -> dev-professor -> dev-reviewer -> rework -> utility


Complex development tasks include planning, guidance, review, and rework.

### DEVOPS

devops-agent -> devops-reviewer

DevOps operations include implementation and review.

### DOCS

docs-writer -> consistency-checker -> utility

Documentation writing followed by consistency check and validation.

### PLAN

plan-writer-* -> plan-reviewer-*

Planning workflows include writing and review, with specialized agents per plan type.

### RESEARCH

research-writer-* -> research-reviewer

Research workflows include writing and review.

## Identity Verification

Both primary agents output identity verification to prevent drift:

### Required Output Format

IDENTITY VERIFIED: I am [agent_name]. I am NOT [other_agent_name].

### JSON Output

Agents must include an agent field in their JSON output:

{
  agent: orchestrator | plankestrator,
  ...
}

## Workflow Enforcement Plugin

### Location

./plugins/workflow-enforcement.ts

### Functionality

- Enforces routing tables via pre-call hooks
- Validates JSON output format includes required fields
- Detects and prevents identity drift
- Ensures agents stay within their whitelisted agent set

### Detailed Documentation


See PLUGIN.md for comprehensive documentation including:
- Lifecycle hooks (6 hooks)
- Error messages
- JSON validation rules
- Agent detection mechanism
- Debugging guide
- Known issues

### Installation

Configured in ~/.config/opencode/opencode.json under the plugins section.

## Data Storage

### Database

- File: opencode.db
- Format: SQLite
- Location: ~/.local/share/opencode/

### Session Storage

- Directory: storage/session_diff/
- Format: JSON files
- Content: Session differences and state changes

### Tool Outputs

- Directory: tool-output/
- Format: Various (JSON, text, logs)
- Content: Individual tool execution results

### Todo Lists

- Directory: storage/todo/
- Format: JSON files
- Content: Task lists and tracking

### Logs

- Directory: log/
- Format: .log files
- Content: Execution logs and debugging info

## File Locations

### Configuration

- Main Config: ~/.config/opencode/opencode.json
- Plugin: ~/.config/opencode/plugins/workflow-enforcement.ts
- Agents: ~/.config/opencode/agents/*.md

### Data


- Root: ~/.local/share/opencode/
- Database: ~/.local/share/opencode/opencode.db
- Storage: ~/.local/share/opencode/storage/
- Logs: ~/.local/share/opencode/log/
- Tool Outputs: ~/.local/share/opencode/tool-output/