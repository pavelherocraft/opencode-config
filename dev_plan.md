# Implementation Plan: Deployment Package for OpenCode Orchestrator Setup

## Goal

Create a self-contained deployment package folder (`deploy-package/`) in the project root (`P:\Programming\Рефакторинг`) that contains ALL files needed to replicate the OpenCode dual-primary-agent orchestration system on a new Windows machine. The package must include clear step-by-step instructions, sanitized configuration (no hardcoded secrets), and an automated installation script.

## Architecture

### Current State — File Inventory (Discovered)

Files exist in **three locations** with varying degrees of currency:

| Location | Status | Contents |
|----------|--------|----------|
| `C:\Users\Admin\.config\opencode\` | **LIVE / AUTHORITATIVE** | opencode.json, plugins/, agents/ (31 .md + 1 .ps1), instructions.md, PLUGIN.md, MCP_SETUP.md, package.json |
| `P:\Programming\Рефакторинг\` (project root) | **WORKING COPY** | AGENTS.md, ARCHITECTURE.md, PLUGIN.md, MCP_SETUP.md, agents/ (32 .md), plugins/workflow-enforcement.ts |
| `P:\Programming\Рефакторинг\opencode-config\` | **STALE / OUT OF DATE** | AGENTS.md, ARCHITECTURE.md, PLUGIN.md — still reference old providers (`alibaba-coding-plan`, `minimax-coding-plan`, `zai-coding-plan`) |

### Critical Findings

1. **SECURITY: Hardcoded API key** — `opencode.json` line 135 contains a plaintext API key for `bailian-token-plan` provider (`sk-sp-D.DDHP.hFmw...`). This MUST be sanitized before packaging.

2. **Agent file discrepancy** — The live config dir (`~/.config/opencode/agents/`) is MISSING `view-image.md` but has `create_backups.ps1` (utility script). The project root `agents/` has `view-image.md` but no backup script. The project root version is the canonical set (32 agent .md files).

3. **MCP_SETUP.md already exists** — A comprehensive 1280+ line guide exists at both `P:\Programming\Рефакторинг\MCP_SETUP.md` and `C:\Users\Admin\.config\opencode\MCP_SETUP.md`. However, the config-dir version has stale model assignments in the subagent table. The project root version is more current.

4. **Plugin dependencies** — `plugins/package.json` at config root references `@opencode-ai/plugin: ^1.15.0`; the config dir's own `package.json` references `@opencode-ai/plugin: 1.4.9`. Must reconcile.

5. **`opencode-config/` subdirectory is stale** — Should NOT be used as a source. All files should be sourced from the live config or the project root working copy.

### Source of Truth for Each File

| File | Authoritative Source | Rationale |
|------|---------------------|-----------|
| opencode.json | `~/.config/opencode/opencode.json` (sanitized) | Live runtime config |
| workflow-enforcement.ts | `~/.config/opencode/plugins/workflow-enforcement.ts` | Live plugin, 1068 lines, most recent |
| Agent .md files (32) | `P:\Programming\Рефакторинг\agents\*.md` | Complete set including view-image.md |
| AGENTS.md | `P:\Programming\Рефакторинг\AGENTS.md` | 473 lines, current |
| ARCHITECTURE.md | `P:\Programming\Рефакторинг\ARCHITECTURE.md` | 660 lines, current |
| PLUGIN.md | `P:\Programming\Рефакторинг\PLUGIN.md` | 894 lines, current |
| MCP_SETUP.md | `P:\Programming\Рефакторинг\MCP_SETUP.md` | 1280+ lines, most current |

### Target Package Structure

```
P:\Programming\Рефакторинг\deploy-package\
├── README.md                              # Quick start + overview
├── DEPLOYMENT_GUIDE.md                    # Step-by-step deployment instructions
├── opencode.json                          # Sanitized (no hardcoded keys)
├── agents/                                # All 32 agent definitions
│   ├── orchestrator.md
│   ├── plankestrator.md
│   ├── orchestrator-identity-probe.md
│   ├── plankestrator-identity-probe.md
│   ├── worker.md
│   ├── bugfix.md
│   ├── bugfix-triage.md
│   ├── plan-bug.md
│   ├── execute-bug.md
│   ├── dev-planner.md
│   ├── dev-professor.md
│   ├── dev-reviewer.md
│   ├── rework.md
│   ├── consistency-checker.md
│   ├── docs-writer.md
│   ├── docs-planner.md
│   ├── utility.md
│   ├── mcp-github.md
│   ├── mcp-read.md
│   ├── mcp-search.md
│   ├── summarizer.md
│   ├── devops-agent.md
│   ├── devops-reviewer.md
│   ├── devops-readonly.md
│   ├── plan-writer-simple.md
│   ├── plan-writer-complex.md
│   ├── plan-reviewer-simple.md
│   ├── plan-reviewer-complex.md
│   ├── research-writer-simple.md
│   ├── research-writer-complex.md
│   ├── research-reviewer.md
│   └── view-image.md
├── plugins/
│   ├── workflow-enforcement.ts            # Plugin source (1068 lines)
│   └── package.json                       # Plugin npm dependencies
├── project-files/                         # Files to copy into each project root
│   ├── AGENTS.md
│   ├── ARCHITECTURE.md
│   ├── PLUGIN.md
│   └── MCP_SETUP.md
└── scripts/
    ├── install.ps1                        # Automated installation (Windows PowerShell)
    └── verify.ps1                         # Post-install verification checks
```

## Files to Modify / Create

### 1. `deploy-package/README.md` — NEW
Quick-start overview: what this package is, what it contains, prerequisites summary, link to DEPLOYMENT_GUIDE.md.

### 2. `deploy-package/DEPLOYMENT_GUIDE.md` — NEW
Comprehensive step-by-step deployment instructions. Adapted from existing MCP_SETUP.md but focused specifically on the deployment workflow (not the full architecture reference). Sections:
- Prerequisites (Node.js, OpenCode CLI, Serena, Git, Python)
- API key setup (`LITELLM_API_KEY` env var)
- Directory creation
- File copy operations (with exact paths)
- opencode.json personalization (serena path with correct username)
- Project-level file placement
- Optional: Unity MCP setup
- Verification steps
- Troubleshooting

### 3. `deploy-package/opencode.json` — NEW (sanitized copy)
Copy from `C:\Users\Admin\.config\opencode\opencode.json` with these changes:
- **REMOVE** the entire `bailian-token-plan` provider block (lines 130-232) — contains hardcoded API key
- **KEEP** the `bifrost-litellm` provider (uses `{env:LITELLM_API_KEY}` — safe)
- All other sections (mcp, agent, command, plugin, shell) remain unchanged

### 4. `deploy-package/agents/*.md` — NEW (32 files)
Copy all 32 agent .md files from `P:\Programming\Рефакторинг\agents\`.

### 5. `deploy-package/plugins/workflow-enforcement.ts` — NEW
Copy from `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (1068 lines).

### 6. `deploy-package/plugins/package.json` — NEW
Copy from `C:\Users\Admin\.config\opencode\plugins\package.json`:
```json
{
  "name": "opencode-plugins",
  "private": true,
  "dependencies": {
    "@opencode-ai/plugin": "^1.15.0"
  }
}
```

### 7. `deploy-package/project-files/AGENTS.md` — NEW
Copy from `P:\Programming\Рефакторинг\AGENTS.md` (473 lines).

### 8. `deploy-package/project-files/ARCHITECTURE.md` — NEW
Copy from `P:\Programming\Рефакторинг\ARCHITECTURE.md` (660 lines).

### 9. `deploy-package/project-files/PLUGIN.md` — NEW
Copy from `P:\Programming\Рефакторинг\PLUGIN.md` (894 lines).

### 10. `deploy-package/project-files/MCP_SETUP.md` — NEW
Copy from `P:\Programming\Рефакторинг\MCP_SETUP.md` (1280+ lines).

### 11. `deploy-package/scripts/install.ps1` — NEW
Automated PowerShell installation script that:
- Checks prerequisites (Node.js, opencode, serena.exe)
- Creates `~/.config/opencode/plugins/` and `~/.config/opencode/agents/`
- Copies opencode.json → `~/.config/opencode/opencode.json`
- Copies plugins/ → `~/.config/opencode/plugins/`
- Copies agents/*.md → `~/.config/opencode/agents/`
- Prompts for `LITELLM_API_KEY` if not set
- Replaces `<USERNAME>` placeholder in serena path within opencode.json
- Prints summary of installed files

Key logic:
```powershell
# Detect username for serena path
$username = $env:USERNAME
$configContent = Get-Content "$PSScriptRoot\..\opencode.json" -Raw
$configContent = $configContent -replace '<USERNAME>', $username
# Write to target
Set-Content "$env:USERPROFILE\.config\opencode\opencode.json" $configContent
```

### 12. `deploy-package/scripts/verify.ps1` — NEW
Post-install verification script that checks:
- All expected files exist in `~/.config/opencode/`
- `LITELLM_API_KEY` env var is set
- `serena.exe` exists at configured path
- Plugin file is valid TypeScript (basic syntax check)
- Agent count matches expected (32)
- opencode.json is valid JSON

## Implementation Details

### opencode.json Sanitization

The critical sanitization step — removing the `bailian-token-plan` provider:

```
BEFORE (lines 130-232 of live opencode.json):
    "bailian-token-plan": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Alibaba Token Plan",
      "options": {
        "baseURL": "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
        "apiKey": "sk-sp-D.DDHP.hFmw.MEUCIQDEIpdkpdSyFEILbswHoisvWTatR0IisYsFwzBwvnXnwQIgHCqxwDTOTB2l+opTT/ieLBEGMtim5107I6W6N6v1jW0="
      },
      ...
    }

AFTER: Entire "bailian-token-plan" key removed from "provider" object.
       Only "bifrost-litellm" remains.
```

### Agent File Reconciliation

The project root `agents/` directory has 32 .md files (the complete set). The live config dir is missing `view-image.md`. The deploy package will use the project root as the source, ensuring all 32 agents are included.

### install.ps1 — Serena Path Personalization

The opencode.json template will use `<USERNAME>` as a placeholder for the serena command path:
```json
"serena": {
  "type": "local",
  "command": ["C:\\Users\\<USERNAME>\\.local\\bin\\serena.exe", ...]
}
```
The install script replaces `<USERNAME>` with `$env:USERNAME` at install time.

## Edge Cases

1. **Non-Windows platforms** — The current setup is Windows-specific (PowerShell, backslash paths, serena.exe). The deployment package should note this limitation. Linux/macOS support would require path adjustments in opencode.json (forward slashes, `serena` binary instead of `serena.exe`).

2. **Existing opencode installation** — If the target machine already has `~/.config/opencode/opencode.json`, the install script should back it up before overwriting (`opencode.json.bak.YYYYMMDD_HHMMSS`).

3. **Missing LITELLM_API_KEY** — The install script must check for this and provide clear instructions on how to obtain and set it. Without it, no models or MCP servers will work.

4. **Bifrost proxy availability** — The setup assumes `hcbifrost.herocraft.com` is reachable from the target machine's network. If deploying outside the HeroCraft network, this URL will need to change.

5. **Unity MCP optional** — unity-mcp is only needed for Unity projects. The deploy guide should clearly mark this as optional.

6. **Plugin npm dependencies** — After copying `plugins/package.json`, the install script should run `npm install` in the plugins directory to install `@opencode-ai/plugin`.

7. **opencode-config/ subdirectory staleness** — The existing `opencode-config/` in the project root is stale and should NOT be used as a source. The deploy package should be built from the authoritative sources listed above.

8. **`bailian-token-plan` provider removal** — Some agents may have been configured to use this provider in the past. The sanitized opencode.json removes it entirely. If a user needs it, they must manually add it back with their own API key.

## Dependencies

### Before Implementing

- [ ] Confirm with user that `bailian-token-plan` provider should be excluded from the deploy package (it contains a hardcoded API key)
- [ ] Confirm the project root `agents/` directory is the canonical set (32 files including view-image.md)
- [ ] Confirm the live `workflow-enforcement.ts` (1068 lines) is the latest version to ship
- [ ] Decide: should the `opencode-config/` stale subdirectory be updated or deprecated?

### External Dependencies (for target machine)

| Dependency | Version | Required For |
|------------|---------|--------------|
| Node.js | 18+ | Plugin runtime |
| OpenCode CLI | Latest | Agent orchestration |
| Git | 2.x | Repository operations |
| Python | 3.10+ | Serena MCP server |
| uv | Latest | Python package manager |
| `LITELLM_API_KEY` | — | All LLM + MCP auth |
| Serena | Latest release | Code symbol operations |
| Unity Editor | 2021.3+ | Unity MCP (optional) |

## Execution Order

1. Create `deploy-package/` directory structure
2. Copy and sanitize `opencode.json` (remove `bailian-token-plan`)
3. Copy 32 agent `.md` files from project root `agents/`
4. Copy `workflow-enforcement.ts` and `package.json` into `plugins/`
5. Copy project files (AGENTS.md, ARCHITECTURE.md, PLUGIN.md, MCP_SETUP.md) into `project-files/`
6. Write `README.md`
7. Write `DEPLOYMENT_GUIDE.md`
8. Write `scripts/install.ps1`
9. Write `scripts/verify.ps1`
10. Final verification — run `verify.ps1` against the package contents
