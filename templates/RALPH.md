# Ralph Loop Guidelines

Autonomous development via [ralph-wiggum](https://github.com/anthropics/claude-code/blob/main/plugins/ralph-wiggum/README.md). Rules here, task in progress file.

## Core Rules (Parent Orchestrator)

1. **USE SUB-AGENTS**: Never do implementation work directly. Use the **Task tool** to spawn a sub-agent for each step. This keeps your context minimal.
2. **One step per iteration**: Determine ONE logical step, spawn sub-agent, receive summary, update progress. Then stop.
3. **Context window**: If context is > 50% full, stop immediately and let the loop restart fresh.
4. **Minimal prompts**: Generate step-specific prompts for sub-agents. Never pass the full task description repeatedly.
5. **CRITICAL: Update your session progress file BEFORE stopping.** Every iteration MUST end with an update to your session progress file (resolved via `.claude/ralph/.active`). The next iteration reads this file to determine what to do — if you don't update it, the next iteration will repeat the same work or get confused. Update the Current section, move completed items to Completed, and log the iteration.
6. **Sandbox + bypass mode**: You are running with `--dangerously-skip-permissions` inside a sandbox. Deny rules in `.claude/settings.local.json` block dangerous commands. The sandbox blocks unauthorized network and filesystem access. Sub-agents inherit all sandbox restrictions and deny rules from the parent session.
7. **Feature branches**: The preflight hook auto-creates a `ralph/<task-slug>` branch when on main/master. Do not force-push to main or master.
8. **Document blockers**: If truly blocked, log the issue in the Blockers section of your session progress file, skip to the next unblocked step, and stop. The next iteration will pick up from there.
9. **Completion promise format**: When task is complete, output `<promise>YOUR_PHRASE</promise>` (XML tags required).

## Session Management

The preflight hook creates a session-stamped progress file for each run:
- Copies your task from `progress.md` into `progress-<session-id>.md`
- Writes the session ID to `.claude/ralph/.active`
- Resets `progress.md` to a blank template

**Resolving your progress file (every iteration):**
1. Read `.claude/ralph/.active` to get `<session-id>`
2. Use `.claude/ralph/progress-<session-id>.md` — NOT `progress.md`

**On task completion:** Delete `.claude/ralph/.active` after outputting the completion promise.

## Sub-Agent Prompt Template

Use the **Task tool** to spawn sub-agents. Provide this minimal prompt format:

```
Step: [Specific action to take]
Location: [File path(s) if applicable]
Context: [1-2 sentences of relevant context]
Reference: Session progress file (via .claude/ralph/.active) for full task context if needed
Report: [What to return - summary, line count, status, etc.]
```

## Progress Tracking

**Enabled**: Progress tracked in session progress file (resolved via `.claude/ralph/.active`). This is the source of truth.

### Workflow (with sub-agents)
1. **Plan** - First iteration: Spawn sub-agent to analyze task, produce step list
2. **Implement** - Each iteration: Spawn sub-agent for ONE step, update progress
3. **Review** - After implementation: Spawn review sub-agent (optionally with pr-review-toolkit)
4. **Fix** - Spawn sub-agent for each fix
5. **Complete** - Push, create PR if configured, output completion promise

### Progress File Format
```markdown
## Task
[Original task description - written once, never duplicated in prompts]

## Plan
- [ ] Step 1: Description
- [ ] Step 2: Description
- [ ] Step 3: Description

## Current
Step: 2
Status: in_progress
Sub-agent: Implementing createTodo function

## Completed
- [x] Step 1: Set up API routes (iteration 2)
  Summary: Created src/api/index.ts with GET/POST/PUT/DELETE routes

## Blockers
- [Issue and why it's blocked]

## Iteration Log
- Iteration 1: Planning phase, created 5 steps
- Iteration 2: Completed step 1 (API routes)
- Iteration 3: Working on step 2 (createTodo)
```

### Sub-Agent Interaction Pattern
```
Parent reads session progress file -> "Step 2 is next: Implement createTodo"
                         |
                         v
Parent spawns sub-agent: "Implement createTodo in src/api/todos.ts.
                          API routes already set up in src/api/index.ts.
                          Return: summary of what was implemented"
                         |
                         v
Sub-agent works (isolated context)
                         |
                         v
Sub-agent returns: "Implemented createTodo with validation, 45 lines"
                         |
                         v
Parent updates session progress file with summary
                         |
                         v
Parent stops (loop restarts fresh)
```

<!--ralph-option:git_strategy
{
  "id": "git_strategy",
  "question": "Git commit strategy?",
  "default": 4,
  "options": [
    {"value": "never", "label": "Never - I'll handle git myself"},
    {"value": "once", "label": "Once - Commit when task is complete"},
    {"value": "each", "label": "Each loop - Commit after every iteration"},
    {"value": "squash", "label": "Squash - Commit each loop, squash when done (Recommended)"}
  ]
}
-->

## Git Strategy

<!--ralph-option:git_never-->
**Manual**: Do not make commits. User handles all git operations.
<!--/ralph-option:git_never-->

<!--ralph-option:git_once-->
**On Completion**: Commit once when the task is fully complete.
- Use descriptive commit message summarizing all changes
<!--/ralph-option:git_once-->

<!--ralph-option:git_each-->
**Each Loop**: Commit after every iteration.
- Prefix: `ralph: <brief description>`
- After each step: (1) update session progress file, (2) run quality gates, (3) `git add` + `git commit`, (4) stop
- Creates detailed history, may need manual cleanup
<!--/ralph-option:git_each-->

<!--ralph-option:git_squash-->
**Squash**: Commit after each loop, squash when task completes.
- During: `WIP: ralph - <step description>`
- Final: Squash all WIP commits into a single descriptive commit:
  ```bash
  git reset --soft $(git merge-base HEAD <base-branch>) && git commit -m "<descriptive message>"
  ```
  where `<base-branch>` is the branch you branched from (typically `main` or `master`).
<!--/ralph-option:git_squash-->

<!--ralph-option:pr_open-->
**Branch Strategy**: Push branch and open a PR when task is complete.
<!--/ralph-option:pr_open-->

<!--ralph-option:pr_merge-->
**Branch Strategy**: Push branch, open a PR, and auto-merge if there are no conflicts.
<!--/ralph-option:pr_merge-->

<!--ralph-option:pr_no-->
**Branch Strategy**: Work in a feature branch but do not push or open a PR.
<!--/ralph-option:pr_no-->

<!--/ralph-option:git_strategy-->

### On Task Completion
- Commit final changes (per git strategy above)
<!--ralph-option:pr_push-->
- Push branch to origin: `git push -u origin HEAD`
- Open PR if none exists:
  - Check: `gh pr list --head $(git branch --show-current) --json number`
  - Create: `gh pr create --fill`
<!--/ralph-option:pr_push-->
<!--ralph-option:pr_automerge-->
- Auto-merge if no conflicts: `gh pr merge --auto --merge`
<!--/ralph-option:pr_automerge-->
<!--ralph-option:pr_push-->
- **If push or PR creation fails** (e.g. `gh` not available, auth issues, network blocked): log the failure in your session progress file and output a warning: `⚠️ Could not push/create PR automatically. Please push the branch and open a PR manually.` Do NOT let this block the completion promise.
<!--/ralph-option:pr_push-->
- **If any git/push/PR operation fails**: log the failure in your session progress file and output a warning. Do NOT let it block the completion promise.
- Delete `.claude/ralph/.active`
- Output completion promise

<!--ralph-option:pr_review_toolkit
{
  "id": "pr_review_toolkit",
  "question": "Use pr-review-toolkit for code review?",
  "default": 1,
  "options": [
    {"value": "yes", "label": "Yes - Run code review agents during review phase (Recommended)"},
    {"value": "no", "label": "No - Skip automated review"}
  ]
}
-->

## Code Review

<!--ralph-option:pr_review_yes-->
Use pr-review-toolkit agents during the **review phase** (workflow step 3, after all implementation steps are complete):
- `code-reviewer` - Check adherence to guidelines
- `silent-failure-hunter` - Find error handling issues
- `comment-analyzer` - Verify comment accuracy

**Invocation:** Only invoke during review iterations. Do not invoke during planning or implementation.
**Fallback:** If pr-review-toolkit agents are unavailable (tool not found, plugin not installed), fall back to manual self-review: re-read all changed files and check for obvious issues, missed edge cases, and guideline violations.
Note: Consumes additional tokens. Disable if context is limited.
<!--/ralph-option:pr_review_yes-->

<!--ralph-option:pr_review_no-->
Skip automated review. Manual review only.
<!--/ralph-option:pr_review_no-->

<!--/ralph-option:pr_review_toolkit-->

## Quality Gates
<!--ralph-option:quality_gates-->
Run these commands to validate changes before committing:
<!--ralph-quality-gate-commands-->
All quality gate commands must exit 0 before committing. If any gate fails:
1. Fix the issues identified by the failing gate
2. Re-run the gate to confirm the fix
3. Only then proceed to commit
<!--/ralph-option:quality_gates-->

## Invocation

### Step 1: Write your task to progress.md

Edit `.claude/ralph/progress.md` and fill in the Task section:

```bash
vim .claude/ralph/progress.md
```

### Step 2: Start the loop with minimal prompt

```bash
/ralph-loop "Continue per .claude/ralph/progress.md" --max-iterations 50 --completion-promise "TASK COMPLETE"
```

Only "Continue per .claude/ralph/progress.md" gets duplicated - the actual task lives in the file.
