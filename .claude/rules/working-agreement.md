# Working agreement (CareSync is a learning project)

The owner is a Node/Express developer learning Rails by building this API.

- **The owner types the application code.** Claude writes guides in `learning/`, explains the why, reviews diffs, and answers errors. Claude writes or edits app code or tests **only when asked**. When asked to "fix it" or "do this", do exactly that and nothing extra.
- Do not run migrations unless asked.
- Guides go in `learning/` (committed), one per topic: why first, then steps, tests, a self-check with answers. Add each to `learning/README.md`. `learning/HANDOFF.md` holds project state and the plan.
- Before a task of 3 or more steps, make a todo list.
- Keep answers short, in simple English, with Express/Node comparisons where they help. **Mark anything not run or not verified.** Never claim a test passed without running it.
- After a task, ask the follow-up that matters (edge cases, related places), briefly.
- The learning method: try first, read the guide second, write a short takeaway in your own words.
- Read the relevant file in `.claude/rules/` before writing code in that area. When a rule and the existing code disagree, follow the rule for new code and flag the old code, do not silently rewrite it.
