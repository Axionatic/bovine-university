# bovine-university
> When I grow up, I'm going to Bovine University!

Ralph Wiggum is a sweet kid. Sure, he has some issues. Don't we all?

Unfortunately, Ralph is not a good match for Claude Code.
- Ralph likes to keep it basic. Claude is a bit of a braniac.
- Ralph prefers short, bite-sized tasks. Claude likes to do everything, all at once.
- Ralph likes to be dangerous (chuckles). Claude takes great care to be safe. Usually.
- Ralph is quick to give up when something doesn't work. Claude will hammer away until your wallet cries out in pain.
- Ralph quite happily forgets things. Claude tries very hard to remember everything (but sometimes forgets anyway).

Bovine University is a very simple set of rules to teach Anthropic's [official ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) to be more ralph-like and less claude-like.
If you've tried using the plugin, you might have noticed:
- Even though Ralph is supposed to do things in small, iterative loops, Claude tries to complete the entire prompt in one go.
- Even though Ralph is supposed to run autonomously, Claude frequently pauses and asks for permissions.
- Even though Ralph is supposed to keep context as short as possible and start a fresh loop rather than compacting, Claude frequently runs-compacts-runs-compacts-runs-compacts.

*What do we teach Claude at BU?*
- You are in a loop. Do one single step of your task, then stop. The loop will handle the rest.
- You are running autonomously. Check `.claude/settings.local.json` for allowed permissions. Requests for other permissions will be auto-denied. Make it work if you can, otherwise document why not and move on.
- If the current step of the current task is taking a long time, check your context window. If it's > 50% full, stop immediately and let the loop take over.
- (optional) Write simple, succinct notes about what you're doing. The next loop will read them.*
- (if using persistant notes) One loop writes some code. The next loop reviews that code. The loop after fixes identified issues. Repeat. Optionally uses Anthropic's [official pr-review-toolkit plugin](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit) - it's good but consumes tokens quickly.


*The Ralph purists may note that even this is unnecessary; and that Ralph by design should explore the codebase to learn what progress has been made on the current prompt. YMMV.
