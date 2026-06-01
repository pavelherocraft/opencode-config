# Fix Plan: Orchestrator Skips consistency-checker When plan_exists=true

**Bug ID:** DEV-SIMPLE-PLAN-PIPELINE + ALL-PIPELINES-CONSISTENCY
**Severity:** Critical — multiple pipelines missing rework loops for consistency-checker; escalate_to field too restrictive
**Date:** 2026-06-02
**Status:** PLAN READY (updated with ALL pipelines fixes — Phases 8-11 added)

---

## Goal

Fix the bug where orchestrator outputs `pipeline: ["worker", "utility"]` when `plan_exists=true` in DEV SIMPLE tasks, instead of the correct `pipeline: ["worker", "consistency-checker", "utility"]`.

Also resolve cascading inconsistencies across all configuration files (whitelist counts, agent naming, pipeline documentation).

**Expanded scope (Phases 8-11):** Fix ALL pipelines that use consistency-checker to include proper rework loops, expand the `escalate_to` field to support new escalation targets, and update all related documentation.

---

## Root Cause Summary

| Layer | File | Problem |
|-------|------|---------|
| **Primary bug** | `~/.config/opencode/agents/orchestrator.md` line 321 | `DEV PLAN EXISTS: worker → utility` — missing `consistency-checker` |
| **Secondary** | `P:/Programming/Рефакторинг/ARCHITECTURE.md` lines 193-197 | Only documents `DEV SIMPLE: worker → utility`, missing `plan_exists=true` variant |
| **Secondary** | `P:/Programming/Рефакторинг/opencode-config/ARCHITECTURE.md` lines 70-74 | Same issue as above (duplicate of project ARCHITECTURE.md) |
| **Tertiary** | `P:/Programming/Рефакторинг/ARCHITECTURE.md` whitelist table | Missing `view-image` agent, has duplicate `devops-agent` entries |
| **Tertiary** | `P:/Programming/Рефакторинг/opencode-config/ARCHITECTURE.md` whitelist table | Same whitelist issues + lists "devops" (#10) instead of "devops-agent" |
| **Pipeline gap** | BUGFIX DEEP pipeline | consistency-checker after rework, but no rework loop if consistency-checker finds issues — indirect loop via dev-reviewer only |
| **Pipeline gap** | DEV COMPLEX pipeline | Same as BUGFIX DEEP — no direct rework loop from consistency-checker |
| **Pipeline gap** | DEV SIMPLE (with plan) | No rework agent at all — consistency-checker finds issues but no mechanism to route back for fixes |
| **Field limitation** | ARCHITECTURE.md / consistency-checker.md | `escalate_to` only supports `"dev-reviewer"` — cannot escalate to `rework`, `worker`, or `execute-bug` |

---

## Files to Modify

| # | File | Location | Change Type |
|---|------|----------|-------------|
| 1 | `orchestrator.md` | `~/.config/opencode/agents/orchestrator.md` | Pipeline fix (line 321) + conditional steps doc (line 414) + rework loop docs + BUGFIX DEEP/DEV COMPLEX rework loops + escalation routing |
| 2 | `ARCHITECTURE.md` | `P:/Programming/Рефакторинг/ARCHITECTURE.md` | Pipeline doc (lines 193-197) + whitelist table (lines 7-31) + rework loop doc + escalate_to field expansion + BUGFIX DEEP/DEV COMPLEX pipeline fixes |
| 3 | `ARCHITECTURE.md` | `P:/Programming/Рефакторинг/opencode-config/ARCHITECTURE.md` | Pipeline doc (lines 70-74) + whitelist table (lines 9-30) + rework loop doc + escalate_to field expansion + BUGFIX DEEP/DEV COMPLEX pipeline fixes |
| 4 | `AGENTS.md` | `P:/Programming/Рефакторинг/AGENTS.md` | Pipeline doc (DEV SIMPLE с планом) + rework loop notation + BUGFIX DEEP/DEV COMPLEX rework loop notation |
| 5 | `AGENTS.md` | `P:/Programming/Рефакторинг/opencode-config/AGENTS.md` | Same as #4 (duplicate file) |
| 6 | `consistency-checker.md` | `~/.config/opencode/agents/consistency-checker.md` | Expand escalate_to field values, add new escalation target documentation |

**Files NOT modified:**
- None — all relevant files require updates for rework loop mechanism and escalate_to expansion

---

## Detailed Step-by-Step Plan

### Phase 1: Fix the Primary Bug — orchestrator.md Pipeline Definition

#### Step 1.1: Fix DEV PLAN EXISTS pipeline (line 321)

**File:** `~/.config/opencode/agents/orchestrator.md`

**Current (WRONG):**
```
**DEV PLAN EXISTS:** worker → utility
```

**Target (CORRECT):**
```
**DEV PLAN EXISTS:** worker → consistency-checker → utility
```

**Exact edit:**
```
Line 321: Change "worker → utility" to "worker → consistency-checker → utility"
```

#### Step 1.2: Update Conditional Steps documentation (line 414)

**File:** `~/.config/opencode/agents/orchestrator.md`

**Current (line 414):**
```
- **consistency-checker**: Only for DEV COMPLEX and BUGFIX DEEP
```

**Target (CORRECT):**
```
- **consistency-checker**: Only for DEV COMPLEX, DEV PLAN EXISTS, and BUGFIX DEEP
```

#### Step 1.3: Add DEV PLAN EXISTS example pipeline walkthrough

**File:** `~/.config/opencode/agents/orchestrator.md`

**Insert after the DEV COMPLEX example (after line ~408):**

```markdown
### Example: DEV PLAN EXISTS Pipeline

\```
Step 0: Call worker
  → Prompt: "Implement this plan: [plan from conversation context]"
  → Wait for implementation

Step 1: Call consistency-checker
  → Prompt: "Validate architecture consistency for modified files against plan"
  → Wait for validation

Step 2: Call utility
  → Prompt: "Syntax check these files: [all modified files]"
  → Wait for syntax check

Step 3: Report results
\```
```

---

### Phase 2: Fix ARCHITECTURE.md Pipeline Documentation (Project Root)

#### Step 2.1: Replace DEV SIMPLE section with two-variant documentation

**File:** `P:/Programming/Рефакторинг/ARCHITECTURE.md`

**Current (lines 193-197):**
```markdown
### DEV SIMPLE

\```
worker → utility
\```
```

**Target:**
```markdown
### DEV SIMPLE

DEV SIMPLE has two variants depending on whether a plan exists:

| Variant | Flow | When to Use |
|---------|------|-------------|
| DEV SIMPLE (without plan) | `worker → utility` | plan_exists=false — direct implementation and validation |
| DEV SIMPLE (with plan) | `worker → consistency-checker → utility` | plan_exists=true — plan-validated implementation |

**Decision rule:** If plan_exists=true, use the "with plan" variant. Otherwise, use the "without plan" variant.
```

---

### Phase 3: Fix opencode-config/ARCHITECTURE.md (Duplicate Config)

#### Step 3.1: Replace DEV SIMPLE section (lines 70-74)

**File:** `P:/Programming/Рефакторинг/opencode-config/ARCHITECTURE.md`

**Current (lines 70-74):**
```markdown
### DEV SIMPLE

\```
worker → utility
\```
```

**Target:** Same as Phase 2.1 — identical two-variant table format.

---

### Phase 4: Fix Whitelist Inconsistencies

#### Step 4.1: Fix project root ARCHITECTURE.md whitelist table

**File:** `P:/Programming/Рефакторинг/ARCHITECTURE.md`

**Current issues:**
1. Header says "(20 agents)" but AGENTS.md says 21
2. Missing `view-image` agent
3. Has duplicate `devops-agent` at positions #10 and #13
4. Missing `devops` agent entry (listed in AGENTS.md as separate from devops-agent)

**Target whitelist table (21 agents):**

```markdown
### orchestrator Whitelist (21 agents)

| # | Agent Name | Role |
|---|------------|------|
| 1 | orchestrator-identity-probe | Identity verification |
| 2 | dev-reviewer | Code review |
| 3 | dev-professor | Development guidance |
| 4 | mcp-github | GitHub operations |
| 5 | worker | Simple development tasks |
| 6 | bugfix | Bug fixing |
| 7 | rework | Rework on feedback |
| 8 | mcp-read | File reading |
| 9 | utility | Syntax checking, formatting |
| 10 | bugfix-triage | Initial bug analysis |
| 11 | plan-bug | Bug fix planning |
| 12 | devops-agent | DevOps operations |
| 13 | devops-reviewer | DevOps review |
| 14 | dev-planner | Development planning |
| 15 | mcp-search | Web search |
| 16 | docs-writer | Documentation writing |
| 17 | summarizer | Content summarization |
| 18 | execute-bug | Bug fix implementation |
| 19 | consistency-checker | Architecture consistency validation |
| 20 | view-image | Image analysis |
| 21 | devops | Legacy DevOps tasks (alias) |
```

**Note on "devops" vs "devops-agent":**
- AGENTS.md lists both `devops` and `devops-agent` as separate entries
- This appears intentional — `devops` is listed as "DevOps tasks" and `devops-agent` as "DevOps operations"
- Keep both but document `devops` as a legacy alias to avoid confusion
- Update Agent Count Summary: orchestrator whitelist count becomes 21

#### Step 4.2: Fix opencode-config/ARCHITECTURE.md whitelist table

**File:** `P:/Programming/Рефакторинг/opencode-config/ARCHITECTURE.md`

Apply the same whitelist table fix as Step 4.1, replacing the current table at lines 9-30.

**Current issues in this file:**
1. Position #10 says `devops` (Role: "DevOps tasks") — different from project root which has duplicate `devops-agent`
2. Position #13 says `devops-agent` — same as project root
3. Missing `view-image` entirely
4. Header says "(20 agents)"

**Target:** Same 21-agent table as Step 4.1.

---

### Phase 5: Verify Cross-File Consistency

#### Step 5.1: Consistency checklist

After all edits, verify these match across all files:

| Check Point | orchestrator.md | ARCHITECTURE.md (root) | ARCHITECTURE.md (config) | AGENTS.md (both) |
|-------------|----------------|----------------------|--------------------------|------------------|
| DEV SIMPLE (no plan) pipeline | `worker → utility` | `worker → utility` | `worker → utility` | `worker → utility` |
| DEV PLAN EXISTS pipeline | `worker → consistency-checker → utility` | `worker → consistency-checker → utility` | `worker → consistency-checker → utility` | `worker → consistency-checker → utility` |
| DEV COMPLEX pipeline | same across all | same | same | same |
| Whitelist count | N/A | 21 agents | 21 agents | 21 agents |
| view-image present | N/A | YES | YES | YES |
| No duplicate devops-agent | N/A | YES (deduped) | YES (deduped) | YES |

#### Step 5.2: Verify with grep/search

Run these searches to confirm no stale references remain:

1. Search for `"worker → utility"` — should only appear in "DEV SIMPLE (without plan)" context, NOT in "DEV PLAN EXISTS" context
2. Search for `"consistency-checker"` in pipeline sections — should appear in DEV PLAN EXISTS, DEV COMPLEX, and BUGFIX DEEP
3. Search for `"20 agents"` — should be replaced with `"21 agents"` everywhere

---

### Phase 6: Add Rework Loop for consistency-checker

#### Step 6.1: Update DEV PLAN EXISTS pipeline in orchestrator.md

**File:** `~/.config/opencode/agents/orchestrator.md`

**Current (after Phase 1 fix):**
```
**DEV PLAN EXISTS:** worker → consistency-checker → utility
```

**Target (with rework loop):**
```
**DEV PLAN EXISTS:** worker → consistency-checker → [if issues: worker → consistency-checker (loop, max 3)] → utility
```

**Exact edit:**
```
Line 321: Change "worker → consistency-checker → utility"
          to "worker → consistency-checker → [if issues: worker → consistency-checker (loop, max 3)] → utility"
```

#### Step 6.2: Add rework loop logic documentation to orchestrator.md

**File:** `~/.config/opencode/agents/orchestrator.md`

**Insert after the DEV PLAN EXISTS pipeline example (after the block added in Step 1.3):**

```markdown
### Rework Loop: consistency-checker → worker

When consistency-checker finds critical architecture issues, the task is routed back to worker for fixes.

**Loop conditions:**
- **Trigger:** consistency-checker reports `issues_found > 0` with severity "critical" or "high"
- **Action:** Route back to worker with the list of issues to fix
- **Re-validation:** After worker fixes, route back to consistency-checker
- **Max iterations:** 3 (prevents infinite loops)
- **Exit conditions:**
  - consistency-checker passes (`issues_found == 0`) → proceed to utility
  - Max iterations reached → report failure with remaining issues

**Loop flow:**
\```
worker → consistency-checker
  ↓ (issues found)
worker (fix issues) → consistency-checker (re-validate)
  ↓ (issues found, iteration < 3)
worker (fix issues) → consistency-checker (re-validate)
  ↓ (issues found, iteration < 3)
worker (fix issues) → consistency-checker (re-validate)
  ↓ (passes OR max iterations reached)
utility (if passed) OR report failure (if max iterations)
\```

**Orchestrator decision logic:**
\```
if consistency-checker.issues_found == 0:
    → call utility
elif consistency-checker.iteration_count < 3:
    → call worker with issues list
    → increment iteration_count
    → call consistency-checker again
else:
    → report failure: "consistency-checker failed after 3 iterations"
    → do NOT call utility
\```
```

#### Step 6.3: Update DEV PLAN EXISTS pipeline example to show rework loop

**File:** `~/.config/opencode/agents/orchestrator.md`

**Update the DEV PLAN EXISTS example (from Step 1.3) to include rework loop:**

```markdown
### Example: DEV PLAN EXISTS Pipeline (with rework loop)

\```
Step 0: Call worker
  → Prompt: "Implement this plan: [plan from conversation context]"
  → Wait for implementation

Step 1: Call consistency-checker (iteration 1)
  → Prompt: "Validate architecture consistency for modified files against plan"
  → Wait for validation

Step 1a: [CONDITIONAL] If consistency-checker found critical issues:
  → Call worker with issues list
  → Prompt: "Fix these consistency issues: [list from consistency-checker]"
  → Wait for fixes
  → Call consistency-checker (iteration 2)
  → Repeat up to 3 iterations total

Step 2: Call utility (only if consistency-checker passed)
  → Prompt: "Syntax check these files: [all modified files]"
  → Wait for syntax check

Step 3: Report results
\```
```

#### Step 6.4: Update ARCHITECTURE.md pipeline documentation (project root)

**File:** `P:/Programming/Рефакторинг/ARCHITECTURE.md`

**Update the DEV SIMPLE "with plan" variant in the two-variant table:**

**Current (after Phase 2 fix):**
```markdown
| DEV SIMPLE (with plan) | `worker → consistency-checker → utility` | plan_exists=true — plan-validated implementation |
```

**Target:**
```markdown
| DEV SIMPLE (with plan) | `worker → consistency-checker → [rework loop, max 3] → utility` | plan_exists=true — plan-validated implementation with rework loop |
```

**Add rework loop documentation after the table:**

```markdown
**Rework loop:** If consistency-checker finds critical issues, task returns to worker for fixes. Loop repeats up to 3 iterations. If consistency-checker passes → utility. If max iterations reached → failure report.
```

#### Step 6.5: Update opencode-config/ARCHITECTURE.md (duplicate config)

**File:** `P:/Programming/Рефакторинг/opencode-config/ARCHITECTURE.md`

Apply the same pipeline table update and rework loop documentation as Step 6.4.

#### Step 6.6: Update AGENTS.md pipeline documentation (project root)

**File:** `P:/Programming/Рефакторинг/AGENTS.md`

**Current (DEV SIMPLE section):**
```markdown
| DEV SIMPLE (с планом) | worker → consistency-checker → utility | Tasks where a plan was created beforehand — implementation is validated against the plan by consistency-checker before final validation. |
```

**Target:**
```markdown
| DEV SIMPLE (с планом) | worker → consistency-checker → [rework loop, max 3] → utility | Tasks where a plan was created beforehand — implementation is validated against the plan by consistency-checker. If issues found, returns to worker for fixes (up to 3 iterations). |
```

#### Step 6.7: Update opencode-config/AGENTS.md (duplicate file)

**File:** `P:/Programming/Рефакторинг/opencode-config/AGENTS.md`

Apply the same pipeline update as Step 6.6. This file is a duplicate of the project root AGENTS.md and must stay synchronized.

#### Step 6.8: Add iteration count tracking documentation to orchestrator.md

**File:** `~/.config/opencode/agents/orchestrator.md`

**Insert after the rework loop logic documentation (from Step 6.2):**

```markdown
### Iteration Count Tracking

The orchestrator must track the rework loop iteration count to enforce the max 3 limit.

**Implementation:**
- Store `iteration_count` in orchestrator session state (internal counter)
- Initialize `iteration_count = 0` when first calling consistency-checker
- Increment `iteration_count += 1` each time routing back to worker
- Pass `iteration_count` to consistency-checker in prompt: "This is iteration {count} of consistency validation"

**Prompt template for worker (rework loop):**
\```
Fix these consistency issues (iteration {iteration_count} of 3):
{issues_list}

Previous implementation: {previous_code_summary}
\```

**Prompt template for consistency-checker (re-validation):**
\```
Re-validate architecture consistency (iteration {iteration_count} of 3):
- Files modified: {modified_files}
- Previous issues: {previous_issues}
- Plan reference: {plan_summary}
\```
```

---

### Phase 8: Fix BUGFIX DEEP Pipeline — Add Direct Rework Loop from consistency-checker

#### Step 8.1: Update BUGFIX DEEP pipeline in orchestrator.md

**File:** `~/.config/opencode/agents/orchestrator.md`

**Current BUGFIX DEEP pipeline:**
```
**BUGFIX DEEP:** bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility
```

**Problem:** If consistency-checker finds issues after rework, there is no direct loop back. The only rework mechanism is via dev-reviewer (which runs BEFORE rework → consistency-checker). This creates an indirect and inefficient loop.

**Target (with direct rework loop):**
```
**BUGFIX DEEP:** bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → [if issues: rework → consistency-checker (loop, max 3)] → utility
```

**Exact edit:** Find the BUGFIX DEEP pipeline definition and append the rework loop notation after `consistency-checker`.

#### Step 8.2: Add BUGFIX DEEP rework loop logic to orchestrator.md

**File:** `~/.config/opencode/agents/orchestrator.md`

**Insert after the existing rework loop documentation (from Phase 6):**

```markdown
### Rework Loop: BUGFIX DEEP — consistency-checker → rework

In BUGFIX DEEP, when consistency-checker finds issues after the initial rework phase, the task is routed back to `rework` (not `worker`) for fixes.

**Why `rework` instead of `worker`:**
- BUGFIX DEEP uses `execute-bug` for the initial implementation
- `rework` is the designated agent for fixing issues based on feedback
- `rework` has context from dev-reviewer's review and can apply targeted fixes

**Loop conditions:**
- **Trigger:** consistency-checker reports `issues_found > 0` with severity "critical" or "high"
- **Action:** Route back to `rework` with the list of issues to fix
- **Re-validation:** After rework fixes, route back to consistency-checker
- **Max iterations:** 3 (prevents infinite loops)
- **Exit conditions:**
  - consistency-checker passes (`issues_found == 0`) → proceed to utility
  - Max iterations reached → report failure with remaining issues

**Loop flow:**
\```
execute-bug → dev-reviewer → rework → consistency-checker
  ↓ (issues found)
rework (fix issues) → consistency-checker (re-validate)
  ↓ (issues found, iteration < 3)
rework (fix issues) → consistency-checker (re-validate)
  ↓ (passes OR max iterations reached)
utility (if passed) OR report failure (if max iterations)
\```
```

#### Step 8.3: Update BUGFIX DEEP pipeline in ARCHITECTURE.md (project root)

**File:** `P:/Programming/Рефакторинг/ARCHITECTURE.md`

**Current:**
```
bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility
```

**Target:**
```
bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → [rework loop, max 3] → utility
```

**Add rework loop documentation after the pipeline:**
```markdown
**Rework loop:** If consistency-checker finds critical issues after the initial rework, task returns to `rework` for additional fixes. Loop repeats up to 3 iterations. If consistency-checker passes → utility. If max iterations reached → failure report.
```

#### Step 8.4: Update BUGFIX DEEP pipeline in opencode-config/ARCHITECTURE.md

**File:** `P:/Programming/Рефакторинг/opencode-config/ARCHITECTURE.md`

Apply the same pipeline update and rework loop documentation as Step 8.3.

#### Step 8.5: Update BUGFIX DEEP pipeline in AGENTS.md (both files)

**File:** `P:/Programming/Рефакторинг/AGENTS.md` and `P:/Programming/Рефакторинг/opencode-config/AGENTS.md`

**Current:**
```
bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility
```

**Target:**
```
bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → [rework loop, max 3] → utility
```

---

### Phase 9: Fix DEV COMPLEX Pipeline — Add Direct Rework Loop from consistency-checker

#### Step 9.1: Update DEV COMPLEX pipeline in orchestrator.md

**File:** `~/.config/opencode/agents/orchestrator.md`

**Current DEV COMPLEX pipeline:**
```
**DEV COMPLEX:** dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility
```

**Problem:** Same as BUGFIX DEEP — if consistency-checker finds issues after rework, there is no direct loop back.

**Target (with direct rework loop):**
```
**DEV COMPLEX:** dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → [if issues: rework → consistency-checker (loop, max 3)] → utility
```

#### Step 9.2: Add DEV COMPLEX rework loop logic to orchestrator.md

**File:** `~/.config/opencode/agents/orchestrator.md`

**Insert after the BUGFIX DEEP rework loop documentation (from Step 8.2):**

```markdown
### Rework Loop: DEV COMPLEX — consistency-checker → rework

In DEV COMPLEX, when consistency-checker finds issues after the initial rework phase, the task is routed back to `rework` for fixes.

**Loop conditions:**
- **Trigger:** consistency-checker reports `issues_found > 0` with severity "critical" or "high"
- **Action:** Route back to `rework` with the list of issues to fix
- **Re-validation:** After rework fixes, route back to consistency-checker
- **Max iterations:** 3
- **Exit conditions:**
  - consistency-checker passes → proceed to utility
  - Max iterations reached → report failure

**Loop flow:**
\```
dev-planner → dev-professor → dev-reviewer → rework → consistency-checker
  ↓ (issues found)
rework (fix issues) → consistency-checker (re-validate)
  ↓ (issues found, iteration < 3)
rework (fix issues) → consistency-checker (re-validate)
  ↓ (passes OR max iterations reached)
utility (if passed) OR report failure (if max iterations)
\```
```

#### Step 9.3: Update DEV COMPLEX pipeline in ARCHITECTURE.md (project root)

**File:** `P:/Programming/Рефакторинг/ARCHITECTURE.md`

**Current:**
```
dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility
```

**Target:**
```
dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → [rework loop, max 3] → utility
```

**Add rework loop documentation after the pipeline:**
```markdown
**Rework loop:** If consistency-checker finds critical issues after the initial rework, task returns to `rework` for additional fixes. Loop repeats up to 3 iterations.
```

#### Step 9.4: Update DEV COMPLEX pipeline in opencode-config/ARCHITECTURE.md

**File:** `P:/Programming/Рефакторинг/opencode-config/ARCHITECTURE.md`

Apply the same pipeline update and rework loop documentation as Step 9.3.

#### Step 9.5: Update DEV COMPLEX pipeline in AGENTS.md (both files)

**File:** `P:/Programming/Рефакторинг/AGENTS.md` and `P:/Programming/Рефакторинг/opencode-config/AGENTS.md`

**Current:**
```
dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility
```

**Target:**
```
dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → [rework loop, max 3] → utility
```

---

### Phase 10: Expand escalate_to Field Values

#### Step 10.1: Update escalate_to field definition in ARCHITECTURE.md (project root)

**File:** `P:/Programming/Рефакторинг/ARCHITECTURE.md`

**Current:**
```json
"escalate_to": "dev-reviewer" | null
```

**Target:**
```json
"escalate_to": "dev-reviewer" | "rework" | "worker" | "execute-bug" | null
```

**Add escalation target documentation:**

```markdown
### escalate_to Field — Expanded Values

The `escalate_to` field in consistency-checker output determines which agent receives the task when issues are found.

| Value | When to Use | Pipeline Context |
|-------|-------------|------------------|
| `"dev-reviewer"` | Issues require architectural review or design decisions | DEV COMPLEX, BUGFIX DEEP (before rework) |
| `"rework"` | Issues are concrete and can be fixed by applying feedback | DEV COMPLEX (after rework), BUGFIX DEEP (after rework), DEV PLAN EXISTS |
| `"worker"` | Issues are simple implementation fixes | DEV PLAN EXISTS (simple rework loop) |
| `"execute-bug"` | Issues are bug-specific and require targeted bug fix | BUGFIX DEEP (if rework cannot fix) |
| `null` | No escalation needed (consistency-checker passed) | All pipelines |

**Decision logic for consistency-checker:**
\```
if issues_found == 0:
    escalate_to = null
elif issues are architectural/design-level:
    escalate_to = "dev-reviewer"
elif issues are concrete fixable items and pipeline has rework agent:
    escalate_to = "rework"
elif issues are simple implementation fixes:
    escalate_to = "worker"
elif issues are bug-specific:
    escalate_to = "execute-bug"
else:
    escalate_to = "dev-reviewer"  # default fallback
\```
```

#### Step 10.2: Update escalate_to field in opencode-config/ARCHITECTURE.md

**File:** `P:/Programming/Рефакторинг/opencode-config/ARCHITECTURE.md`

Apply the same escalate_to field expansion and documentation as Step 10.1.

#### Step 10.3: Update orchestrator.md to handle new escalation routings

**File:** `~/.config/opencode/agents/orchestrator.md`

**Insert after the rework loop documentation sections:**

```markdown
### Escalation Routing — consistency-checker escalate_to

When consistency-checker returns an `escalate_to` value, the orchestrator routes the task accordingly.

**Routing table:**

| escalate_to value | Next agent | Context |
|-------------------|------------|---------|
| `"dev-reviewer"` | dev-reviewer | Architectural issues requiring review |
| `"rework"` | rework | Concrete fixable issues (post-review pipelines) |
| `"worker"` | worker | Simple implementation fixes (DEV PLAN EXISTS) |
| `"execute-bug"` | execute-bug | Bug-specific issues (BUGFIX DEEP) |
| `null` | utility | Consistency-checker passed — proceed to syntax check |

**Orchestrator decision logic:**
\```
consistency_checker_result = call consistency-checker
if consistency_checker_result.escalate_to == null:
    → call utility
elif consistency_checker_result.escalate_to == "rework":
    → call rework with issues list
    → after rework completes, call consistency-checker again (re-validate)
elif consistency_checker_result.escalate_to == "worker":
    → call worker with issues list
    → after worker completes, call consistency-checker again (re-validate)
elif consistency_checker_result.escalate_to == "execute-bug":
    → call execute-bug with issues list
    → after execute-bug completes, call consistency-checker again (re-validate)
elif consistency_checker_result.escalate_to == "dev-reviewer":
    → call dev-reviewer with issues list
    → after dev-reviewer completes, follow dev-reviewer's recommendation
\```

**Iteration tracking for escalation loops:**
- Each escalation loop iteration increments `iteration_count`
- Max 3 iterations per loop (same as rework loop limit)
- If max iterations reached → report failure, do NOT proceed to utility
```

---

### Phase 11: Update consistency-checker.md Agent Configuration

#### Step 11.1: Update consistency-checker.md escalate_to field documentation

**File:** `~/.config/opencode/agents/consistency-checker.md`

**Find the section that documents the `escalate_to` field output and update it:**

**Current (expected):**
```markdown
**Output fields:**
- `escalate_to`: "dev-reviewer" or null
```

**Target:**
```markdown
**Output fields:**
- `escalate_to`: "dev-reviewer" | "rework" | "worker" | "execute-bug" | null

**Escalation target selection:**
- Use `"dev-reviewer"` when issues require architectural review or design decisions
- Use `"rework"` when issues are concrete and fixable (preferred for post-review pipelines)
- Use `"worker"` when issues are simple implementation fixes (DEV PLAN EXISTS context)
- Use `"execute-bug"` when issues are bug-specific (BUGFIX DEEP context)
- Use `null` when no issues are found (consistency-checker passed)
```

#### Step 11.2: Add escalation decision tree to consistency-checker.md

**File:** `~/.config/opencode/agents/consistency-checker.md`

**Insert after the output fields section:**

```markdown
### Escalation Decision Tree

When issues are found, select the appropriate escalation target:

1. **Is the issue architectural?** (wrong layer, violated pattern, design flaw)
   → `escalate_to: "dev-reviewer"`

2. **Is the issue a concrete, fixable item?** (missing validation, wrong naming, incomplete implementation)
   → `escalate_to: "rework"`

3. **Is the issue a simple implementation fix?** (typo, missing import, small logic error)
   → `escalate_to: "worker"`

4. **Is the issue bug-specific?** (regression, edge case not handled, wrong bug fix)
   → `escalate_to: "execute-bug"`

5. **Default fallback:**
   → `escalate_to: "dev-reviewer"`
```

---

### Phase 7: Final Cross-File Consistency Verification (Post-Rework-Loop)

#### Step 7.1: Updated consistency checklist

| Check Point | orchestrator.md | ARCHITECTURE.md (root) | ARCHITECTURE.md (config) | AGENTS.md (root) | AGENTS.md (config) | consistency-checker.md |
|-------------|----------------|----------------------|--------------------------|------------------|-------------------|----------------------|
| DEV PLAN EXISTS pipeline | includes rework loop notation | includes rework loop notation | includes rework loop notation | includes rework loop notation | includes rework loop notation | N/A |
| BUGFIX DEEP pipeline | includes rework loop notation | includes rework loop notation | includes rework loop notation | includes rework loop notation | includes rework loop notation | N/A |
| DEV COMPLEX pipeline | includes rework loop notation | includes rework loop notation | includes rework loop notation | includes rework loop notation | includes rework loop notation | N/A |
| Rework loop max iterations | documented as 3 | documented as 3 | documented as 3 | documented as 3 | documented as 3 | N/A |
| Exit conditions documented | YES | YES | YES | YES | YES | N/A |
| Loop flow diagram present | YES (all 3 pipelines) | N/A (reference only) | N/A (reference only) | N/A (reference only) | N/A (reference only) | N/A |
| Iteration count tracking | YES (implementation + prompts) | N/A | N/A | N/A | N/A | N/A |
| escalate_to expanded values | YES (routing table) | YES (5 values) | YES (5 values) | N/A | N/A | YES (decision tree) |
| Escalation decision logic | YES | YES | YES | N/A | N/A | YES |

#### Step 7.2: Verify rework loop logic is consistent

1. Search for `"max 3"` or `"max iterations"` — should appear in all pipeline documentation files
2. Search for `"rework loop"` — should appear in orchestrator.md, both ARCHITECTURE.md files, and both AGENTS.md files
3. Search for `"iteration_count"` — should appear in orchestrator.md iteration tracking section
4. Verify no file documents the old linear pipeline without the loop for DEV PLAN EXISTS, BUGFIX DEEP, or DEV COMPLEX
5. Search for `"escalate_to"` — should show 5 valid values in ARCHITECTURE.md (both), orchestrator.md, and consistency-checker.md
6. Search for `"escalation"` — should appear in orchestrator.md (routing table) and consistency-checker.md (decision tree)
7. Verify BUGFIX DEEP pipeline uses `rework` (not `worker`) in its rework loop
8. Verify DEV COMPLEX pipeline uses `rework` (not `worker`) in its rework loop
9. Verify DEV PLAN EXISTS pipeline uses `worker` in its rework loop (simpler context)

---

## Risks & Mitigations

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| orchestrator.md edit breaks formatting | Medium | Low | Verify markdown syntax after edit; test with a sample task |
| Whitelist dedup breaks existing routing | High | Low | Keep `devops` entry as separate agent; don't remove any agent that might be referenced in opencode.json |
| Duplicate ARCHITECTURE.md files diverge again | Medium | Medium | Consider making opencode-config/ARCHITECTURE.md a symlink to root ARCHITECTURE.md in future |
| conditional steps doc refers to wrong pipelines | Low | Low | Step 1.2 updates the reference explicitly |
| Agent count mismatch in summary tables | Low | Low | Step 4.1 updates Agent Count Summary table |
| Rework loop creates infinite cycling | High | Low | Hard-coded max 3 iterations prevents infinite loops; orchestrator must track iteration count |
| Worker cannot fix consistency issues | Medium | Medium | After max iterations, orchestrator reports failure instead of silently proceeding to utility |
| Iteration count not persisted across agent calls | High | Medium | Iteration count must be stored in orchestrator session state or passed in agent prompts |
| **BUGFIX DEEP rework loop conflicts with existing dev-reviewer loop** | Medium | Medium | Document clearly that the new loop is AFTER rework → consistency-checker, not replacing the dev-reviewer loop |
| **DEV COMPLEX rework loop creates redundant rework calls** | Medium | Low | The rework agent already ran once before consistency-checker; second call should only fix consistency-specific issues |
| **escalate_to expansion causes routing ambiguity** | High | Medium | Clear decision tree in consistency-checker.md (Step 11.2) prevents ambiguity; default fallback to dev-reviewer |
| **orchestrator doesn't recognize new escalate_to values** | High | Low | Step 10.3 adds explicit routing table for all new values in orchestrator.md |
| **consistency-checker.md not updated, agent uses old escalate_to values** | High | Medium | Step 11 explicitly updates consistency-checker.md; verify with grep after edit |

---

## Testing Strategy

### Manual Test 1: DEV SIMPLE with plan_exists=true

**Prerequisites:**
1. Ensure all config file edits are saved
2. Ensure no opencode sessions are running (restart opencode after config changes)

**Test Steps:**
1. Switch to plankestrator
2. Create a simple plan: "Create a new file called test.py with a hello world function"
3. Save the plan
4. Switch to orchestrator
5. Ask: "Implement the plan that was just created"
6. **Expected orchestrator JSON output:**
   ```json
   {
     "agent": "orchestrator",
     "type": "DEV",
     "complexity": "SIMPLE",
     "plan_exists": true,
     "pipeline": ["worker", "consistency-checker", "utility"],
     "next_agent": "worker"
   }
   ```
7. **Verify:** orchestrator calls worker → consistency-checker → utility in sequence

### Manual Test 2: DEV SIMPLE with plan_exists=false

**Test Steps:**
1. Start fresh orchestrator session (no prior plan in context)
2. Ask: "Fix the typo in README.md line 5"
3. **Expected orchestrator JSON output:**
   ```json
   {
     "agent": "orchestrator",
     "type": "DEV",
     "complexity": "SIMPLE",
     "plan_exists": false,
     "pipeline": ["worker", "utility"],
     "next_agent": "worker"
   }
   ```

### Manual Test 3: Verify no regression in DEV COMPLEX

1. Ask orchestrator: "Refactor the entire authentication module to use OAuth2"
2. **Expected:** `pipeline: ["dev-planner", "dev-professor", "dev-reviewer", "rework", "consistency-checker", "utility"]`

### Validation Test: Cross-file consistency

Run consistency-checker agent after all changes and verify:
- `checks_performed` > 0
- `issues_found` == 0
- `issues_unfixable` == 0

### Manual Test 4: Rework Loop — consistency-checker finds issues, worker fixes

**Test Steps:**
1. Switch to plankestrator, create a plan with a deliberate architecture violation (e.g., "Add a function that directly accesses the database from the UI layer")
2. Save the plan
3. Switch to orchestrator, ask to implement the plan
4. **Expected flow:**
   - worker implements (creates the violating code)
   - consistency-checker detects architecture violation → reports `issues_found > 0`
   - orchestrator routes back to worker with issues list
   - worker fixes the violation (moves DB access to proper layer)
   - consistency-checker re-validates → `issues_found == 0`
   - utility runs syntax check
5. **Verify:** Loop executed exactly 1 iteration, then proceeded to utility

### Manual Test 5: Rework Loop — max iterations reached

**Test Steps:**
1. Create a plan that will produce unfixable or repeatedly failing consistency checks
2. Ask orchestrator to implement
3. **Expected flow:**
   - worker → consistency-checker (issues found, iteration 1)
   - worker → consistency-checker (issues found, iteration 2)
   - worker → consistency-checker (issues found, iteration 3)
   - orchestrator reports failure: "consistency-checker failed after 3 iterations"
   - utility is NOT called
4. **Verify:** Loop stopped at 3 iterations, failure reported, utility skipped

### Manual Test 6: Rework Loop — consistency-checker passes on first try

**Test Steps:**
1. Create a plan with no architecture violations
2. Ask orchestrator to implement
3. **Expected flow:**
   - worker implements
   - consistency-checker validates → `issues_found == 0`
   - utility runs syntax check
4. **Verify:** No rework loop triggered, linear pipeline executed (worker → consistency-checker → utility)

### Manual Test 7: BUGFIX DEEP — consistency-checker finds issues, rework fixes

**Test Steps:**
1. Ask orchestrator to fix a complex bug using BUGFIX DEEP pipeline
2. Simulate consistency-checker finding an architecture issue after the initial rework
3. **Expected flow:**
   - bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker (issues found)
   - orchestrator routes back to `rework` with issues list
   - rework fixes the consistency issue
   - consistency-checker re-validates → `issues_found == 0`
   - utility runs syntax check
4. **Verify:** Loop executed with `rework` agent (not `worker`), then proceeded to utility

### Manual Test 8: DEV COMPLEX — consistency-checker finds issues, rework fixes

**Test Steps:**
1. Ask orchestrator to implement a complex feature using DEV COMPLEX pipeline
2. Simulate consistency-checker finding an architecture issue after the initial rework
3. **Expected flow:**
   - dev-planner → dev-professor → dev-reviewer → rework → consistency-checker (issues found)
   - orchestrator routes back to `rework` with issues list
   - rework fixes the consistency issue
   - consistency-checker re-validates → `issues_found == 0`
   - utility runs syntax check
4. **Verify:** Loop executed with `rework` agent, then proceeded to utility

### Manual Test 9: escalate_to = "worker" — DEV PLAN EXISTS simple fix

**Test Steps:**
1. Create a simple plan with a minor consistency issue
2. Ask orchestrator to implement
3. **Expected flow:**
   - worker implements
   - consistency-checker finds simple issue → `escalate_to: "worker"`
   - orchestrator routes back to `worker` with issues list
   - worker fixes the issue
   - consistency-checker re-validates → `issues_found == 0`
   - utility runs syntax check
4. **Verify:** `escalate_to` was `"worker"`, not `"rework"` (simple fix context)

### Manual Test 10: escalate_to = "execute-bug" — BUGFIX DEEP bug-specific issue

**Test Steps:**
1. Ask orchestrator to fix a bug using BUGFIX DEEP pipeline
2. Simulate consistency-checker finding a bug-specific regression
3. **Expected flow:**
   - bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker (bug-specific issue found)
   - consistency-checker sets `escalate_to: "execute-bug"`
   - orchestrator routes to `execute-bug` with issues list
   - execute-bug fixes the regression
   - consistency-checker re-validates → `issues_found == 0`
   - utility runs syntax check
4. **Verify:** `escalate_to` was `"execute-bug"`, bug-specific fix applied

### Manual Test 11: escalate_to = "dev-reviewer" — architectural issue

**Test Steps:**
1. Create a plan that results in an architectural violation
2. Ask orchestrator to implement
3. **Expected flow:**
   - worker implements
   - consistency-checker finds architectural issue → `escalate_to: "dev-reviewer"`
   - orchestrator routes to `dev-reviewer`
   - dev-reviewer provides guidance
   - Follow dev-reviewer's recommendation (may route to rework or worker)
4. **Verify:** `escalate_to` was `"dev-reviewer"`, architectural review performed

---

## Estimated Effort

| Phase | Estimated Time | Complexity |
|-------|---------------|------------|
| Phase 1: orchestrator.md pipeline fix | 5 minutes | Low (3 line edits + insertion) |
| Phase 2: ARCHITECTURE.md pipeline doc | 5 minutes | Low (1 section replacement) |
| Phase 3: opencode-config/ARCHITECTURE.md | 5 minutes | Low (same as Phase 2) |
| Phase 4: Whitelist fixes | 10 minutes | Medium (table restructuring in 2 files) |
| Phase 5: Cross-file verification | 10 minutes | Medium (manual search + comparison) |
| Phase 6: Rework loop mechanism (DEV PLAN EXISTS) | 20 minutes | Medium (pipeline notation + loop logic docs + iteration tracking in 5 files) |
| Phase 7: Post-rework-loop verification | 10 minutes | Medium (updated consistency checks across 5 files) |
| **Phase 8: BUGFIX DEEP rework loop** | **15 minutes** | **Medium (pipeline notation + loop logic in 4 files)** |
| **Phase 9: DEV COMPLEX rework loop** | **15 minutes** | **Medium (pipeline notation + loop logic in 4 files)** |
| **Phase 10: escalate_to field expansion** | **15 minutes** | **Medium (field definition + routing table + decision logic in 3 files)** |
| **Phase 11: consistency-checker.md update** | **10 minutes** | **Low (escalate_to field + decision tree in 1 file)** |
| Testing | 40 minutes | Medium (11 manual test scenarios, including 5 new escalation/rework loop tests) |
| **Total** | **~165 minutes (~2.75 hours)** | **Medium-High** |

---

## Execution Order

The phases should be executed in this exact order to minimize risk:

1. **Phase 1** first — fixes the primary bug in the global orchestrator config
2. **Phase 2** next — fixes project root documentation
3. **Phase 3** — fixes duplicate config (opencode-config/ARCHITECTURE.md)
4. **Phase 4** — fixes whitelist consistency (lower priority but prevents future confusion)
5. **Phase 5** — initial cross-file verification
6. **Phase 6** — add rework loop mechanism for DEV PLAN EXISTS (builds on Phase 1 pipeline fix)
   - Step 6.1-6.3: orchestrator.md updates
   - Step 6.4-6.5: ARCHITECTURE.md updates (both files)
   - Step 6.6-6.7: AGENTS.md updates (both files)
   - Step 6.8: iteration count tracking documentation
7. **Phase 8** — add rework loop for BUGFIX DEEP pipeline
   - Step 8.1: orchestrator.md pipeline update
   - Step 8.2: BUGFIX DEEP rework loop logic
   - Step 8.3-8.4: ARCHITECTURE.md updates (both files)
   - Step 8.5: AGENTS.md updates (both files)
8. **Phase 9** — add rework loop for DEV COMPLEX pipeline
   - Step 9.1: orchestrator.md pipeline update
   - Step 9.2: DEV COMPLEX rework loop logic
   - Step 9.3-9.4: ARCHITECTURE.md updates (both files)
   - Step 9.5: AGENTS.md updates (both files)
9. **Phase 10** — expand escalate_to field values
   - Step 10.1: ARCHITECTURE.md (project root) field expansion + decision logic
   - Step 10.2: ARCHITECTURE.md (opencode-config/) same update
   - Step 10.3: orchestrator.md escalation routing table
10. **Phase 11** — update consistency-checker.md agent configuration
    - Step 11.1: escalate_to field documentation
    - Step 11.2: escalation decision tree
11. **Phase 7** — final post-rework-loop verification (across all 6 files)
12. **Testing** — validate the fix works end-to-end, including all rework loop and escalation scenarios

---

## Summary of All Exact Edits

### Edit 1: orchestrator.md line 321
```
OLD: **DEV PLAN EXISTS:** worker → utility
NEW: **DEV PLAN EXISTS:** worker → consistency-checker → utility
```

### Edit 2: orchestrator.md line 414
```
OLD: - **consistency-checker**: Only for DEV COMPLEX and BUGFIX DEEP
NEW: - **consistency-checker**: Only for DEV COMPLEX, DEV PLAN EXISTS, and BUGFIX DEEP
```

### Edit 3: orchestrator.md — insert DEV PLAN EXISTS pipeline example after line ~408
```
INSERT: ### Example: DEV PLAN EXISTS Pipeline (with worker → consistency-checker → utility steps)
```

### Edit 4: ARCHITECTURE.md lines 193-197 (project root)
```
OLD: ### DEV SIMPLE\n\n```\nworker → utility\n```
NEW: ### DEV SIMPLE (with two-variant table documentation)
```

### Edit 5: ARCHITECTURE.md lines 70-74 (opencode-config/)
```
OLD: ### DEV SIMPLE\n\n```\nworker → utility\n```
NEW: ### DEV SIMPLE (with two-variant table documentation)
```

### Edit 6: ARCHITECTURE.md whitelist table (project root, lines 7-31)
```
OLD: orchestrator Whitelist (20 agents) with duplicate devops-agent and missing view-image
NEW: orchestrator Whitelist (21 agents) with deduped entries, view-image added
```

### Edit 7: ARCHITECTURE.md whitelist table (opencode-config/, lines 9-30)
```
OLD: orchestrator Whitelist (20 agents) with "devops" at #10 and missing view-image
NEW: orchestrator Whitelist (21 agents) with deduped entries, view-image added
```

### Edit 8: orchestrator.md line 321 — add rework loop notation
```
OLD: **DEV PLAN EXISTS:** worker → consistency-checker → utility
NEW: **DEV PLAN EXISTS:** worker → consistency-checker → [if issues: worker → consistency-checker (loop, max 3)] → utility
```

### Edit 9: orchestrator.md — insert rework loop logic documentation
```
INSERT: ### Rework Loop: consistency-checker → worker (with loop conditions, flow diagram, orchestrator decision logic)
```

### Edit 10: orchestrator.md — update DEV PLAN EXISTS pipeline example
```
UPDATE: Add Step 1a (conditional rework loop) to the pipeline example
```

### Edit 11: ARCHITECTURE.md (root) — update DEV SIMPLE table + add rework loop doc
```
UPDATE: "with plan" variant to include rework loop notation
INSERT: Rework loop documentation paragraph after the table
```

### Edit 12: ARCHITECTURE.md (opencode-config/) — same as Edit 11
```
UPDATE: "with plan" variant to include rework loop notation
INSERT: Rework loop documentation paragraph after the table
```

### Edit 13: AGENTS.md (project root) — update DEV SIMPLE (с планом) pipeline
```
OLD: worker → consistency-checker → utility
NEW: worker → consistency-checker → [rework loop, max 3] → utility
```

### Edit 14: AGENTS.md (opencode-config/) — same as Edit 13
```
OLD: worker → consistency-checker → utility
NEW: worker → consistency-checker → [rework loop, max 3] → utility
```

### Edit 15: orchestrator.md — insert iteration count tracking documentation
```
INSERT: ### Iteration Count Tracking (with implementation details, prompt templates for worker and consistency-checker)
```

### Edit 16: orchestrator.md — update BUGFIX DEEP pipeline with rework loop
```
OLD: **BUGFIX DEEP:** bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility
NEW: **BUGFIX DEEP:** bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → [if issues: rework → consistency-checker (loop, max 3)] → utility
```

### Edit 17: orchestrator.md — insert BUGFIX DEEP rework loop logic
```
INSERT: ### Rework Loop: BUGFIX DEEP — consistency-checker → rework (with loop conditions, flow diagram, why rework not worker)
```

### Edit 18: orchestrator.md — update DEV COMPLEX pipeline with rework loop
```
OLD: **DEV COMPLEX:** dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility
NEW: **DEV COMPLEX:** dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → [if issues: rework → consistency-checker (loop, max 3)] → utility
```

### Edit 19: orchestrator.md — insert DEV COMPLEX rework loop logic
```
INSERT: ### Rework Loop: DEV COMPLEX — consistency-checker → rework (with loop conditions, flow diagram)
```

### Edit 20: ARCHITECTURE.md (root) — update BUGFIX DEEP pipeline + add rework loop doc
```
UPDATE: BUGFIX DEEP pipeline to include rework loop notation
INSERT: Rework loop documentation paragraph after the pipeline
```

### Edit 21: ARCHITECTURE.md (opencode-config/) — same as Edit 20
```
UPDATE: BUGFIX DEEP pipeline to include rework loop notation
INSERT: Rework loop documentation paragraph after the pipeline
```

### Edit 22: ARCHITECTURE.md (root) — update DEV COMPLEX pipeline + add rework loop doc
```
UPDATE: DEV COMPLEX pipeline to include rework loop notation
INSERT: Rework loop documentation paragraph after the pipeline
```

### Edit 23: ARCHITECTURE.md (opencode-config/) — same as Edit 22
```
UPDATE: DEV COMPLEX pipeline to include rework loop notation
INSERT: Rework loop documentation paragraph after the pipeline
```

### Edit 24: AGENTS.md (both files) — update BUGFIX DEEP pipeline
```
OLD: bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility
NEW: bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → [rework loop, max 3] → utility
```

### Edit 25: AGENTS.md (both files) — update DEV COMPLEX pipeline
```
OLD: dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility
NEW: dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → [rework loop, max 3] → utility
```

### Edit 26: ARCHITECTURE.md (both files) — expand escalate_to field
```
OLD: "escalate_to": "dev-reviewer" | null
NEW: "escalate_to": "dev-reviewer" | "rework" | "worker" | "execute-bug" | null
INSERT: Escalation target selection table + decision logic
```

### Edit 27: orchestrator.md — add escalation routing table
```
INSERT: ### Escalation Routing — consistency-checker escalate_to (with routing table, orchestrator decision logic, iteration tracking)
```

### Edit 28: consistency-checker.md — update escalate_to field documentation
```
OLD: escalate_to: "dev-reviewer" or null
NEW: escalate_to: "dev-reviewer" | "rework" | "worker" | "execute-bug" | null
INSERT: Escalation target selection guidelines
```

### Edit 29: consistency-checker.md — add escalation decision tree
```
INSERT: ### Escalation Decision Tree (with 5-step decision process for selecting escalation target)
```
