# Plan: Update DEV SIMPLE Pipeline with Conditional Consistency-Checker

## Goal

Add a conditional `consistency-checker` step to the DEV SIMPLE pipeline, differentiated by whether a plan exists. The orchestrator should follow the appropriate pipeline variant based on the `plan_exists` JSON field.

**Target behavior:**

| Pipeline | Flow |
|----------|------|
| DEV SIMPLE (без плана / no plan) | `worker → utility` |
| DEV SIMPLE (с планом / with plan) | `worker → consistency-checker → utility` |
| DEV COMPLEX | **DO NOT TOUCH** |

## Architecture

The pipeline is **not** programmatically enforced. The `workflow-enforcement.ts` plugin only enforces:
1. **Routing tables** — who can call whom (whitelist check)
2. **JSON validation** — required fields exist and have valid values
3. **Identity drift** — agents don't impersonate other agents

The orchestrator follows pipeline logic from **AGENTS.md documentation** and its **own prompt**. Therefore, changes are documentation-driven, not code-driven.

**Decision mechanism:** The orchestrator already outputs `plan_exists: boolean` in its JSON. This field naturally determines which DEV SIMPLE variant to use:
- `plan_exists: false` → `worker → utility` (skip consistency-checker)
- `plan_exists: true` → `worker → consistency-checker → utility` (run consistency-checker)

## Files

| # | File | Action | Reason |
|---|------|--------|--------|
| 1 | `AGENTS.md` (lines 254-259) | **UPDATE (required)** | Pipeline documentation — orchestrator reads this to know the flow |
| 2 | `~/.config/opencode/opencode.json` (line 407) | **UPDATE (recommended)** | Add pipeline logic to orchestrator prompt for in-context guidance |
| 3 | `plugins/workflow-enforcement.ts` | **NO CHANGE** | No pipeline logic exists here; only routing table enforcement |

## Dependencies

- **None** — consistency-checker is already in the orchestrator routing table (line 27 in workflow-enforcement.ts, line 452 in opencode.json)
- **None** — consistency-checker subagent is already configured (lines 666-688 in opencode.json)
- **None** — orchestrator already outputs `plan_exists` field in its JSON

## Plan

### Phase 1: Update AGENTS.md (Required)

**File:** `P:\Programming\Рефакторинг\AGENTS.md`  
**Location:** Lines 254-259 (DEV SIMPLE section)

**Current content:**
```markdown
### DEV SIMPLE


worker -> utility

Simple development tasks go from implementation to validation.
```

**Replace with:**
```markdown
### DEV SIMPLE

**Without plan** (`plan_exists: false`):

worker -> utility

Simple development tasks without a plan go directly from implementation to validation.

**With plan** (`plan_exists: true`):

worker -> consistency-checker -> utility

Simple development tasks with a pre-existing plan include consistency validation to ensure implementation matches the plan.
```

**Rationale:**
- Two clearly labeled variants with explicit conditions
- `plan_exists` field referenced — matches orchestrator JSON output field
- `consistency-checker` step only added when plan exists (plan = more risk of drift)
- DEV COMPLEX section remains **untouched** (lines 262-268)

---

### Phase 2: Update Orchestrator Prompt (Recommended)

**File:** `C:\Users\Admin\.config\opencode\opencode.json`  
**Location:** Line 407 — orchestrator `"prompt"` field

**Current prompt:**
```
You MUST output JSON in EVERY response. First line: 'IDENTITY VERIFIED: I am orchestrator...'. Second: JSON code block with fields: agent, type, complexity, plan_exists, plan_source, goal, next_agent, pipeline. Third: Call Task tool if next_agent is not null. This is MANDATORY. NO EXCEPTIONS.

## Tool Priority

For code operations, ALWAYS try Serena MCP tools FIRST:
- serena_find_symbol (not grep)
- serena_find_referencing_symbols (not grep)
- serena_get_symbols_overview (not grep)
- serena_rename_symbol (not edit with regex)
- serena_replace_symbol_body (not edit)

Use built-in tools (grep, read, edit) as FALLBACK when Serena fails or for non-symbol tasks.
```

**Append to prompt** (add after the existing Tool Priority section):
```

## Pipeline Logic

Follow these pipelines based on task type:

| Task | Pipeline |
|------|----------|
| BUGFIX SIMPLE | bugfix-triage -> worker -> utility |
| BUGFIX DEEP | bugfix-triage -> plan-bug -> execute-bug -> dev-reviewer -> rework -> consistency-checker -> utility |
| DEV SIMPLE (no plan) | worker -> utility |
| DEV SIMPLE (with plan) | worker -> consistency-checker -> utility |
| DEV COMPLEX | dev-planner -> dev-professor -> dev-reviewer -> rework -> consistency-checker -> utility |
| DEVOPS | devops-agent -> devops-reviewer |
| DOCS | docs-writer -> utility |
```

**Rationale:**
- Gives orchestrator explicit pipeline knowledge in its own prompt
- Removes reliance on reading AGENTS.md at runtime (orchestrator may not read it)
- The `DEV SIMPLE (with plan)` variant explicitly references `plan_exists` condition
- Consolidates all pipeline definitions in one place the orchestrator always sees

**⚠️ JSON escaping note:** The prompt value is a JSON string with `\n` for newlines. The appended content must use `\n\n` for paragraph breaks and `\n` for line breaks within the JSON string value.

---

### Phase 3: Verify No Changes Needed in workflow-enforcement.ts

**File:** `P:\Programming\Рефакторинг\plugins\workflow-enforcement.ts`

**Verification checklist:**

| Check | Status | Detail |
|-------|--------|--------|
| consistency-checker in orchestrator routing table | ✅ Already present | Line 27: `"consistency-checker"` |
| Plugin enforces pipeline ordering | ❌ Not applicable | Plugin does NOT implement pipeline enforcement — it only validates routing tables, JSON schema, and identity |
| Pipeline field validation | ✅ Already present | Lines 566-568: validates `pipeline` is array or null |
| next_agent whitelist validation | ✅ Already present | Lines 559-563: validates `next_agent` is in routing table |

**Conclusion:** No changes needed. The plugin already allows orchestrator → consistency-checker calls via the routing table.

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Orchestrator ignores the conditional logic and always/never calls consistency-checker | Medium | The prompt explicitly states the condition tied to `plan_exists` field, which the orchestrator already outputs |
| DEV COMPLEX accidentally modified | Low | Plan explicitly marks DEV COMPLEX as DO NOT TOUCH; implementation only touches lines 254-259 |
| Prompt update makes JSON string too long | Low | Current prompt is ~450 chars; addition is ~400 chars; total under 1000 chars — well within limits |
| Orchestrator doesn't read AGENTS.md | Medium | Mitigated by Phase 2 — pipeline logic embedded directly in prompt |
| consistency-checker adds latency for DEV SIMPLE tasks with plans | Low | Acceptable trade-off — plan-based tasks benefit from consistency validation |

## Testing Strategy

### Manual Verification

1. **DEV SIMPLE without plan:**
   - Give orchestrator a DEV task classified as SIMPLE with `plan_exists: false`
   - Verify JSON output: `"pipeline": ["worker", "utility"]`
   - Verify orchestrator calls: `worker` → then `utility`
   - Verify orchestrator does NOT call `consistency-checker`

2. **DEV SIMPLE with plan:**
   - Give orchestrator a DEV task classified as SIMPLE with `plan_exists: true`
   - Verify JSON output: `"pipeline": ["worker", "consistency-checker", "utility"]`
   - Verify orchestrator calls: `worker` → `consistency-checker` → `utility`

3. **DEV COMPLEX unchanged:**
   - Give orchestrator a DEV task classified as COMPLEX
   - Verify pipeline matches: `dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility`
   - Verify no deviation from existing behavior

4. **Plugin enforcement still works:**
   - Verify `workflow-enforcement.ts` still validates routing tables
   - Verify `consistency-checker` calls are allowed (whitelist check passes)

### Automated Verification

- No automated tests exist for pipeline flow — this is documentation/prompt driven
- The plugin's JSON validation will catch invalid `pipeline` field values (must be array)
- The plugin's routing table enforcement will catch if orchestrator tries to call an agent not in its whitelist

## Estimated Effort

| Phase | Effort | Time |
|-------|--------|------|
| Phase 1: AGENTS.md update | Trivial | 2 minutes |
| Phase 2: opencode.json prompt update | Simple (JSON escaping) | 5 minutes |
| Phase 3: Verify workflow-enforcement.ts | Read-only verification | 2 minutes |
| Testing | Manual validation | 10-15 minutes |
| **Total** | | **~20 minutes** |

## Summary of Changes

```
AGENTS.md                    | UPDATE  | Lines 254-259 replaced with conditional DEV SIMPLE
~/.config/opencode/opencode.json | UPDATE  | Line 407 — append pipeline table to orchestrator prompt
plugins/workflow-enforcement.ts  | NOOP    | No changes needed
```
