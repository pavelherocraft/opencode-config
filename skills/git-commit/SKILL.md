---
name: git-commit
description: 'Internal git commit toolkit for the git-commit agent. Runs commit.ps1 to analyze repo state (-Analyze flag: status, staged/unstaged stats, recent conventional-commit style, hygiene warnings) and to create gated commits (-Message with explicit -Files or -StagedOnly, optional -Push). Blocks secrets, sensitive filenames, and conflict markers; warns on large files and non-conventional subjects. Hidden from all other agents by skill permissions.'
---

# Git Commit (gated, conventional)

Internal toolkit loaded by the `git-commit` subagent as its default path.
Not advertised to primary sessions or other agents.

## Usage

Analyze (dry-run, nothing committed — run this FIRST):

```powershell
& "$env:USERPROFILE\.config\opencode\skills\git-commit\scripts\commit.ps1" -Analyze
# optional: -RepoDir <path>
```

Commit (agent composes the message; script enforces the gates):

```powershell
& ".../commit.ps1" -Message "feat(agents): add git-commit agent" -Files CHANGELOG.md, agents/git-commit.md
& ".../commit.ps1" -Message "..." -StagedOnly      # commit exactly what is staged
& ".../commit.ps1" -Message "..." -Files ... -Push # commit then push current branch
```

Output lines: `STATUS:/STAGED:/UNSTAGED:/STYLE:/WARN:/BLOCK:/COMMITTED:/PUSHED:/ERROR:`.
Exit codes: 0 ok, 2 usage/environment error, 3 gate block.

## Workflow for the agent

1. Run `-Analyze`. Read STATUS, STAGED, UNTRACKED and RECENT COMMIT STYLE.
2. Decide what belongs in THIS commit (task-relevant files only; never bundle
   unrelated junk: archives, `generated-images/`, build artifacts).
3. Compose the subject in the repo's own style (read the STYLE section —
   this repo uses English conventional commits like `feat(provider): ...`,
   `chore(sync): ...`; scope = area name; subject in lowercase, imperative).
4. Commit via `-Files` (explicit list) or `-StagedOnly`. NEVER both blind.
5. Push ONLY when the task explicitly asked to push.
6. Report back: COMMITTED hash + subject + FILES list (and PUSHED if pushed).
   If BLOCK/ERROR — report the gate output verbatim; do not try to bypass.

## Gates enforced by the script (do not fight them)

| Gate | Effect |
|------|--------|
| git identity (user.name/user.email) missing | BLOCK |
| sensitive filename staged (`.env*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `id_rsa*`, `credentials.json`, service-account json) | BLOCK |
| secret pattern in staged diff (`sk-`, `ghp_/gho_/…`, `github_pat_`, `AKIA…`, `PRIVATE KEY` blocks, `xox…`, `AIza…`, `Bearer <literal>`) | BLOCK |
| conflict markers `<<<<<<<`/`>>>>…` in staged diff | BLOCK |
| staged file > 5MB | WARN |
| subject > 72 chars / non-conventional | WARN |
| neither `-Files` nor `-StagedOnly` given | BLOCK (no blind `git add -A`) |

`{env:VAR}` placeholders are NOT secrets and pass the scan.

## Hard rules

- Never use `--no-verify`, `--amend`, `--force-push` via this script (it has
  no flags for them). If the user explicitly asks for amend/force — use plain
  git in the Fallback path and say so in the report.
- One logical change per commit. Split unrelated changes into separate calls.
- Never commit secrets even if the user insists — explain the BLOCK instead.
