# Ralph Loop Guidelines

Autonomous development via [ralph-wiggum](https://github.com/anthropics/claude-code/blob/main/plugins/ralph-wiggum/README.md). Rules here, task in progress file.

## Core Rules (Parent Orchestrator)

1. **USE SUB-AGENTS**: Never do implementation work directly. Spawn a sub-agent for each step. This keeps your context minimal.
2. **One step per iteration**: Determine ONE logical step, spawn sub-agent, receive summary, update progress. Then stop.
3. **Minimal prompts**: Generate step-specific prompts for sub-agents. Never pass the full task description repeatedly.
4. **CRITICAL: Update progress.md BEFORE stopping.** Every iteration MUST end with an update to `.claude/ralph/progress.md`. The next iteration reads this file to determine what to do — if you don't update it, the next iteration will repeat the same work or get confused. Update the Current section, move completed items to Completed, and log the iteration.
5. **Sandbox + bypass mode**: You are running with `--dangerously-skip-permissions` inside a sandbox. Deny rules in `.claude/settings.local.json` block dangerous commands. The sandbox blocks unauthorized network and filesystem access.
6. **Feature branches**: The preflight hook auto-creates a `ralph/<task-slug>` branch when on main/master. Do not force-push to main or master.
7. **Document blockers**: If truly blocked, log the issue in progress.md and continue with other tasks.
8. **Completion promise format**: When task is complete, output `<promise>YOUR_PHRASE</promise>` (XML tags required).

## Sub-Agent Prompt Template

When spawning a sub-agent, use this minimal format:

```
Step: [Specific action to take]
Location: [File path(s) if applicable]
Context: [1-2 sentences of relevant context]
Reference: .claude/ralph/progress.md for full task context if needed
Report: [What to return - summary, line count, status, etc.]
```

## Progress Tracking

**Enabled**: Progress tracked in `.claude/ralph/progress.md`. This is the source of truth.

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
Parent reads progress.md -> "Step 2 is next: Implement createTodo"
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
Parent updates progress.md with summary
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
    {"value": "never", "label": "Never - Manual git"},
    {"value": "once", "label": "Once - On task completion"},
    {"value": "each", "label": "Each - After every loop"},
    {"value": "squash", "label": "Squash - Each loop, squash at end (Recommended)"}
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
- Creates detailed history, may need manual cleanup
<!--/ralph-option:git_each-->

<!--ralph-option:git_squash-->
**Squash**: Commit after each loop, squash when task completes.
- During: `WIP: ralph - <step description>`
- Final: Squash all WIP commits into single descriptive commit
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
- **If push or PR creation fails** (e.g. `gh` not available, auth issues, network blocked): log the failure in progress.md and output a warning: `⚠️ Could not push/create PR automatically. Please push the branch and open a PR manually.` Do NOT let this block the completion promise.
<!--/ralph-option:pr_push-->
- Output completion promise

<!--ralph-option:pr_review_toolkit
{
  "id": "pr_review_toolkit",
  "question": "Use pr-review-toolkit for code review?",
  "default": 1,
  "options": [
    {"value": "yes", "label": "Yes - Automated review agents (Recommended)"},
    {"value": "no", "label": "No - Skip automated review"}
  ]
}
-->

## Code Review

<!--ralph-option:pr_review_yes-->
Use pr-review-toolkit agents during review phase:
- `code-reviewer` - Check adherence to guidelines
- `silent-failure-hunter` - Find error handling issues
- `comment-analyzer` - Verify comment accuracy

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
